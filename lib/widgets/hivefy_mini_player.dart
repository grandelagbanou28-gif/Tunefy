import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/theme_provider.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/screens/player_screen.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/app_colors.dart';
import 'package:muzo/widgets/audio_device_badge.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

final playerColourProvider = StateProvider<Color>((ref) => Colors.black);

/// Extracts the dominant colour of a piece of artwork. Shared by the mini
/// player and the Now Playing page so both always agree on the background
/// tint, and fed to the app-wide Material You palette.
Future<Color?> dominantArtworkColor(String url) async {
  if (url.isEmpty) return null;
  try {
    final pi = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(url),
    );
    return pi.dominantColor?.color;
  } catch (_) {
    return null;
  }
}

class HivefyMiniPlayer extends ConsumerStatefulWidget {
  const HivefyMiniPlayer({super.key});

  @override
  ConsumerState<HivefyMiniPlayer> createState() => _HivefyMiniPlayerState();
}

class _HivefyMiniPlayerState extends ConsumerState<HivefyMiniPlayer> {
  // Accumulated drag distance so a plain tap (with micro finger jitter) never
  // triggers skip / open-player. Swipes must travel a real distance.
  double _accumDx = 0;
  double _accumDy = 0;
  Timer? _pendingTap;

  static const Duration _doubleTapWindow = Duration(milliseconds: 260);

  void _handleSingleTap() {
    _pendingTap?.cancel();
    _pendingTap = Timer(_doubleTapWindow, () {
      _pendingTap = null;
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _openFullPlayer();
    });
  }

