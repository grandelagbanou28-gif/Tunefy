import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/data/curated_new_releases_2026.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/trending_service.dart';

class ReleaseItem {
  final String id;
  final String provider;
  final String externalId;
  final String title;
  final String? artistName;
  final String? artistId;
  final DateTime? releaseDate;
  final String? coverUrl;
  final String contentType;
  final String? countryCode;
  final double popularityScore;
  final bool verified;

  const ReleaseItem({
    required this.id,
    required this.provider,
    required this.externalId,
    required this.title,
    this.artistName,
    this.artistId,
    this.releaseDate,
    this.coverUrl,
    required this.contentType,
    this.countryCode,
    this.popularityScore = 0,
    this.verified = false,
  });

  factory ReleaseItem.fromMuzo(MuzoItem item, {String? countryCode}) {
    final cover = item.thumbnails.isNotEmpty ? item.thumbnails.first.url : null;
    final artist = item.artists?.isNotEmpty == true
        ? item.artists!.first.name
        : (item.displayArtist != 'Unknown' ? item.displayArtist : null);
    final artistId = item.artists?.isNotEmpty == true
        ? item.artists!.first.id
        : null;
    var type = item.resultType;
    if (type == 'video' || type == 'song' || type == 'track' || type == 'user_track') {
      type = 'track';
    } else if (type == 'album' || type == 'playlist') {
      type = 'album';
    } else if (type == 'artist' || type == 'channel') {
      type = 'artist';
    } else if (item.releaseDate != null && item.browseId?.startsWith('dz:') == true) {
      type = 'album';
    } else {
      type = 'track';
    }
    return ReleaseItem(
      id: item.sourceId ?? item.browseId ?? item.videoId ?? item.title,
      provider: item.source ?? 'local',
      externalId: item.sourceId ?? item.browseId ?? '',
      title: item.title,
      artistName: artist,
      artistId: artistId,
      releaseDate: item.releaseDate,
      coverUrl: cover,
      contentType: type,
      countryCode: countryCode,
      popularityScore: 0,
      verified: item.verified,
    );
  }

  factory ReleaseItem.fromJson(Map<String, dynamic> j) {
    DateTime? parsed;
    final raw = j['release_date'];
    if (raw is String && raw.isNotEmpty) {
      parsed = DateTime.tryParse(raw);
    }
    return ReleaseItem(
      id: j['id'] as String? ?? '',
      provider: j['provider'] as String? ?? '',
      externalId: j['external_id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      artistName: j['artist_name'] as String?,
      artistId: j['artist_id'] as String?,
      releaseDate: parsed,
      coverUrl: j['cover_url'] as String?,
      contentType: j['content_type'] as String? ?? 'track',
      countryCode: j['country_code'] as String?,
      popularityScore: (j['popularity_score'] as num?)?.toDouble() ?? 0,
      verified: j['verified'] as bool? ?? false,
    );
  }
}

class ReleaseResponse {
  final bool success;
  final List<ReleaseItem> data;
  final String? nextCursor;
  final bool hasMore;

  const ReleaseResponse({
    required this.success,
    required this.data,
    this.nextCursor,
    this.hasMore = false,
  });

  factory ReleaseResponse.fromJson(Map<String, dynamic> j) {
    final items = ((j['data'] as List?) ?? const [])
        .map((e) => ReleaseItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return ReleaseResponse(
      success: j['success'] as bool? ?? false,
      data: items,
      nextCursor: j['next_cursor'] as String?,
      hasMore: j['has_more'] as bool? ?? false,
    );
  }
}

/// Builds release lists from real in-app sources (Deezer genre charts +
/// Apple RSS). Replaces the old localhost:8091 backend that never ran on
/// the device, which left every New Releases / New Albums shelf empty.
class ReleasesService {
  ReleasesService._();

  static const _timeout = Duration(seconds: 14);

  /// Rap FR / rap US / afro (plus R&B, which those shelves always blended in).
  static const List<int> _urbanGenres = <int>[
    DeezerApiService.genreRapHipHop,
    DeezerApiService.genreRnbSoul,
    DeezerApiService.genreAfricanMusic,
  ];

  static Future<List<MuzoItem>> _safe(Future<List<MuzoItem>> f) async {
    try {
      return await f.timeout(_timeout);
    } catch (_) {
      return const <MuzoItem>[];
    }
  }

