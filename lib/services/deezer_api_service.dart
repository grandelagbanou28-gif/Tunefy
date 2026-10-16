import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/album_details.dart';
import 'package:muzo/models/artist_details.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

final deezerApiServiceProvider = Provider<DeezerApiService>((ref) {
  return DeezerApiService();
});

/// Deezer public REST API — real catalog metadata, **no key required**.
///
/// Catalog endpoints (search / track / album / artist / genre / chart) are
/// publicly documented. Tracks carry a 30-second preview, which is NOT a real
/// song, so we never expose it as playable audio: Dezeer items are
/// metadata-only seeds (title/artist/album/cover/duration) that callers
/// resolve to full-length playable tracks via the main YouTube search — the
/// same contract as charts seeds. Every item is stamped with real provenance.
class DeezerApiService {
  static const String _base = 'https://api.deezer.com';
  static const Duration _timeout = Duration(seconds: 10);

  // ── Search ────────────────────────────────────────────────────────────────

  /// Real catalog search. Never throws — failures return [] so callers can
  /// fall through to the next source.
  Future<List<MuzoItem>> searchTracks(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
          '$_base/search/track?q=${Uri.encodeComponent(q)}&limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('Deezer non-200: ${resp.statusCode}');
        return const [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tracks = data['data'] as List? ?? [];
      return tracks
          .whereType<Map>()
          .map((e) => _trackToMuzo(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('Deezer search error: $e');
      return const [];
    }
  }

  // ── New releases / albums (date-aware: device clock, ALL countries) ───────

  /// Cached list of Deezer genre ids (used to reach every country's albums).
  List<int>? _cachedGenreIds;

  /// Timestamp of the last global album pool fetch (2-minute TTL).
  DateTime? _poolFetchedAt;
  List<MuzoItem>? _cachedPool;

  /// All albums available in the LAST [days] days, regardless of country:
  /// it merges the per-genre worldwide charts (`/chart/{genreId}/albums`) so
  /// we cover "toutes les nouvelles sorties / albums, peu importe le pays"
  /// instead of relying on one region-locked editorial feed. Results are
  /// metadata seeds carrying a `dz:<id>` browseId; AlbumScreen resolves the
  /// full tracklist. Never throws — failures return [].
  Future<List<MuzoItem>> newReleases({int days = 7, int limit = 30}) async {
    final all = await _albumsFromGlobalCharts();
    return _filterByDays(all, days: days).take(limit).toList();
  }

  /// Same global pool, wider date window (sane default: 30 days).
  Future<List<MuzoItem>> recentAlbums({int days = 30, int limit = 40}) async {
    final all = await _albumsFromGlobalCharts();
    return _filterByDays(all, days: days).take(limit).toList();
  }

  /// Real album search (Deezer `/search/album`) — used to surface genre
  /// albums (rap FR/US, gospel, afrobeats) the global top-artist pool misses.
  /// Never throws — failures return [].
  Future<List<MuzoItem>> searchAlbums(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
          '$_base/search/album?q=${Uri.encodeComponent(q)}&limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final albums = data['data'] as List? ?? [];
      return albums
          .whereType<Map>()
          .map((e) => _albumToMuzo(Map<String, dynamic>.from(e)))
          .where((a) => a.browseId != null && a.browseId != 'dz:')
          .toList();
    } catch (e) {
      debugPrint('Deezer searchAlbums error: $e');
      return const [];
    }
  }

  /// NEW singles/tracks, honestly filtered against the DEVICE clock so "fresh"
  /// really means the last [days] days. Deezer's `/chart/{id}/tracks` feed does
  /// not expose a release date, so we derive real new songs by:
  ///   1. taking the albums released within [days] days (`release_date`,
  ///      compared against `DateTime.now()`),
  ///   2. loading each recent album's lead track via `albumDetails`,
  ///   3. stamping every track with its album's `releaseDate`.
  /// The result is a list of songs that genuinely came out recently. Items are
  /// metadata seeds (`dz_<id>`) resolved to playable YouTube songs by callers.
  /// Never throws.
  Future<List<MuzoItem>> newTracks({int days = 7, int limit = 24}) async {
    try {
      final recentAlbums = await _albumsFromGlobalCharts()
          .then((all) => _filterByDays(all, days: days));
      if (recentAlbums.isEmpty) return const [];

      final albumSamples = recentAlbums.take(12).toList();
      final detailsList = <AlbumDetails?>[];
      // Chunked so Deezer's rate limit (a sub-5s burst trips it and empties
      // the whole home) never sees 50 parallel calls at once.
      for (final batch in _chunks(albumSamples, 4)) {
        detailsList.addAll(await Future.wait(batch.map((album) async {
          try {
            return await albumDetails(album.sourceId ?? album.browseId ?? '');
          } catch (_) {
            return null;
          }
        })));
      }

      final result = <MuzoItem>[];
      for (var i = 0; i < detailsList.length; i++) {
        final album = albumSamples[i];
        final details = detailsList[i];
        if (details == null || details.tracks.isEmpty) continue;
        final rel = album.releaseDate;
        // Take up to 5 lead tracks of a freshly released album = real new
        // songs, each stamped with the album's device-clock-verified date.
        final count = details.tracks.length > 5 ? 5 : details.tracks.length;
        for (final tr in details.tracks.take(count)) {
          result.add(tr.copyWith(releaseDate: rel));
          if (result.length >= limit) break;
        }
        if (result.length >= limit) break;
      }
      // Guard: if for some reason nothing survived, fall back to world-wide
      // chart tracks (still honest: they are current, just not date-stamped).
      if (result.isEmpty) {
        final chart = await _globalNewTracksFallback(days: days, limit: limit);
        return chart;
      }
      return result;
    } catch (e) {
      debugPrint('Deezer new tracks error: $e');
      return const [];
    }
  }

  Future<List<MuzoItem>> _globalNewTracksFallback(
      {int days = 7, int limit = 24}) async {
    try {
      final genreIds = await _genreIds();
      if (genreIds.isEmpty) return const [];
      final results = await Future.wait(genreIds.map((id) async {
        try {
          final uri = Uri.parse('$_base/chart/$id/tracks?limit=15');
          final resp = await http.get(uri).timeout(_timeout);
          if (resp.statusCode != 200) return const <MuzoItem>[];
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final tracks = body['data'] as List? ?? [];
          return tracks
              .whereType<Map>()
              .map((e) => _trackToMuzo(Map<String, dynamic>.from(e)))
              .toList();
        } catch (_) {
          return const <MuzoItem>[];
        }
      }));
      final merged = <String, MuzoItem>{};
      for (final list in results) {
        for (final tr in list) {
          merged.putIfAbsent(tr.sourceId ?? tr.title.toLowerCase(), () => tr);
        }
      }
      return merged.values.toList().take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  List<MuzoItem> _filterByDays(List<MuzoItem> albums, {required int days}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    // Pre-releases (next Friday albums) and date-only local-midnight stamps
    // in other timezones must not vanish from "nouvelles sorties".
    final horizon = now.add(const Duration(days: 7));
    return albums
        .where((a) {
          final rel = a.releaseDate;
          return rel != null && !rel.isBefore(cutoff) && !rel.isAfter(horizon);
        })
        .toList();
  }

  Future<List<MuzoItem>> _albumsFromGlobalCharts() async {
    final now = DateTime.now();
    final cached = _cachedPool;
    if (cached != null &&
        cached.isNotEmpty &&
        _poolFetchedAt != null &&
        now.difference(_poolFetchedAt!) < const Duration(minutes: 2)) {
      return cached;
    }
    try {
      // Fast path: worldwide album chart first (single call, most up-to-date).
      final chartAlbums = await _chartAlbums(0);
      if (chartAlbums.isNotEmpty) {
        final dated = chartAlbums.where((a) => a.releaseDate != null).toList()
          ..sort((a, b) => (b.releaseDate ?? DateTime(1970))
              .compareTo(a.releaseDate ?? DateTime(1970)));
        if (dated.isNotEmpty) {
          _cachedPool = dated;
          _poolFetchedAt = now;
          return dated;
        }
      }
      // Fallback: build the pool from the albums of the REAL worldwide top
      // artists (`/chart/0/artists` still works) ordered by release date DESC.
      final artists = await topArtists(limit: 40);
      if (artists.isEmpty) {
        // Never freeze an empty pool for 10 minutes — leave the cache empty
        // so the next call retries immediately.
        _cachedPool = null;
        _poolFetchedAt = null;
        return const [];
      }

      final artistAlbums = <List<MuzoItem>>[];
      for (final batch in _chunks(artists, 5)) {
        artistAlbums.addAll(await Future.wait(batch.map((artist) async {
          try {
            final id = artist.sourceId ?? artist.browseId;
            if (id == null || id.isEmpty) return const <MuzoItem>[];
            final uri = Uri.parse(
                '$_base/artist/$id/albums?order=$_albumOrderDesc&limit=30');
            final resp = await http.get(uri).timeout(_timeout);
            if (resp.statusCode != 200) return const <MuzoItem>[];
            final body = jsonDecode(resp.body) as Map<String, dynamic>;
            final albums = body['data'] as List? ?? [];
            return albums
                .whereType<Map>()
                .map((e) => _albumToMuzo(Map<String, dynamic>.from(e)))
                .toList();
          } catch (_) {
            return const <MuzoItem>[];
          }
        })));
      }

      // Supplement with the global album chart (when it returns data) so a
      // quiet week on top-40 discographies still fills.
      artistAlbums.add(await _chartAlbums(0));

      final merged = <String, MuzoItem>{};
      for (final list in artistAlbums) {
        for (final alb in list) {
          final key = alb.sourceId ?? alb.title.toLowerCase();
          final existing = merged[key];
          // Keep the most recent copy of a duplicate album (reissues, features).
          if (existing == null ||
              (alb.releaseDate != null &&
                  (existing.releaseDate == null ||
                      alb.releaseDate!.isAfter(existing.releaseDate!)))) {
            merged[key] = alb;
          }
        }
      }
      final dated = merged.values.where((a) => a.releaseDate != null).toList()
        ..sort((a, b) => (b.releaseDate ?? DateTime(1970))
            .compareTo(a.releaseDate ?? DateTime(1970)));
      if (dated.isEmpty) {
        _cachedPool = null;
        _poolFetchedAt = null;
        return const [];
      }
      _cachedPool = dated;
      _poolFetchedAt = now;
      return dated;
    } catch (e) {
      debugPrint('Deezer global charts error: $e');
      _cachedPool = null;
      _poolFetchedAt = null;
      return const [];
    }
  }

  /// Deezer `/chart/{genreId}/albums` (0 = worldwide). Returns [] on failure.
  Future<List<MuzoItem>> _chartAlbums(int genreId) async {
    try {
      final uri = Uri.parse('$_base/chart/$genreId/albums?limit=40');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final albums = body['data'] as List? ?? [];
      return albums
          .whereType<Map>()
          .map((e) => _albumToMuzo(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static const String _albumOrderDesc = 'DESC';

  List<List<T>> _chunks<T>(List<T> items, int size) {
    if (size <= 0) return [items];
    return <List<T>>[
      for (var i = 0; i < items.length; i += size)
        items.sublist(i, i + size > items.length ? items.length : i + size),
    ];
  }

  Future<List<int>> _genreIds() async {
    if (_cachedGenreIds != null) return _cachedGenreIds!;
    try {
      final uri = Uri.parse('$_base/genre?limit=20');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final genres = body['data'] as List? ?? [];
      final ids = genres
          .whereType<Map>()
          .map((e) => (e['id'] is int) ? (e['id'] as int) : 0)
          .where((id) => id > 0)
          .take(10)
          .toList();
      if (ids.isNotEmpty) _cachedGenreIds = ids;
      return ids;
    } catch (e) {
      debugPrint('Deezer genre error: $e');
      return const [];
    }
  }

  // ── Global charts (real current hits) ─────────────────────────────────────

  /// Real worldwide top Tracks of the moment (Deezer `/chart/0/tracks`).
  /// Metadata seeds (`dz_<id>`) that callers resolve to playable YouTube songs.
  /// Never throws.
  Future<List<MuzoItem>> topTracks({int limit = 40}) async {
    try {
      final uri = Uri.parse('$_base/chart/0/tracks?limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final tracks = body['data'] as List? ?? [];
      return tracks
          .whereType<Map>()
          .map((e) => _trackToMuzo(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('Deezer chart tracks error: $e');
      return const [];
    }
  }

  // ── Genre charts (the only in-genre keyless feed) ─────────────────────────

  /// Deezer genre ids verified to answer with genuinely in-genre content:
  /// Rap/Hip-Hop, African Music (afrobeats / afro rap / amapiano), R&B.
  /// Deezer's `/genre/{id}/artists` and `/genre/{id}/albums` paths are either
  /// invalid or ignore the id entirely, so categories and the home shelves
  /// read the per-genre CHARTS instead.
  static const int genreRapHipHop = 116;
  static const int genreAfricanMusic = 2;
  static const int genreRnbSoul = 165;

  /// Map a category / sub-category label onto a Deezer chart genre id, or null
  /// when Deezer has no chart for it (gospel, ASMR, podcasts, ambient…).
  /// Afro runs BEFORE rap so "afro rap" lands on African Music, and pop/rock
  /// are checked last so "afropop" cannot fall through to the pop chart.
  static int? chartGenreFor(String label) {
    final t = label.toLowerCase();
    bool has(String k) => t.contains(k);
    if (has('afro') ||
        has('amapiano') ||
        has('african') ||
        has('west africa') ||
        has('east africa') ||
        has('highlife') ||
        has('nigerian') ||
        has('ghana')) {
      return genreAfricanMusic;
    }
    if (has('rap') ||
        has('hip hop') ||
        has('hip-hop') ||
        has('hiphop') ||
        has('drill') ||
        has('trap') ||
        has('boom bap') ||
        has('grime') ||
        has('conscious')) {
      return genreRapHipHop;
    }
    if (has('r&b') || has('rnb') || has('soul') || has('funk')) {
      return genreRnbSoul;
    }
    if (has('reggaeton') || has('salsa') || has('latin') || has('bachata')) {
      return 197;
    }
    if (has('edm') ||
        has('electro') ||
        has('techno') ||
        has('house') ||
        has('dance')) {
      return 113;
    }
    if (has('jazz')) return 129;
    if (has('rock')) return 152;
    if (has('metal')) return 464;
    if (has('blues')) return 153;
    if (has('reggae') || has('dancehall')) return 144;
    if (has('classical')) return 98;
    if (has('brazil')) return 75;
    if (has('india')) return 81;
    if (has('k-pop') || has('kpop') || has('asian')) return 16;
    if (has('pop')) return 132;
    return null;
  }

  /// Raw rows of one genre chart — kept as JSON because the track→MuzoItem
  /// mapper drops the nested album id (album seeds need it).
  Future<List<Map<String, dynamic>>> _chartTrackRows(int genreId,
      {int limit = 25}) async {
    try {
      final uri = Uri.parse('$_base/chart/$genreId/tracks?limit=$limit');
      // This rescue call is what fills a thin section, and on the phone's
      // network it was the one that kept hitting the 10s ceiling and returned
      // nothing (the same URL answers in ~1s from a healthy connection).
      final resp = await http.get(uri).timeout(const Duration(seconds: 14));
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('Deezer genre chart error ($genreId): $e');
      return const [];
    }
  }

  /// Current hits of ONE genre (`/chart/{genreId}/tracks`) as metadata seeds.
  /// Never throws.
  Future<List<MuzoItem>> chartTracksInGenre(int genreId,
      {int limit = 25}) async {
    return (await _chartTrackRows(genreId, limit: limit))
        .map((e) => _trackToMuzo(e))
        .toList();
  }

  /// The albums behind one genre chart, hydrated from `/album/{id}` so each
  /// card carries a real `release_date` and a real Deezer album id (which is
  /// what makes AlbumScreen open with a full tracklist). Never throws.
  Future<List<MuzoItem>> albumsInGenre(int genreId, {int limit = 20}) async {
    final tracks = await _chartTrackRows(genreId, limit: 25);
    final albumIds = <String>[];
    for (final t in tracks) {
      final id = (t['album'] as Map?)?['id']?.toString() ?? '';
      if (id.isNotEmpty && !albumIds.contains(id)) albumIds.add(id);
      if (albumIds.length >= limit) break;
    }
    return _albumsByIds(albumIds);
  }

  /// Dated albums released within the last [days] days that are charting in
  /// [genreIds] — "new albums" restricted to the genres the app serves,
  /// instead of the worldwide pool that leaks pop and rock into it.
  Future<List<MuzoItem>> newAlbumsInGenres(List<int> genreIds,
      {int days = 30, int limit = 24}) async {
    final batches = await Future.wait(
        genreIds.map((id) => albumsInGenre(id, limit: 20)));
    final cutoff = DateTime.now().subtract(Duration(days: days));
    // Pre-releases and date-only timezone skew: allow a 7-day future horizon.
    final horizon = DateTime.now().add(const Duration(days: 7));
    final merged = <String, MuzoItem>{};
    for (final list in batches) {
      for (final a in list) {
        final rel = a.releaseDate;
        if (rel == null || rel.isBefore(cutoff) || rel.isAfter(horizon)) {
          continue;
        }
        final key = a.sourceId ?? a.title.toLowerCase();
        final existing = merged[key];
        if (existing == null ||
            (existing.releaseDate != null &&
                rel.isAfter(existing.releaseDate!))) {
          merged[key] = a;
        }
      }
    }
    final out = merged.values.toList()
      ..sort((a, b) => (b.releaseDate ?? DateTime(1970))
          .compareTo(a.releaseDate ?? DateTime(1970)));
    return out.take(limit).toList();
  }

  /// New SONGS inside [genreIds]: lead tracks of the albums that just came out
  /// in those genres, each stamped with its album's real `release_date`.
  Future<List<MuzoItem>> newTracksInGenres(List<int> genreIds,
      {int days = 14, int limit = 24}) async {
    final albums =
        await newAlbumsInGenres(genreIds, days: days, limit: limit);
    final out = <MuzoItem>[];
    final seen = <String>{};
    for (final batch in _chunks(albums.take(12).toList(), 4)) {
      final details = await Future.wait(batch.map((a) async {
        try {
          return await albumDetails(a.sourceId ?? a.browseId ?? '');
        } catch (_) {
          return null;
        }
      }));
      for (var i = 0; i < details.length; i++) {
        final d = details[i];
        if (d == null || d.tracks.isEmpty) continue;
        for (final t in d.tracks.take(2)) {
          final key = t.title.toLowerCase().trim();
          if (key.isEmpty || !seen.add(key)) continue;
          out.add(t.copyWith(releaseDate: batch[i].releaseDate));
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  Future<List<MuzoItem>> _albumsByIds(List<String> ids) async {
    final out = <MuzoItem>[];
    for (final batch in _chunks(ids, 4)) {
      final rows = await Future.wait(batch.map((id) async {
        try {
          final resp =
              await http.get(Uri.parse('$_base/album/$id')).timeout(_timeout);
          if (resp.statusCode != 200) return null;
          return _albumToMuzo(
              jsonDecode(resp.body) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }));
      out.addAll(rows.whereType<MuzoItem>());
    }
    return out;
  }

  /// Real worldwide top Artists of the moment (Deezer `/chart/0/artists`).
  /// Name + official cover; Deezer freshens this chart continuously, so the
  /// home row always reflects who is actually popular right now. Never throws.
  Future<List<MuzoItem>> topArtists({int limit = 40}) async {
    try {
      final uri = Uri.parse('$_base/chart/0/artists?limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final artists = body['data'] as List? ?? [];
      return artists
          .whereType<Map>()
          .map((e) => _artistToMuzo(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('Deezer chart artists error: $e');
      return const [];
    }
  }

  /// Deezer albums chart — real chart, real Deezer album ids (no fake
  /// placeholders). May return only a handful of entries (Deezer's global
  /// album chart ist thin these days) — callers fall back to a masked
  /// "dataUnavailable" state instead of inventing album popularity.
  Future<List<MuzoItem>> chartAlbums({int limit = 12}) async {
    try {
      final uri = Uri.parse('$_base/chart/0/albums?limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final albums = body['data'] as List? ?? [];
      final out = <MuzoItem>[];
      for (final e in albums.whereType<Map>()) {
        final album = _albumToMuzo(Map<String, dynamic>.from(e));
        if (album.browseId != null && album.browseId != 'dz:') {
          out.add(album);
        }
      }
      return out;
    } catch (e) {
      debugPrint('Deezer chart albums error: $e');
      return const [];
    }
  }

  // ── Album details (complete tracklist) ────────────────────────────────────

  /// Full album + its COMPLETE tracklist. Every track is a metadata seed
  /// (`dz_<id>`) with artist/cover/album backfilled; callers (AlbumScreen)
  /// resolve it to playable YouTube songs via MultiApiService before playing
  /// so "tous les sons" of the album are available. Never throws.
  Future<AlbumDetails?> albumDetails(
    String deezerId, {
    String? fallbackTitle,
    String? fallbackThumb,
  }) async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/album/$deezerId'))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final album = jsonDecode(resp.body) as Map<String, dynamic>;
      final trResp = await http
          .get(Uri.parse('$_base/album/$deezerId/tracks?limit=100'))
          .timeout(_timeout);
      final embedded = album['tracks'] is Map
          ? ((album['tracks'] as Map<String, dynamic>)['data'] as List?) ?? []
          : const <dynamic>[];
      final trackList = trResp.statusCode == 200
          ? ((jsonDecode(trResp.body) as Map<String, dynamic>)['data'] as List?)
                  ??
              embedded
          : embedded;

      final artist = album['artist'] is Map
          ? (album['artist'] as Map<String, dynamic>)['name']?.toString() ?? ''
          : '';
      final artistId = album['artist'] is Map
          ? (album['artist'] as Map<String, dynamic>)['id']?.toString()
          : null;
      final cover = album['cover_big']?.toString() ??
          album['cover_medium']?.toString() ??
          fallbackThumb ??
          '';
      final title = album['title']?.toString() ?? fallbackTitle ?? '';
      final release = album['release_date']?.toString() ?? '';
      final year = release.split('-').firstWhere(
            (s) => s.length == 4,
            orElse: () => '',
          );

      final tracks = <MuzoItem>[];
      for (final t in trackList.whereType<Map>()) {
        var base = _trackToMuzo(Map<String, dynamic>.from(t));
        if (base.title.isEmpty) continue;
        base = base.copyWith(album: MuzoAlbum(name: title, id: deezerId));
        if ((base.artists == null || base.artists!.isEmpty) &&
            artist.isNotEmpty) {
          base = base.copyWith(artists: [MuzoArtist(name: artist, id: artistId)]);
        }
        if (base.thumbnails.isEmpty && cover.isNotEmpty) {
          base = base.copyWith(
            thumbnails: [MuzoThumbnail(url: cover, width: 250, height: 250)],
          );
        }
        tracks.add(base);
      }

      return AlbumDetails(
        id: 'dz:$deezerId',
        title: title,
        artist: artist,
        year: year,
        thumbnail: cover,
        tracks: tracks,
        type: 'album',
      );
    } catch (e) {
      debugPrint('Deezer albumDetails error: $e');
      return null;
    }
  }

  // ── Playlists ──────────────────────────────────────────────────────────────

  /// Real Deezer playlists matching [query] (fan "best of", label and radio
  /// selections). The YouTube worker is the only other playlist source and it
  /// timed out on every call measured on the handset, so the artist-page shelf
  /// needs a catalog that actually answers. Ids carry a `dzpl:` prefix so
  /// [playlistDetails] can be reached without asking YouTube for a playlist
  /// that does not exist there. Never throws.
  Future<List<MuzoItem>> searchPlaylists(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
          '$_base/search/playlist?q=${Uri.encodeComponent(q)}&limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final rows =
          ((jsonDecode(resp.body) as Map<String, dynamic>)['data'] as List?) ??
              const <dynamic>[];
      final out = <MuzoItem>[];
      for (final e in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(e);
        final id = m['id']?.toString() ?? '';
        final title = m['title']?.toString() ?? '';
        if (id.isEmpty || title.isEmpty) continue;
        final cover = m['picture_big']?.toString() ??
            m['picture_medium']?.toString() ??
            '';
        final creator = m['creator'] is Map
            ? (m['creator'] as Map)['name']?.toString() ?? ''
            : '';
        out.add(MuzoItem(
          title: title,
          thumbnails: cover.isNotEmpty
              ? [MuzoThumbnail(url: cover, width: 250, height: 250)]
              : const [],
          resultType: 'playlist',
          isExplicit: false,
          browseId: 'dzpl:$id',
          videoId: null,
          artists: creator.isNotEmpty ? [MuzoArtist(name: creator)] : null,
          source: 'deezer',
          sourceId: id,
          sourceUrl: m['link']?.toString() ?? '',
          fetchedAt: DateTime.now(),
          metadata: {
            if (m['nb_tracks'] is int) 'nb_tracks': m['nb_tracks'],
          },
        ));
      }
      return out;
    } catch (e) {
      debugPrint('Deezer searchPlaylists error: $e');
      return const [];
    }
  }

  /// Full playlist + its tracklist. Tracks are `dz_` metadata seeds, exactly
  /// like [albumDetails]: callers resolve them to full-length songs before
  /// playback, the 30 s Deezer preview being the last resort. Never throws.
  Future<PlaylistDetails?> playlistDetails(
    String deezerId, {
    String? fallbackTitle,
    String? fallbackThumb,
  }) async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/playlist/$deezerId'))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final pl = jsonDecode(resp.body) as Map<String, dynamic>;

      final creator = pl['creator'] is Map
          ? (pl['creator'] as Map<String, dynamic>)['name']?.toString() ?? ''
          : '';
      final cover = pl['picture_big']?.toString() ??
          pl['picture_medium']?.toString() ??
          fallbackThumb ??
          '';
      final title = pl['title']?.toString() ?? fallbackTitle ?? '';

      final embedded = pl['tracks'] is Map
          ? ((pl['tracks'] as Map<String, dynamic>)['data'] as List?) ??
              const <dynamic>[]
          : const <dynamic>[];
      final tracks = <MuzoItem>[];
      for (final t in embedded.whereType<Map>()) {
        var base = _trackToMuzo(Map<String, dynamic>.from(t));
        if (base.title.isEmpty) continue;
        if (base.thumbnails.isEmpty && cover.isNotEmpty) {
          base = base.copyWith(
            thumbnails: [MuzoThumbnail(url: cover, width: 250, height: 250)],
          );
        }
        tracks.add(base);
      }

      // A playlist over 50 tracks only carries a `tracklist` href — one extra
      // call, still bounded, so the shelf never opens on a half-empty page.
      if (tracks.isEmpty && pl['tracklist'] is Map) {
        final href = (pl['tracklist'] as Map)['href']?.toString() ?? '';
        if (href.isNotEmpty) {
          final trResp = await http
              .get(Uri.parse('$href${href.contains('?') ? '&' : '?'}limit=100'))
              .timeout(_timeout);
          if (trResp.statusCode == 200) {
            final rows =
                ((jsonDecode(trResp.body) as Map<String, dynamic>)['data']
                        as List?) ??
                    const <dynamic>[];
            for (final t in rows.whereType<Map>()) {
              final base = _trackToMuzo(Map<String, dynamic>.from(t));
              if (base.title.isEmpty) continue;
              tracks.add(base);
            }
          }
        }
      }

      return PlaylistDetails(
        id: 'dzpl:$deezerId',
        title: title,
        author: creator,
        thumbnail: cover,
        tracks: tracks,
      );
    } catch (e) {
      debugPrint('Deezer playlistDetails error: $e');
      return null;
    }
  }

  // ── Classement national / de scène ────────────────────────────────────────

  /// Les mots qui nomment un magasin (le code Apple de deux lettres de
  /// `GenreChartSpec.countries`) dans un titre de radio Deezer. C'est une
  /// table de découverte de SOURCE, pas de contenu : aucun artiste n'y figure.
  static const Map<String, List<String>> _storefrontWords =
      <String, List<String>>{
    'fr': <String>['french', 'france', 'fr', 'français', 'française'],
    'us': <String>['us', 'usa', 'united states', 'american', 'america'],
    'ca': <String>['canada', 'canadian'],
    'gb': <String>['uk', 'united kingdom', 'british', 'grime'],
    'ng': <String>['nigeria', 'naija', 'nigerian'],
    'gh': <String>['ghana', 'ghanaian'],
    'ci': <String>['ivoire', 'ivoirien', 'ivorian'],
    'cm': <String>['cameroun', 'cameroon', 'camerounaise'],
    'bj': <String>['benin', 'bénin', 'beninese'],
    'za': <String>['south africa', 'za'],
    'ke': <String>['kenya', 'kenyan'],
    'tz': <String>['tanzania', 'tanzanian'],
  };

  static String _words(String s) {
    // Les titres Deezer sont souvent français : sans cette étape, « Rap
    // Français » devient « rap fr ais » et le mot « fr » ne se reconnaît plus.
    final folded = s.toLowerCase().replaceAllMapped(
        RegExp('[àâäéèêëîïôöùûüçñ]'), (m) => _accents[m.group(0)] ?? m.group(0)!);
    return folded.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static const Map<String, String> _accents = <String, String>{
    'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  /// Comparaison par MOTS ENTERS : « us » doit répondre dans « Rap US » et
  /// jamais dans « Future » ou « Gust ».
  static String _padded(String s) => ' ${_words(s)} ';

  /// Une radio ne couvre une ligne que si son titre cite À LA FOIS le pays de
  /// la ligne et un mot de sa scène. « Hip-hop » (sans pays) ne peut donc pas
  /// remplir « Rap FR », et « Rap US » ne remplit pas « Rap FR ».
  @visibleForTesting
  static bool sceneRadioMatch(
      String title, List<String> countries, List<String> tokens) {
    final hay = _padded(title);
    final words = <String>{
      for (final c in countries) ...(_storefrontWords[_words(c)] ?? const <String>[]),
    };
    if (words.isEmpty) return false;
    final countryHit = words.any((w) => hay.contains(_padded(w)));
    final sceneHit = tokens.any((t) => hay.contains(_padded(t)));
    return countryHit && sceneHit;
  }

  /// Index de la playlist qui porte le nom de la scène (à défaut la première
  /// assez fournie) ; -1 quand aucune ne convient.
  @visibleForTesting
  static int pickScenePlaylist(List<({String title, int nbTracks})> rows,
      List<String> tokens) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].nbTracks < 10) continue;
      if (tokens.any((t) => _padded(rows[i].title).contains(_padded(t)))) return i;
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].nbTracks >= 10) return i;
    }
    return rows.isEmpty ? -1 : 0;
  }

  static Future<List<Map<String, String>>>? _radiosFlight;

  /// La liste des radios Deezer (103 entrées, 71 ko).
  ///
  /// Single-flight : les cinq rayons de genre du Home partent en même temps et
  /// partagent cet unique appel au lieu de retélécharger chacun les 71 ko sur
  /// un uplink déjà saturé. Mesuré le 2026-10-16 sur l'appareil : les cinq
  /// lignes appelaient `/radio` en parallèle avec la page artiste ouverte,
  /// chaque requête sautait au plafond de 10 s et `sceneChart` rentrait vide.
  Future<List<Map<String, String>>> _radios() {
    return _radiosFlight ??= _loadRadios().then((rows) {
      // Une liste vide n'est pas un résultat : ne pas la mémoriser pour la
      // session entière, sinon une coupure réseau condamne le cran pour toute
      // la durée de vie du process.
      if (rows.isEmpty) _radiosFlight = null;
      return rows;
    });
  }

  Future<List<Map<String, String>>> _loadRadios() async {
    // La table est stockée sur l'appareil : elle change rarement, et c'est elle
    // qui sautait en premier sous la charge (71 ko au moment où l'uplink portait
    // déjà les cinq rayons du Home et une page artiste).
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_radiosPrefsKey);
      if (raw != null) {
        final stored = jsonDecode(raw) as Map<String, dynamic>;
        final ts = (stored['ts'] as num?)?.toInt() ?? 0;
        final cached = <Map<String, String>>[];
        for (final e in ((stored['rows'] as List?) ?? const <dynamic>[])
            .whereType<Map>()) {
          final id = e['id']?.toString() ?? '';
          final title = e['title']?.toString() ?? '';
          if (id.isNotEmpty && title.isNotEmpty) {
            cached.add({'id': id, 'title': title});
          }
        }
        final age =
            DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
        if (cached.isNotEmpty && age < _radiosTableTtl) return cached;
      }
    } catch (_) {}
    final out = <Map<String, String>>[];
    try {
      final resp =
          await http.get(Uri.parse('$_base/radio?limit=200')).timeout(_timeout);
      if (resp.statusCode == 200) {
        final rows =
            ((jsonDecode(resp.body) as Map<String, dynamic>)['data'] as List?) ??
                const <dynamic>[];
        for (final e in rows.whereType<Map>()) {
          final id = e['id']?.toString() ?? '';
          final title = e['title']?.toString() ?? '';
          if (id.isNotEmpty && title.isNotEmpty) {
            out.add({'id': id, 'title': title});
          }
        }
      }
    } catch (e) {
      debugPrint('Deezer radios error: $e');
    }
    if (out.isNotEmpty) unawaited(_storeRadios(out));
    return out;
  }

  static const String _radiosPrefsKey = 'dz.radios.v1';
  static const Duration _radiosTableTtl = Duration(days: 7);

  Future<void> _storeRadios(List<Map<String, String>> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _radiosPrefsKey,
          jsonEncode({
            'ts': DateTime.now().millisecondsSinceEpoch,
            'rows': rows,
          }));
    } catch (_) {}
  }

  /// Une étape ne doit jamais vider le rayon : ce qui a répondu dans le budget
  /// est rendu, le reste est abandonné. `null` = l'étape a dépassé son budget.
  static Future<T?> _within<T>(Future<T> fut, Duration budget) async {
    try {
      return await fut.timeout(budget);
    } on TimeoutException {
      return null;
    }
  }

  /// Les pistes d'une ressource `{id}/tracks` du catalogue Deezer.
  Future<List<MuzoItem>> _tracksOf(String path, {int limit = 30}) async {
    try {
      final sep = path.contains('?') ? '&' : '?';
      final resp = await http
          .get(Uri.parse('$_base$path$sep' 'limit=$limit'))
          .timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final rows =
          ((jsonDecode(resp.body) as Map<String, dynamic>)['data'] as List?) ??
              const <dynamic>[];
      return rows
          .whereType<Map>()
          .map((e) => _trackToMuzo(Map<String, dynamic>.from(e)))
          .where((t) => t.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Deezer tracks of $path error: $e');
      return const [];
    }
  }

  /// Le classement Deezer d'UNE scène DANS UN PAYS : la radio nationale dont le
  /// titre cite le pays et la scène (« French Rap », « Rap US »), puis, quand
  /// aucune radio ne couvre la scène (afrobeats, amapiano, afro trap…), la
  /// sélection Deezer trouvée avec le nom de la scène elle-même.
  ///
  /// Ces deux flux répondent en 2-4 s sans clé, ne listent QUE des sorties
  /// label, et — contrairement au top de ventes du magasin — tiennent compte du
  /// pays. Mesuré le 2026-10-16 depuis le réseau de l'utilisateur : le chart
  /// le plus étiqueté du Home (`rss.marketingtools.apple.com`) est injoignable
  /// (000 après 20 s) et `topSongs()` retombe sur le RSS legacy, d'où DaBaby
  /// 2020 et Diddy 2010 dans « Afro Rap » et un « Hip-hop » US rempli de rap
  /// français par le chart Deezer MONDIAL.
  ///
  /// La radio passe d'abord et n'est jamais mélangée à une radio sans pays ; le
  /// résultat est fusionné dans l'ordre, l'appelant déduplique et décide s'il
  /// suffit. Ne lève jamais.
  Future<List<MuzoItem>> sceneChart(List<String> countries, List<String> tokens,
      String sceneName,
      {int limit = 30}) async {
    // Les deux flux partent EN PARALLÈLE : chaînés l'un après l'autre, ils
    // mesuraient ~20 s pour les 14 s accordées par le provider, qui abandonnait
    // donc la ligne entière (scene=0 sur les cinq rayons, log 12:42).
    final playlistFut = _scenePlaylist(sceneName, limit);
    final merged = <MuzoItem>[
      ...await _sceneRadios(countries, tokens, limit),
    ];
    if (merged.length < limit) merged.addAll(await playlistFut);
    if (merged.isEmpty) {
      debugPrint('Deezer sceneChart: rien pour ${countries.join("+")} '
          'x « $sceneName »');
    }
    return merged.take(limit).toList();
  }

  /// Les radios qui citent À LA FOIS le pays de la ligne et un mot de sa scène.
  Future<List<MuzoItem>> _sceneRadios(
      List<String> countries, List<String> tokens, int limit) async {
    final rows = await _within(_radios(), const Duration(seconds: 6)) ??
        const <Map<String, String>>[];
    final titles = <String>[];
    final calls = <Future<List<MuzoItem>>>[];
    for (final r in rows) {
      if (!sceneRadioMatch(r['title'] ?? '', countries, tokens)) continue;
      titles.add(r['title'] ?? '');
      calls.add(_tracksOf('/radio/${r['id']}/tracks', limit: limit));
      // Trois radios au plus : l'uplink porte déjà les cinq rayons du Home.
      if (calls.length == 3) break;
    }
    if (calls.isEmpty) return const [];
    final lists = await _within(Future.wait(calls), const Duration(seconds: 6)) ??
        const <List<MuzoItem>>[];
    final merged = <MuzoItem>[];
    for (var i = 0; i < lists.length; i++) {
      if (lists[i].isEmpty) continue;
      debugPrint('Deezer sceneChart: radio « ${titles[i]} » -> '
          '${lists[i].length} pistes');
      merged.addAll(lists[i]);
    }
    return merged;
  }

  /// À défaut de radio nationale (afrobeats, amapiano, afro trap… n'en ont
  /// pas) : la sélection Deezer trouvée avec le nom de la scène elle-même.
  Future<List<MuzoItem>> _scenePlaylist(String sceneName, int limit) async {
    final found = await _within(searchPlaylists(sceneName, limit: 8),
            const Duration(seconds: 5)) ??
        const <MuzoItem>[];
    // Ce sont les MOTS DE LA SCÈNE demandée qui arbitrent (« afrobeats » doit
    // gagner sur « Best Of 2020 »), pas les étiquettes du magasin : « afro » ne
    // se lit pas comme « afrobeats » en comparaison par mot entier.
    final picked = pickScenePlaylist([
      for (final p in found)
        (
          title: p.title,
          nbTracks: p.metadata?['nb_tracks'] is int
              ? p.metadata!['nb_tracks'] as int
              : 0
        ),
    ], _words(sceneName).split(' '));
    if (picked < 0 || picked >= found.length) return const [];
    final pl = found[picked];
    final details = await _within(
        playlistDetails(pl.sourceId ?? '', fallbackTitle: pl.title),
        const Duration(seconds: 5));
    final tracks = (details?.tracks ?? const <MuzoItem>[])
        .where((t) => t.title.isNotEmpty)
        .toList();
    if (tracks.isNotEmpty) {
      debugPrint('Deezer sceneChart: playlist « ${pl.title} » -> '
          '${tracks.length} pistes');
    }
    return tracks;
  }

  // ── Mapping ───────────────────────────────────────────────────────────────

  MuzoItem _albumToMuzo(Map<String, dynamic> a) {
    final artist = a['artist'] as Map?;
    final albumId = a['id']?.toString() ?? '';
    final title = a['title']?.toString() ?? '';
    final cover =
        a['cover_medium']?.toString() ?? a['cover_big']?.toString() ?? '';
    final rel = a['release_date']?.toString();
    final nbTracks = a['nb_tracks'] is int ? a['nb_tracks'] as int : null;
    // Search / artist-albums expose `record_type` (album|single|ep);
    // full album detail exposes `album_type`. Never use `type` — that is
    // always the resource kind ("album"), not the record kind.
    final recordType =
        a['record_type']?.toString() ?? a['album_type']?.toString();
    return MuzoItem(
      title: title,
      thumbnails: cover.isNotEmpty
          ? [MuzoThumbnail(url: cover, width: 250, height: 250)]
          : const [],
      resultType: 'album',
      isExplicit: false,
      // dz: prefix tells AlbumScreen to load the full tracklist from Deezer.
      browseId: albumId.isEmpty ? null : 'dz:$albumId',
      videoId: null,
      artists: artist != null && artist['name'] != null
          ? [MuzoArtist(name: artist['name'].toString(), id: artist['id']?.toString())]
          : null,
      album: MuzoAlbum(name: title, id: albumId),
      releaseDate: rel != null ? DateTime.tryParse(rel) : null,
      source: 'deezer',
      sourceId: albumId,
      sourceUrl: a['link']?.toString() ?? '',
      fetchedAt: DateTime.now(),
      metadata: {
        if (nbTracks != null) 'nb_tracks': nbTracks,
        if (recordType != null) 'album_type': recordType,
        if (recordType != null) 'record_type': recordType,
      },
    );
  }

  /// Albums of one artist, ordered by release date DESC — the only Deezer
  /// list endpoint that returns real `release_date` values. Used so
  /// "Nouveaux albums" can trust dates instead of undated search hits.
  Future<List<MuzoItem>> albumsForArtist(String artistName,
      {int limit = 12}) async {
    final q = artistName.trim();
    if (q.isEmpty) return const [];
    try {
      final searchUri = Uri.parse(
          '$_base/search/artist?q=${Uri.encodeComponent(q)}&limit=1');
      final searchResp = await http.get(searchUri).timeout(_timeout);
      if (searchResp.statusCode != 200) return const [];
      final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final artists = searchData['data'] as List? ?? [];
      if (artists.isEmpty) return const [];
      final first = artists.first as Map<String, dynamic>;
      final id = first['id']?.toString();
      final name = first['name']?.toString() ?? q;
      if (id == null || id.isEmpty) return const [];

      final uri = Uri.parse(
          '$_base/artist/$id/albums?order=release_date%20DESC&limit=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final albums = body['data'] as List? ?? [];
      return albums
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            // Artist albums omit the nested artist — stamp the resolved name.
            if (m['artist'] == null) {
              m['artist'] = {'id': id, 'name': name};
            }
            return _albumToMuzo(m);
          })
          .where((a) => a.browseId != null && a.browseId != 'dz:')
          .toList();
    } catch (e) {
      debugPrint('Deezer albumsForArtist error: $e');
      return const [];
    }
  }

  /// The artist's own catalogue as TITLE SEEDS: `/artist/{id}/albums`
  /// (albums + singles, newest first) then each release's tracklist, deduped
  /// by title. The artist page needs 100+ tracks but the YouTube backend
  /// search answers ~40 per query, so the discography is where the extra
  /// titles come from — Deezer returns a real one per release instead of
  /// guessing from a keyword search.
  ///
  /// Seeds carry a `dz_` id (Deezer previews are 30 s clips), so callers must
  /// resolve them to full tracks before playback. Never throws.
  Future<List<MuzoItem>> tracksForArtist(String artistName,
      {int maxTitles = 200}) async {
    final q = artistName.trim();
    if (q.isEmpty) return const [];
    try {
      final searchUri = Uri.parse(
          '$_base/search/artist?q=${Uri.encodeComponent(q)}&limit=1');
      final searchResp = await http.get(searchUri).timeout(_timeout);
      if (searchResp.statusCode != 200) return const [];
      final artists =
          (jsonDecode(searchResp.body) as Map)['data'] as List? ?? [];
      if (artists.isEmpty) return const [];
      final first = Map<String, dynamic>.from(artists.first as Map);
      final artistId = first['id']?.toString();
      final artistLabel = first['name']?.toString() ?? q;
      if (artistId == null || artistId.isEmpty) return const [];

      final releasesUri = Uri.parse(
          '$_base/artist/$artistId/albums'
          '?filter=albums%2Csingles&order=release_date%20DESC&limit=50');
      final releasesResp = await http.get(releasesUri).timeout(_timeout);
      if (releasesResp.statusCode != 200) return const [];
      final releases =
          ((jsonDecode(releasesResp.body) as Map)['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      if (releases.isEmpty) return const [];

      final out = <MuzoItem>[];
      final seenTitles = <String>{};
      // 4 releases in flight: a 50-wide burst trips Deezer's rate limit and
      // the whole call answers empty. 30 releases ≈ 250 distinct titles.
      for (final batch in _chunks(releases.take(30).toList(), 4)) {
        final trackLists = await Future.wait(batch.map((rel) async {
          final relId = rel['id']?.toString() ?? '';
          if (relId.isEmpty) return const <MuzoItem>[];
          try {
            final r = await http
                .get(Uri.parse('$_base/album/$relId/tracks?limit=40'))
                .timeout(_timeout);
            if (r.statusCode != 200) return const <MuzoItem>[];
            final rows =
                (jsonDecode(r.body) as Map)['data'] as List? ?? [];
            return rows.whereType<Map>().map((e) {
              final t = Map<String, dynamic>.from(e);
              // Backfill what a per-album row may omit, so every seed shows
              // the artist and cover the page's rows are built from.
              t['artist'] ??= {'id': artistId, 'name': artistLabel};
              t['album'] ??= {
                'id': rel['id'],
                'title': rel['title'],
                'cover_medium': rel['cover_medium'],
              };
              return _trackToMuzo(t);
            }).toList();
          } catch (_) {
            return const <MuzoItem>[];
          }
        }));
        for (final list in trackLists) {
          for (final t in list) {
            final key = t.title.toLowerCase().trim();
            if (key.isEmpty || !seenTitles.add(key)) continue;
            out.add(t);
            if (out.length >= maxTitles) return out;
          }
        }
      }
      debugPrint('Deezer tracksForArtist: "$q" -> ${out.length} titles');
      return out;
    } catch (e) {
      debugPrint('Deezer tracksForArtist error: $e');
      return const [];
    }
  }

  /// Fill missing `releaseDate` on search hits via `/album/{id}` (batched).
  /// Genre/artist search never returns dates; without this, undated catalog
  /// (e.g. Gims 2013) would pass every "recent" window filter.
  Future<List<MuzoItem>> hydrateAlbumDates(List<MuzoItem> albums,
      {int max = 24}) async {
    final out = <MuzoItem>[];
    final pending = albums.take(max).toList();
    for (final batch in _chunks(pending, 4)) {
      final hydrated = await Future.wait(batch.map((a) async {
        if (a.releaseDate != null) return a;
        final id = a.sourceId ?? '';
        if (id.isEmpty) return a;
        try {
          final resp = await http
              .get(Uri.parse('$_base/album/$id'))
              .timeout(_timeout);
          if (resp.statusCode != 200) return a;
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final rel = body['release_date']?.toString();
          final nb = body['nb_tracks'] is int ? body['nb_tracks'] as int : null;
          final rec = body['record_type']?.toString() ??
              body['album_type']?.toString();
          final date = rel != null ? DateTime.tryParse(rel) : null;
          if (date == null && nb == null && rec == null) return a;
          return a.copyWith(
            releaseDate: date ?? a.releaseDate,
            metadata: {
              ...?a.metadata,
              if (nb != null) 'nb_tracks': nb,
              if (rec != null) 'album_type': rec,
              if (rec != null) 'record_type': rec,
            },
          );
        } catch (_) {
          return a;
        }
      }));
      out.addAll(hydrated);
    }
    // Keep any beyond the hydrate cap (still undated, caller may drop them).
    if (albums.length > max) out.addAll(albums.skip(max));
    return out;
  }

  MuzoItem _artistToMuzo(Map<String, dynamic> a) {
    final name = a['name']?.toString() ?? '';
    final pic = a['picture_xl']?.toString() ??
        a['picture_big']?.toString() ??
        a['picture_medium']?.toString() ??
        '';
    final id = a['id']?.toString() ?? '';
    return MuzoItem(
      title: name,
      thumbnails: pic.isNotEmpty
          ? [MuzoThumbnail(url: pic, width: 500, height: 500)]
          : const [],
      resultType: 'artist',
      isExplicit: false,
      browseId: id.isEmpty ? null : id,
      videoId: null,
      artists: name.isNotEmpty
          ? [MuzoArtist(name: name, id: id.isEmpty ? null : id)]
          : null,
      source: 'deezer',
      sourceId: id.isEmpty ? null : id,
      sourceUrl: a['link']?.toString() ?? '',
      fetchedAt: DateTime.now(),
    );
  }

  MuzoItem _trackToMuzo(Map<String, dynamic> t) {
    final artist = t['artist'] as Map?;
    final album = t['album'] as Map?;
    final cover =
        album?['cover_medium']?.toString() ?? album?['cover_big']?.toString() ?? '';
    final dur = t['duration'] is int ? (t['duration'] as int?) ?? 0 : 0;
    final id = t['id']?.toString() ?? '';
    final artistName = artist?['name']?.toString() ?? '';
    final albumName = album?['title']?.toString() ?? '';
    final artistId = artist?['id']?.toString();
    // Deezer's public API only ever carries a 30s clip, never the full file.
    // It travels in `metadata.dzPreview` rather than in `audioUrl`, so the
    // track keeps looking like the metadata seed it is (YouTube resolution
    // stays the preferred path) while `MultiApiService` can still fall back to
    // it: a Deezer title YouTube cannot match used to be dropped and the shelf
    // lost it. With the clip it stays listed AND audible.
    final preview = t['preview']?.toString() ?? '';
    return MuzoItem(
      title: t['title']?.toString() ?? '',
      thumbnails: cover.isNotEmpty
          ? [MuzoThumbnail(url: cover, width: 250, height: 250)]
          : const [],
      resultType: 'song',
      isExplicit: t['explicit_lyrics'] == true,
      // Metadata-only id (dz_ prefix) keeps it out of isActuallyPlayable —
      // like it_ singles — until it is resolved to a full YouTube track.
      videoId: id.isEmpty ? null : 'dz_$id',
      durationSeconds: dur,
      duration: dur > 0
          ? '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}'
          : null,
      artists: artistName.isNotEmpty
          ? [MuzoArtist(name: artistName, id: artistId)]
          : null,
      album: albumName.isNotEmpty ? MuzoAlbum(name: albumName, id: '') : null,
      audioUrl: null,
      metadata: preview.isEmpty
          ? null
          : {'dzPreview': preview},
      source: 'deezer',
      sourceId: id,
      sourceUrl: t['link']?.toString() ?? '',
      fetchedAt: DateTime.now(),
    );
  }
}