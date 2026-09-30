import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/album_details.dart';
import 'package:muzo/models/muzo_item.dart';

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
      source: 'deezer',
      sourceId: id,
      sourceUrl: t['link']?.toString() ?? '',
      fetchedAt: DateTime.now(),
    );
  }
}