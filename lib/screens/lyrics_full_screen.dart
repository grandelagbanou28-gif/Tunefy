import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:muzo/utils/net_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/lyrics_service.dart';
import 'package:muzo/services/lyrics_translation_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/song_options_menu.dart';
import 'package:muzo/widgets/song_video_backdrop.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

class LyricsFullScreen extends ConsumerStatefulWidget {
  final MediaItem mediaItem;

  const LyricsFullScreen({super.key, required this.mediaItem});

  @override
  ConsumerState<LyricsFullScreen> createState() => _LyricsFullScreenState();
}

class _LyricsFullScreenState extends ConsumerState<LyricsFullScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _lineKeys = [];
  final ValueNotifier<int> _activeLine = ValueNotifier<int>(-1);
  List<TimedLyricLine>? _timed;
  bool _autoScrollPaused = false;
  Timer? _autoScrollResumeTimer;

  VideoPlayerController? _videoController;
  bool _hasVideo = false;
  /// Propriété du signal « un fond vidéo occupe l'écran » (voir
  /// `claimLyricsVideoBackdrop`) : la pochette du player doit libérer son
  /// décodeur, Android n'en supporte pas deux.
  int? _backdropToken;
  /// Une vidéo déjà décodée qu'il faudra relancer au retour au premier plan.
  bool _videoToResume = false;
  StreamSubscription<bool>? _playingSub;
  late MediaItem _currentMediaItem;
  Lyrics? _lastLyrics;

  // Ken Burns animation
  late AnimationController _kenBurnsController;
  late Animation<double> _kenBurnsScale;
  late Animation<Offset> _kenBurnsOffset;

  static final YoutubeExplode _yt = YoutubeExplode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentMediaItem = widget.mediaItem;

    // Ken Burns: slow zoom 1.0→1.15 + gentle pan, 12s cycle, repeat forever
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _kenBurnsScale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _kenBurnsController, curve: Curves.easeInOut),
    );
    _kenBurnsOffset = Tween<Offset>(
      begin: const Offset(-0.02, -0.01),
      end: const Offset(0.02, 0.01),
    ).animate(
      CurvedAnimation(parent: _kenBurnsController, curve: Curves.easeInOut),
    );
    _kenBurnsController.repeat(reverse: true);

    _initVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollResumeTimer?.cancel();
    _activeLine.dispose();
    _kenBurnsController.dispose();
    _scrollController.dispose();
    _playingSub?.cancel();
    releaseLyricsVideoBackdrop(_backdropToken);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_videoToResume) {
        _videoToResume = false;
        unawaited(_initVideoForMedia(_currentMediaItem));
      }
      return;
    }
    // La surface du TextureView meurt avec l'app arrière-plan : un décodeur
    // qui continue d'écrire dessus fait planter le processus.
    final vc = _videoController;
    if (vc == null && !_hasVideo) return;
    _videoToResume = vc != null;
    _playingSub?.cancel();
    _playingSub = null;
    _videoController = null;
    releaseLyricsVideoBackdrop(_backdropToken);
    _backdropToken = null;
    if (mounted) setState(() => _hasVideo = false);
    unawaited(vc?.dispose());
  }

  Future<void> _initVideo() async {
    return _initVideoForMedia(widget.mediaItem);
  }

  Future<void> _initVideoForMedia(MediaItem media) async {
    final videoId = media.id;
    if (videoId.isEmpty) return;
    // Pendant la résolution, aucun décodeur n'est tenu ici : la pochette animée
    // du player peut garder le sien. Le jeton n'est reclamé qu'au succès.
    releaseLyricsVideoBackdrop(_backdropToken);
    _backdropToken = null;

    // Skip video entirely when connection is unstable
    try {
      final results = await safeConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        if (mounted) setState(() => _hasVideo = false);
        return;
      }
    } catch (_) {}

    _playingSub?.cancel();
    final oldController = _videoController;
    _videoController = null;
    _hasVideo = false;
    if (oldController != null) {
      try { await oldController.dispose(); } catch (_) {}
    }
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 8));
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
      final cap = 45 * 1024 * 1024;
      String? url;
      if (muxed.isNotEmpty) {
        AudioStreamInfo? best;
        for (final s in muxed) {
          if (s.size.totalBytes <= cap) best = s;
        }
        url = (best ?? muxed.first).url.toString();
      } else {
        final videoOnly = manifest.videoOnly.toList()
          ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
        if (videoOnly.isNotEmpty) url = videoOnly.first.url.toString();
      }
      if (url == null || !mounted) return;
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = vc;
      try {
        await vc.initialize().timeout(const Duration(seconds: 10));
      } catch (_) {
        await vc.dispose();
        if (mounted) setState(() { _videoController = null; _hasVideo = false; });
        return;
      }
      if (!mounted) {
        await vc.dispose();
        return;
      }
      await vc.setLooping(true);
      await vc.setVolume(0);
      if (!mounted) {
        await vc.dispose();
        return;
      }
      _backdropToken = claimLyricsVideoBackdrop();
      setState(() => _hasVideo = true);
      final audioHandler = ref.read(audioHandlerProvider);
      _playingSub?.cancel();
      _playingSub = audioHandler.player.playingStream.listen((playing) {
        if (!mounted) return;
        // Le fond suit la lecture : appeler play() même quand la musique est
        // en pause laissait une vidéo tourner pour rien.
        if (playing) {
          _videoController?.play();
        } else {
          _videoController?.pause();
        }
      });
      if (audioHandler.player.playing) await vc.play();
    } catch (_) {
      final dead = _videoController;
      _videoController = null;
      // Un contrôleur abandonné sans dispose retient son décodeur ; à force,
      // c'est tout le processus qui tombe.
      if (dead != null) {
        try {
          await dead.dispose();
        } catch (_) {}
      }
    }
  }

  void _onPosition(Duration position) {
    final timed = _timed;
    if (timed == null || timed.isEmpty) return;
    final active = _activeIndexFor(position, timed);
    if (active == _activeLine.value) return;
    _activeLine.value = active;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(active));
  }

  int _activeIndexFor(Duration position, List<TimedLyricLine> timed) {
    var low = 0;
    var high = timed.length - 1;
    var active = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (timed[mid].time <= position) {
        active = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return active;
  }

  void _seekToLine(int index) {
    final timed = _timed;
    if (timed == null || index < 0 || index >= timed.length) return;
    HapticFeedback.selectionClick();
    unawaited(ref.read(audioHandlerProvider).seek(timed[index].time));
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails == null) return false;
      _pauseAutoScroll();
      _scheduleAutoScrollResume();
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) return false;
      _pauseAutoScroll();
      _scheduleAutoScrollResume();
    } else if (notification is ScrollEndNotification) {
      _scheduleAutoScrollResume();
    }
    return false;
  }

  void _pauseAutoScroll() {
    if (_autoScrollPaused) return;
    _autoScrollPaused = true;
    _autoScrollResumeTimer?.cancel();
  }

  void _scheduleAutoScrollResume() {
    if (!_autoScrollPaused) return;
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = Timer(const Duration(seconds: 3), () {
      _autoScrollResumeTimer = null;
      if (!mounted || !_autoScrollPaused) return;
      _autoScrollPaused = false;
      _scrollToActive(_activeLine.value);
    });
  }

  void _scrollToActive(int index) {
    if (_autoScrollPaused) return;
    if (index < 0 || index >= _lineKeys.length) return;
    final context = _lineKeys[index].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  MuzoItem _muzoItem(MediaItem mediaItem) {
    return MuzoItem(
      videoId: mediaItem.id,
      title: mediaItem.title,
      resultType: mediaItem.extras?['resultType'] ?? 'video',
      isExplicit: false,
      artists: [MuzoArtist(name: mediaItem.artist ?? '', id: mediaItem.extras?['artistId'])],
      thumbnails: mediaItem.artUri != null
          ? [MuzoThumbnail(url: mediaItem.artUri.toString(), width: 0, height: 0)]
          : [],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(positionProvider, (prev, next) {
      final position = next.valueOrNull;
      if (position == null) return;
      _onPosition(position);
    });
    ref.listen(currentMediaItemProvider, (prev, next) {
      final media = next.value;
      if (media == null) return;
      if (media.id == _currentMediaItem.id) return;
      _currentMediaItem = media;
      if (mounted) {
        setState(() {
          _activeLine.value = -1;
          _timed = null;
          _autoScrollPaused = false;
          _lineKeys.clear();
          _scrollController.hasClients ? _scrollController.jumpTo(0) : null;
        });
      }
      _initVideoForMedia(media);
    });

    // Single source of truth: the live provider, so the lyrics page always
    // shows the SAME track as the now-playing screen (never a stale copy).
    final current = ref.watch(currentMediaItemProvider).valueOrNull;
    final mediaItem = current ?? _currentMediaItem;
    final lyricsAsync = ref.watch(currentLyricsProvider(mediaItem.id));

    // Flicker-guard: while the new song's lyrics load, keep the previously
    // shown lyrics so the page doesn't flash a blank spinner.
    final Lyrics? loadedLyrics = lyricsAsync.valueOrNull;
    if (loadedLyrics != null || !lyricsAsync.isLoading) {
      _lastLyrics = loadedLyrics;
    }
    final Lyrics? effectiveLyrics =
        loadedLyrics ?? _lastLyrics;
    final audioHandler = ref.watch(audioHandlerProvider);
    final player = audioHandler.player;
    final storage = ref.read(storageServiceProvider);
    final bgUrl = mediaItem.artUri?.toString() ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _hasVideo && _videoController != null
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
                : bgUrl.isNotEmpty
                    ? AnimatedBuilder(
                        animation: _kenBurnsController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: _kenBurnsOffset.value,
                            child: Transform.scale(
                              scale: _kenBurnsScale.value,
                              child: child,
                            ),
                          );
                        },
                        child: Image.network(
                          bgUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[900],
                          ),
                        ),
                      )
                    : Container(color: Colors.grey[900]),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(210),
                    Colors.black.withAlpha(170),
                    Colors.black.withAlpha(235),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(mediaItem, storage),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: effectiveLyrics == null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 160),
                              child: Center(
                                child: Column(
                                  children: [
                                    const Icon(Icons.lyrics_outlined,
                                        color: Colors.white38, size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.noLyricsFound,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _buildLyricsBody(
                              mediaItem,
                              effectiveLyrics,
                              ref.watch(translatedLyricsProvider(mediaItem.id)),
                            ),
                    ),
                  ),
                ),
                _buildProgressBar(player, mediaItem),
                _buildNavControls(player),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(MediaItem mediaItem, StorageService storage) {
    final l10n = AppLocalizations.of(context);
    final result = _muzoItem(mediaItem);
    final bgUrl = mediaItem.artUri?.toString() ?? '';
    final title = mediaItem.title;
    final artist = mediaItem.artist ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.navigate_before, size: 30, color: Colors.white),
                tooltip: l10n.back,
              ),
              const Spacer(),
              ValueListenableBuilder<List<MuzoItem>>(
                valueListenable: storage.favoritesListenable,
                builder: (context, _, __) {
                  final liked = storage.isFavorite(mediaItem.id);
                  return IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      storage.toggleFavorite(result);
                    },
                    icon: Icon(
                      liked ? Icons.star_rounded : Icons.star_border_rounded,
                      color: liked ? const Color(0xFF1DDA63) : Colors.white,
                      size: 26,
                    ),
                  );
                },
              ),
              IconButton(
                onPressed: () => SongOptionsMenu.show(ref, result, fromPlayer: true),
                icon: const Icon(Icons.more_horiz, color: Colors.white, size: 26),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: bgUrl.isNotEmpty
                      ? Image.network(
                          bgUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[800],
                            child: const Icon(Icons.music_note, color: Colors.white38, size: 20),
                          ),
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          color: Colors.grey[800],
                          child: const Icon(Icons.music_note, color: Colors.white38, size: 20),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsBody(
    MediaItem mediaItem,
    Lyrics lyrics,
    AsyncValue<List<TranslatedLyricLine>?> translatedAsync,
  ) {
  final translatedLines = translatedAsync.valueOrNull;
  final showTranslation = translatedLines != null && translatedLines.isNotEmpty;

  final timed = parseTimedLyrics(
      lyrics, mediaItem.duration ?? const Duration(minutes: 4));
  if (timed.isEmpty) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 160),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.lyrics_outlined, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              l10n.noLyricsFound,
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  _timed = timed;

  if (timed.length != _lineKeys.length) {
    _lineKeys
      ..clear()
      ..addAll(List.generate(timed.length, (_) => GlobalKey()));
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < timed.length; i++)
        _buildLyricLine(i, timed, showTranslation, translatedLines),
    ],
  );
}

  Widget _buildLyricLine(
    int i,
    List<TimedLyricLine> timed,
    bool showTranslation,
    List<TranslatedLyricLine>? translatedLines,
  ) {
    String? trText;
    if (showTranslation) {
      for (final t in translatedLines!) {
        if (t.index == i) {
          trText = t.text.isEmpty ? null : t.text;
          break;
        }
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _seekToLine(i),
      child: Padding(
        key: _lineKeys[i],
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ValueListenableBuilder<int>(
          valueListenable: _activeLine,
          builder: (context, active, __) {
            final isActive = i == active;
            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white38,
                fontSize: isActive ? 20 : 16,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: -0.3,
                height: 1.3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(timed[i].text),
                  if (isActive && trText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        trText,
                        style: const TextStyle(
                          color: Color(0xFF1DDA63),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressBar(AudioPlayer player, MediaItem mediaItem) {
    final total = mediaItem.duration ?? player.duration ?? Duration.zero;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnapshot) {
        final pos = posSnapshot.data ?? Duration.zero;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 5),
          child: Column(
            children: [
              // The very same widget the Now Playing bar uses. A plain Slider
              // renders the same position differently — it jumps from tick to
              // tick and freezes between updates, while ProgressBar
              // interpolates with its own clock — so the two bars visibly
              // drifted apart even though they read the same stream.
              ProgressBar(
                barHeight: 2,
                thumbRadius: 5,
                thumbGlowRadius: 0,
                baseBarColor: Colors.white54.withAlpha(50),
                bufferedBarColor: Colors.transparent,
                progressBarColor: Colors.white,
                thumbColor: Colors.white,
                timeLabelLocation: TimeLabelLocation.none,
                progress: pos,
                total: total,
                onSeek: player.seek,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(_fmt(total), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavControls(AudioPlayer player) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, seqSnap) {
        final seq = seqSnap.data;
        final hasPrev = seq != null && seq.currentIndex > 0;
        final hasNext = seq != null && seq.currentIndex < seq.sequence.length - 1;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: l10n.previous,
              onPressed: hasPrev ? player.seekToPrevious : null,
              icon: Icon(
                Icons.skip_previous,
                color: hasPrev ? Colors.white : Colors.white30,
                size: 32,
              ),
            ),
            const SizedBox(width: 10),
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (context, snapshot) {
                final state = snapshot.data;
                final playing = state?.playing ?? false;
                final isLoading = state?.processingState == ProcessingState.loading ||
                    state?.processingState == ProcessingState.buffering;

                return GestureDetector(
                  onTap: () {
                    if (isLoading) return;
                    playing ? player.pause() : player.play();
                  },
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Center(
                      child: isLoading
                          ? const SizedBox(
                              width: 60,
                              height: 60,
                              child: SpotifySpinner(strokeWidth: 2.5, color: Color(0xFF1DB954)),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 36,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: l10n.next,
              onPressed: hasNext ? player.seekToNext : null,
              icon: Icon(
                Icons.skip_next,
                color: hasNext ? Colors.white : Colors.white30,
                size: 32,
              ),
            ),
          ],
        );
      },
    );
  }
}
