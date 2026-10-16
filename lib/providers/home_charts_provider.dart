import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/trending_service.dart';

/// Editorial data for the "Découvrir tout" home block, 100% YouTube-playable.
///
/// Backed by Apple's public RSS storefronts (real per-country top songs,
/// albums and playlists) whose entries are resolved to playable YouTube
/// items through muzoapi — exactly like the Charts category pipeline. No
/// third-party streaming service (Deezer, etc.) is involved any more.
class HomeCharts {
  final List<MuzoItem> tracks;
  final List<MuzoItem> albums;
  final List<MuzoItem> playlists;

  const HomeCharts({
    this.tracks = const [],
    this.albums = const [],
    this.playlists = const [],
  });
}

/// Bumped by the Home pull-to-refresh: a refresh must hit the network even
/// when today's disk snapshot is still fresh, otherwise the gesture is a no-op.
final homeChartsRefreshNonce = StateProvider<int>((ref) => 0);

final homeChartsProvider = FutureProvider<HomeCharts>((ref) async {
  final api = ref.read(muzoApiServiceProvider);
  final bucket = ContentCacheService.refreshBucket;
  final day = ContentCacheService.dayBucket;
  final nonce = ref.watch(homeChartsRefreshNonce);

  Future<List<MuzoItem>?> fromCache(String name) async {
    if (nonce > 0) return null; // explicit refresh → network
    try {
      final raw = await ContentCacheService.instance
          .readJsonIfFresh('homecharts|$name|d$day');
      if (raw != null && raw.isNotEmpty) {
        return raw
            .whereType<Map>()
            .map((m) => MuzoItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
    return null;
  }

  Future<void> persist(String name, List<MuzoItem> items) async {
    try {
      await ContentCacheService.instance
          .writeJson('homecharts|$name|d$day', items.map((i) => i.toJson()).toList());
    } catch (_) {}
  }

  /// Offline fallback: replays the newest snapshot found in the previous
  /// buckets. Only consulted when today's bucket AND the network both came
  /// back empty, so online freshness is untouched.
  Future<List<MuzoItem>> fromRecentBuckets(String name) async {
    for (var d = day - 1; d > day - 7; d--) {
      try {
        final raw = await ContentCacheService.instance.readJsonIfFresh(
          'homecharts|$name|d$d',
          maxAge: ContentCacheService.staleCeiling,
        );
        if (raw != null && raw.isNotEmpty) {
          final items = raw
              .whereType<Map>()
              .map((m) => MuzoItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          if (items.isNotEmpty) return items;
        }
      } catch (_) {}
    }
    return const [];
  }

  /// One entry per wanted entity: [query] is the string sent to the worker,
  /// [title]/[artist] are what the source feed actually named. The worker
  /// answers with the closest match it has, never with a guarantee, so the
  /// answer is checked against them instead of being trusted — see
  /// [matchesNamedEntity].
  Future<List<MuzoItem>> resolveInBatches(
    List<({String query, String title, String artist})> wanted,
    String filter, {
    bool song = false,
  }) async {
    final out = <MuzoItem>[];
    final seenIds = <String>{};
    var rejected = 0;
    for (var i = 0; i < wanted.length; i += 5) {
      final chunk = wanted.skip(i).take(5).toList();
      final results = await Future.wait(chunk.map((w) async {
        try {
          final resp = await api
              .search(w.query, filter: filter)
              .timeout(const Duration(seconds: 9));
          for (final r in resp.results) {
            if (song) {
              if (r.videoId == null) continue;
            } else if ((r.browseId ?? r.videoId) == null) {
              continue;
            }
            if (!matchesNamedEntity(r, w.title, w.artist)) {
              rejected++;
              continue;
            }
            return r;
          }
        } catch (_) {}
        return null;
      }));
      for (final r in results.whereType<MuzoItem>()) {
        final idKey = (r.videoId ?? r.browseId ?? '${r.title}|${r.displayArtist}')
            .toLowerCase();
        if (idKey.isEmpty || seenIds.contains(idKey)) continue;
        seenIds.add(idKey);
        out.add(r);
      }
      if (out.length >= 20) break;
    }
    if (rejected > 0) {
      debugPrint('HomeCharts/$filter: $rejected look-alike results rejected '
          '(${out.length} kept)');
    }
    return out;
  }

  // Offline: replay today's snapshot (or the newest previous bucket) and
  // never reach for Apple RSS / muzoapi, which cannot answer right now.
  if (await ContentCacheService.isOffline()) {
    Future<List<MuzoItem>> offlineBucket(String name) async {
      try {
        final today = await ContentCacheService.instance.readJsonIfFresh(
          'homecharts|$name|d$day',
          maxAge: ContentCacheService.offlineCeiling,
        );
        if (today != null && today.isNotEmpty) {
          return today
              .whereType<Map>()
              .map((m) => MuzoItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      } catch (_) {}
      return await fromRecentBuckets(name);
    }

    final buckets = await Future.wait([
      offlineBucket('tracks'),
      offlineBucket('albums'),
      offlineBucket('playlists'),
    ]);
    return HomeCharts(
      tracks: buckets[0],
      albums: buckets[1],
      playlists: buckets[2],
    );
  }

  // ─── Tracks / Albums / Playlists — resolved in parallel so one slow
  // section never blocks the others. Each section has its own deadline. ───
  Future<List<MuzoItem>> resolveTracks() async {
    var cached = await fromCache('tracks');
    if (cached != null) return cached;
    try {
      final pool = await Future.wait(
              [TrendingService.topSongs('fr'), TrendingService.topSongs('us')])
          .timeout(const Duration(seconds: 12));
      final seen = <String>{};
      final wanted = <({String query, String title, String artist})>[];
      for (final list in pool) {
        for (final t in list) {
          final k = '${t.title}|${t.artist}'.toLowerCase();
          if (seen.contains(k)) continue;
          seen.add(k);
          wanted.add(
              (query: '${t.title} ${t.artist}', title: t.title, artist: t.artist));
          if (wanted.length >= 24) break;
        }
      }
      final result = await resolveInBatches(wanted, 'songs', song: true);
      if (result.isNotEmpty) {
        await persist('tracks', result);
        return result;
      }
    } catch (_) {}
    return await fromRecentBuckets('tracks');
  }

  Future<List<MuzoItem>> resolveAlbums() async {
    var cached = await fromCache('albums');
    if (cached != null) return cached;
    try {
      final pool = await Future.wait([
        TrendingService.topAlbums('fr'),
        TrendingService.topAlbums('us')
      ]).timeout(const Duration(seconds: 12));
      // Ce rayon s'intitule « Nouveaux albums » alors qu'Apple RSS donne ici le
      // TOP des ventes, pas les sorties : mesuré sur l'appareil (2026-10-15),
      // « Deux frères » (PNL, 2019) et « Dans la légende » (PNL, 2016) y
      // passaient pour des nouveautés. La fenêtre de 30 jours est la même que
      // celle du rayon Nouveaux albums de l'accueil, et une sortie sans date
      // réelle n'est pas une nouveauté vérifiable → elle est écartée.
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final horizon = DateTime.now().add(const Duration(days: 7));
      final seen = <String>{};
      final wanted = <({String query, String title, String artist})>[];
      var undated = 0;
      for (final list in pool) {
        for (final a in list) {
          if (!TrendingService.isUrbanGenre(a.genre)) continue;
          final rel = a.releaseDate;
          if (rel == null || rel.isBefore(cutoff) || rel.isAfter(horizon)) {
            undated++;
            continue;
          }
          final k = '${a.title}|${a.artist}'.toLowerCase();
          if (seen.contains(k)) continue;
          seen.add(k);
          wanted.add(
              (query: '${a.title} ${a.artist}', title: a.title, artist: a.artist));
          if (wanted.length >= 12) break;
        }
      }
      debugPrint('HomeCharts/albums: ${wanted.length} dated in the 30d window, '
          '$undated dropped (old or undated)');
      final result = await resolveInBatches(wanted, 'albums');
      if (result.isNotEmpty) {
        await persist('albums', result);
        return result;
      }
    } catch (_) {}
    return await fromRecentBuckets('albums');
  }

  Future<List<MuzoItem>> resolvePlaylists() async {
    var cached = await fromCache('playlists');
    if (cached != null) return cached;
    try {
      final pool = await Future.wait([
        TrendingService.topPlaylists('fr'),
        TrendingService.topPlaylists('us'),
      ]).timeout(const Duration(seconds: 12));
      final seen = <String>{};
      final wanted = <({String query, String title, String artist})>[];
      for (final list in pool) {
        for (final p in list) {
          final k = p.title.toLowerCase();
          if (seen.contains(k)) continue;
          seen.add(k);
          wanted.add((query: p.title, title: p.title, artist: ''));
          if (wanted.length >= 12) break;
        }
      }
      final result = await resolveInBatches(wanted, 'playlists');
      if (result.isNotEmpty) {
        await persist('playlists', result);
        return result;
      }
    } catch (_) {}
    return await fromRecentBuckets('playlists');
  }

  final results = await Future.wait([
    resolveTracks(),
    resolveAlbums(),
    resolvePlaylists(),
  ]).timeout(const Duration(seconds: 35), onTimeout: () => const [
    <MuzoItem>[],
    <MuzoItem>[],
    <MuzoItem>[],
  ]);

  final rotated = ContentCacheService.rotate;
  return HomeCharts(
    tracks: rotated(results[0], bucket),
    albums: rotated(results[1], bucket),
    playlists: rotated(results[2], bucket),
  );
});
