import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:muzo/models/muzo_item.dart';

/// Scans the device's own music files (MediaStore on Android, MPMedia on iOS)
/// and exposes them as [MuzoItem]s.
///
/// This is the one source that needs no network and no server: every track the
/// user already has on their phone plays instantly and offline. Each item is
/// tagged `resultType == 'local_file'` and carries its `file://` URI in
/// [MuzoItem.audioUrl], which the audio handler plays directly.
class LocalLibraryService {
  LocalLibraryService._();
  static final LocalLibraryService instance = LocalLibraryService._();

  final OnAudioQuery _query = OnAudioQuery();

  List<MuzoItem> _cache = const [];
  bool _scanned = false;

  /// True once a scan has produced (possibly empty) results.
  bool get hasScanned => _scanned;

  /// Last scan result, cached in memory.
  List<MuzoItem> get songs => _cache;

  /// Asks for the audio permission (no-op / true on desktop & web).
  Future<bool> ensurePermission() async {
    if (kIsWeb) return true;
    try {
      // checkAndRequest() checks and, if needed, requests the platform
      // permission. On Android <13 it maps to READ_EXTERNAL_STORAGE, on 13+
      // to READ_MEDIA_AUDIO (both declared in the manifest).
      final granted = await _query.checkAndRequest(retryRequest: true);
      return granted;
    } catch (e) {
      debugPrint('LocalLibrary: permission error: $e');
      return false;
    }
  }

  /// Scans the device and returns the playable local tracks, sorted by title.
  /// Results are memoized; pass [force] to rescan.
  Future<List<MuzoItem>> scan({bool force = false}) async {
    if (_scanned && !force) return _cache;
    if (kIsWeb) {
      _scanned = true;
      _cache = const [];
      return _cache;
    }
    if (!await ensurePermission()) {
      _scanned = true;
      _cache = const [];
      return _cache;
    }
    try {
      final songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      final items = <MuzoItem>[];
      for (final s in songs) {
        final path = s.data;
        if (path.isEmpty) continue;
        // Skip files that no longer exist on disk (stale MediaStore rows).
        try {
          if (!File(path).existsSync()) continue;
        } catch (_) {}
        final item = _toItem(s);
        if (item != null) items.add(item);
      }
      _cache = items;
      _scanned = true;
      debugPrint('LocalLibrary: scanned ${items.length} local tracks');
      return _cache;
    } catch (e) {
      debugPrint('LocalLibrary: scan error: $e');
      _scanned = true;
      _cache = const [];
      return _cache;
    }
  }

  MuzoItem? _toItem(SongModel s) {
    final path = s.data;
    if (path.isEmpty) return null;
    final id = 'local_${s.id}';
    final artist = (s.artist == null || s.artist!.isEmpty || s.artist == '<unknown>')
        ? 'Artiste inconnu'
        : s.artist!;
    final durationMs = s.duration;
    return MuzoItem(
      title: s.title.isNotEmpty ? s.title : s.displayNameWOExt,
      videoId: id,
      thumbnails: const [],
      resultType: 'local_file',
      isExplicit: false,
      artists: [MuzoArtist(name: artist, id: null)],
      album: (s.album != null && s.album!.isNotEmpty)
          ? MuzoAlbum(name: s.album!, id: s.albumId?.toString() ?? '')
          : null,
      durationSeconds: durationMs != null && durationMs > 0
          ? (durationMs ~/ 1000)
          : null,
      // file:// URIs are treated as reusable by the stream extractor, so the
      // audio handler plays them directly with zero network.
      audioUrl: Uri.file(path).toString(),
      source: 'local',
      metadata: {'localPath': path, 'localId': s.id},
    );
  }

  /// Embedded artwork bytes for a local track (null if none). Used by the
  /// local-library screen to show real cover art.
  Future<Uint8List?> artwork(int localId, {int size = 300}) async {
    if (kIsWeb) return null;
    try {
      return await _query.queryArtwork(
        localId,
        ArtworkType.AUDIO,
        size: size,
        quality: 80,
      );
    } catch (_) {
      return null;
    }
  }
}
