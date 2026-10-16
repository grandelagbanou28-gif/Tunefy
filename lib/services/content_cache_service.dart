import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:muzo/utils/net_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent content cache for category sub-sections.
///
/// Every resolved sub-section is stored on disk together with its save time.
/// A cached entry is served instantly while it is younger than [ttl], so pages
/// open immediately and still refresh on their own.
class ContentCacheService {
  ContentCacheService._();

  static final ContentCacheService instance = ContentCacheService._();

  /// Shelf disk fallback: serves the cached snapshot when it is still younger
  /// than [ttl] (default [browseTtl]) so a category/shelf stays identical for
  /// three days instead of reshuffling on every launch; refreshes only once the
  /// window passes. Runs [fetch], persists non-empty wins, and replays the
  /// last-known snapshot (up to [staleCeiling]) when the network fails or
  /// comes back empty — so home shelves keep showing their last content
  /// offline instead of vanishing.
  ///
  /// "New" shelves (new releases / daily picks) pass a shorter [ttl]
  /// ([dailyTtl]) so they still renew every day.
  ///
  /// When [isOffline] is true the fetch is skipped entirely and the last
  /// snapshot is replayed at once: offline, network calls would only burn
  /// seconds on timeouts before ending on the very same fallback.
  ///
  /// Bodies wrapped in this must not call `ref.watch` after their first
  /// await (the watch would fire after init and throw); use `ref.read`
  /// inside.
  static Future<List<MuzoItem>> shelfCached(
    String key,
    Future<List<MuzoItem>> Function() fetch, {
    Duration? ttl,
  }) async {
    if (await isOffline()) {
      return await instance.readStale(key, maxAge: offlineCeiling) ??
          <MuzoItem>[];
    }
    // Fresh window first: within [ttl] the shelf is served straight from disk
    // and does not touch the network, so content is stable for three days.
    final cached = await instance.readIfFresh(key, maxAge: ttl ?? browseTtl);
    if (cached != null) return cached;
    try {
      final fresh = await fetch();
      if (fresh.isNotEmpty) {
        unawaited(instance.write(key, fresh));
        return fresh;
      }
    } catch (_) {}
    return await instance.readStale(key) ?? <MuzoItem>[];
  }

  /// [shelfCached] with a one-day fresh window — for the date-sensitive "new"
  /// shelves (new songs, new releases, release radar, daily mix, recommended).
  static Future<List<MuzoItem>> shelfCachedDaily(
    String key,
    Future<List<MuzoItem>> Function() fetch,
  ) =>
      shelfCached(key, fetch, ttl: dailyTtl);

  /// stale-while-revalidate pour les rayons : ce qui est déjà sur l'appareil
  /// est servi TOUT DE SUITE, et le rafraîchissement se joue en tâche de fond.
  ///
  /// [shelfCached] bloque pendant tout le fetch dès que le cache a dépassé son
  /// TTL : un rayon de catégorie (32 graines à résoudre sur YouTube, 8-15 s le
  /// piece au travailleur) tenait son appelant en `loading` pendant une à deux
  /// minutes, et sur un accueil chaque ligne en chargement se rendait
  /// `SizedBox.shrink()` — les catégories n'apparaissaient tout simplement pas.
  /// Le contenu déjà vu devient donc visible immédiatement, pendant que la
  /// nouvelle version se télécharge.
  static Future<List<MuzoItem>> shelfCachedStaleFirst(
    String key,
    Future<List<MuzoItem>> Function() fetch, {
    Duration? ttl,
  }) async {
    if (await isOffline()) {
      return await instance.readStale(key, maxAge: offlineCeiling) ??
          <MuzoItem>[];
    }
    final stale = await instance.readStale(key);
    if (stale == null || stale.isEmpty) {
      // Rien à montrer : comportement classique, le premier fetch bloque.
      return shelfCached(key, fetch, ttl: ttl);
    }
    if (await instance.readIfFresh(key, maxAge: ttl ?? browseTtl) == null) {
      // Périmé : on revalide sans attendre la réponse.
      unawaited(fetch().then((fresh) {
        if (fresh.isNotEmpty) unawaited(instance.write(key, fresh));
      }).catchError((Object e) {
        debugPrint('shelfCachedStaleFirst $key: revalidation échouée: $e');
      }));
    }
    return stale;
  }