  static Future<ReleaseResponse> fetch({
    String type = 'all',
    String period = 'today',
    String? country,
    int limit = 100,
    String? cursor,
    int page = 0,
    List<String> searchHistory = const [],
  }) async {
    final now = DateTime.now();
    final cutoff = switch (period) {
      'today' => DateTime(now.year, now.month, now.day),
      'week' => now.subtract(const Duration(days: 7)),
      'month' => now.subtract(const Duration(days: 30)),
      _ => now.subtract(const Duration(days: 7)),
    };
    final horizon = now.add(const Duration(days: 7));
    final wantTracks = type == 'all' || type == 'track';
    final wantAlbums = type == 'all' || type == 'album';
    final wantArtists = type == 'all' || type == 'artist';

    // Each "Charger plus" page widens every source by one more batch, so the
    // feed keeps growing instead of stopping at the first 100 items.
    final scale = page + 1;

    final deezer = DeezerApiService();

    final futures = <Future<List<MuzoItem>>>[
      // Urban-only catalogue windows. Deezer's worldwide release pool and
      // MusicBrainz's open first-release calendar are genre-agnostic, which is
      // what used to leak pop, rock and gospel reissues into these feeds.
      if (wantAlbums || wantTracks)
        _safe(wantAlbums
            ? deezer.newAlbumsInGenres(
                _urbanGenres, days: 30, limit: 50 * scale)
            : deezer.newTracksInGenres(
                _urbanGenres, days: 7, limit: 40 * scale)),
      if (wantTracks)
        _safe(deezer.newTracksInGenres(
            _urbanGenres, days: 7, limit: 40 * scale)),
      if (wantAlbums)
        _safe(_rssAlbums(cutoff.subtract(const Duration(days: 7)), horizon)),
      if (wantArtists)
        _safe(deezer.topArtists(limit: 30 * scale)),
    ];

    final batches = await Future.wait(futures);
    final merged = <String, ReleaseItem>{};

    // Curated web-verified seeds first (albums + tracks with real dates) so
    // New Albums / New Releases is never empty when live feeds are thin.
    if (wantAlbums || wantTracks) {
      for (final c in curatedNewReleases2026) {
        if (!curatedIsFresh(c, window: const Duration(days: 14))) continue;
        if (!isUrbanOrAfroRelease(c)) continue;
        if (c.title.trim().isEmpty || c.title.trim() == c.artist.trim()) continue;
        final isAlbum = c.event == 'album';
        if (isAlbum && !wantAlbums) continue;
        if (!isAlbum && !wantTracks) continue;
        if (type != 'all' && type != (isAlbum ? 'album' : 'track')) continue;
        final release = ReleaseItem(
          id: 'curated|${c.artist}|${c.title}',
          provider: 'curated',
          externalId: '',
          title: c.title,
          artistName: c.artist,
          releaseDate: c.releasedAt,
          contentType: isAlbum ? 'album' : 'track',
          countryCode: country,
          verified: true,
        );
        final k = '${release.contentType}|${release.id}';
        if (!merged.containsKey(k)) merged[k] = release;
      }
    }

    for (final list in batches) {
      for (final item in list) {
        final rel = item.releaseDate;
        if (rel != null) {
          if (rel.isBefore(cutoff.subtract(const Duration(days: 1)))) continue;
          if (rel.isAfter(horizon)) continue;
        }
        final release = ReleaseItem.fromMuzo(item, countryCode: country);
        if (release.title.trim().isEmpty) continue;
        if (type != 'all' && release.contentType != type) continue;
        final k = release.id.isNotEmpty
            ? '${release.contentType}|${release.id}'
            : '${release.contentType}|${release.title}|${release.artistName}';
        if (merged.containsKey(k)) continue;
        merged[k] = release;
      }
    }

    var items = merged.values.toList()
      ..sort((a, b) {
        // Artists the user has searched for (Ninho, …) jump to the very top,
        // then the usual geo/genre boost, then newest first in-tier.
        final pa = _releasePriority(a) + _searchBoost(a, searchHistory);
        final pb = _releasePriority(b) + _searchBoost(b, searchHistory);
        if (pa != pb) return pb.compareTo(pa);
        final da = a.releaseDate;
        final db = b.releaseDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    // A full page means the sources still have more to give; a short page (or a
    // bounded source such as the curated list) ends the feed.
    final hasMore = items.length >= limit;
    if (items.length > limit) {
      items = items.sublist(0, limit);
    }

    return ReleaseResponse(
      success: items.isNotEmpty,
      data: items,
      hasMore: hasMore,
    );
  }

  static Future<List<MuzoItem>> _rssAlbums(DateTime cutoff, DateTime horizon) async {
    // Wide storefront coverage: a release that is "new" in one country is often
    // still charting in another, so the union catches far more of the week's
    // real output than a single feed.
    const stores = [
      'fr', 'us', 'gb', 'de', 'it', 'es', 'pt', 'be', 'ch', 'ca', 'au', 'nz',
      'ng', 'bj', 'ci', 'gh', 'cm', 'sn', 'cd', 'za', 'ke', 'ml', 'tg',
    ];
    final out = <MuzoItem>[];
    final seen = <String>{};
    for (final cc in stores) {
      if (out.length >= 60) break;
      final batch = await TrendingService.topAlbums(cc);
      for (final a in batch) {
        if (out.length >= 60) break;
        // New Releases is a rap / R&B / afro shelf: the storefront feeds mix
        // in pop, rock and soundtrack reissues that have nothing to do with it.
        if (!TrendingService.isUrbanGenre(a.genre)) continue;
        final rel = a.releaseDate;
        if (rel == null || rel.isBefore(cutoff) || rel.isAfter(horizon)) {
          continue;
        }
        final k = '${a.title}|${a.artist}'.toLowerCase();
        if (!seen.add(k)) continue;
        out.add(MuzoItem(
          title: a.title,
          thumbnails: a.cover.isNotEmpty
              ? [MuzoThumbnail(url: a.cover, width: 300, height: 300)]
              : const [],
          resultType: 'album',
          isExplicit: false,
          artists: [MuzoArtist(name: a.artist)],
          releaseDate: rel,
          source: 'itunes rss',
          sourceId: k,
          fetchedAt: DateTime.now(),
        ));
      }
    }
    return out;
  }

  /// Same geo/genre boost as Home's Nouvelles sorties (rap FR/US/afro,
  /// Bénin / CI / NG first) so New Releases screens match the home shelf.
  static int _releasePriority(ReleaseItem r) {
    final hay =
        '${r.title} ${r.artistName ?? ''} ${r.countryCode ?? ''}'.toLowerCase();
    var score = 0;
    const regions = <String>[
      'bénin', 'benin', 'bj', 'nigeria', 'nigerian', 'ng',
      "côte d'ivoire", 'cote d\'ivoire', 'ci', 'ivorian', 'ivoirien',
      'abidjan', 'lagos', 'congo', 'congolais', 'ghana', 'gh', 'cameroun',
    ];
    const genres = <String>[
      'rap', 'hip-hop', 'hip hop', 'drill', 'trap', 'afro', 'afrobeats',
      'amapiano', 'gospel',
    ];
    var region = false;
    for (final x in regions) {
      if (hay.contains(x)) {
        score += 55;
        region = true;
        break;
      }
    }
    if (hay.contains('bj') ||
        hay.contains('ci') ||
        hay.contains('ng') ||
        hay.contains('bénin') ||
        hay.contains('benin') ||
        hay.contains('abidjan') ||
        hay.contains('lagos') ||
        hay.contains('nigeria')) {
      score += 35;
    }
    var genre = false;
    for (final g in genres) {
      if (hay.contains(g)) {
        score += 40;
        genre = true;
        break;
      }
    }
    if (region && genre) score += 30;
    return score;
  }

  /// Releases from artists the user has actually searched for outrank
  /// everything else: the feed follows listening intent, not just the charts.
  static int _searchBoost(ReleaseItem r, List<String> searches) {
    if (searches.isEmpty) return 0;
    final hay = '${r.title} ${r.artistName ?? ''}'.toLowerCase();
    for (final q in searches) {
      final query = q.trim().toLowerCase();
      if (query.isEmpty) continue;
      if (hay.contains(query)) return 1000;
    }
    return 0;
  }

  static Future<ReleaseResponse> fetchAll({
    String? country,
    int limit = 100,
  }) =>
      fetch(type: 'all', period: 'month', country: country, limit: limit);

  static Future<ReleaseResponse> fetchTracks({
    String? country,
    int limit = 100,
  }) =>
      fetch(type: 'track', period: 'month', country: country, limit: limit);

  static Future<ReleaseResponse> fetchAlbums({
    String? country,
    int limit = 100,
  }) =>
      fetch(type: 'album', period: 'month', country: country, limit: limit);

  static Future<ReleaseResponse> fetchArtists({
    String? country,
    int limit = 100,
  }) =>
      fetch(type: 'artist', period: 'month', country: country, limit: limit);
}

final releasesServiceProvider = Provider<ReleasesService>((ref) {
  return ReleasesService._();
});
