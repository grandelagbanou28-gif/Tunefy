import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/stream_extraction_service.dart';

/// Resolves tracks in the background *before* the user taps them.
///
/// Without it, every first tap pays a full resolution (the local yt-dlp server
/// alone can take seconds on a cold miss), and a dead source is discovered only
/// after the tap — which is exactly when it looks like "this song does not
/// work". Warming a shelf as it is displayed moves that discovery off the
/// critical path and makes the first tap instant.
///
/// Deliberately conservative:
/// - a strict concurrency cap, because a shelf can hold 50 items and firing 50
///   resolutions at once starves the one the user actually pressed;
/// - a stagger between tasks, for the same reason;
/// - no retries and no re-warming of what is already cached;
/// - nothing at all while offline.
class StreamPrewarmer {
  StreamPrewarmer._();
  static final StreamPrewarmer instance = StreamPrewarmer._();

  /// Resolutions in flight at once. Two is enough to hide latency without
  /// crowding out the track the user just pressed.
  static const int _concurrency = 2;

  /// Pause between two resolutions, so a visible shelf warms gradually.
  static const Duration _stagger = Duration(milliseconds: 180);

  /// Hard cap per call: the rows nobody scrolls to are not worth the network.
  static const int _maxPerCall = 12;

  final Set<String> _queued = <String>{};
  int _inFlight = 0;
  final List<_WarmTask> _pending = <_WarmTask>[];

  /// Ids warmed this session, for diagnostics.
  int warmed = 0;
  int failed = 0;

  /// Warms the first [limit] playable items of a shelf or a result list.
  void warm(List<MuzoItem> items, {int limit = _maxPerCall}) {
    // Cheap guard before touching connectivity: never queue while offline.
    unawaited(_pump(items, limit));
  }

  Future<void> _pump(List<MuzoItem> items, int limit) async {
    List<ConnectivityResult> state;
    try {
      state = await Connectivity().checkConnectivity();
    } catch (_) {
      return;
    }
    if (state.contains(ConnectivityResult.none)) return;

    var taken = 0;
    for (final item in items) {
      if (taken >= limit) break;
      final id = item.videoId;
      // Metadata seeds (dz_/it_/sp_) are not streamable, and audio results
      // never need resolving twice.
      if (id == null || id.isEmpty) continue;
      if (StreamExtractionService.isMetadataSeedId(id)) continue;
      if (item.audioUrl != null && item.audioUrl!.isNotEmpty) continue;
      if (!_queued.add(id)) continue;
      _pending.add(_WarmTask(
        videoId: id,
        title: item.title,
        artist: item.displayArtist,
        durationSeconds: item.durationSeconds,
      ));
      taken++;
    }
    _drain();
  }

  void _drain() {
    while (_inFlight < _concurrency && _pending.isNotEmpty) {
      final task = _pending.removeAt(0);
      _inFlight++;
      unawaited(_run(task));
    }
  }

  Future<void> _run(_WarmTask task) async {
    try {
      if (await StreamExtractionService.isWarm(task.videoId)) return;
      final url = await StreamExtractionService.getStreamUrl(
        task.videoId,
        title: task.title,
        artist: task.artist,
        durationSeconds: task.durationSeconds,
      );
      if (url != null && url.isNotEmpty) {
        warmed++;
      } else {
        failed++;
      }
    } catch (_) {
      failed++;
    } finally {
      _queued.remove(task.videoId);
      _inFlight--;
      // Stagger so a burst of shelves does not open 40 sockets at once.
      Future<void>.delayed(_stagger, _drain);
    }
  }

  /// Drops the pending queue — used when leaving a screen, so an abandoned
  /// shelf stops competing with the one the user is now looking at.
  void cancelPending() {
    for (final t in _pending) {
      _queued.remove(t.videoId);
    }
    _pending.clear();
  }

  /// One-line summary for the diagnostics surface.
  String report() => 'préchauffés: $warmed, échoués: $failed, en file: ${_pending.length}';
}

class _WarmTask {
  final String videoId;
  final String title;
  final String artist;
  final int? durationSeconds;

  const _WarmTask({
    required this.videoId,
    required this.title,
    required this.artist,
    this.durationSeconds,
  });
}
