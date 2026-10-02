import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/clips_provider.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/pexels_api_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/widgets/spotify_spinner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// TikTok-style vertical clips feed: full-screen swipeable music videos with
/// like / share / download actions. Real video streams (360p muxed) play
/// inline; when a stream cannot be opened the clip falls back to its cover
/// art with the audio running through the normal player.
class ClipsFeedScreen extends ConsumerStatefulWidget {
  const ClipsFeedScreen({
    super.key,
    this.initialIndex = 0,
    this.externalClips,
  });

  final int initialIndex;

  /// When provided, the feed plays this fixed list instead of the rotating
  /// clip queries — used by "Liked videos", so the same vertical player
  /// serves the user's own library.
  final List<MuzoItem>? externalClips;

  @override
  ConsumerState<ClipsFeedScreen> createState() => _ClipsFeedScreenState();
}

class _ClipsFeedScreenState extends ConsumerState<ClipsFeedScreen> {
  late final PageController _controller;
  final ScrollController _dotsScrollController = ScrollController();
  ClipPageController? _active;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _currentPage = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    // Nothing to set up for the mini player: the layout reads `overlayScenes`,
    // which the navigator observer derives from this route being on the stack.
    // That is the point — no flag means nothing to forget to clear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The clip speaks for itself: audio and video at the same time means two
      // competing soundtracks, and the track that was playing just kept going
      // under the feed. Pausing here (not on every page change) stops the
      // audio once, when the feed takes over the screen.
      final handler = ref.read(audioHandlerProvider);
      if (handler.player.playing) {
        handler.pause();
      }
    });
  }

  @override
  void dispose() {
    _active?.dispose();
    _controller.dispose();
    _dotsScrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _activate(int index, List<MuzoItem> clips) {
    if (index < 0 || index >= clips.length) return;
    final item = clips[index];
    if (_active?.videoId == item.videoId) return;
    _active?.dispose();
    // Video only: the clip speaks for itself and no audio track is started,
    // so the mini player never pops up over the feed.
    _active = ClipPageController(
      item: item,
      handlerPlayer: ref.read(audioHandlerProvider).player,
    )..start();
  }

  void _scrollDotsToIndex(int index) {
    if (!_dotsScrollController.hasClients) return;
    final target = (index * 18.0) - 80.0;
    _dotsScrollController.animateTo(
      target.clamp(0.0, _dotsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool _activatedInitial = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final external = widget.externalClips;
    final clipsAsync =
        external != null ? AsyncValue.data(external) : ref.watch(clipsFeedProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: clipsAsync.when(
        loading: () => const Center(
          child: SpotifySpinner(color: Color(0xFF1DDA63)),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.clipsLoadFailed,
                  style: TextStyle(color: Colors.white.withValues(alpha: .8))),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.read(clipsFeedProvider.notifier).loadMore(),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (clips) {
          if (clips.isEmpty) {
            return Center(
              child: Text(l10n.clipsEmpty,
                  style: TextStyle(color: Colors.white70)),
            );
          }
          if (!_activatedInitial) {
            _activatedInitial = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _activate(widget.initialIndex, clips);
            });
          }
          return Stack(

            children: [
              PageView.builder(
                controller: _controller,
                scrollDirection: Axis.vertical,
                itemCount: clips.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentPage = i);
                  _activate(i, clips);
                  _scrollDotsToIndex(i);
                  // A fixed list (liked videos) must not trigger pagination.
                  if (widget.externalClips == null) {
                    ref.read(clipsFeedProvider.notifier).onPageChanged(i);
                  }
                },
                itemBuilder: (context, i) {
                  return _ClipPage(
                    key: ValueKey(clips[i].videoId),
                    item: clips[i],
                    activeController: _active,
                    isActive: _active?.videoId == clips[i].videoId,
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 80,
                child: SizedBox(
                  height: 20,
                  child: ListView.builder(
                    controller: _dotsScrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: clips.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, i) {
                      final active = i == _currentPage;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _controller.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: active ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Owns one page's video playback. The video track is MUTED — all audio runs
/// through the global audio handler so the mini player reflects the clip and
/// sound keeps playing after leaving the feed. When the music video cannot be
/// resolved, a stock clip stands in so the feed never shows a still picture.
class ClipPageController {
  ClipPageController({
    required this.item,
    required this.handlerPlayer,
    PexelsApiService? pexels,
  })  : videoId = item.videoId,
        _pexels = pexels ?? PexelsApiService();

  final MuzoItem item;
  final String? videoId;
  final dynamic handlerPlayer;
  final PexelsApiService _pexels;
  VideoPlayerController? _player;
  StreamSubscription<bool>? _playingSub;
  Timer? _fallbackTimer;
  bool disposed = false;

  /// True when the playing video is a stock stand-in rather than the real
  /// music video, so the page can credit the source.
  bool get isBackdrop => _backdrop;

  bool _backdrop = false;

  /// Keywords sent to the stock library when the music video is unavailable.
  String get _backdropQuery {
    final genre = item.metadata?['genre']?.toString() ?? '';
    if (genre.isNotEmpty) return 'live $genre music concert';
    final artist = item.displayArtist;
    if (artist.isNotEmpty) return 'live $artist concert';
    return 'live music concert';
  }

  Future<void> start() async {
    try {
      final url = await resolveVideoUrl(item.videoId!);
      if (disposed) return;
      if (url == null) {
        await _startBackdrop();
        return;
      }
      await _attach(Uri.parse(url), backdrop: false);
    } catch (_) {
      if (!disposed) await _startBackdrop();
    }
  }

  /// Stock clip stand-in: same muted-video treatment, so a clip whose music
  /// video is blocked still moves instead of freezing on the cover art.
  Future<void> _startBackdrop() async {
    if (disposed || !_pexels.isConfigured) return;
    try {
      final clip = await _pexels.findClip(
        _backdropQuery,
        cacheKey: 'clip:$videoId',
      );
      if (clip == null || disposed) return;
      await _attach(Uri.parse(clip.videoUrl), backdrop: true);
    } catch (_) {
      // Cover-art fallback keeps the feed usable.
    }
  }

  Future<void> _attach(Uri url, {required bool backdrop}) async {
    final vc = VideoPlayerController.networkUrl(url);
    _player = vc;
    _backdrop = backdrop;
    await vc.initialize();
    if (disposed) {
      await vc.dispose();
      return;
    }
    await vc.setLooping(true);
    // Stock backdrops carry no usable audio, so they stay silent; a real clip
    // plays its own sound. The feed no longer relies on the audio handler, so
    // it must start on its own.
    await vc.setVolume(backdrop ? 0 : 100);
    await vc.play();
    // No mirroring of the audio handler any more. The feed pauses the music when
    // it opens, and this subscription treated "handler not playing" as "pause the
    // clip" — which froze the video the instant the feed appeared. The clip owns
    // its playback; nothing outside this screen can stop it.
  }

  static final YoutubeExplode _yt = YoutubeExplode();

  /// Best muxed stream URL under a sane size cap, else lowest videoOnly.
  ///
  /// Order: the app's own extraction service first (it already races every
  /// resolver and caches hits), then YoutubeExplode, then the stock backdrop.
  /// YoutubeExplode is last because YouTube's bot-check makes it fail slowly
  /// from a phone IP, which used to hold the page on "video unavailable".
  static Future<String?> resolveVideoUrl(String videoId,
      {int capMb = 45}) async {
    try {
      final viaService = await StreamExtractionService.getVideoStreamUrl(videoId);
      if (viaService != null) return viaService;
    } catch (e) {
      debugPrint('ClipPageController: video service failed — $e');
    }
    final viaYt = await _resolveViaYoutubeExplode(videoId, capMb: capMb);
    if (viaYt != null) return viaYt;
    try {
      return await StreamExtractionService.getVideoStreamUrl(videoId);
    } catch (e) {
      debugPrint('ClipPageController: local video server failed — $e');
      return null;
    }
  }

  static Future<String?> _resolveViaYoutubeExplode(String videoId,
      {int capMb = 45}) async {
    try {
      final manifest =
          await _yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 12));
      // Prefer a small-ish muxed stream (plays everywhere): largest one
      // still under a sane size cap so quality stays decent on mobile data.
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
      final cap = capMb * 1024 * 1024;
      if (muxed.isNotEmpty) {
        AudioStreamInfo? best;
        for (final s in muxed) {
          if (s.size.totalBytes <= cap) best = s;
        }
        return (best ?? muxed.first).url.toString();
      }
      final videoOnly = manifest.videoOnly.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
      if (videoOnly.isNotEmpty) return videoOnly.first.url.toString();
    } catch (_) {
      return null;
    }
    return null;
  }

  void dispose() {
    disposed = true;
    _fallbackTimer?.cancel();
    _playingSub?.cancel();
    _player?.pause();
    _player?.dispose();
    _player = null;
  }
}

/// Like / dislike persistence for clips (separate from favorites).
class ClipReactions {
  static Future<Set<String>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? <String>[]).toSet();
  }

  static Future<bool> isLiked(String id) async => (await _load('clip_liked')).contains(id);
  static Future<bool> isDisliked(String id) async =>
      (await _load('clip_disliked')).contains(id);

  static Future<void> toggleLike(String id) => _toggle('clip_liked', 'clip_disliked', id);
  static Future<void> toggleDislike(String id) => _toggle('clip_disliked', 'clip_liked', id);

  static Future<void> _toggle(String key, String opposite, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(key) ?? <String>[]).toSet();
    final other = (prefs.getStringList(opposite) ?? <String>[]).toSet()..remove(id);
    if (!set.remove(id)) set.add(id);
    await prefs.setStringList(key, set.toList());
    await prefs.setStringList(opposite, other.toList());
  }
}

/// Fond fixe affiché quand aucune vidéo n'a pu être résolue pour ce clip.
class _ClipUnavailableBackdrop extends StatelessWidget {
  const _ClipUnavailableBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFF1A1A2E));
  }
}

class _ClipPage extends ConsumerStatefulWidget {
  const _ClipPage({
    super.key,
    required this.item,
    required this.activeController,
    required this.isActive,
  });

  final MuzoItem item;
  final ClipPageController? activeController;
  final bool isActive;

  @override
  ConsumerState<_ClipPage> createState() => _ClipPageState();
}

class _ClipPageState extends ConsumerState<_ClipPage> {
  bool? _liked;

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    final id = widget.item.videoId!;
    _liked = await ClipReactions.isLiked(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final thumb = item.thumbnails.isNotEmpty ? item.thumbnails.last.url : '';
    final video = widget.activeController?._player;
    final hasVideo = widget.isActive && video != null && video.value.isInitialized;
    final isBackdrop = hasVideo && (widget.activeController?.isBackdrop ?? false);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ─── Visual layer ───
        if (hasVideo)
          // FittedBox(cover) over the full screen, *without* an AspectRatio
          // parent: AspectRatio sizes to the ratio inside the viewport, which
          // for a 16:9 clip on a tall phone means a small band with black bars.
          // Letting cover fill and crop is what a clips feed looks like.
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: video.value.size.width,
                height: video.value.size.height,
                child: VideoPlayer(video),
              ),
            ),
          )
        else
          // Aucune vidéo playable : on affiche un état fixe et discret. Le
          // zoom lent (Ken Burns) sur la pochette est volontairement retiré —
          // une image qui bouge donne l'illusion d'un clip qui tourne.
          Stack(
            fit: StackFit.expand,
            children: [
              if (thumb.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const _ClipUnavailableBackdrop(),
                  errorWidget: (_, __, ___) => const _ClipUnavailableBackdrop(),
                  color: const Color(0xFF1A1A2E).withValues(alpha: .55),
                  colorBlendMode: BlendMode.srcOver,
                )
              else
                const _ClipUnavailableBackdrop(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.white70, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      l10n.clipUnavailable,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

        // ─── Gradients for legibility ───
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Colors.black.withValues(alpha: .45), Colors.transparent],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black.withValues(alpha: .65), Colors.transparent],
              ),
            ),
            child: const SizedBox(height: 320, width: double.infinity),
          ),
        ),

        // Tap toggles pause/play on the clip itself. It used to drive the audio
        // handler, but the clip no longer goes through it — tapping the video
        // resumed the *track* while the video kept running.
        // Double-tap left/right seeks backward/forward.
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              final vc = widget.activeController?._player;
              if (vc == null) return;
              if (vc.value.isPlaying) {
                vc.pause();
              } else {
                vc.play();
              }
            },
            onDoubleTapDown: (details) {
              final w = MediaQuery.of(context).size.width;
              final vc = widget.activeController?._player;
              if (vc == null) return;
              final pos = vc.value.position;
              final dur = vc.value.duration;
              if (details.localPosition.dx < w / 2) {
                final target = pos - const Duration(seconds: 10);
                vc.seekTo(target < Duration.zero ? Duration.zero : target);
              } else {
                final target = pos + const Duration(seconds: 10);
                vc.seekTo(target > dur ? dur : target);
              }
              HapticFeedback.selectionClick();
            },
          ),
        ),

        // ─── Right rail actions ───
        Positioned(
          right: 12,
          bottom: 140,
          child: Column(
            children: [
              _railAction(
                icon: (_liked ?? false)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: (_liked ?? false) ? const Color(0xFFFE2C55) : Colors.white,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await ClipReactions.toggleLike(item.videoId!);
                  _liked = await ClipReactions.isLiked(item.videoId!);
                  setState(() {});
                  if (_liked ?? false) {
                    try {
                      await ref.read(storageServiceProvider).toggleFavorite(item);
                    } catch (_) {}
                  }
                },
              ),
              const SizedBox(height: 18),
              _railAction(
                icon: Icons.shortcut_rounded,
                color: Colors.white,
                onTap: () {
                  HapticFeedback.selectionClick();
                  final id = item.videoId;
                  if (id == null) return;
                  // ignore: deprecated_member_use
                  Share.share('https://youtube.com/watch?v=$id');
                },
              ),
              const SizedBox(height: 18),
              _DownloadRailButton(item: item),
            ],
          ),
        ),

        // ─── Bottom info ───
        Positioned(
          left: 16,
          right: 84,
          bottom: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '@${item.displayArtist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              // Pexels asks for the source to be credited when the API is
              // used for free, so a stock backdrop is labelled as such.
              if (isBackdrop) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.pexels.com/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    l10n.clipVideoCredit,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 11.5,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white38,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _railAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: 34),
    );
  }
}

