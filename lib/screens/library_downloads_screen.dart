import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/download_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_search_bar.dart';
import 'package:muzo/widgets/app_alert_dialog.dart';

class LibraryDownloadsScreen extends ConsumerStatefulWidget {
  const LibraryDownloadsScreen({super.key});

  @override
  ConsumerState<LibraryDownloadsScreen> createState() =>
      _LibraryDownloadsScreenState();
}

class _LibraryDownloadsScreenState extends ConsumerState<LibraryDownloadsScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshTotals();
    ref.read(storageServiceProvider).downloadsListenable.addListener(_onDownloads);
  }

  @override
  void dispose() {
    ref.read(storageServiceProvider).downloadsListenable.removeListener(_onDownloads);
    _searchController.dispose();
    super.dispose();
  }

  void _onDownloads() {
    _refreshTotals();
    if (mounted) setState(() {});
  }

  /// Sums the real size of every file on disk (téléchargements).
  Future<void> _refreshTotals() async {
    final downloads = ref.read(storageServiceProvider).getDownloads();
    var bytes = 0;
    for (final d in downloads) {
      final p = d['path'];
      if (p is String && p.isNotEmpty) {
        try {
          final f = File(p);
          if (await f.exists()) bytes += await f.length();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() => _totalBytes = bytes);
  }

  static String _formatBytes(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: storage.downloadsListenable,
          builder: (context, _) {
            final downloads = storage.getDownloads();
            final filtered = _searchQuery.isEmpty
                ? downloads
                : downloads.where((d) {
                    final result = d['result'];
                    if (result == null) return false;
                    final title = result['title']?.toString() ?? '';
                    return title.toLowerCase().contains(_searchQuery.toLowerCase());
                  }).toList();

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SpotifyBackButton(),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                l10n.downloads,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: spotifyWhite),
                              ),
                            ),
                            if (downloads.isNotEmpty)
                              GestureDetector(
                                onTap: () => _showClearAllDialog(context, storage, l10n),
                                child: const Icon(FluentIcons.delete_24_regular, color: spotifyLightGrey, size: 20),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: spotifyWhite.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: spotifyWhite.withValues(alpha: 0.10)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                storage.offlineMode ? Icons.cloud_off_rounded : Icons.cloud_outlined,
                                color: storage.offlineMode
                                    ? const Color(0xFF1DB954)
                                    : spotifyLightGrey,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.offlineMode,
                                      style: const TextStyle(
                                          color: spotifyWhite, fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      storage.offlineMode
                                          ? l10n.offlineNotDownloaded
                                          : (downloads.isNotEmpty
                                              ? l10n.downloadCountSizes
                                                  .replaceAll('{count}', '${downloads.length}')
                                                  .replaceAll('{size}', _formatBytes(_totalBytes))
                                              : ''),
                                      style: const TextStyle(color: spotifyLightGrey, fontSize: 11, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: storage.offlineMode,
                                activeTrackColor: const Color(0xFF1DB954),
                                activeThumbColor: spotifyBlack,
                                inactiveThumbColor: spotifyLightGrey,
                                inactiveTrackColor: spotifyWhite.withValues(alpha: 0.15),
                                onChanged: (v) {
                                  unawaited(storage.setOfflineMode(v));
                                  HapticFeedback.selectionClick();
                                },
                              ),
                            ],
                          ),
                        ),
                        if (downloads.isNotEmpty && !storage.offlineMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Text(
                              l10n.downloadCountSizes
                                  .replaceAll('{count}', '${downloads.length}')
                                  .replaceAll('{size}', _formatBytes(_totalBytes)),
                              style: const TextStyle(
                                  color: spotifyLightGrey, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildSearchBar(l10n),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(FluentIcons.arrow_download_24_regular, size: 64, color: spotifyLightGrey),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noDownloadsYet,
                            style: const TextStyle(color: spotifyLightGrey, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final d = filtered[index];
                          final result = d['result'];
                          if (result == null) return const SizedBox.shrink();
                          final song = MuzoItem.fromJson(Map<String, dynamic>.from(result));
                          final img = song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';
                          return SpotifySongChip(
                            imageUrl: img,
                            songTitle: song.title,
                            singerName: song.displayArtist,
                            size: 47,
                            videoId: song.videoId,
                            isDeletable: true,
                            result: song,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              playSongAndOpenNowPlaying(context, song);
                            },
                            onDelete: () => _removeDownload(context, d['videoId'], l10n),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Removes the track from the list AND deletes the real .m4a file (no
  /// orphan files left on the device).
  void _removeDownload(BuildContext context, String videoId, AppLocalizations l10n) {
    final storage = ref.read(storageServiceProvider);
    // Delete the file first: DownloadService resolves the path from the
    // registry, then the entry is dropped from storage.
    unawaited(DownloadService().deleteDownload(videoId).then((_) async {
      await storage.removeDownload(videoId);
    }));
  }

  void _showClearAllDialog(BuildContext context, StorageService storage, AppLocalizations l10n) {
    showAppAlertDialog(
      context: context,
      title: l10n.clearAllDownloads,
      content: Text(l10n.clearDownloadsConfirm, style: const TextStyle(color: spotifyWhite)),
      actions: [
        TextButton(
          onPressed: () { if (context.mounted && Navigator.canPop(context)) Navigator.pop(context); },
          child: Text(l10n.cancel, style: const TextStyle(color: spotifyWhite)),
        ),
        TextButton(
          onPressed: () {
            unawaited(_deleteAllFiles());
            storage.clearDownloads();
            if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
          },
          child: Text(l10n.deleteAll, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _deleteAllFiles() async {
    final downloads = ref.read(storageServiceProvider).getDownloads();
    final paths = downloads.map((d) => d['path']).whereType<String>().toList();
    for (final p in paths) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return SpotifySearchBar(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      hintText: l10n.search,
      height: 40,
    );
  }
}
