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
import 'package:muzo/widgets/song_video_backdrop.dart';

class AlbumArtNLyrics extends ConsumerStatefulWidget {
  final double playerArtImageSize;
  const AlbumArtNLyrics({super.key, required this.playerArtImageSize});

  @override
  ConsumerState<AlbumArtNLyrics> createState() => _AlbumArtNLyricsState();
}

class _AlbumArtNLyricsState extends ConsumerState<AlbumArtNLyrics>
    with WidgetsBindingObserver {
  bool _showLyrics = false;
  bool _isLoadingLyrics = false;
  Lyrics? _lyrics;
  String? _lastFetchedTitle;

  /// Canvas (looping muted video over the cover). Loaded per track, disposed
  /// on track change / unmount. Null = static artwork.
  VideoPlayerController? _canvasController;
  String? _canvasKey;
  ModalRoute? _overlayRoute;
  AnimationStatusListener? _overlayListener;

  @override
  void initState() {
    super.initState();
    lyricsVideoBackdropOpen.addListener(_onLyricsBackdropChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lyricsVideoBackdropOpen.removeListener(_onLyricsBackdropChanged);
    _detachOverlayListener();
    _canvasController?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchOverlayRoutes();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreCanvas());
    } else {
      _yieldCanvas();
    }
  }

  /// Le décodeur vidéo d'Android est une ressource unique : la pochette animée
  /// le rend dès qu'une page est passée par-dessus le player (clips, concert,
  /// paroles) et le reprend quand elle disparaît. Deux décodeurs simultanés
  /// tuent le processus, mini-player compris.
  void _watchOverlayRoutes() {
    final route = ModalRoute.of(context);
    if (identical(route, _overlayRoute)) return;
    _detachOverlayListener();
    _overlayRoute = route;
    final animation = route?.secondaryAnimation;
    if (animation == null) return;
    _overlayListener = (status) {
      if (status == AnimationStatus.completed) {
        _yieldCanvas();
      } else if (status == AnimationStatus.dismissed) {
        unawaited(_restoreCanvas());
      }
    };
    animation.addStatusListener(_overlayListener!);
  }

  void _detachOverlayListener() {
    final listener = _overlayListener;
    final animation = _overlayRoute?.secondaryAnimation;
    if (listener != null && animation != null) {
      animation.removeStatusListener(listener);
    }
    _overlayListener = null;
  }

  void _yieldCanvas() {
    if (_canvasController == null) return;
    _disposeCanvas();
    if (mounted) setState(() {});
  }

  Future<void> _restoreCanvas() async {
    final media = ref.read(currentMediaItemProvider).valueOrNull;
    if (media == null) return;
    if (_canvasController != null || _canvasKey == null) return;
    final storage = ref.read(storageServiceProvider);
    if (!storage.canvasEnabled || lyricsVideoBackdropOpen.value) return;
    _canvasKey = media.id;
    await _loadCanvas(media);
  }

  /// L'écran des paroles a sa propre vidéo : la pochette ne se contente pas de
  /// la mettre en pause, elle rend le décodeur.
  void _onLyricsBackdropChanged() {
    if (lyricsVideoBackdropOpen.value) {
      _yieldCanvas();
    } else {
      unawaited(_restoreCanvas());
    }
  }

  /// Starts (or restarts) the Canvas loop for [mediaItem]. The caller owns
  /// [_canvasKey]: it disposes the previous controller and stamps the new key
  /// before calling, so stale completions can never play the wrong video.
  Future<void> _loadCanvas(MediaItem mediaItem) async {
    final videoId = mediaItem.id;
    if (videoId.isEmpty) return;
    final storage = ref.read(storageServiceProvider);
    if (!storage.canvasEnabled) return;
    // Un autre écran tient déjà le décodeur : ne jamais empiler deux vidéos.
    if (lyricsVideoBackdropOpen.value) return;
    VideoPlayerController? probe;
    var keep = false;
    try {
      final url = await StreamExtractionService.getVideoStreamUrl(videoId)
          .timeout(const Duration(seconds: 45));
      if (!mounted || _canvasKey != videoId) return;
      if (url == null || url.isEmpty) return;
      probe = VideoPlayerController.networkUrl(Uri.parse(url));
      _canvasController = probe;
      await probe.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || _canvasKey != videoId) return;
      // Une vidéo dont la trame n'a pas de taille connue ne peut pas être
      // mise à l'échelle : le FittedBox en dessous diviserait par zéro.
      final size = probe.value.size;
      if (size.width <= 0 || size.height <= 0) return;
      keep = true;
      await probe.setVolume(0);
      await probe.setLooping(true);
      if (!_showLyrics && !lyricsVideoBackdropOpen.value) await probe.play();
      if (mounted) setState(() {});
    } catch (_) {
      // No canvas for this track: the static cover stays. Silent by design.
    } finally {
      // Lâcher un contrôleur sans le fermer retient un décodeur MediaCodec.
      // Un par titre raté, et c'est tout le processus qui tombe — mini-player
      // compris, parce que lui ne meurt pas seul.
      if (!keep) {
        final dead = probe;
        if (dead != null) {
          if (identical(_canvasController, dead)) _canvasController = null;
          await dead.dispose();
        }
      }
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
        if (!_isLoadingLyrics && (_lyrics == null || (_lyrics!.plainLyrics.isEmpty && _lyrics!.syncedLyrics.isEmpty))) {
          // If no valid lyrics, hide the lyrics view
          if (_showLyrics) _setLyricsVisible(false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyrics = null;
          _lastFetchedTitle = mediaItem.title;
          _isLoadingLyrics = false;
        });
        if (_showLyrics) _setLyricsVisible(false);
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

    // Canvas follows the track. Neither the release nor the new decode happens
    // inside build: disposing a controller there leaves the frame's Texture
    // pointing at a dead surface, and starting the next loop before the
    // previous one is freed means two decoders at once — both crash the app.
    final currentMedia = mediaItemAsync.valueOrNull;
    if (currentMedia != null && currentMedia.id != _canvasKey) {
      _canvasKey = currentMedia.id;
      final stale = _canvasController;
      _canvasController = null;
      final media = currentMedia;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await stale?.dispose();
        if (!mounted || _canvasKey != media.id) return;
        await _loadCanvas(media);
      });
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
                  if (canvas != null &&
                      canvas.value.isInitialized &&
                      canvas.value.size.width > 0 &&
                      canvas.value.size.height > 0) {
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
                            : (_lyrics == null || _lyrics!.plainLyrics.isEmpty && _lyrics!.syncedLyrics.isEmpty)
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
                              final media = mediaItemAsync.valueOrNull;
                              if (media != null) {
                                final stale = _canvasController;
                                _canvasController = null;
                                _canvasKey = media.id;
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) async {
                                  await stale?.dispose();
                                  if (!mounted || _canvasKey != media.id) return;
                                  await _loadCanvas(media);
                                });
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