/// Downloads the clip as a real VIDEO file and saves it to the device
/// Gallery (Movies/Tunefy). Progress is local to the button; completion is
/// persisted so the check mark survives restarts.
class _DownloadRailButton extends ConsumerStatefulWidget {
  const _DownloadRailButton({required this.item});

  final MuzoItem item;

  @override
  ConsumerState<_DownloadRailButton> createState() => _DownloadRailButtonState();
}

class _DownloadRailButtonState extends ConsumerState<_DownloadRailButton> {
  double? _progress;
  bool _done = false;
  bool _failed = false;
  static const _doneKey = 'clip_gallery_dl';

  @override
  void initState() {
    super.initState();
    _loadDone();
  }

  Future<void> _loadDone() async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_doneKey) ?? <String>[]);
    final id = widget.item.videoId;
    if (id != null && set.contains(id) && mounted) setState(() => _done = true);
  }

  Future<void> _download() async {
    final id = widget.item.videoId;
    if (id == null || _progress != null || _done) return;
    setState(() {
      _progress = 0.0;
      _failed = false;
    });
    try {
      final url = await ClipPageController.resolveVideoUrl(id, capMb: 90);
      if (url == null) throw Exception('stream unavailable');

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/tunefy_clip_$id.mp4';
      await Dio().download(
        url,
        path,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = (received / total).clamp(0.0, 0.95));
          }
        },
      );

      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(path, album: 'Tunefy');
      if (File(path).existsSync()) File(path).deleteSync();

      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_doneKey) ?? <String>[])..add(id);
      await prefs.setStringList(_doneKey, set);

      if (mounted) {
        setState(() {
          _progress = null;
          _done = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _progress = null;
          _failed = true;
        });
        Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _failed = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_progress != null || _done || _failed) return;
        HapticFeedback.selectionClick();
        unawaited(_download());
      },
      child: _progress != null
          ? SizedBox(
              width: 30,
              height: 30,
              child: SpotifySpinner(
                value: _progress,
                strokeWidth: 3,
                color: const Color(0xFF1DDA63),
              ),
            )
          : Icon(
              _failed
                  ? Icons.error_outline_rounded
                  : _done
                      ? Icons.download_done_rounded
                      : Icons.save_alt_rounded,
              color: _failed
                  ? Colors.redAccent
                  : _done
                      ? const Color(0xFF1DDA63)
                      : Colors.white,
              size: 32,
            ),
    );
  }
}
