import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_marquee/widget_marquee.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/models/artist_details.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/theme_provider.dart';
import 'package:muzo/providers/artist_bio_provider.dart';
import 'package:muzo/providers/download_provider.dart';
import 'package:muzo/widgets/audio_device_button.dart';
import 'package:muzo/widgets/song_options_menu.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/screens/dj_screen.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/lyrics_service.dart';
import 'package:muzo/services/lyrics_translation_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/utils/app_colors.dart';
import 'package:muzo/widgets/hivefy_mini_player.dart';
import 'package:muzo/screens/lyrics_full_screen.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

class HivefyFullPlayer extends ConsumerStatefulWidget {
  const HivefyFullPlayer({super.key, this.onClose});

  /// Closes the player whatever way it was opened (pushed route or bottom
  /// sheet). Falls back to a navigator pop when null.
  final VoidCallback? onClose;

  @override
  ConsumerState<HivefyFullPlayer> createState() => _HivefyFullPlayerState();
}

class _HivefyFullPlayerState extends ConsumerState<HivefyFullPlayer> {
  /// Created with the queue's CURRENT index as its initial page. A controller
  /// without an initialPage mounts on page 0, and `onPageChanged` then fires
  /// immediately, which seeked the player to track 0 — that was the
  /// "opening Now Playing restarts the song (or starts another one)".
  PageController? _pageController;

  /// Page we moved to ourselves (to follow the player). `onPageChanged` must
  /// not treat that as a user swipe and re-seek the track it just came from.
  int _programmaticPage = -1;
  ArtistDetails? _artistDetails;
  bool _loadingArtist = false;
  bool _biographyExpanded = false;
  StreamSubscription<int?>? _currentIndexSub;
  final ScrollController _lyricsScrollController = ScrollController();
  final List<GlobalKey> _lyricsLineKeys = [];
  int _lyricsActiveLine = -1;
  Lyrics? _lastLyrics;
  String? _lastLyricsForId;

  @override
  void initState() {
    super.initState();
    _updateBgColor();
    _fetchArtist();
    _listenCurrentIndex();
  }

  @override
  void dispose() {
    _currentIndexSub?.cancel();
    _pageController?.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  /// Keep the album-art PageView in sync with the player's current index so
  /// that pausing, skipping or re-ordering the queue never leaves a stale
  /// album cover on screen.
  void _listenCurrentIndex() {
    final player = ref.read(audioHandlerProvider).player;
    _currentIndexSub = player.currentIndexStream.listen((index) {
      if (!mounted || index == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _pageController;
        if (!mounted || controller == null || !controller.hasClients) return;
        final current = controller.page?.round();
        if (current != index) {
          try {
            _programmaticPage = index;
            controller
                .animateToPage(
              index,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            )
                .whenComplete(() {
              _programmaticPage = -1;
            });
          } catch (_) {
            _programmaticPage = -1;
          }
        }
      });
    });
  }

  Future<void> _updateBgColor() async {
    final mediaItem = ref.read(currentMediaItemProvider).valueOrNull;
    final c = await dominantArtworkColor(mediaItem?.artUri?.toString() ?? '');
    if (!mounted || c == null) return;
    final hsl = HSLColor.fromColor(c);
    ref.read(playerColourProvider.notifier).state =
        hsl.withLightness((hsl.lightness * 0.35).clamp(0.0, 1.0)).toColor();
    if (ref.read(storageServiceProvider).dynamicColorEnabled) {
      ref.read(albumArtColorProvider.notifier).state = c;
    }
  }

