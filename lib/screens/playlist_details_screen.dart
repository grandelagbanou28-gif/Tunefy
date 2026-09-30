import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/models/user_data.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/providers/download_provider.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/widgets/song_options_menu.dart';
import 'package:muzo/widgets/global_background.dart';
import 'package:muzo/widgets/app_alert_dialog.dart';
import 'package:muzo/l10n/app_localizations.dart';

class PlaylistDetailsScreen extends ConsumerWidget {
  final String playlistName;
  final bool isSystemPlaylist;

  const PlaylistDetailsScreen({
    super.key,
    required this.playlistName,
    this.isSystemPlaylist = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final l10n = AppLocalizations.of(context);

    return GlobalBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(playlistName),
          actions: [
            if (!isSystemPlaylist)
              IconButton(
                icon: const Icon(FluentIcons.delete_24_regular),
                onPressed: () {
                  // Confirm delete
                  showAppAlertDialog(
                    context: context,
                    title: l10n.deletePlaylistTitle,
                    content: const Text(
                      'This cannot be undone.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          storage.deletePlaylist(playlistName);
                          Navigator.pop(context); // Close dialog
                          Navigator.pop(context); // Go back to library
                        },
                        child: Text(
                          'Delete',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],

        ),
        body: Builder(
          builder: (context) {
            if (playlistName == 'Favorites') {
              return ValueListenableBuilder<List<MuzoItem>>(
                valueListenable: storage.favoritesListenable,
                builder: (context, favorites, _) {
                  return _buildSongList(context, ref, favorites, storage);
                },
              );
            } else if (playlistName == 'Downloads') {
              return ValueListenableBuilder(
                valueListenable: storage.downloadsListenable,
                builder: (context, box, _) {
                  final downloadState = ref.watch(downloadProvider);
                  final activeSongs = downloadState.activeDownloads.values
                      .toList();

                  final downloads = storage.getDownloads();
                  final storedSongs = downloads
                      .map(
                        (d) => MuzoItem.fromJson(
                          Map<String, dynamic>.from(d['result']),
                        ),
                      )
                      .toList();

                  // Combine active first.
                  final allSongs = [...activeSongs, ...storedSongs];

                  return _buildSongList(
                    context,
                    ref,
                    allSongs,
                    storage,
                    progressMap: downloadState.progressMap,
                  );
                },
              );
            } else {
              return ValueListenableBuilder<List<Playlist>>(
                valueListenable: storage.playlistsListenable,
                builder: (context, playlists, _) {
                  final songs = storage.getPlaylistSongs(playlistName);
                  return _buildSongList(context, ref, songs, storage);
                },
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    List<MuzoItem> songs,
    StorageService storage, {
    Map<String, double>? progressMap,
  }) {
    if (songs.isEmpty) {
      return const Center(
        child: Text('No songs found', style: TextStyle(color: Colors.grey)),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnBg = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05);
    final btnBorder = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    final btnContentColor = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        // Play All Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: btnBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: btnBorder,
                    width: 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      storage.recordPlayedPlaylist(playlistName);
                      ref.read(audioHandlerProvider).playAll(songs);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.play_24_filled,
                            color: btnContentColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Play All',
                            style: TextStyle(
                              color: btnContentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Songs List
        Expanded(
          child: Builder(
            builder: (context) {
              final canReorder =
                  playlistName != 'Favorites' && playlistName != 'Downloads';
              return ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: songs.length,
                buildDefaultDragHandles: false,
                onReorderItem: (fromIndex, toIndex) =>
                    storage.movePlaylistTrack(playlistName, fromIndex, toIndex),
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final song = songs[index];
                  final progress = progressMap?[song.videoId];
                  final isDownloading = progress != null;

                  return ListTile(
                    key: ValueKey(song.videoId ?? 'playlist_idx_$index'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnails.isNotEmpty
                        ? song.thumbnails.last.url
                        : '',
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                      width: 46,
                      height: 46,
                      child: Icon(
                        FluentIcons.music_note_2_24_regular,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: isDownloading
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF1ED760)),
                            minHeight: 3,
                          ),
                        ),
                      )
                    : Text(
                        song.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        playlistName == 'Favorites'
                            ? FluentIcons.heart_24_filled
                            : playlistName == 'Downloads'
                                ? (isDownloading
                                    ? FluentIcons.dismiss_circle_24_regular
                                    : FluentIcons.delete_24_regular)
                                : FluentIcons.subtract_circle_24_regular,
                        color: playlistName == 'Favorites'
                            ? const Color(0xFF1ED760)
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        size: 18,
                      ),
                      onPressed: () {
                        if (playlistName == 'Favorites') {
                          storage.toggleFavorite(song);
                        } else if (playlistName == 'Downloads') {
                          if (isDownloading) {
                            ref
                                .read(downloadProvider.notifier)
                                .deleteDownload(song.videoId!);
                          } else {
                            storage.removeDownload(song.videoId!);
                          }
                        } else {
                          storage.removeFromPlaylist(
                            playlistName,
                            song.videoId ?? '',
                          );
                        }
                      },
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.more_vert, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      onPressed: () => SongOptionsMenu.show(ref, song),
                    ),
                    if (canReorder)
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  openArtistForSong(context, song);
                },
                onLongPress: () {
                  if (!isDownloading) {
                    SongOptionsMenu.show(ref, song);
                  }
                },
              );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
