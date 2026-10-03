import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:muzo/providers/player_provider.dart';
import 'dart:ui';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/services/lyrics_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/widgets/lyrics_view.dart';
import 'package:muzo/providers/theme_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

class AlbumArtNLyrics extends ConsumerStatefulWidget {
  final double playerArtImageSize;
  const AlbumArtNLyrics({super.key, required this.playerArtImageSize});

  @override
  ConsumerState<AlbumArtNLyrics> createState() => _AlbumArtNLyricsState();
}

class _AlbumArtNLyricsState extends ConsumerState<AlbumArtNLyrics> {
  bool _showLyrics = false;
  bool _isLoadingLyrics = false;
  Lyrics? _lyrics;
  String? _lastFetchedTitle;

  /// Canvas (looping muted video over the cover). Loaded per track, disposed
  /// on track change / unmount. Null = static artwork.
  VideoPlayerController? _canvasController;
  String? _canvasKey;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _canvasController?.dispose();
    super.dispose();
  }

  /// Starts (or restarts) the Canvas loop for [mediaItem]. The caller owns
  /// [_canvasKey]: it disposes the previous controller and stamps the new key
  /// before calling, so stale completions can never play the wrong video.
  Future<void> _loadCanvas(MediaItem mediaItem) async {
    final videoId = mediaItem.id;
    if (videoId.isEmpty) return;
    final storage = ref.read(storageServiceProvider);
    if (!storage.canvasEnabled) return;
    try {
      final url = await StreamExtractionService.getVideoStreamUrl(videoId)
          .timeout(const Duration(seconds: 45));
      if (!mounted || _canvasKey != videoId) return;
      if (url == null || url.isEmpty) return;
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      _canvasController = vc;
      await vc.initialize();
      if (!mounted || _canvasKey != videoId) {
        await vc.dispose();
        if (identical(_canvasController, vc)) _canvasController = null;
        return;
      }
      await vc.setVolume(0);
      await vc.setLooping(true);
      if (!_showLyrics) await vc.play();
      if (mounted) setState(() {});
    } catch (_) {
      // No canvas for this track: the static cover stays. Silent by design.
    }
  }

  void _disposeCanvas() {
    final vc = _canvasController;
    _canvasController = null;
    unawaited(vc?.dispose());
  }

  void _setLyricsVisible(bool visible) {
    if (_showLyrics == visible) return;
    setState(() => _showLyrics = visible);
    // Don't burn battery decoding video behind the lyrics sheet.
    final vc = _canvasController;
    if (vc == null || !vc.value.isInitialized) return;
    if (visible) {
      unawaited(vc.pause());
    } else if (ref.read(storageServiceProvider).canvasEnabled) {
      unawaited(vc.play());
    }
  }

  Future<void> _fetchLyrics(MediaItem mediaItem) async {
    if (_lastFetchedTitle == mediaItem.title) return;
    if (_isLoadingLyrics) return; // Prevent concurrent fetches

    setState(() {
      _lyrics = null;
      _isLoadingLyrics = true;
    });

    try {
      final lyrics = await ref
          .read(lyricsServiceProvider)
          .fetchLyrics(
            mediaItem.title,
            mediaItem.artist ?? '',
            // mediaItem.duration may be null before stream loads; fall back to player's actual duration
            mediaItem.duration?.inSeconds ??
                ref.read(audioHandlerProvider).player.duration?.inSeconds ??
                0,
          );
      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _lastFetchedTitle = mediaItem.title;
          _isLoadingLyrics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyrics = null;
          _lastFetchedTitle = mediaItem.title;
          _isLoadingLyrics = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentMediaItemProvider, (prev, next) {
      final mediaItem = next.valueOrNull;
      if (mediaItem != null &&
          mediaItem.title != _lastFetchedTitle &&
          _showLyrics) {
        _fetchLyrics(mediaItem);
      }
    });

    final mediaItemAsync = ref.watch(currentMediaItemProvider);
    final audioHandler = ref.watch(audioHandlerProvider);

    // Canvas follows the track: a new id disposes the old loop and starts a
    // fresh resolve. Disposal during build is safe (no setState involved).
    final currentMedia = mediaItemAsync.valueOrNull;
    if (currentMedia != null && currentMedia.id != _canvasKey) {
      _disposeCanvas();
      _canvasKey = currentMedia.id;
      unawaited(_loadCanvas(currentMedia));
    }

    final safeSize = widget.playerArtImageSize.clamp(10.0, double.infinity);

    return SizedBox(
      width: safeSize,
      height: safeSize,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 30,
              offset: Offset(0, 15),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              mediaItemAsync.when(
                data: (mediaItem) {
                  if (mediaItem?.artUri == null) {
                    return Container(color: Colors.grey[900]);
                  }
                  final canvas = _canvasController;
                  if (canvas != null && canvas.value.isInitialized) {
                    return SizedBox(
                      width: widget.playerArtImageSize,
                      height: widget.playerArtImageSize,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: canvas.value.size.width,
                          height: canvas.value.size.height,
                          child: VideoPlayer(canvas),
                        ),
                      ),
                    );
                  }
                  return CachedNetworkImage(
                    imageUrl: mediaItem!.artUri.toString().replaceAll(
                      RegExp(r'w\d+-h\d+'),
                      'w800-h800',
                    ),
                    fit: BoxFit.cover,
                    width: widget.playerArtImageSize,
                    height: widget.playerArtImageSize,
                    errorWidget: (context, url, error) => Icon(
                      Icons.music_note,
                      size: 50,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  );
                },
                loading: () => Container(color: Colors.grey[900]),
                error: (_, __) => Container(
                  color: Colors.grey[900],
                  child: const Icon(Icons.error),
                ),
              ),

              // Lyrics Overlay
              if (_showLyrics)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        color:
                            (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.black
                                    : Colors.white)
                                .withValues(alpha: 0.45),
                        child: _isLoadingLyrics
                            ? Center(
                                child: SpotifySpinner(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              )
                            : _lyrics == null
                            ? Center(
                                child: Text(
                                  AppLocalizations.of(context).noLyricsFound,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              )
                            : LyricsView(
                                lyrics: _lyrics!,
                                onClose: () => _setLyricsVisible(false),
                                positionStream:
                                    audioHandler.player.positionStream,
                                totalDuration:
                                    audioHandler.player.duration ??
                                    Duration.zero,
                                isEmbedded: true,
                                videoId:
                                    mediaItemAsync.valueOrNull?.id,
                                accentColor:
                                    ref
                                        .watch(currentPaletteProvider)
                                        .asData
                                        ?.value
                                        ?.darkVibrantColor
                                        ?.color ??
                                    Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),

              // Lyrics Button Overlay (Hide if lyrics are shown)
              if (!_showLyrics)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              final mediaItem = mediaItemAsync.value;
                              if (mediaItem != null) {
                                _setLyricsVisible(true);
                                _fetchLyrics(mediaItem);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    FluentIcons.text_quote_20_filled,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppLocalizations.of(context).lyrics,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
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
              // Canvas toggle (bottom-left): looping video visuals on/off.
              // The cover underneath keeps showing when Canvas is off or has
              // no video for this track.
              Positioned(
                bottom: 12,
                left: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final storage =
                                ref.read(storageServiceProvider);
                            final next = !storage.canvasEnabled;
                            await storage.setCanvasEnabled(next);
                            if (!mounted) return;
                            if (!next) {
                              _disposeCanvas();
                              setState(() {});
                            } else {
                              final media =
                                  mediaItemAsync.valueOrNull;
                              _canvasKey = null;
                              if (media != null) {
                                _disposeCanvas();
                                _canvasKey = media.id;
                                unawaited(_loadCanvas(media));
                              }
                              setState(() {});
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Builder(builder: (context) {
                              final on = ref
                                  .read(storageServiceProvider)
                                  .canvasEnabled;
                              return Icon(
                                Icons.movie_outlined,
                                color: on
                                    ? const Color(0xFF1DDA63)
                                    : Colors.white70,
                                size: 18,
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