  Future<void> _fetchArtist() async {
    final mediaItem = ref.read(currentMediaItemProvider).valueOrNull;
    if (mediaItem == null) return;
    final artistId = mediaItem.extras?['artistId'] as String?;
    if (_loadingArtist) return;
    _loadingArtist = true;
    try {
      final storage = ref.read(storageServiceProvider);
      final avatar = artistId != null && artistId.isNotEmpty
          ? storage.getArtistImage(artistId)
          : null;
      if (avatar != null &&
          avatar.isNotEmpty &&
          avatar != 'INVALID_ARTIST' &&
          mounted) {
        setState(() {
          _artistDetails = ArtistDetails(
            artistName: mediaItem.artist ?? '',
            artistAvatar: avatar,
            playlistId: '',
            recommendedArtists: const [],
            featuredOnPlaylists: const [],
          );
        });
      }
      final api = MuzoApiService(storage);
      final details = await api.getArtistDetails(artistId ?? '');
      if (mounted && details != null) {
        setState(() => _artistDetails = details);
        if (details.artistAvatar.isNotEmpty && artistId != null && artistId.isNotEmpty) {
          await storage.setArtistImage(artistId, details.artistAvatar);
        }
      }
    } catch (_) {}
    _loadingArtist = false;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Widget _marqueeText(
    String text, {
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w600,
    Color color = Colors.white,
    double letterSpacing = 0,
  }) {
    if (text.length <= 30) {
      return Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return SizedBox(
      height: fontSize * 1.3,
      child: Marquee(
        delay: const Duration(milliseconds: 300),
        duration: const Duration(seconds: 10),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
          ),
        ),
      ),
    );
  }