  /// True when the app should not touch the network: the manual offline
  /// switch is on, or the device reports no usable link. Results are memoised
  /// for [offlineMemoTtl] so a single Home rebuild does not run a dozen
  /// connectivity probes.
  static bool _offlineMemo = false;
  static DateTime _offlineMemoAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration offlineMemoTtl = Duration(seconds: 2);

  static Future<bool> isOffline() async {
    final now = DateTime.now();
    if (now.difference(_offlineMemoAt) < offlineMemoTtl) return _offlineMemo;
    var offline = false;
    try {
      if (Hive.isBoxOpen('downloads')) {
        offline = (Hive.box('downloads').get('offlineMode') ?? false) == true;
      }
    } catch (_) {}
    if (!offline) {
      try {
        final results = await safeConnectivity();
        // `vpn` counts as a link: the test rig routes the phone's traffic to
        // the PC over USB (gnirehtet → a tun0 network marked INTERNET&VALIDATED,
        // with no Wi-Fi at all). Read as offline, every shelf replayed its
        // stored snapshot — up to `offlineCeiling` = 365 days — while the
        // network was in fact fine, which is what made "Nouvelles sorties"
        // show months-old titles as brand new.
        offline = results.isEmpty ||
            (!results.contains(ConnectivityResult.mobile) &&
                !results.contains(ConnectivityResult.wifi) &&
                !results.contains(ConnectivityResult.ethernet) &&
                !results.contains(ConnectivityResult.vpn));
      } catch (_) {
        offline = false;
      }
    }
    _offlineMemo = offline;
    _offlineMemoAt = now;
    return offline;
  }

  /// Drops the 2s connectivity memo so tests can flip the network state.
  @visibleForTesting
  static void resetOfflineMemo() {
    _offlineMemoAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Offline replays use a year-long ceiling: unlike the online fallback
  /// (which must not pin old content), a title seen once should stay browsable
  /// on a flight — matching how Spotify keeps its local catalogue visible.
  static const Duration offlineCeiling = Duration(days: 365);

  /// Default fresh window for a cache read that passes no explicit [maxAge].
  /// Browse shelves do NOT use it — they pass [browseTtl] (3 days); this one
  /// stays short so anything that forgot to declare a window still renews.
  static const Duration ttl = Duration(hours: 6);

  /// Absolute ceiling when falling back to a stale entry (offline / slow
  /// network). Without it an old snapshot could be replayed forever.
  static const Duration staleCeiling = Duration(days: 7);

  /// Shorter TTL for anything date-sensitive (new releases, chart tops).
  /// Charts and release calendars move daily — keep them on a 24h clock so
  /// "Nouveaux albums / sorties" never serve a 3-day-old snapshot.
  static const Duration dailyTtl = Duration(hours: 24);

  /// For the rotating "recommendations of the day" (Sunday picks): the pick
  /// must change every calendar day, so the entry expires at the next
  /// midnight rather than 24h after it was written.
  static Duration sundayTtl([DateTime? now]) {
    final today = now ?? DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day + 1);
    final left = midnight.difference(today);
    // Never hand back a near-zero TTL: a request made seconds before midnight
    // would refetch on every call.
    return left < const Duration(hours: 1) ? const Duration(hours: 1) : left;
  }

  /// Browse refresh window for every non-date-sensitive shelf (category subs,
  /// seed artists, recommendations, iTunes catalog reads): a section keeps the
  /// same titles for 3 days, then renews on the next visit. Shorter than this
  /// and a row reshuffles on every launch; [refreshBucket] ticks on the same
  /// 3-day clock so the renewal is a visible reshuffle, not just a re-fetch of
  /// the same order.
  static const Duration browseTtl = Duration(days: 3);

  static const String _prefix = 'ccache.v4.';

