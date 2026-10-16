import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/overlay_scenes.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Pro concert-video page, YouTube-style:
/// - 16:9 player with tap-to-toggle controls, seekable progress bar,
///   play/pause button and time labels;
/// - title + artist below the player;
/// - the remaining videos of the same list ("up next") underneath.
/// The mini player is hidden while this page is open.
class ConcertVideoScreen extends ConsumerStatefulWidget {
  const ConcertVideoScreen({
    super.key,
    required this.videos,
    this.initialIndex = 0,
  });

  final List<MuzoItem> videos;
  final int initialIndex;

  @override
  ConsumerState<ConcertVideoScreen> createState() => _ConcertVideoScreenState();
}

class _ConcertVideoScreenState extends ConsumerState<ConcertVideoScreen> {
  VideoPlayerController? _controller;
  int _index = 0;
  bool _loading = true;
  bool _error = false;
  bool _showControls = true;
  Timer? _hideTimer;
  // Videos that failed to resolve in this session: skipped automatically so
  // one dead link never blocks the page. The error state only shows when
  // every video in the list failed.
  final Set<int> _failed = <int>{};

  MuzoItem get _current => widget.videos[_index];

  @override
void initState() {
      super.initState();
      _index = widget.initialIndex.clamp(0, widget.videos.length - 1);
      // The mini player is hidden because this route is tagged as a player
      // scene (see the push helper at the bottom of this file) — no flag to set
      // here, and therefore none that can survive a botched teardown.
      // The video must be the only sound, so any audio is stopped.
      unawaited(ref.read(audioHandlerProvider).pause());
      _load(_index);
    }

    @override
    void dispose() {
      _hideTimer?.cancel();
      _controller?.dispose();
      super.dispose();
    }

