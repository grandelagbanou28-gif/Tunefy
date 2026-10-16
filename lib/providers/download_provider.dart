import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/download_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadState {
  final Map<String, double> progressMap;
  final Map<String, MuzoItem> activeDownloads;

  DownloadState({this.progressMap = const {}, this.activeDownloads = const {}});

  DownloadState copyWith({
    Map<String, double>? progressMap,
    Map<String, MuzoItem>? activeDownloads,
  }) {
    return DownloadState(
      progressMap: progressMap ?? this.progressMap,
      activeDownloads: activeDownloads ?? this.activeDownloads,
    );
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) {
    return DownloadNotifier(ref);
  },
);

class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref ref;
  final DownloadService _downloadService = DownloadService();

  DownloadNotifier(this.ref) : super(DownloadState());

  /// Downloads already in flight and the taps waiting for a slot. "Download
  /// all" on an artist page used to start ~100 simultaneous multi-source
  /// races, which got the resolvers rate-limited and made most of those
  /// downloads fail — three at a time keeps the network responsive and every
  /// track of the list gets its turn.
  static const int _maxConcurrent = 3;
  int _running = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> _acquireSlot() async {
    while (_running >= _maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _running++;
  }

  void _releaseSlot() {
    _running--;
    if (_waiters.isNotEmpty && _running < _maxConcurrent) {
      _waiters.removeAt(0).complete();
    }
  }

  Future<bool> startDownload(MuzoItem result) async {
    if (result.videoId == null) return false;

    await _acquireSlot();
    try {
      // Add to active downloads
      state = state.copyWith(
        activeDownloads: {...state.activeDownloads, result.videoId!: result},
        progressMap: {...state.progressMap, result.videoId!: 0.0},
      );

      final success = await _downloadService.downloadSong(
        result,
        onProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            state = state.copyWith(
              progressMap: {...state.progressMap, result.videoId!: progress},
            );
          }
        },
      );

      // Remove from active downloads
      final newActive = Map<String, MuzoItem>.from(state.activeDownloads);
      newActive.remove(result.videoId);

      final newProgress = Map<String, double>.from(state.progressMap);
      newProgress.remove(result.videoId);

      state = state.copyWith(
        activeDownloads: newActive,
        progressMap: newProgress,
      );

      return success;
    } finally {
      _releaseSlot();
    }
  }

  /// Downloads a clip as a real VIDEO file and saves it to the device
  /// Gallery (Movies/Tunefy), then records the videoId in SharedPreferences
  /// so the check mark survives restarts. Returns true on success.
  Future<bool> downloadClipVideo(String videoId) async {
    try {
      final url = await StreamExtractionService.getVideoStreamUrl(videoId);
      if (url == null) return false;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/tunefy_clip_$videoId.mp4';
      await Dio().download(
        url,
        path,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
          },
        ),
      );

      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(path, album: 'Tunefy');
      if (File(path).existsSync()) File(path).deleteSync();

      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList('clip_gallery_dl') ?? <String>[])
        ..add(videoId);
      await prefs.setStringList('clip_gallery_dl', set);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteDownload(String videoId) async {
    final storage = ref.read(storageServiceProvider);

    // Check if it's an active download
    if (state.activeDownloads.containsKey(videoId)) {
      // TODO: Cancel active download (requires DownloadService update)
      // For now, just remove from state
      final newActive = Map<String, MuzoItem>.from(state.activeDownloads);
      newActive.remove(videoId);

      final newProgress = Map<String, double>.from(state.progressMap);
      newProgress.remove(videoId);

      state = state.copyWith(
        activeDownloads: newActive,
        progressMap: newProgress,
      );
    }

    // Remove from storage registry and delete the real .m4a file from disk
    // (no orphan files left behind).
    await _downloadService.deleteDownload(videoId);
    if (storage.getDownloadPath(videoId) != null) {
      await storage.removeDownload(videoId);
    }
  }
}
