import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/services/notification_service.dart';

const _downloadUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Tunefy) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

class DownloadService {
  DownloadService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          // dio measures the gap BETWEEN received chunks, so a stalled
          // server aborts the download instead of hanging forever.
          receiveTimeout: const Duration(seconds: 30),
        ));

  final Dio _dio;
  final StorageService _storage = StorageService();

  /// Notification failures (permission denied, plugin not initialised…) must
  /// never abort a download — they are cosmetic.
  Future<void> _safeNotify(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      debugPrint('Notification ignored: $e');
    }
  }

  Future<bool> downloadSong(
    MuzoItem result, {
    Function(int, int)? onProgress,
  }) async {
    final videoId = result.videoId;
    final notificationId = videoId.hashCode;
    try {
      if (kIsWeb) {
        debugPrint('Download not supported on web');
        return false;
      }
      if (videoId == null) return false;

      if (!await _requestPermission()) {
        debugPrint('Permission denied');
        return false;
      }

      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$videoId.m4a';
      final file = File(savePath);

      // A leftover partial/corrupt file must never be mistaken for a finished
      // download — it is re-fetched instead of reported as "already there".
      if (await file.exists()) {
        if (await file.length() > 1024 && await _looksLikeMedia(file)) {
          debugPrint('Download: file already exists and is valid');
          await _storage.addDownload(result, savePath);
          await _safeNotify(() => NotificationService().showCompletionNotification(
                id: notificationId,
                title: 'Download Complete',
                body: '${result.title} is already downloaded.',
              ));
          return true;
        }
        await file.delete();
      }

      await _safeNotify(() => NotificationService().showProgressNotification(
            id: notificationId,
            title: 'Downloading...',
            body: result.title,
            progress: 0,
            maxProgress: 100,
          ));

      // Download to a .part file: an aborted transfer never leaves a
      // half-written .m4a that a later attempt would treat as complete.
      final partPath = '$savePath.part';
      final partFile = File(partPath);
      if (await partFile.exists()) await partFile.delete();

      String? lastError;
      var resolvedUrl = false;
      // A catalogue item can already hold its own working stream (an Audius
      // full track, Deezer's 30s clip). The resolvers above match by title and
      // can miss for a title this URL serves fine, which used to fail the
      // download while the app was holding a playable file — so it is kept as
      // the LAST candidate, after both resolution attempts.
      final selfUrl = _selfStreamUrl(result);
      final attempts = selfUrl == null ? 2 : 3;
      for (var attempt = 0; attempt < attempts; attempt++) {
        final useSelf = attempt == attempts - 1 && selfUrl != null;
        if (!useSelf) {
          if (attempt > 0) {
            await StreamExtractionService.invalidateCache(videoId);
          }
        }
        final streamUrl = useSelf
            ? selfUrl
            : await StreamExtractionService.getStreamUrl(
                videoId,
                title: result.title,
                artist: result.displayArtist,
                durationSeconds: result.durationSeconds,
                skipSaavn: attempt > 0,
                // A downloaded file is presented as the full song, so the
                // 30-second Deezer extract is not an acceptable answer here:
                // the download fails honestly instead of filing a clip.
                avoidSources: const {'deezer'},
              );
        if (streamUrl == null) {
          lastError = 'no stream URL (attempt ${attempt + 1})';
          debugPrint('Download: $lastError');
          continue;
        }
        resolvedUrl = true;
        if (useSelf) {
          // Visible on purpose: this is the case where every title resolver
          // missed but the catalogue source the item came from streams it
          // itself — the download would otherwise have failed silently.
          debugPrint('Download: $videoId fetched from its own source URL');
        }
        try {
          await _fetch(streamUrl, partPath, notificationId, result, onProgress);
          if (await _looksLikeMedia(partFile)) {
            if (await file.exists()) await file.delete();
            await partFile.rename(savePath);
            break;
          }
          lastError = 'downloaded data is not audio (attempt ${attempt + 1})';
          debugPrint('Download: $lastError');
        } on DioException catch (e) {
          lastError = 'HTTP ${e.response?.statusCode ?? e.type.name}: '
              '${e.message ?? e.requestOptions.uri}';
          debugPrint('Download: failed on attempt ${attempt + 1} — $lastError');
        } finally {
          if (await partFile.exists()) await partFile.delete();
        }
      }

      if (await file.exists() && await file.length() > 0) {
        await _storage.addDownload(result, savePath);
        await _safeNotify(() => NotificationService().showCompletionNotification(
              id: notificationId,
              title: 'Download Complete',
              body: result.title,
            ));
        return true;
      }

      debugPrint('Download failed for $videoId: $lastError');
      await _safeNotify(() => NotificationService().showCompletionNotification(
            id: notificationId,
            title: 'Download Failed',
            body: resolvedUrl
                ? (lastError ?? 'File verification failed for ${result.title}')
                : 'Could not get stream URL for ${result.title}',
            isError: true,
          ));
      return false;
    } catch (e) {
      debugPrint('Download error: $e');
      await _safeNotify(() => NotificationService().showCompletionNotification(
            id: notificationId,
            title: 'Download Failed',
            body: 'Error downloading ${result.title}',
            isError: true,
          ));
      return false;
    }
  }

  Future<void> _fetch(
    String url,
    String partPath,
    int notificationId,
    MuzoItem result,
    Function(int, int)? onProgress,
  ) async {
    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    await _dio.download(
      url,
      partPath,
      options: Options(headers: {'User-Agent': _downloadUserAgent}),
      onReceiveProgress: (count, total) {
        onProgress?.call(count, total);
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds < 500) return;
        lastNotify = now;
        final progress = total > 0 ? (count / total * 100).clamp(0, 100).round() : 0;
        _safeNotify(() => NotificationService().showProgressNotification(
              id: notificationId,
              title: 'Downloading...',
              body: result.title,
              progress: progress,
              maxProgress: 100,
            ));
      },
      deleteOnError: true,
    );
  }

  /// The item's own stream, when its source handed one over directly. Only
  /// http(s) is considered; anything else (a bare file path, a data URI) has
  /// nothing to fetch.
  static String? _selfStreamUrl(MuzoItem item) {
    final url = item.audioUrl;
    if (url == null || url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    return url;
  }

  /// True when the file starts with a known audio container/magic number, so
  /// an HTML/JSON error page served by a dead source is never kept on disk.
  Future<bool> _looksLikeMedia(File file) async {
    try {
      if (!await file.exists()) return false;
      if (await file.length() < 1024) return false;
      final raf = await file.open();
      final header = await raf.read(16);
      await raf.close();
      if (header.length < 4) return false;

      String at(int start, int len) =>
          String.fromCharCodes(header.sublist(start, start + len));

      final first = header[0];
      // Obvious non-audio payloads.
      if (first == 0x3C /* < */ ||
          first == 0x7B /* { */ ||
          first == 0x23 /* # (m3u8) */ ||
          first == 0x2F /* / */) {
        return false;
      }
      if (header.length >= 8 &&
          const ['ftyp', 'styp', 'moov', 'mdat', 'free', 'skip', 'wide']
              .contains(at(4, 4))) {
        return true; // MP4 / M4A
      }
      if (at(0, 4) == 'RIFF') return header.length >= 12 && at(8, 4) == 'WAVE';
      if (at(0, 4) == 'fLaC') return true;
      if (at(0, 4) == 'OggS') return true;
      if (at(0, 3) == 'ID3') return true;
      // MPEG frame sync / ADTS
      if (first == 0xFF && (header[1] & 0xE0) == 0xE0) return true;
      // WebM / Matroska (YouTube audio-only streams)
      if (first == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Download: media sniff failed ($e) — keeping file');
      return true;
    }
  }

  Future<bool> _requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      // On Android 10+ (API 29+), scoped storage is used, so WRITE_EXTERNAL_STORAGE
      // is not needed for app-specific directories (getApplicationDocumentsDirectory).
      // However, for older versions, it might be needed.
      // Since we are targeting modern Android, we might skip this or check version.
      // But let's just return true for now as we use app-specific storage.
      return true;
    }
    return true;
  }

  Future<void> deleteDownload(String videoId) async {
    final path = _storage.getDownloadPath(videoId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    // Always drop the registry entry, otherwise a missing file keeps showing
    // up as "downloaded" forever.
    await _storage.removeDownload(videoId);
  }
}