  Future<void> _load(int index) async {
    final old = _controller;
    _controller = null;
    if (old != null) await old.dispose();
    if (!mounted) return;
    setState(() {
      _index = index;
      _loading = true;
      _error = false;
      _showControls = true;
    });
    _armHideTimer();
    final videoId = widget.videos[index].videoId;
    if (videoId == null || videoId.isEmpty) {
      await _failOrNext(index);
      return;
    }
    try {
      final url =
          await StreamExtractionService.getVideoStreamUrl(videoId).timeout(
        const Duration(seconds: 60),
      );
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        await _failOrNext(index);
        return;
      }
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = vc;
      await vc.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) {
        await vc.dispose();
        return;
      }
      vc.addListener(_onEnded);
      await vc.setLooping(false);
      await vc.play();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('ConcertVideoScreen: $e');
      await _failOrNext(index);
    }
  }

  /// A video that cannot resolve is skipped like an ended one: the next
  /// playable video loads on its own. The error state only appears when every
  /// video in the list failed — then Retry clears the dead set and tries the
  /// current video again.
  Future<void> _failOrNext(int index) async {
    if (!mounted) return;
    _failed.add(index);
    var next = -1;
    for (var i = 0; i < widget.videos.length; i++) {
      if (!_failed.contains(i)) {
        next = i;
        break;
      }
    }
    if (next == -1) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    await _load(next);
  }

  void _onEnded() {
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) return;
    final pos = vc.value.position;
    final dur = vc.value.duration;
    if (dur > Duration.zero && pos >= dur - const Duration(milliseconds: 400)) {
      _playNext();
    }
  }

  void _playNext() {
    if (_index + 1 < widget.videos.length) {
      HapticFeedback.selectionClick();
      unawaited(_load(_index + 1));
    }
  }

  void _togglePlayPause() {
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) return;
    HapticFeedback.selectionClick();
    if (vc.value.isPlaying) {
      unawaited(vc.pause());
    } else {
      unawaited(vc.play());
    }
    setState(() {});
    _armHideTimer();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _armHideTimer();
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final vc = _controller;
      if (vc != null && vc.value.isInitialized && vc.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildPlayer(l10n)),
            SliverToBoxAdapter(child: _buildMeta()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  l10n.concertEventVideos,
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final v = widget.videos[i];
                    return _UpNextRow(
                      video: v,
                      playing: i == _index,
                      onTap: () {
                        if (i == _index) return;
                        HapticFeedback.selectionClick();
                        // Explicit tap retries even a video skipped before.
                        _failed.remove(i);
                        unawaited(_load(i));
                      },
                    );
                  },
                  childCount: widget.videos.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer(AppLocalizations l10n) {
    final vc = _controller;
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: SpotifySpinner(
                        strokeWidth: 2.5,
                        color: Color(0xFF1DDA63),
                      ),
                    ),
                  )
                : _error || vc == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.videocam_off,
                                color: Colors.white38, size: 44),
                            const SizedBox(height: 8),
                            Text(
                              l10n.clipUnavailable,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () {
                                _failed.clear();
                                unawaited(_load(_index));
                              },
                              child: Text(
                                l10n.retry,
                                style: const TextStyle(
                                  color: Color(0xFF1DDA63),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControls,
                        child: VideoPlayer(vc),
                      ),
          ),
        ),
        // Top bar: back + title.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 18),
              child: Row(
                children: [
                  SpotifyBackButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _current.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom controls: progress + play/pause + times.
        if (_showControls && !_loading && !_error && vc != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 18, 12, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _ControlButton(
                          icon: vc.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onTap: _togglePlayPause,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: vc,
                            builder: (context, value, _) {
                              final dur = value.duration;
                              final pos = value.position;
                              return Row(
                                children: [
                                  Text(
                                    _fmt(pos),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 3,
                                        thumbShape:
                                            const RoundSliderThumbShape(
                                                enabledThumbRadius: 6),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                                overlayRadius: 12),
                                        activeTrackColor:
                                            const Color(0xFF1DDA63),
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: const Color(0xFF1DDA63),
                                      ),
                                      child: Slider(
                                        value: dur > Duration.zero
                                            ? pos.inMilliseconds
                                                .clamp(0, dur.inMilliseconds)
                                                .toDouble()
                                            : 0,
                                        max: dur > Duration.zero
                                            ? dur.inMilliseconds.toDouble()
                                            : 1,
                                        onChangeStart: (_) =>
                                            _hideTimer?.cancel(),
                                        onChanged: (v) async {
                                          await vc.seekTo(Duration(
                                              milliseconds: v.toInt()));
                                        },
                                        onChangeEnd: (_) => _armHideTimer(),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _fmt(dur),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        _ControlButton(
                          icon: Icons.skip_next_rounded,
                          enabled: _index + 1 < widget.videos.length,
                          onTap: _playNext,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Center play/pause flash when paused.
        if (_showControls &&
            !_loading &&
            !_error &&
            vc != null &&
            vc.value.isInitialized &&
            !vc.value.isPlaying)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMeta() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _current.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: spotifyWhite,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (_current.displayArtist.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _current.displayArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onTap, this.enabled = true});

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: enabled ? Colors.white : Colors.white30, size: 30),
      onPressed: enabled ? onTap : null,
    );
  }
}

class _UpNextRow extends StatelessWidget {
  const _UpNextRow({
    required this.video,
    required this.playing,
    required this.onTap,
  });

  final MuzoItem video;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb =
        video.thumbnails.isNotEmpty ? video.thumbnails.last.url : '';
    final dur = video.durationSeconds;
    final durLabel = dur != null && dur > 0
        ? '${dur ~/ 60}:${'${dur % 60}'.padLeft(2, '0')}'
        : '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: thumb,
                    width: 146,
                    height: 82,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 146,
                      height: 82,
                      color: spotifyDarkGrey,
                      child: const Icon(Icons.music_video,
                          color: spotifyLightGrey, size: 28),
                    ),
                  ),
                  if (playing)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: const Center(
                          child: Icon(
                            Icons.equalizer_rounded,
                            color: Color(0xFF1DDA63),
                            size: 28,
                          ),
                        ),
                      ),
                    )
                  else
                    const Positioned.fill(
                      child: Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  if (durLabel.isNotEmpty)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          durLabel,
                          style: const TextStyle(
                            color: spotifyWhite,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: playing ? const Color(0xFF1DDA63) : spotifyWhite,
                      fontSize: 13.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (video.displayArtist.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      video.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: spotifyLightGrey.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pushes the YouTube-style concert video page. Exported so artist and
/// concert-detail screens share the exact same entry point.
void openConcertVideo(
  BuildContext context,
  List<MuzoItem> videos,
  int index,
) {
  if (videos.isEmpty) return;
  HapticFeedback.selectionClick();
  Navigator.of(context).push(
    SlidePageRoute(
      page: ConcertVideoScreen(
        videos: videos,
        initialIndex: index.clamp(0, videos.length - 1),
      ),
      arguments: const SceneArg(PlayerScene.clips),
    ),
  );
}
