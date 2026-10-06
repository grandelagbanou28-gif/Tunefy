import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/discovery_models.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/category_curator.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/itunes_api_service.dart';
import 'package:muzo/services/musicbrainz_service.dart';
import 'package:muzo/services/trending_service.dart';
import 'package:muzo/utils/period_utils.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService(
    deezer: ref.read(deezerApiServiceProvider),
    cache: ContentCacheService.instance,
    musicBrainz: ref.read(musicBrainzServiceProvider),
  );
});

/// Aggregates the four discovery sections (new releases, new albums,
/// popular artists of previous month, popular albums of previous month)
/// from real catalog sources. Never invents popularity statistics: when a
/// source provides no trustworthy popularity data for the period, the
/// corresponding section is marked `dataUnavailable`.
class DiscoveryService {
  final DeezerApiService deezer;
  final ContentCacheService cache;
  final ItunesApiService itunes;
  final MusicBrainzService musicBrainz;

  /// Refresh policy, per shelf:
  ///  * new releases / new albums → every day;
  ///  * the Sunday "recommendation of the day" → expires at the next midnight;
  ///  * every other category (artists, podcasts…) → every 2 days.
  static const Duration cacheTtl = ContentCacheService.twoDayTtl;
  static const Duration dailyCacheTtl = ContentCacheService.dailyTtl;
  static const Duration emptyCacheTtl = Duration(minutes: 2);

  /// TTL for one specific shelf, overridable per call.
  static Duration ttlForKey(String key) {
    if (key.contains('newReleases') ||
        key.contains('newAlbums') ||
        key.contains('popularArtists') ||
        key.contains('popularAlbums')) {
      return dailyCacheTtl;
    }
    if (key.contains('sunday') || key.contains('Sunday')) {
      return ContentCacheService.sundayTtl();
    }
    return cacheTtl;
  }

  DiscoveryService({
    required this.deezer,
    required this.cache,
    ItunesApiService? itunes,
    MusicBrainzService? musicBrainz,
  })  : itunes = itunes ?? ItunesApiService(),
        musicBrainz = musicBrainz ?? MusicBrainzService();

  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, dynamic> _memory = {};

  Future<T?> _readCache<T>(String key) async {
    final at = _fetchedAt[key];
    if (at == null) return null;
    final value = _memory[key];
    final isEmpty = value is DiscoverySection && value.items.isEmpty;
    final ttl = isEmpty ? emptyCacheTtl : ttlForKey(key);
    if (DateTime.now().difference(at) < ttl) {
      return value as T?;
    }
    return null;
  }

  void _writeCache<T>(String key, T value) {
    _memory[key] = value;
    _fetchedAt[key] = DateTime.now();
  }

  /// Drop a cached empty/error section so pull-to-refresh actually refetches.
  void invalidate(String key) {
    _memory.remove(key);
    _fetchedAt.remove(key);
  }

  // ─── Real monthly history ────────────────────────────────────────────────
  //
  // There is no free API that serves last month's artist chart. Deezer's
  // `/chart/0` is the chart of the moment, Apple RSS has no history, and
  // Spotify's editorial charts need an authenticated session. So the only way
  // to end up with a *real* "artists of the past month" is to start recording:
  // each fetch appends today's chart to a 35-day history, and the monthly view
  // is then computed from what this device actually observed. It is empty until
  // enough days have passed — and that is honest, where a fabricated ranking
  // would not be.

  static const String _chartHistoryBox = 'chart_history';
  static const int _chartHistoryDays = 35;

  Future<void> _appendChartHistory(List<String> names) async {
    if (names.isEmpty) return;
    try {
      final box = Hive.isBoxOpen(_chartHistoryBox)
          ? Hive.box(_chartHistoryBox)
          : await Hive.openBox(_chartHistoryBox);
      final day = ContentCacheService.dayBucket;
      await box.put(day, names.take(60).toList());
      // Keep the window bounded: one key per day, 35 days.
      final cutoff = day - _chartHistoryDays;
      for (final k in box.keys.cast<String>().toList()) {
        final parsed = int.tryParse(k.replaceAll('d', ''));
        if (parsed != null && parsed < cutoff) await box.delete(k);
      }
    } catch (_) {
      // History is an enrichment; never let it break the current chart.
    }
  }

