import 'dart:convert';

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

  /// How long a cached sub-section stays valid. Browsing shelves ("Tendance
  /// du moment", "Hits Bénin", every Rap/Afro row) used to hold a 3-day
  /// snapshot: the shelf looked frozen for days on end. 6h keeps pages
  /// instant while the content visibly renews at least a few times a day.
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

  /// Mid-frequency shelves (artists, podcasts, other categories): fresh twice
  /// a week is enough and saves a lot of requests.
  static const Duration twoDayTtl = Duration(hours: 48);

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

  /// Number of 3-day buckets since the epoch — the rotation counter that makes
  /// "every 3 days everything refreshes" deterministic across devices.
  static int get refreshBucket =>
      DateTime.now().toUtc().difference(DateTime.utc(2024, 1, 1)).inDays ~/ 3;

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
}