  @override
  void initState() {
    super.initState();
    _updatePlayerCardColour();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _updatePlayerCardColour();
    });
  }

  @override
  void dispose() {
    _pendingTap?.cancel();
    super.dispose();
  }

  void _openFullPlayer() {
    // Captured before the sheet: when this widget is disposed while the
    // player is open, `ref` throws in whenComplete and the flag stays true,
    // which hides the mini player for the whole session.
    final expanded = ref.read(isPlayerExpandedProvider.notifier);
    expanded.state = true;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black12,
      builder: (ctx) {
        return SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Stack(
            children: [
              Container(color: AppColors.cardTranslucent),
              Align(
                alignment: Alignment.bottomCenter,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    // The player lives inside this sheet, so it must dismiss
                    // the SHEET -- a Navigator.pop here would pop the page
                    // underneath and leave the sheet stuck on screen.
                    child: ExpandedPlayer(
                      onClose: () => Navigator.of(ctx).maybePop(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      expanded.state = false;
    });
  }

  /// Double tap on the cover/title toggles playback without opening the
  /// player. Kept on the title zone only, so the progress bar and buttons
  /// never trigger it by accident.
  void _togglePlayback() {
    HapticFeedback.selectionClick();
    final player = ref.read(audioHandlerProvider).player;
    if (player.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  Future<void> _updatePlayerCardColour() async {
    final mediaItem = ref.read(currentMediaItemProvider).valueOrNull;
    final c = await dominantArtworkColor(mediaItem?.artUri?.toString() ?? '');
    if (!mounted || c == null) return;
    final hsl = HSLColor.fromColor(c);
    ref.read(playerColourProvider.notifier).state =
        hsl.withLightness((hsl.lightness * 0.35).clamp(0.0, 1.0)).toColor();
    // Same artwork drives the app-wide Material You tint, as long as the
    // user did not pin the brand colour in the settings.
    if (ref.read(storageServiceProvider).dynamicColorEnabled) {
      ref.read(albumArtColorProvider.notifier).state = c;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentMediaItemProvider, (prev, next) {
      final item = next.valueOrNull;
      if (item != null && mounted) {
        if (item.id != prev?.valueOrNull?.id) {
          ref.read(isMiniPlayerCollapsedProvider.notifier).state = false;
        }
        _updatePlayerCardColour();
      }
    });

    final audioHandler = ref.watch(audioHandlerProvider);
    final mediaItemAsync = ref.watch(currentMediaItemProvider);

    return mediaItemAsync.maybeWhen(
      data: (mediaItem) {
        if (mediaItem == null) return const SizedBox.shrink();
        final id = mediaItem.id;
        final storage = ref.read(storageServiceProvider);

        return GestureDetector(
          onHorizontalDragStart: (_) => _accumDx = 0,
          onHorizontalDragUpdate: (details) => _accumDx += details.delta.dx,
          onHorizontalDragEnd: (details) async {
            final v = details.primaryVelocity ?? 0;
            final travelled = _accumDx.abs() >= 40;
            _accumDx = 0;
            if (!travelled) return;
            if (v > 300) {
              await audioHandler.skipToPrevious();
            } else if (v < -300) {
              await audioHandler.skipToNext();
            }
          },
          onVerticalDragStart: (_) => _accumDy = 0,
          onVerticalDragUpdate: (details) => _accumDy += details.delta.dy,
          onVerticalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            final draggedUp = _accumDy <= -40;
            _accumDy = 0;
            if (v > 300) {
              HapticFeedback.selectionClick();
              ref.read(isMiniPlayerCollapsedProvider.notifier).state = true;
              return;
            }
            if (draggedUp && v < -300) {
              _pendingTap?.cancel();
              HapticFeedback.selectionClick();
              _openFullPlayer();
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: ref.watch(playerColourProvider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _handleSingleTap,
                        onDoubleTap: _togglePlayback,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: mediaItem.artUri?.toString() ?? '',
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey[800],
                              child: const Icon(Icons.music_note, color: Colors.white70, size: 20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _handleSingleTap,
                          onDoubleTap: _togglePlayback,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mediaItem.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                mediaItem.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          storage.toggleFavorite(MuzoItem(
                            videoId: id,
                            title: mediaItem.title,
                            resultType: 'video',
                            isExplicit: false,
                            artists: [MuzoArtist(name: mediaItem.artist ?? '', id: null)],
                            thumbnails: mediaItem.artUri != null
                                ? [MuzoThumbnail(url: mediaItem.artUri.toString(), width: 0, height: 0)]
                                : [],
                          ));
                        },
                        child: Padding(
                           padding: const EdgeInsets.all(8),
                          child: ValueListenableBuilder<List<MuzoItem>>(
                            valueListenable: storage.favoritesListenable,
                            builder: (context, _, __) {
                              final liked = storage.isFavorite(id);
                              return Image.asset(
                                liked
                                    ? 'assets/icons/tick.png'
                                    : 'assets/icons/add.png',
                                width: 26,
                                height: 26,
                                color: liked
                                    ? const Color(0xFF1DDA63)
                                    : Colors.white70,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const AudioDeviceBadge(),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: StreamBuilder<PlayerState>(
                            stream: audioHandler.player.playerStateStream,
                            builder: (context, snapshot) {
                              final state = snapshot.data;
                              final playing = state?.playing ?? false;
                              final isLoading = state?.processingState == ProcessingState.loading ||
                                  state?.processingState == ProcessingState.buffering;

                              if (isLoading) {
                                return const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: SpotifySpinner(
                                    strokeWidth: 2,
                                    color: Color(0xFF1DB954),
                                  ),
                                );
                              }

                              return IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  playing ? Icons.pause_outlined : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () {
                                  playing ? audioHandler.pause() : audioHandler.resume();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: StreamBuilder<Duration>(
                    stream: audioHandler.player.positionStream,
                    builder: (context, snapshot) {
                      final pos = snapshot.data ?? Duration.zero;
                      final total = audioHandler.player.duration ?? Duration.zero;
                      final progress = total.inMilliseconds > 0
                          ? pos.inMilliseconds / total.inMilliseconds
                          : 0.0;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withAlpha(51),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          minHeight: 2,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}