  /// Names ranked by how often they showed up over the recorded window, most
  /// frequent first. Returns an empty list until the history is long enough to
  /// mean anything.
  Future<List<String>> recordedMonthlyRanking({int minDays = 7}) async {
    try {
      final box = Hive.isBoxOpen(_chartHistoryBox)
          ? Hive.box(_chartHistoryBox)
          : await Hive.openBox(_chartHistoryBox);
      final days = box.keys
          .cast<String>()
          .where((k) => box.get(k) is List)
          .toList();
      if (days.length < minDays) return const [];
      final score = <String, int>{};
      for (final k in days) {
        final positions = (box.get(k) as List).cast<String>();
        for (var rank = 0; rank < positions.length; rank++) {
          // A top-10 appearance is worth more than a top-50 one.
          final name = positions[rank];
          score[name] = (score[name] ?? 0) + (positions.length - rank);
        }
      }
      final ranked = score.entries.toList()
        ..sort((a, b) {
          final byScore = b.value.compareTo(a.value);
          return byScore != 0 ? byScore : a.key.compareTo(b.key);
        });
      return ranked.take(30).map((e) => e.key).toList();
    } catch (_) {
      return const [];
    }
  }

  void invalidateNewContent() {
    final day = 'd${ContentCacheService.dayBucket}';
    for (final k in _memory.keys.toList()) {
      // popularArtists / popularAlbums are day-bucketed charts too: drop them
      // as well, otherwise "Artistes/Albums populaires" kept the old snapshot
      // for the whole 48h TTL and looked frozen.
      if (k.startsWith('discovery|newReleases|$day') ||
          k.startsWith('discovery|newAlbums|$day') ||
          k.startsWith('discovery|popularArtists') ||
          k.startsWith('discovery|popularAlbums')) {
        invalidate(k);
      }
    }
  }