  void _openQueueSheet() {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.01,
        maxChildSize: 0.95,
        expand: false,
        snap: true,
        builder: (_, scrollController) => Container(
          constraints: BoxConstraints(maxHeight: size.height, maxWidth: size.width),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.cardTranslucent, Colors.black87],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: SizedBox(
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white54,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.queue,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.playingNext,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                fit: FlexFit.tight,
                child: Column(
                  children: [
                    _buildQueueToggles(context),
                    Expanded(child: _buildQueueList(scrollController)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shuffle / autoplay row sitting on top of the queue list. "Smart shuffle"
  /// keeps the current track playing and reorders everything that comes after
  /// it, which is what the plain shuffle button cannot do.
  Widget _buildQueueToggles(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final audioHandler = ref.read(audioHandlerProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      // Flexible, not plain children: the three labels are localized and
      // "Smart shuffle" is already wide enough in French to exceed a narrow
      // phone, which overflowed the row by ~28px.
      child: Row(
        children: [
          Flexible(
            child: ValueListenableBuilder<bool>(
              valueListenable: audioHandler.isShuffleModeNotifier,
              builder: (context, shuffleOn, _) {
                return _QueueToggle(
                  icon: Icons.shuffle,
                  label: l10n.shuffle,
                  active: shuffleOn,
                  onTap: () => audioHandler.toggleShuffle(),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ValueListenableBuilder<bool>(
              valueListenable: audioHandler.isSmartShuffleNotifier,
              builder: (context, smartOn, _) {
                return _QueueToggle(
                  icon: Icons.auto_awesome,
                  label: l10n.smartShuffle,
                  active: smartOn,
                  onTap: () => audioHandler.toggleSmartShuffle(),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ValueListenableBuilder<bool>(
              valueListenable: audioHandler.isAutoplayNotifier,
              builder: (context, autoplayOn, _) {
                return _QueueToggle(
                  icon: Icons.radio,
                  label: l10n.autoplay,
                  active: autoplayOn,
                  onTap: () => audioHandler.toggleAutoplay(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(ScrollController scrollController) {
    final l10n = AppLocalizations.of(context);
    final audioHandler = ref.read(audioHandlerProvider);
    final player = audioHandler.player;

    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final sequence = state?.sequence ?? [];
        final currentIndex = state?.currentIndex ?? 0;
        final nextItems = currentIndex + 1 < sequence.length
            ? sequence.sublist(currentIndex + 1)
            : [];

        if (nextItems.isEmpty) {
          return Center(
            child: Text(l10n.noUpcomingSongs,
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          );
        }

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: nextItems.length,
          itemBuilder: (context, index) {
            final item = nextItems[index].tag as MediaItem;
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: item.artUri?.toString() ?? '',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 40,
                    height: 40,
                    color: Colors.grey[800],
                    child: const Icon(Icons.music_note, color: Colors.white38, size: 18),
                  ),
                ),
              ),
              title: Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              subtitle: Text(item.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () {
                Navigator.of(context).pop();
                final target = currentIndex + 1 + index;
                unawaited(() async {
                  try {
                    await player.seek(Duration.zero, index: target);
                    await player.play();
                  } catch (e) {
                    debugPrint('Queue jump failed: $e');
                  }
                }());
              },
            );
          },
        );
      },
    );
  }

  MuzoItem _buildMuzoItemFromMedia(MediaItem mediaItem) {
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

  @override
  Widget build(BuildContext context) {
    ref.listen(currentMediaItemProvider, (prev, next) {
      final item = next.valueOrNull;
      if (item != null && item != prev?.valueOrNull) {
        _updateBgColor();
        _fetchArtist();
      }
    });

    final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
    final audioHandler = ref.watch(audioHandlerProvider);
    final player = audioHandler.player;
    final storage = ref.watch(storageServiceProvider);
    final downloadState = ref.watch(downloadProvider);

    if (mediaItem == null) {
      return const SizedBox.shrink();
    }

    final isLiked = storage.isFavorite(mediaItem.id);
    final isDownloading = downloadState.activeDownloads.containsKey(mediaItem.id);
    final downloadProgress = downloadState.progressMap[mediaItem.id] ?? 0.0;
    final lyricsAsync = ref.watch(currentLyricsProvider(mediaItem.id));

    // Flicker-guard: while this song's lyrics are still loading, keep showing
    // the previously loaded lyrics instead of a blank spinner. As soon as the
    // fetch returns (lyrics or "not found") we switch to this song's result.
    final Lyrics? loadedLyrics = lyricsAsync.valueOrNull;
    if (loadedLyrics != null || !lyricsAsync.isLoading) {
      _lastLyrics = loadedLyrics;
      _lastLyricsForId = mediaItem.id;
    }
    final Lyrics? effectiveLyrics =
        loadedLyrics ?? (_lastLyricsForId == mediaItem.id ? null : _lastLyrics);

    return Container(
      color: ref.watch(playerColourProvider),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 40),
            _buildHeader(mediaItem, isLiked, storage),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 20),
                    _buildAlbumArt(player, mediaItem),
                    const SizedBox(height: 20),
                    _buildTitleAndLike(mediaItem),
                    _streamProgressBar(player, mediaItem),
                    _playBackControl(player),
                    const SizedBox(height: 8),
                    _buildActionButtons(mediaItem, isDownloading, downloadProgress),
                    const SizedBox(height: 8),
                    _buildDjEntry(),
                    const SizedBox(height: 8),
                    _buildArtistCard(mediaItem),
                    const SizedBox(height: 24),
                    if (effectiveLyrics != null &&
                        parseTimedLyrics(effectiveLyrics, const Duration(minutes: 4)).isNotEmpty)
                      _buildLyricsCard(
                        player,
                        mediaItem,
                        effectiveLyrics,
                        ref.watch(translatedLyricsProvider(mediaItem.id)),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(MediaItem mediaItem, bool isLiked, StorageService storage) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
            onPressed: () {
              final close = widget.onClose;
              if (close != null) {
                close();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.nowPlaying,
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 2),
                _marqueeText(
                  mediaItem.album ?? '',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.tunefyDj,
                icon: const Icon(Icons.graphic_eq,
                    color: Color(0xFF1DB954), size: 24),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DjScreen()),
                  );
                },
              ),
              GestureDetector(
                onTap: () {
                  final muzoItem = _buildMuzoItemFromMedia(mediaItem);
                  SongOptionsMenu.show(ref, muzoItem, fromPlayer: true);
                },
                child: const Icon(Icons.more_vert, color: Colors.white, size: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(AudioPlayer player, MediaItem mediaItem) {
    return SizedBox(
      height: 340,
      child: StreamBuilder<SequenceState?>(
        stream: player.sequenceStateStream,
        builder: (context, seqSnap) {
          final seq = seqSnap.data;
          final queue = seq?.sequence ?? [];
          final curIdx = seq?.currentIndex ?? 0;

          if (queue.isEmpty) {
            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: mediaItem.artUri?.toString() ?? '',
                  width: MediaQuery.of(context).size.width * 0.80,
                  height: MediaQuery.of(context).size.width * 0.80,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: MediaQuery.of(context).size.width * 0.80,
                    height: MediaQuery.of(context).size.width * 0.80,
                    color: Colors.grey[800],
                    child: const Icon(Icons.music_note, color: Colors.white38, size: 64),
                  ),
                ),
              ),
            );
          }

          // Created on first build with the track that is actually playing, so
          // the pager never lands on page 0 and drags the player with it.
          _pageController ??= PageController(initialPage: curIdx);
          final pageController = _pageController!;

          return PageView.builder(
            controller: pageController,
            itemCount: queue.length,
            onPageChanged: (index) async {
              if (_programmaticPage == index) return;
              if (index != curIdx) {
                await player.seek(Duration.zero, index: index);
                await player.play();
              }
            },
            itemBuilder: (context, index) {
              final item = queue[index].tag as MediaItem;
              final screenWidth = MediaQuery.of(context).size.width;
              double imageWidth = screenWidth * 0.80 > 400 ? 400 : screenWidth * 0.80;
              return Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: item.artUri?.toString() ?? '',
                    width: imageWidth,
                    height: imageWidth,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: imageWidth,
                      height: imageWidth,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white38, size: 64),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTitleAndLike(MediaItem mediaItem) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _marqueeText(
                    mediaItem.title,
                    fontSize: 22,
                    letterSpacing: -1.4,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: 4),
                  _marqueeText(
                    mediaItem.artist ?? l10n.unknownArtist,
                    fontSize: 15,
                    letterSpacing: -1.4,
                    fontWeight: FontWeight.w300,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streamProgressBar(AudioPlayer player, MediaItem mediaItem) {
    final total = mediaItem.duration ?? player.duration ?? Duration.zero;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnapshot) {
        final pos = posSnapshot.data ?? Duration.zero;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 5),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, pressedElevation: 5, elevation: 0.5),
                  overlayShape: SliderComponentShape.noOverlay,
                  trackShape: const _CustomTrackShape(activeTrackHeight: 2, inactiveTrackHeight: 2),
                  trackHeight: 2,
                ),
                child: Slider(
                  value: total.inMilliseconds > 0
                      ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0,
                  onChanged: total == Duration.zero
                      ? null
                      : (v) => player.seek(Duration(milliseconds: (v * total.inMilliseconds).toInt())),
                  activeColor: Colors.white,
                  inactiveColor: Colors.white54.withAlpha(50),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _playBackControl(AudioPlayer player) {
    final audioHandler = ref.read(audioHandlerProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: audioHandler.isShuffleModeNotifier,
            builder: (context, isShuffle, _) {
              return GestureDetector(
                onTap: () => audioHandler.toggleShuffle(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Icon(Icons.shuffle, color: isShuffle ? const Color(0xFF1DB954) : Colors.white70, size: 24),
                      ),
                      if (isShuffle)
                        Positioned(
                          bottom: 2,
                          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF1DB954), shape: BoxShape.circle)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          GestureDetector(
            onTap: () => player.seekToPrevious(),
            child: const SizedBox(
              width: 55,
              height: 55,
              child: Center(child: Icon(Icons.skip_previous, color: Colors.white, size: 33)),
            ),
          ),
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
                  width: 75,
                  height: 75,
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                            width: 64,
                            height: 64,
                            child: SpotifySpinner(strokeWidth: 2.5, color: Color(0xFF1DB954)),
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Icon(
                              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 38,
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
          GestureDetector(
            onTap: () => player.seekToNext(),
            child: const SizedBox(
              width: 55,
              height: 55,
              child: Center(child: Icon(Icons.skip_next, color: Colors.white, size: 33)),
            ),
          ),
          ValueListenableBuilder<LoopMode>(
            valueListenable: audioHandler.repeatModeNotifier,
            builder: (context, repeatMode, _) {
              return GestureDetector(
                onTap: () => audioHandler.cycleRepeatMode(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Icon(
                          repeatMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                          color: repeatMode != LoopMode.off ? const Color(0xFF1DB954) : Colors.white70,
                          size: 24,
                        ),
                      ),
                      if (repeatMode != LoopMode.off)
                        Positioned(
                          bottom: 2,
                          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF1DB954), shape: BoxShape.circle)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(MediaItem mediaItem, bool isDownloading, double downloadProgress) {
    final l10n = AppLocalizations.of(context);
    final storage = ref.read(storageServiceProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Download
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: isDownloading
                ? null
                : () async {
                    if (storage.isDownloaded(mediaItem.id)) {
                      showGlassSnackBar(context, l10n.alreadyDownloaded);
                      return;
                    }
                    HapticFeedback.selectionClick();
                    final result = _buildMuzoItemFromMedia(mediaItem);
                    await ref.read(downloadProvider.notifier).startDownload(result);
                  },
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: isDownloading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: SpotifySpinner(
                          value: downloadProgress,
                          strokeWidth: 2,
                          color: const Color(0xFF1DDA63),
                          backgroundColor: Colors.white24,
                        ),
                      )
                    : ValueListenableBuilder(
                        valueListenable: storage.downloadsListenable,
                        builder: (context, _, __) {
                          final done = storage.isDownloaded(mediaItem.id);
                          return Image.asset(
                            done
                                ? 'assets/icons/complete_download.png'
                                : 'assets/icons/download.png',
                            width: 32,
                            height: 32,
                            color: done
                                ? const Color(0xFF1DDA63)
                                : Colors.white70,
                          );
                        },
                      ),
              ),
            ),
          ),
          // Device selector sits before the favourite "+".
          const AudioDeviceButton(
              size: 24, color: Colors.white70, showName: true),
          // Favorite (add/liked) — placed next to the download button.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              HapticFeedback.selectionClick();
              final result = _buildMuzoItemFromMedia(mediaItem);
              storage.toggleFavorite(result);
            },
            child: ValueListenableBuilder<List<MuzoItem>>(
              valueListenable: storage.favoritesListenable,
              builder: (context, favorites, _) {
                final liked = storage.isFavorite(mediaItem.id);
                return Image.asset(
                  liked ? 'assets/icons/tick.png' : 'assets/icons/add.png',
                  width: 32,
                  height: 32,
                  color: liked ? const Color(0xFF1DDA63) : Colors.white70,
                );
              },
            ),
          ),
          const Spacer(),
          // Share
          GestureDetector(
            onTap: () async {
              final details = StringBuffer();
              details.writeln("${l10n.songLabel}: ${mediaItem.title}");
              if (mediaItem.artist != null) details.writeln("${l10n.artistLabel}: ${mediaItem.artist}");
              if (mediaItem.album != null) details.writeln("${l10n.albumLabel}: ${mediaItem.album}");
              await Share.share(details.toString(), subject: l10n.sharingFromTunefy);
            },
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Center(child: Icon(Icons.share_outlined, color: Colors.white70, size: 24)),
            ),
          ),
          // Queue
          GestureDetector(
            onTap: _openQueueSheet,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Center(child: Icon(Icons.queue_music, color: Colors.white70, size: 24)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDjEntry() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DjScreen()),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: AppColors.cardTranslucent),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.graphic_eq, color: Color(0xFF1DB954), size: 20),
                const SizedBox(width: 10),
                Text(
                  l10n.tunefyDj,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtistCard(MediaItem mediaItem) {
    final l10n = AppLocalizations.of(context);
    final artistName = mediaItem.artist ?? '';
    final avatarUrl = mediaItem.artUri?.toString() ?? '';
    final displayName = (_artistDetails?.artistName.isNotEmpty ?? false)
        ? _artistDetails!.artistName
        : artistName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardTranslucent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 190,
                    child: avatarUrl.isNotEmpty
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[800],
                              child: const Icon(Icons.person, color: Colors.white38, size: 48),
                            ),
                          )
                        : Container(
                            color: Colors.grey[800],
                            child: const Icon(Icons.person, color: Colors.white38, size: 48),
                          ),
                  ),
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withAlpha(150),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 16,
                    right: 16,
                    child: Text(
                      l10n.aboutTheArtist,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            blurRadius: 10.0,
                            color: Colors.black,
                            offset: Offset(2.0, 2.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: -0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: _buildArtistBio(displayName),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtistBio(String artistName) {
    final l10n = AppLocalizations.of(context);
    if (artistName.trim().isEmpty) {
      return Text(
        l10n.tapToOpenArtistPage,
        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
      );
    }

    final bio = ref.watch(artistBioProvider(artistName)).valueOrNull;

    if (bio == null || bio.isEmpty) {
      return Text(
        l10n.tapToOpenArtistPage,
        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
      );
    }

    // The bio comes from French Wikipedia; translate it into the app's
    // selected language so the description follows the chosen language.
    final translatedBio =
        ref.watch(translatedTextProvider((text: bio))).valueOrNull ?? bio;

    const maxLines = 2;
    final isLong = translatedBio.length > 160;
    final needsEllipsis = isLong && !_biographyExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translatedBio,
          maxLines: needsEllipsis ? maxLines : null,
          overflow: needsEllipsis ? TextOverflow.ellipsis : null,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        if (isLong)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _biographyExpanded = !_biographyExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _biographyExpanded
                        ? l10n.reduce
                        : (ref.watch(translatedTextProvider((text: 'Read more')))
                                .valueOrNull ??
                            'Read more'),
                    style: const TextStyle(
                      color: Color(0xFF1DDA63),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _biographyExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF1DDA63),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLyricsCard(
    AudioPlayer player,
    MediaItem mediaItem,
    Lyrics lyrics,
    AsyncValue<List<TranslatedLyricLine>?> translatedAsync,
  ) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardTranslucent,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        l10n.lyricPreview,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.music_note,
                        color: const Color(0xFF1DDA63),
                        size: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 400,
                  width: double.infinity,
                  child:
                      _buildLyricsBody(player, mediaItem, lyrics, translatedAsync),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 34,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LyricsFullScreen(mediaItem: mediaItem),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text(
                          l10n.viewLyrics,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsBody(
    AudioPlayer player,
    MediaItem mediaItem,
    Lyrics lyrics,
    AsyncValue<List<TranslatedLyricLine>?> translatedAsync,
  ) {
  final l10n = AppLocalizations.of(context);
  final translatedLines = translatedAsync.valueOrNull;
  final showTranslation = translatedLines != null && translatedLines.isNotEmpty;

  final timed = parseTimedLyrics(
      lyrics, mediaItem.duration ?? const Duration(minutes: 4));

  if (timed.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lyrics_outlined, color: Colors.white38, size: 32),
          SizedBox(height: 8),
          Text(
            l10n.noLyricsFound,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  if (timed.length != _lyricsLineKeys.length) {
    _lyricsLineKeys
      ..clear()
      ..addAll(List.generate(timed.length, (_) => GlobalKey()));
  }

  return StreamBuilder<Duration>(
    stream: player.positionStream,
    builder: (context, snap) {
      final position = snap.data ?? Duration.zero;
      int active = 0;
      for (var i = 0; i < timed.length; i++) {
        if (position >= timed[i].time) {
          active = i;
        } else {
          break;
        }
      }

      if (active != _lyricsActiveLine) {
        _lyricsActiveLine = active;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || active >= _lyricsLineKeys.length) return;
          final ctx = _lyricsLineKeys[active].currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              alignment: 0.3,
            );
          }
        });
      }

      return ListView.builder(
        controller: _lyricsScrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: timed.length,
        itemBuilder: (context, i) {
          final line = timed[i];
          final isActive = i == active;
          TranslatedLyricLine? tr;
          if (showTranslation) {
            for (final t in translatedLines) {
              if (t.index == i) {
                tr = t;
                break;
              }
            }
          }
          final trText = tr == null
              ? null
              : (tr.text.isEmpty ? null : tr.text);
          return Padding(
            key: _lyricsLineKeys[i],
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontSize: isActive ? 16.5 : 14.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                height: 1.3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isActive && showTranslation && trText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        trText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1DDA63),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

}

class _QueueToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _QueueToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF1DB954).withValues(alpha: 0.18)
              : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFF1DB954) : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? const Color(0xFF1DB954) : Colors.white70,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTrackShape extends SliderTrackShape {
  final double activeTrackHeight;
  final double inactiveTrackHeight;

  const _CustomTrackShape({required this.activeTrackHeight, required this.inactiveTrackHeight});

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = inactiveTrackHeight;
    final double trackLeft = offset.dx + sliderTheme.overlayShape!.getPreferredSize(isEnabled, isDiscrete).width / 2;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width - sliderTheme.overlayShape!.getPreferredSize(isEnabled, isDiscrete).width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    Offset? secondaryOffset,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final Paint activePaint = Paint()..color = sliderTheme.activeTrackColor ?? Colors.white;
    final Paint inactivePaint = Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey;
    final Rect leftTrackSegment = Rect.fromLTRB(
      trackRect.left,
      trackRect.top + (trackRect.height - activeTrackHeight) / 2,
      thumbCenter.dx,
      trackRect.bottom - (trackRect.height - activeTrackHeight) / 2,
    );
    final Rect rightTrackSegment = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top + (trackRect.height - inactiveTrackHeight) / 2,
      trackRect.right,
      trackRect.bottom - (trackRect.height - inactiveTrackHeight) / 2,
    );
    context.canvas.drawRect(leftTrackSegment, activePaint);
    context.canvas.drawRect(rightTrackSegment, inactivePaint);
  }
}
