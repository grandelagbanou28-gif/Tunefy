import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Picks which yt-dlp proxy the app should talk to, and fails over without
/// ever shipping a new build.
///
/// Why this exists: the stream server lives on a PaaS that redeploys on new
/// URLs, and a client that hardcodes one host breaks silently the next time
/// that happens (every request 404s, playback just stops). The good practice
/// is:
///
///  1. keep a *priority list* of candidates, not a single URL;
///  2. remember the last server that actually answered, and try it first;
///  3. let a small remote JSON file reorder / extend the list, so the URL can
///     change without shipping an app update;
///  4. trip a circuit breaker instead of re-waiting the full timeout on a host
///     that just failed.
class StreamEndpointResolver {
  StreamEndpointResolver({http.Client? client}) : _client = client ?? http.Client();

  /// Compiled-in fallbacks. Always last-resort: they cannot be updated without
  /// a release, but they keep a fresh install working.
  static const List<String> builtinBases = [
    'https://tunefy-ytdlp.vercel.app',
    'https://vercel-proxy-murex-tau.vercel.app',
  ];

  /// Optional remote list, e.g. `https://cdn…/endpoints.json`.
  /// Format: `{"bases": ["https://a", "https://b"]}`.
  static const String _remoteConfigUrl = String.fromEnvironment(
    'STREAM_ENDPOINTS_URL',
    defaultValue: '',
  );

  static const String _box = 'settings';
  static const String _activeKey = 'stream_active_base';
  static const String _failuresKey = 'stream_base_failures';
  static const Duration _remoteTimeout = Duration(seconds: 5);
  static const int _failureThreshold = 3;

  final http.Client _client;

  /// Guarded so concurrent resolutions share one probe.
  Future<List<String>>? _inFlight;

  /// Ordered candidates: last known good first, then remote config, then
  /// whatever the user pinned in Settings, then the built-ins.
  Future<List<String>> candidates() async {
    final saved = await _readBox();
    final userPinned = (saved?.get('ytdlpServerUrl') as String?)?.trim();
    final lastGood = (saved?.get(_activeKey) as String?)?.trim();
    final remote = await _remoteBases();

    final ordered = <String>[];
    void add(String? value) {
      final v = value?.trim();
      if (v == null || v.isEmpty) {
        return;
      }
      if (!v.startsWith('http')) {
        return;
      }
      if (ordered.any((e) => e == v)) {
        return;
      }
      ordered.add(v);
    }

    add(lastGood);
    add(userPinned);
    for (final b in remote) {
      add(b);
    }
    for (final b in builtinBases) {
      add(b);
    }
    return ordered;
  }

  /// Returns the first candidate that answers, persisting it for next launch.
  /// Returns an empty list when nothing responds — callers then fall back to
  /// their own resolvers rather than hanging.
  Future<List<String>> healthyBases({bool force = false}) {
    final pending = _inFlight;
    if (pending != null && !force) return pending;
    final future = _probeAll(force: force);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<List<String>> _probeAll({bool force = false}) async {
    final box = await _readBox();
    final failures = _failures(box);
    final list = await candidates();
    final working = <String>[];

    for (final base in list) {
      if (!force && (failures[base] ?? 0) >= _failureThreshold) {
        // Circuit open: skip without spending a request on a known-dead host.
        continue;
      }
      if (await _probe(base)) {
        working.add(base);
        failures[base] = 0;
        if (box != null) {
          await box.put(_activeKey, base);
          await box.put(_failuresKey, failures);
        }
        break;
      }
      failures[base] = (failures[base] ?? 0) + 1;
      if (box != null) await box.put(_failuresKey, failures);
    }
    // Only the base that answered is returned, so the caller's race is short.
    return working;
  }

  /// Cheap liveness check: the API answers 200 with a JSON body. A dead host
  /// fails in ~2s instead of burning the 30-45s resolution timeout.
  Future<bool> _probe(String base) async {
    try {
      final uri = Uri.parse('$base/api/stream').replace(
        queryParameters: {'videoId': _probeVideoId, 'kind': 'probe'},
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data is Map && (data['url'] is String || data['error'] != null);
    } catch (_) {
      return false;
    }
  }

  /// A very old, extremely popular video: the server caches its resolution, so
  /// this probe stays cheap and never flakes.
  static const String _probeVideoId = 'dQw4w9WgXcQ';

  Future<List<String>> _remoteBases() async {
    if (_remoteConfigUrl.isEmpty) return const [];
    try {
      final response = await _client
          .get(Uri.parse(_remoteConfigUrl))
          .timeout(_remoteTimeout);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body);
      if (data is! Map) return const [];
      final bases = (data['bases'] as List?) ?? const [];
      return bases.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('StreamEndpoints: remote config failed — $e');
      return const [];
    }
  }

  Map<String, int> _failures(Box? box) {
    final raw = box?.get(_failuresKey);
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    return <String, int>{};
  }

  Future<Box?> _readBox() async {
    try {
      if (Hive.isBoxOpen(_box)) return Hive.box(_box);
      return await Hive.openBox(_box);
    } catch (_) {
      return null;
    }
  }

  /// Clears the failure counters so the next resolution re-tries every host.
  static Future<void> resetCircuitBreaker() async {
    try {
      final box = Hive.isBoxOpen(_box) ? Hive.box(_box) : await Hive.openBox(_box);
      await box.delete(_failuresKey);
    } catch (_) {}
  }
}