  /// Nouvelles sorties — albums released in the last 7 days.
  /// Disk snapshot rolls every calendar day (never a multi-day-old shelf).
  /// Sources: Deezer (dated discographies) + MusicBrainz (first-release
  /// calendar) + Apple RSS tops with real `im:releaseDate`.
  Future<DiscoverySection<MuzoItem>> fetchNewReleases({
    DiscoveryPeriod? period,
  }) async {
    final p = period ?? last7Days();
    final key =
        'discovery|newReleases|d${ContentCacheService.dayBucket}|${p.id}';
    final cached = await _readCache<DiscoverySection<MuzoItem>>(key);
    if (cached != null) return cached;

    try {
      final raw = await _mergeReleaseSources(days: 7, rssLimit: 16, mbLimit: 40);
      final items = _filterAndSort(raw, p);
      final section = DiscoverySection<MuzoItem>(
        title: 'Nouvelles sorties',
        period: p,
        items: items,
      );
      _writeCache(key, section);
      if (items.isNotEmpty) await _persist(key, items);
      return section;
    } catch (e) {
      debugPrint('DiscoveryService newReleases error: $e');
      final stale = await _restoreMuzo(
            key,
            p,
            'Nouvelles sorties',
            maxAge: ContentCacheService.dailyTtl,
          ) ??
          await _restoreRecentSection(
            'discovery|newReleases',
            suffix: '|${p.id}',
            period: p,
            title: 'Nouvelles sorties',
          );
      if (stale != null) return stale;
      return DiscoverySection<MuzoItem>(
        title: 'Nouvelles sorties',
        period: p,
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Nouveaux albums — albums released in the last 30 days.
  /// Disk snapshot rolls every calendar day (never a multi-day-old shelf).
  Future<DiscoverySection<MuzoItem>> fetchNewAlbums({
    DiscoveryPeriod? period,
  }) async {
    final p = period ?? last30Days();
    final key =
        'discovery|newAlbums|d${ContentCacheService.dayBucket}|${p.id}';
    final cached = await _readCache<DiscoverySection<MuzoItem>>(key);
    if (cached != null) return cached;

    try {
      final raw = await _mergeReleaseSources(days: 30, rssLimit: 20, mbLimit: 50);
      final items = _filterAndSort(raw, p);
      final section = DiscoverySection<MuzoItem>(
        title: 'Nouveaux albums',
        period: p,
        items: items,
      );
      _writeCache(key, section);
      if (items.isNotEmpty) await _persist(key, items);
      return section;
    } catch (e) {
      debugPrint('DiscoveryService newAlbums error: $e');
      final stale = await _restoreMuzo(
            key,
            p,
            'Nouveaux albums',
            maxAge: ContentCacheService.dailyTtl,
          ) ??
          await _restoreRecentSection(
            'discovery|newAlbums',
            suffix: '|${p.id}',
            period: p,
            title: 'Nouveaux albums',
          );
      if (stale != null) return stale;
      return DiscoverySection<MuzoItem>(
        title: 'Nouveaux albums',
        period: p,
        errorMessage: e.toString(),
      );
    }
  }

  /// Parallel multi-source harvest. Individual sources never throw.
  Future<List<MuzoItem>> _mergeReleaseSources({
    required int days,
    required int rssLimit,
    required int mbLimit,
  }) async {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final horizon = now.add(const Duration(days: 7));

    Future<List<MuzoItem>> safe(Future<List<MuzoItem>> f) async {
      try {
        return await f.timeout(const Duration(seconds: 14));
      } catch (_) {
        return const <MuzoItem>[];
      }
    }

    final batches = await Future.wait([
      safe(days <= 7
          ? deezer.newReleases(days: days, limit: 40)
          : deezer.recentAlbums(days: days, limit: 40)),
      safe(musicBrainz.releasesBetween(cutoff, horizon, limit: mbLimit)),
      safe(_rssAlbums(cutoff: cutoff, horizon: horizon, limit: rssLimit)),
    ]);

    final merged = <String, MuzoItem>{};
    for (final list in batches) {
      for (final item in list) {
        final id = item.sourceId ?? item.browseId ?? item.videoId;
        final key = id != null && id.isNotEmpty
            ? 'id:$id'
            : normalizeContentKey(item) ?? item.title.toLowerCase();
        if (key.isEmpty || merged.containsKey(key)) continue;
        final rel = item.releaseDate;
        if (rel == null) continue;
        if (rel.isBefore(cutoff.subtract(const Duration(days: 1)))) continue;
        if (rel.isAfter(horizon)) continue;
        merged[key] = item;
      }
    }
    return merged.values.toList();
  }

  /// Apple RSS top albums across major storefronts with real release dates.
  Future<List<MuzoItem>> _rssAlbums({
    required DateTime cutoff,
    required DateTime horizon,
    required int limit,
  }) async {
    const stores = <String>['fr', 'us', 'ng', 'bj', 'gb', 'de'];
    final out = <MuzoItem>[];
    final seen = <String>{};
    for (final cc in stores) {
      if (out.length >= limit) break;
      final batch = await TrendingService.topAlbums(cc);
      for (final a in batch) {
        if (out.length >= limit) break;
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

  /// Artistes populaires du mois précédent — backed by the REAL Deezer
  /// `/chart/0/artists` (worldwide popularity, refreshed by Deezer).
  /// popularityScore is derived from the artist's real chart rank, so a
  /// higher rank always means a higher score — never invented stats. If the
  /// chart is unreachable the section is marked `dataUnavailable` (masked
  /// rather than faked).
  Future<DiscoverySection<PopularArtist>> fetchPopularArtists({
    DiscoveryPeriod? period,
  }) async {
    final p = period ?? previousMonth();
    // Day bucket in the key: Deezer refreshes these charts continuously, so a
    // bucket-less key pinned the shelf to one snapshot for the full 48h TTL —
    // the row looked frozen for days. The bucket rolls it over every day.
    final key = 'discovery|popularArtists|d${ContentCacheService.dayBucket}';
    final cached = await _readCache<DiscoverySection<PopularArtist>>(key);
    if (cached != null) return cached;

    try {
      final chart = await deezer.topArtists(limit: 60);
      if (chart.isEmpty) {
        final section = DiscoverySection<PopularArtist>(
          title: 'Artistes populaires',
          period: p,
          availability: SectionAvailability.dataUnavailable,
        );
        _writeCache(key, section);
        return section;
      }

      final items = <PopularArtist>[];
      final seen = <String>{};
      for (final (i, r) in chart.indexed) {
        final name = r.title;
        if (name.isEmpty || seen.contains(name.toLowerCase())) continue;
        seen.add(name.toLowerCase());
        items.add(PopularArtist(
          name: name,
          imageUrl: r.thumbnails.isNotEmpty ? r.thumbnails.first.url : null,
          artistId: r.sourceId ?? r.browseId,
          popularityScore:
              (chart.length - i) / chart.length, // real chart-rank derived
        ));
        if (items.length >= 20) break;
      }

      final section = DiscoverySection<PopularArtist>(
        title: 'Artistes populaires',
        period: p,
        items: items,
      );
      _writeCache(key, section);
      if (items.isNotEmpty) {
        unawaited(cache.writeJson(key, items.map((i) => i.toJson()).toList()));
        // Record today's chart so a real past-month ranking can be built from
        // what this device actually saw, instead of pretending Deezer serves
        // history (it does not).
        unawaited(_appendChartHistory(items.map((i) => i.name).toList()));
      }
      return section;
    } catch (e) {
      debugPrint('DiscoveryService popularArtists error: $e');
      final maps = await _restoreRecentBucket('discovery|popularArtists');
      if (maps != null) {
        final items = maps.map((m) => PopularArtist.fromJson(m)).toList();
        if (items.isNotEmpty) {
          return DiscoverySection<PopularArtist>(
            title: 'Artistes populaires',
            period: p,
            items: items,
          );
        }
      }
      return DiscoverySection<PopularArtist>(
        title: 'Artistes populaires',
        period: p,
        availability: SectionAvailability.dataUnavailable,
      );
    }
  }

  /// Albums populaires du mois précédent — real Deezer global album chart
  /// (`/chart/0/albums`). popularityScore derived from real chart rank.
  /// Same honesty rule as artists: dataUnavailable if the chart is empty
  /// or unreachable, never fabricated rankings.
  Future<DiscoverySection<PopularAlbum>> fetchPopularAlbums({
    DiscoveryPeriod? period,
  }) async {
    final p = period ?? previousMonth();
    // Day bucket, same reason as popularArtists above.
    final key = 'discovery|popularAlbums|d${ContentCacheService.dayBucket}';
    final cached = await _readCache<DiscoverySection<PopularAlbum>>(key);
    if (cached != null) return cached;

    try {
      final chart = await deezer.chartAlbums(limit: 20);
      if (chart.isEmpty) {
        final section = DiscoverySection<PopularAlbum>(
          title: 'Albums populaires',
          period: p,
          availability: SectionAvailability.dataUnavailable,
        );
        _writeCache(key, section);
        return section;
      }

      final items = <PopularAlbum>[];
      final seen = <String>{};
      for (final (i, r) in chart.indexed) {
        final k = (r.browseId ?? r.title).toLowerCase();
        if (k.isEmpty || seen.contains(k)) continue;
        seen.add(k);
        items.add(PopularAlbum(
          title: r.title,
          artistName: r.artists?.isNotEmpty == true
              ? r.artists!.first.name
              : null,
          coverUrl: r.thumbnails.isNotEmpty ? r.thumbnails.first.url : null,
          albumId: r.browseId ?? r.sourceId,
          releaseDate: r.releaseDate,
          popularityScore: (chart.length - i) / chart.length,
        ));
        if (items.length >= 20) break;
      }

      final section = DiscoverySection<PopularAlbum>(
        title: 'Albums populaires',
        period: p,
        items: items,
      );
      _writeCache(key, section);
      if (items.isNotEmpty) {
        unawaited(cache.writeJson(key, items.map((i) => i.toJson()).toList()));
      }
      return section;
    } catch (e) {
      debugPrint('DiscoveryService popularAlbums error: $e');
      final maps = await _restoreRecentBucket('discovery|popularAlbums');
      if (maps != null) {
        final items = maps.map((m) => PopularAlbum.fromJson(m)).toList();
        if (items.isNotEmpty) {
          return DiscoverySection<PopularAlbum>(
            title: 'Albums populaires',
            period: p,
            items: items,
          );
        }
      }
      return DiscoverySection<PopularAlbum>(
        title: 'Albums populaires',
        period: p,
        availability: SectionAvailability.dataUnavailable,
      );
    }
  }

  /// Dedupes by sourceId then artist+title, filters to [period], sorts
  /// newest-first. Song cards (non-album/non-artist) must also pass
  /// [isActuallyPlayable] so the shelf never shows dead iTunes/Spotify
  /// placeholders without a streamable audioUrl.
  /// Rolling windows keep undated items only as a last resort when the
  /// shelf would otherwise be empty (filled by the caller via a second pass).
  List<MuzoItem> _filterAndSort(List<MuzoItem> raw, DiscoveryPeriod p) {
    final seen = <String>{};
    final dated = <MuzoItem>[];
    final undated = <MuzoItem>[];
    for (final item in raw) {
      final id = item.sourceId ?? item.browseId ?? item.videoId;
      final key = id != null && id.isNotEmpty
          ? 'id:$id'
          : normalizeContentKey(item) ?? item.title.toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;

      final isSongShelf = item.resultType == 'song' ||
          item.resultType == 'video' ||
          item.resultType == 'user_track';
      if (isSongShelf && !isActuallyPlayable(item)) continue;

      final rel = item.releaseDate;
      final rolling = p.id == 'last7Days' || p.id == 'last30Days';
      if (rel == null) {
        if (!rolling) continue;
        seen.add(key);
        undated.add(item);
        continue;
      }
      if (!p.contains(rel)) continue;

      seen.add(key);
      dated.add(item);
    }
    // Prefer strictly dated releases — undated only pad a thin shelf.
    final out = dated.length >= 5 ? dated : [...dated, ...undated];
    out.sort((a, b) {
      final da = a.releaseDate;
      final db = b.releaseDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return out;
  }

  Future<void> _persist(String key, List<MuzoItem> items) async {
    try {
      await cache.writeJson(key, items.map((i) => i.toJson()).toList());
    } catch (_) {}
  }

  Future<DiscoverySection<MuzoItem>?> _restoreMuzo(
    String key,
    DiscoveryPeriod p,
    String title, {
    Duration? maxAge,
  }) async {
    try {
      final raw = await cache.readJsonIfFresh(key, maxAge: maxAge);
      if (raw == null || raw.isEmpty) return null;
      final items = raw
          .whereType<Map>()
          .map((m) => MuzoItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      return DiscoverySection<MuzoItem>(
        title: title,
        period: p,
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  /// Offline fallback for every disk-persisted shelf: replays the newest
  /// snapshot found in this bucket or the previous [days] ones. Day buckets
  /// roll every midnight even with no network to refill them, so restoring
  /// only the current bucket would still leave shelves empty offline.
  Future<List<Map<String, dynamic>>?> _restoreRecentBucket(
    String base, {
    String suffix = '',
    int days = 7,
  }) async {
    final bucket = ContentCacheService.dayBucket;
    for (var d = bucket; d > bucket - days; d--) {
      try {
        final raw = await cache.readJsonIfFresh(
          '$base|d$d$suffix',
          maxAge: ContentCacheService.staleCeiling,
        );
        if (raw != null && raw.isNotEmpty) {
          return raw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      } catch (_) {}
    }
    return null;
  }

  /// Offline fallback for the release shelves: same-bucket snapshot first,
  /// then previous days, so the shelf survives a dead network.
  Future<DiscoverySection<MuzoItem>?> _restoreRecentSection(
    String base, {
    String suffix = '',
    required DiscoveryPeriod period,
    required String title,
    int days = 7,
  }) async {
    final maps =
        await _restoreRecentBucket(base, suffix: suffix, days: days);
    if (maps == null) return null;
    final items = maps.map((m) => MuzoItem.fromJson(m)).toList();
    if (items.isEmpty) return null;
    return DiscoverySection<MuzoItem>(
      title: title,
      period: period,
      items: items,
    );
  }
}
