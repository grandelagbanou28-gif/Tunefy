import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/content_cache_service.dart';

final musicBrainzServiceProvider = Provider<MusicBrainzService>((ref) {
  return MusicBrainzService();
});

/// MusicBrainz API — free, no key needed. Metadata + search.
class MusicBrainzService {
  static const _base = 'https://musicbrainz.org/ws/2';
  static const _timeout = Duration(seconds: 12);
  static const _ua = 'MuzoTunefy/1.0 ( contact@muzo.app )';

  final Map<String, MusicBrainzArtist?> _artistCache = {};

  Future<List<MuzoItem>> searchTracks(String query) async {
    try {
      final uri = Uri.parse(
          '$_base/recording/?query=${Uri.encodeComponent(query)}&fmt=json&limit=20');
      final resp =
          await http.get(uri, headers: {'User-Agent': _ua}).timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final data = json.decode(resp.body);
      final recordings = data['recordings'] as List? ?? [];
      return recordings.map<MuzoItem>((r) {
        final title = r['title'] ?? '';
        final artistCredits = r['artist-credit'] as List? ?? [];
        final artist =
            artistCredits.isNotEmpty ? artistCredits[0]['name'] ?? '' : '';
        final durationMs = r['length'] as int? ?? 0;
        return MuzoItem(
          videoId: null,
          title: '$title - $artist',
          artists: [MuzoArtist(name: artist, id: null)],
          thumbnails: [],
          resultType: 'video',
          isExplicit: false,
          durationSeconds: durationMs > 0 ? (durationMs / 1000).round() : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('MusicBrainz search error: $e');
      return [];
    }
  }

  // ── Dated releases (authoritative first-release calendar) ─────────────────

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Releases with a MusicBrainz `releasedate` inside `[from, to]`
  /// (inclusive). Results are disk-cached for the current UTC day so the
  /// shelves roll every calendar day without hammering MusicBrainz
  /// (1 req/s rate limit). Filtered to Album/EP primary types, no
  /// compilation/live/broadcast secondary types, and no single-track
  /// releases.
  Future<List<MuzoItem>> releasesBetween(
    DateTime from,
    DateTime to, {
    int limit = 80,
  }) async {
    final key =
        'mb|rel|${_iso(from)}..${_iso(to)}|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .whereType<Map>()
            .map((m) => MuzoItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}

    final out = <MuzoItem>[];
    try {
      final query = 'releasedate:[${_iso(from)} TO ${_iso(to)}]';
      final uri = Uri.parse(
          '$_base/release/?query=${Uri.encodeComponent(query)}'
          '&fmt=json&limit=$limit');
      final resp =
          await http.get(uri, headers: {'User-Agent': _ua}).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('MusicBrainz releasesBetween HTTP ${resp.statusCode}');
        return const [];
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final releases = data['releases'] as List? ?? const [];
      for (final raw in releases) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final title = (m['title'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        final primary = (m['primary-type'] as String? ?? '').toLowerCase();
        if (primary.isNotEmpty &&
            primary != 'album' &&
            primary != 'ep') {
          continue;
        }
        final secondaries = (m['secondary-types'] as List? ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toSet();
        if (secondaries.contains('compilation') ||
            secondaries.contains('live') ||
            secondaries.contains('broadcast') ||
            secondaries.contains('remix') ||
            secondaries.contains('soundtrack')) {
          continue;
        }
        final dateStr = (m['date'] as String? ?? '').trim();
        final date = dateStr.isEmpty ? null : DateTime.tryParse(dateStr);
        if (date == null) continue;
        // Single-track / single-medium releases are not "albums".
        final formats = (m['formats'] as List? ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toSet();
        if (formats.contains('single') && formats.length == 1) continue;
        final mediumCount = m['medium-count'];
        if (mediumCount is int && mediumCount <= 0) continue;
        final trackCounts = m['medium-track-counts'] as List?;
        if (trackCounts != null) {
          var total = 0;
          for (final c in trackCounts) {
            if (c is int) total += c;
          }
          if (total == 1) continue;
        }
        final credits = m['artist-credit'] as List? ?? const [];
        final artists = <MuzoArtist>[];
        for (final c in credits) {
          if (c is! Map) continue;
          final name = (c['name'] as String? ?? '').trim();
          if (name.isEmpty) continue;
          final id = (c['artist'] as Map?)?['id']?.toString();
          artists.add(MuzoArtist(name: name, id: id));
        }
        if (artists.isEmpty) continue;
        out.add(MuzoItem(
          title: title,
          thumbnails: const [],
          resultType: 'album',
          isExplicit: false,
          artists: artists,
          releaseDate: date,
          source: 'musicbrainz',
          sourceId: (m['id'] as String?) ?? '',
          metadata: {
            'primary_type': primary,
            'country': m['country']?.toString() ?? '',
          },
          fetchedAt: DateTime.now(),
        ));
        if (out.length >= limit) break;
      }
    } catch (e) {
      debugPrint('MusicBrainz releasesBetween error: $e');
      return out;
    }
    if (out.isNotEmpty) {
      await ContentCacheService.instance
          .writeJson(key, out.map((e) => e.toJson()).toList());
    }
    return out;
  }

  /// Recent recordings (singles/tracks) released in [from, to]. The album feed
  /// alone misses songs that came out without a parent album, so this is the
  /// dedicated "new songs" source. Same disk cache and rate-limit care as
  /// [releasesBetween].
  Future<List<MuzoItem>> recentRecordings(
    DateTime from,
    DateTime to, {
    int limit = 80,
  }) async {
    final key =
        'mb|rec|${_iso(from)}..${_iso(to)}|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .whereType<Map>()
            .map((m) => MuzoItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}

    final out = <MuzoItem>[];
    try {
      final query = 'releasedate:[${_iso(from)} TO ${_iso(to)}]';
      final uri = Uri.parse(
          '$_base/recording/?query=${Uri.encodeComponent(query)}'
          '&fmt=json&limit=$limit');
      final resp =
          await http.get(uri, headers: {'User-Agent': _ua}).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('MusicBrainz recentRecordings HTTP ${resp.statusCode}');
        return const [];
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final recordings = data['recordings'] as List? ?? const [];
      for (final raw in recordings) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final title = (m['title'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        final dateStr = (m['date'] as String? ?? '').trim();
        final date = dateStr.isEmpty ? null : DateTime.tryParse(dateStr);
        if (date == null) continue;
        final credits = m['artist-credit'] as List? ?? const [];
        final artists = <MuzoArtist>[];
        for (final c in credits) {
          if (c is! Map) continue;
          final name = (c['name'] as String? ?? '').trim();
          if (name.isEmpty) continue;
          final id = (c['artist'] as Map?)?['id']?.toString();
          artists.add(MuzoArtist(name: name, id: id));
        }
        if (artists.isEmpty) continue;
        out.add(MuzoItem(
          title: title,
          thumbnails: const [],
          resultType: 'track',
          isExplicit: false,
          artists: artists,
          releaseDate: date,
          source: 'musicbrainz',
          sourceId: (m['id'] as String?) ?? '',
          fetchedAt: DateTime.now(),
        ));
        if (out.length >= limit) break;
      }
    } catch (e) {
      debugPrint('MusicBrainz recentRecordings error: $e');
      return out;
    }
    if (out.isNotEmpty) {
      await ContentCacheService.instance
          .writeJson(key, out.map((e) => e.toJson()).toList());
    }
    return out;
  }

  // ── Artist validation (geo + genre evidence) ──────────────────────────────

  static const Map<String, String> _countryName = {
    'US': 'usa',
    'GB': 'uk',
    'FR': 'france',
    'BJ': 'benin',
    'NG': 'nigeria',
    'GH': 'ghana',
    'ZA': 'south africa',
    'KE': 'kenya',
    'TZ': 'east africa',
    'UG': 'east africa',
    'RW': 'east africa',
    'ET': 'east africa',
    'SN': 'west africa',
    'ML': 'west africa',
    'CI': 'west africa',
    'TG': 'west africa',
    'BF': 'west africa',
    'CM': 'africa',
    'CG': 'africa',
    'CD': 'africa',
    'JM': 'caribbean',
    'TT': 'caribbean',
    'BB': 'caribbean',
    'HT': 'caribbean',
    'CU': 'caribbean',
    'DO': 'caribbean',
    'PR': 'caribbean',
    'BR': 'brazil',
    'IN': 'india',
  };

  /// Look up one artist: country/area + genres. Cached per name in memory.
  ///
  /// [preferGeo] (a canonical country key like "benin") breaks homonym ties:
  /// MusicBrainz answers up to five hits for a stage name and the plain
  /// `limit=1` lookup used to take whichever the index happened to rank first,
  /// so "Sidiki" (Côte d'Ivoire) could be graded against "Sidiki" (Belgium).
  /// With no hint the old behaviour stands — first hit, one request.
  Future<MusicBrainzArtist?> findArtist(String name, {String? preferGeo}) async {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final hint = (preferGeo ?? '').trim().toLowerCase();
    final cacheKey = hint.isEmpty ? trimmed : '$trimmed|$hint';
    if (_artistCache.containsKey(cacheKey)) return _artistCache[cacheKey];
    try {
      final uri = Uri.parse(
          '$_base/artist/?query=${Uri.encodeComponent('artist:"$name"')}'
          // `inc=tags` is what makes the genre evidence exist: measured on
          // 2026-10-11, the plain search answer carries NO tags at all
          // (Soolking → []), while the same single request with inc=tags
          // returns ['french','hip hop','rap']. One extra query param, no
          // extra round trip — the 1 req/s limit stays untouched.
          '&fmt=json&inc=tags&limit=${hint.isEmpty ? 1 : 5}');
      final resp =
          await http.get(uri, headers: {'User-Agent': _ua}).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final artists = data['artists'] as List? ?? [];
      if (artists.isEmpty) {
        _artistCache[cacheKey] = null;
        return null;
      }
      final hits = <MusicBrainzArtist>[];
      for (final raw in artists.whereType<Map>()) {
        final a = Map<String, dynamic>.from(raw);
        final area = a['area'] as Map?;
        final country = a['country']?.toString() ??
            area?['country-code']?.toString() ??
            '';
        final genres = <String>[
          for (final g in (a['genres'] as List? ?? []))
            if (g is Map) g['name']?.toString() ?? '',
          for (final g in (a['tags'] as List? ?? []))
            if (g is Map) g['name']?.toString() ?? '',
        ].where((s) => s.isNotEmpty).toList();
        hits.add(MusicBrainzArtist(
          name: a['name']?.toString() ?? '',
          country: country,
          area: area?['name']?.toString(),
          sortName: a['sort-name']?.toString(),
          genres: genres.toSet().toList(),
        ));
      }
      if (hits.isEmpty) {
        _artistCache[cacheKey] = null;
        return null;
      }
      var pick = hits.first;
      if (hint.isNotEmpty) {
        // A hit the caller's country claims wins; a same-name recording artist
        // beats any other only when nothing matches the country.
        final byGeo = hits.where((h) => _geoContains(hint, _geoKeyFor(h)));
        final exact = hits.where((h) => _norm(h.name) == _norm(name));
        pick = byGeo.isNotEmpty
            ? byGeo.first
            : (exact.isNotEmpty ? exact.first : hits.first);
      }
      _artistCache[cacheKey] = pick;
      return pick;
    } catch (e) {
      debugPrint('MusicBrainz findArtist error: $e');
      _artistCache[cacheKey] = null;
      return null;
    }
  }

  /// The canonical country key MusicBrainz reports for [a] ("BJ" → "benin").
  String _geoKeyFor(MusicBrainzArtist a) =>
      _countryName[a.country.toUpperCase()] ?? '';

  /// Authoritative rescue for a strict-gate rejection: keep only candidates
  /// whose artist MusicBrainz places in the section's country. When the
  /// database says the artist is from somewhere *else*, a matching genre is
  /// deliberately not enough — that is how Nigerian gospel used to leak back
  /// into "Gospel Bénin" through the rescue meant to save it. Genre evidence
  /// alone still counts when the artist has no country on record at all.
  Future<List<MuzoItem>> rescueMatches(
    List<MuzoItem> candidates, {
    required String geo,
    String? genre,
  }) async {
    final out = <MuzoItem>[];
    for (final item in candidates.take(6)) {
      final artist = item.artists?.isNotEmpty == true
          ? item.artists!.first.name
          : item.displayArtist.trim().split(RegExp(r'\s+-\s+')).first;
      if (artist.trim().isEmpty) continue;
      final info = await findArtist(artist, preferGeo: geo);
      if (info == null) continue;
      final evidence = <String>[];
      // '' = the database gives no country for this artist (not "another one").
      final artistGeo = info.country.isEmpty ? '' : _geoKeyFor(info);
      final countryConfirmed =
          artistGeo.isNotEmpty && _geoContains(geo, artistGeo);
      if (countryConfirmed) evidence.add('country:${info.country}');
      final g = _norm(genre ?? '');
      var genreConfirmed = false;
      if (g.isNotEmpty) {
        for (final mbGenre in info.genres) {
          if (_norm(mbGenre).contains(g) || g.contains(_norm(mbGenre))) {
            genreConfirmed = true;
            evidence.add('genre:$mbGenre');
            break;
          }
        }
      }
      if (countryConfirmed || (genreConfirmed && artistGeo.isEmpty)) {
        out.add(item.copyWith(
          verified: true,
          relevanceScore: 85,
          metadata: {'musicbrainz': evidence},
        ));
      }
    }
    return out;
  }

  bool _geoContains(String geo, String country) {
    final g = geo.trim().toLowerCase();
    if (g == country) return true;
    switch (g) {
      case 'west africa':
        return const {'benin', 'nigeria', 'ghana'}.contains(country);
      case 'east africa':
        return const {'east africa', 'kenya'}.contains(country);
      case 'africa':
        return const {
          'benin',
          'nigeria',
          'ghana',
          'south africa',
          'kenya',
          'east africa',
          'west africa',
        }.contains(country);
      case 'caribbean':
        return const {'caribbean', 'jamaica'}.contains(country);
      default:
        return false;
    }
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u00e0-\u00ff]'), '')
      .trim();
}

/// Verified evidence about one artist from the MusicBrainz database.
class MusicBrainzArtist {
  final String name;
  final String country;
  final String? area;
  final String? sortName;
  final List<String> genres;

  const MusicBrainzArtist({
    this.name = '',
    this.country = '',
    this.area,
    this.sortName,
    this.genres = const [],
  });
}
