import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/widgets/spotify_back_button.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.item});

  final MuzoItem item;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _error = false;

  static final YoutubeExplode _yt = YoutubeExplode();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final videoId = widget.item.videoId;
    if (videoId == null || videoId.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = true; });
      return;
    }
    try {
      final url = await _resolveVideoUrl(videoId);
      if (!mounted) return;
      if (url == null) {
        setState(() { _loading = false; _error = true; });
        return;
      }
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = vc;
      await vc.initialize();
      if (!mounted) {
        await vc.dispose();
        return;
      }
      await vc.setLooping(true);
      await vc.play();
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('VideoPlayerScreen: $e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  static Future<String?> _resolveVideoUrl(String videoId) async {
    try {
      final viaService = await StreamExtractionService.getVideoStreamUrl(videoId);
      if (viaService != null) return viaService;
    } catch (e) {
      debugPrint('VideoPlayerScreen: service failed — $e');
    }
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 12));
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
      if (muxed.isNotEmpty) return muxed.first.url.toString();
    } catch (e) {
      debugPrint('VideoPlayerScreen: ytexplode failed — $e');
    }
    return null;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _buildContent(l10n),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: SpotifyBackButton(
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_loading) {
      return const CircularProgressIndicator(color: Color(0xFF1DB954));
    }
    if (_error || _controller == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.clipUnavailable,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      );
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}
