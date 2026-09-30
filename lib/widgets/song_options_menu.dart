import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/download_provider.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/download_service.dart';
import 'package:muzo/widgets/playlist_selection_dialog.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/services/navigator_key.dart';
import 'dart:async';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:muzo/widgets/sleep_timer_dialog.dart';
import 'package:muzo/l10n/app_localizations.dart';

class SongOptionsMenu extends ConsumerWidget {
  final MuzoItem result;
  final bool fromHistory;
  final bool fromPlayer;
  final VoidCallback? onClose;

  const SongOptionsMenu({
    super.key,
    required this.result,
    this.fromHistory = false,
    this.fromPlayer = false,
    this.onClose,
  });

  static DateTime? _lastShowTime;

  static void show(
    WidgetRef ref,
    MuzoItem result, {
    bool fromHistory = false,
    bool fromPlayer = false,
  }) {
    final now = DateTime.now();
    if (_lastShowTime != null &&
        now.difference(_lastShowTime!) < const Duration(milliseconds: 500)) {
      return; // Debounce rapid taps
    }
    _lastShowTime = now;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // A real modal sheet (DraggableScrollableSheet) so the menu can be
    // dismissed by swiping down, its options scrolled with one continuous
    // gesture, and the page behind is inert — no stuck overlay, no freeze.
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.25,
        maxChildSize: 0.85,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xF00D0D0D) : const Color(0xD9F2F2F7),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SongOptionsMenu(
                    result: result,
                    fromHistory: fromHistory,
                    fromPlayer: fromPlayer,
                    onClose: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void hide(WidgetRef ref) {}

  /// Shares the track the way Hivefy does: a short text block (title, artist,
  /// album, link) with the artwork attached as a PNG when it can be loaded.
  Future<void> _shareItem() async {
    final details = StringBuffer()
      ..writeln(result.title)
      ..writeln(result.displayArtist);
    final album = result.album?.name;
    if (album != null && album.isNotEmpty) details.writeln(album);
    if (result.videoId != null) {
      details.writeln('https://youtube.com/watch?v=${result.videoId}');
    }

    Uint8List? imageBytes;
    final imageUrl = result.thumbnails.isNotEmpty
        ? result.thumbnails.last.url
        : '';
    if (imageUrl.isNotEmpty) {
      try {
        final provider = NetworkImage(imageUrl);
        final stream = provider.resolve(const ImageConfiguration());
        final completer = Completer<ImageInfo>();
        stream.addListener(ImageStreamListener((info, _) {
          if (!completer.isCompleted) completer.complete(info);
        }));
        final info = await completer.future;
        final byteData = await info.image.toByteData(
          format: ImageByteFormat.png,
        );
        imageBytes = byteData?.buffer.asUint8List();
        info.image.dispose();
      } catch (e) {
        debugPrint('Share artwork unavailable: $e');
      }
    }

    await Share.shareXFiles(
      imageBytes == null
          ? const []
          : [
              XFile.fromData(
                imageBytes,
                name: '${result.title}.png',
                mimeType: 'image/png',
              ),
            ],
      text: details.toString(),
      subject: result.title,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<List<MuzoItem>>(
      valueListenable: storage.favoritesListenable,
      builder: (context, favorites, _) {
        final isFav =
            result.videoId != null && storage.isFavorite(result.videoId!);
        final isDownloaded =
            result.videoId != null && storage.isDownloaded(result.videoId!);

        // Get Thumbnail URL
        String imageUrl = '';
        if (result.thumbnails.isNotEmpty) {
          imageUrl = result.thumbnails.last.url;
        }

        final List<Widget> options = [
          _buildMenuOption(
            context,
            icon: FluentIcons.list_24_regular,
            label: l10n.addToQueue,
            onTap: () async {
              onClose?.call();
              final queueMessage = l10n.addedToQueue;
              final failureMessage = l10n.failedToAddToQueue;
              final added = await ref
                  .read(audioHandlerProvider)
                  .addToQueue(result);
              final ctx = navigatorKey.currentContext;
              if (ctx != null && ctx.mounted) {
                showGlassSnackBar(
                  ctx,
                  added ? queueMessage : failureMessage,
                );
              }
            },
          ),
          _buildMenuOption(
            context,
            icon: FluentIcons.share_24_regular,
            label: l10n.share,
            onTap: () async {
              onClose?.call();
              await _shareItem();
            },
          ),
          if (fromPlayer) ...[
            _buildMenuOption(
              context,
              icon: FluentIcons.timer_24_regular,
              label: l10n.sleepTimer,
              onTap: () {
                onClose?.call();
                final ctx = navigatorKey.currentContext;
                if (ctx != null) {
                  showDialog(
                    context: ctx,
                    builder: (context) => const SleepTimerDialog(),
                  );
                }
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: ref
                  .watch(audioHandlerProvider)
                  .isLofiModeNotifier,
              builder: (context, isLofi, _) {
                return _buildSwitchOption(
                  context,
                  icon: FluentIcons.wand_24_regular,
                  label: l10n.lofiMode,
                  value: isLofi,
                  onChanged: (val) =>
                      ref.read(audioHandlerProvider).toggleLofiMode(),
                );
              },
            ),
          ],
          _buildMenuOption(
            context,
            icon: FluentIcons.play_circle_24_regular,
            label: l10n.playNext,
            onTap: () {
              onClose?.call();
              ref.read(audioHandlerProvider).playNext(result);
            },
          ),
          _buildMenuOption(
            context,
            icon: FluentIcons.add_24_regular,
            label: l10n.addToPlaylist,
            onTap: () {
              onClose?.call();
              final ctx = navigatorKey.currentContext;
              if (ctx != null) {
                showCupertinoDialog(
                  context: ctx,
                  barrierDismissible: true,
                  builder: (context) => PlaylistSelectionDialog(song: result),
                );
              }
            },
          ),
          _buildMenuOption(
            context,
            icon: isFav
                ? FluentIcons.heart_24_filled
                : FluentIcons.heart_24_regular,
            label: isFav ? l10n.removeFromFavorites : l10n.addToFavorites,
            iconColor: isFav ? Colors.red : Theme.of(context).colorScheme.onSurface,
            onTap: () {
              onClose?.call();
              storage.toggleFavorite(result);
              final ctx = navigatorKey.currentContext;
              if (ctx != null) {
                showGlassSnackBar(
                  ctx,
                  isFav
                      ? l10n.removedFromFavoritesToast
                      : l10n.addedToFavoritesToast,
                );
              }
            },
          ),
          if (fromHistory) ...[
            _buildMenuOption(
              context,
              icon: FluentIcons.history_24_regular,
              label: l10n.removeFromHistory,
              onTap: () {
                onClose?.call();
                if (result.videoId != null) {
                  storage.removeFromHistory(result.videoId!);
                  final ctx = navigatorKey.currentContext;
                  if (ctx != null) {
                    showGlassSnackBar(ctx, l10n.removedFromHistory);
                  }
                }
              },
            ),
          ],
          _buildMenuOption(
            context,
            icon: isDownloaded
                ? FluentIcons.checkmark_24_regular
                : FluentIcons.arrow_download_24_regular,
            label: isDownloaded ? l10n.removeDownload : l10n.downloaded,
            onTap: () async {
              onClose?.call();
              final downloadService = DownloadService();
              final ctx = navigatorKey.currentContext;
              if (result.videoId != null) {
                if (storage.isDownloaded(result.videoId!)) {
                  await downloadService.deleteDownload(result.videoId!);
                  if (ctx != null && ctx.mounted) {
                    showGlassSnackBar(ctx, l10n.removedDownloadToast);
                  }
                } else {
                  if (ctx != null) {
                    showGlassSnackBar(ctx, l10n.downloadStarted);
                  }

                  final success = await ref
                      .read(downloadProvider.notifier)
                      .startDownload(result);

                  final ctxAfter = navigatorKey.currentContext;
                  if (ctxAfter != null && ctxAfter.mounted) {
                    showGlassSnackBar(
                      ctxAfter,
                      success ? l10n.downloadComplete : l10n.downloadFailed,
                    );
                  }
                }
              }
            },
          ),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 56,
                                  height: 56,
                                  color: isDark ? Colors.grey[900] : Colors.grey[300],
                                  child: Icon(
                                    FluentIcons.music_note_2_24_regular,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: isDark ? Colors.grey[900] : Colors.grey[300],
                            child: Icon(
                              FluentIcons.music_note_2_24_regular,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.artists?.map((a) => a.name).join(', ') ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 0.5,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 4),
            Column(
              children: [
                for (int i = 0; i < options.length; i++) ...[
                  options[i],
                  if (i < options.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 60),
                      child: Container(
                        height: 0.5,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildMenuOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final effectiveIconColor = iconColor ?? Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        child: Row(
          children: [
            Icon(icon, color: effectiveIconColor, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) {
    final effectiveIconColor = iconColor ?? Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 20),
        child: Row(
          children: [
            Icon(icon, color: effectiveIconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: CupertinoSwitch(
                value: value,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  onChanged(val);
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                thumbColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