  Future<Map<String, dynamic>?> _readRaw(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Returns the cached songs for [key], or null when absent, expired or
  /// corrupt. Expired entries are left in place — they are overwritten by the
  /// next successful write.
  Future<List<MuzoItem>?> readIfFresh(String key, {Duration? maxAge}) async {
    final raw = await _readRaw(key);
    if (raw == null) return null;
    try {
      final ts = (raw['ts'] as num?)?.toInt() ?? 0;
      final saved = DateTime.fromMillisecondsSinceEpoch(ts);
      if (DateTime.now().difference(saved) >= (maxAge ?? ttl)) return null;
      final songs = (raw['songs'] as List? ?? [])
          .map((e) => MuzoItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (songs.isEmpty) return null;
      return songs;
    } catch (_) {
      return null;
    }
  }

  /// Returns the cached songs for [key] regardless of age (stale-while-
  /// revalidate fallback), or null when absent/corrupt. Used so browse
  /// sections keep showing the last-known content even when the fresh window
  /// has passed and the network is unavailable or slow.
  ///
  /// [maxAge] bounds the staleness: an entry older than it is ignored, so a
  /// snapshot can never be replayed indefinitely (which is what made a shelf
  /// look identical for days on end).
  Future<List<MuzoItem>?> readStale(String key, {Duration? maxAge}) async {
    final raw = await _readRaw(key);
    if (raw == null) return null;
    try {
      final ceiling = maxAge ?? staleCeiling;
      final ts = (raw['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(ts)) >=
          ceiling) {
        return null;
      }
      final songs = (raw['songs'] as List? ?? [])
          .map((e) => MuzoItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (songs.isEmpty) return null;
      return songs;
    } catch (_) {
      return null;
    }
  }

  /// Persists [songs] under [key]. Failures are silently ignored — the cache
  /// is a pure optimization.
  Future<void> write(String key, List<MuzoItem> songs) async {
    if (songs.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'songs': songs.map((s) => s.toJson()).toList(),
      }));
    } catch (_) {}
  }

  /// Tout ce qui a déjà été vu et qui parle de [needle], quel que soit le
  /// rayon ou la recherche qui l'a affiché un jour.
  ///
  /// Hors-ligne, exiger la clé exacte d'un instantané est trop strict : un
  /// titre croisé dans « Rap FR » doit rester trouvable en le tapant. La
  /// chaîne brute est testée avant d'être décodée, pour ne pas parser tout le
  /// cache à la recherche d'un mot qui n'y est pas.
  Future<List<MuzoItem>> cachedSongsMatching(
    String needle, {
    int max = 80,
    int maxEntries = 400,
  }) async {
    final q = needle.trim().toLowerCase();
    if (q.isEmpty) return const <MuzoItem>[];
    final out = <MuzoItem>[];
    final seen = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      var scanned = 0;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        if (scanned++ >= maxEntries || out.length >= max) break;
        final stored = prefs.getString(key);
        if (stored == null || !stored.toLowerCase().contains(q)) continue;
        try {
          final raw = jsonDecode(stored) as Map<String, dynamic>;
          for (final e in (raw['songs'] as List? ?? const <dynamic>[])) {
            final item = MuzoItem.fromJson(Map<String, dynamic>.from(e));
            final hay =
                '${item.title} ${item.displayArtist} ${item.album?.name ?? ''}'
                    .toLowerCase();
            if (!hay.contains(q)) continue;
            final id = item.videoId ?? item.browseId ?? hay;
            if (id.isEmpty || !seen.add(id)) continue;
            out.add(item);
            if (out.length >= max) break;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  /// Generic JSON-list cache with the same TTL. Returns the stored list when
  /// fresh, otherwise null.
  Future<List<dynamic>?> readJsonIfFresh(String key, {Duration? maxAge}) async {
    final raw = await _readRaw(key);
    if (raw == null) return null;
    try {
      final ts = (raw['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) >=
          (maxAge ?? ttl)) {
        return null;
      }
      return raw['data'] as List?;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, List<dynamic> data) async {
    if (data.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      }));
    } catch (_) {}
  }

  /// Stale-while-revalidate reader for the generic JSON-list cache: returns the
  /// stored list regardless of [ttl], bounded only by [maxAge], so offline
  /// category sections can replay their last snapshot instead of erroring out.
  Future<List<dynamic>?> readJsonStale(String key, {Duration? maxAge}) async {
    final raw = await _readRaw(key);
    if (raw == null) return null;
    try {
      final ceiling = maxAge ?? staleCeiling;
      final ts = (raw['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(ts)) >=
          ceiling) {
        return null;
      }
      return raw['data'] as List?;
    } catch (_) {
      return null;
    }
  }

  /// Number of 3-day buckets since the epoch, shifted by the per-install seed:
  /// the content pool refreshes everywhere on the same rhythm, but each device
  /// starts it at a different place. The 3-day tick matches [browseTtl] so a
  /// shelf renews and reshuffles at the same moment. Only ever used as a
  /// rotation offset — never inside a cache key, which would duplicate the
  /// cache per device.
  static int get refreshBucket =>
      DateTime.now().toUtc().difference(DateTime.utc(2024, 1, 1)).inDays ~/ 3 +
      deviceSeed;

  /// Per-install random seed (0..9999), generated once and persisted, so two
  /// users browsing the same genre see a different rotation of artists /
  /// tracks / shelves while the content stays genre-appropriate. Shared by
  /// every rotation offset and "of the day" pick, and folded into [refreshBucket]
  /// so the effective rotation differs device-to-device.
  static const String _seedKey = 'ccache.deviceSeed';
  static int? _deviceSeed;

  /// Synchronous accessor: returns the seed once loaded, else 0 until
  /// [ensureDeviceSeed] has run at startup. Rotation is cosmetic, so a 0 on
  /// the very first frame (before prefs resolve) is harmless.
  static int get deviceSeed => _deviceSeed ?? 0;

  /// Loads (or lazily creates) the per-install seed. Call once at app startup.
  static Future<int> ensureDeviceSeed() async {
    if (_deviceSeed != null) return _deviceSeed!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var seed = prefs.getInt(_seedKey);
      if (seed == null) {
        seed = DateTime.now().microsecondsSinceEpoch.remainder(100000)
            .remainder(10000);
        await prefs.setInt(_seedKey, seed);
      }
      _deviceSeed = seed;
    } catch (_) {
      _deviceSeed = 0;
    }
    return _deviceSeed!;
  }

  /// UTC day number — embed in date-sensitive cache keys so chart/release
  /// snapshots roll over every calendar day without manual invalidation.
  static int get dayBucket =>
      DateTime.now().toUtc().difference(DateTime.utc(2024, 1, 1)).inDays;

  /// Rotates a list by [offset] positions so each bucket leads with different
  /// content without discarding any item.
  static List<T> rotate<T>(List<T> items, int offset) {
    if (items.length <= 1 || offset <= 0) return items;
    final off = offset % items.length;
    return [...items.skip(off), ...items.take(off)];
  }

  // ── Invalidation ───────────────────────────────────────────────────────────
  // Riverpod invalidation alone is not enough: every shelf re-reads its disk
  // entry on the next build, and a "fresh" entry short-circuits the network
  // fetch. Pull-to-refresh must therefore delete the entries it wants gone.

  /// Drops a single cached entry so the next read goes to the network.
  Future<void> invalidate(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Drops every cached entry whose key starts with [prefix] (e.g.
  /// `catsub|`, `discovery|`). Used by pull-to-refresh to force the whole
  /// Home to genuinely re-fetch instead of replaying disk snapshots.
  Future<void> invalidatePrefix(String prefix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doomed = prefs
          .getKeys()
          .where((k) => k.startsWith(_prefix) && k.substring(_prefix.length).startsWith(prefix))
          .toList();
      for (final k in doomed) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// Wipes the whole content cache (used when going back online after a long
  /// offline stretch, so nothing stale is ever promoted back to fresh).
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doomed = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in doomed) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// Bump this number whenever a rule that *manufactures* browse content
  /// changes (veto logic, geo detection, seeds, chart source). The stored rows
  /// would otherwise be promoted to "fresh" by [browseTtl] and freeze the old,
  /// wrong content for three days — hiding the fix and making it look broken.
  /// V4 = les rayons de genre du Home lisent désormais un classement NATIONAL
  /// (radio/playlist de la scène) au lieu du chart Deezer mondial.
  static const String _browseGateMigrationKey = 'ccache.migrate.browseRulesV4';

  /// One-shot migration, run at startup: drops the category, podcast-category
  /// and home-genre-shelf snapshots once per rule change, so each row is
  /// rebuilt by current logic. Later launches keep their 3-day content as
  /// intended.
  static Future<void> migrateBrowseRulesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_browseGateMigrationKey) == true) return;
      await instance.invalidatePrefix('catsub|');
      await instance.invalidatePrefix('podcat|');
      await instance.invalidatePrefix('shelf|genrechart|');
      await prefs.setBool(_browseGateMigrationKey, true);
    } catch (_) {}
  }
}
