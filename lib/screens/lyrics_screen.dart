import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/services/lyrics_service.dart';
import 'package:muzo/widgets/lyrics_view.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/theme_provider.dart';
import 'package:muzo/widgets/spotify_spinner.dart';
import 'dart:ui';

class LyricsScreen extends ConsumerStatefulWidget {
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int durationSeconds;

  const LyricsScreen({
    super.key,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.durationSeconds,
  });

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  Lyrics? _lyrics;
  bool _isLoading = true;
  String? _lastFetchedTitle;
  String? _lastFetchedArtist;

  @override
  void initState() {
    super.initState();
    _fetchLyrics(widget.title, widget.artist, widget.durationSeconds);
    ref.listen(currentMediaItemProvider, (prev, next) {
      final media = next.value;
      if (media == null) return;
      final newTitle = media.title;
      final newArtist = media.artist ?? '';
      if (newTitle == _lastFetchedTitle && newArtist == _lastFetchedArtist) return;
      _lastFetchedTitle = newTitle;
      _lastFetchedArtist = newArtist;
      if (mounted) {
        setState(() {
          _isLoading = true;
          _lyrics = null;
        });
      }
      _fetchLyrics(newTitle, newArtist, media.duration?.inSeconds ?? 0);
    });
  }

  Future<void> _fetchLyrics(String title, String artist, int duration) async {
    _lastFetchedTitle = title;
    _lastFetchedArtist = artist;
    try {
      final lyrics = await ref
          .read(lyricsServiceProvider)
          .fetchLyrics(title, artist, duration);
      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = ref.watch(audioHandlerProvider);
    final media = ref.watch(currentMediaItemProvider).valueOrNull;
    final title = media?.title ?? widget.title;
    final artist = media?.artist ?? widget.artist;
    final thumbnailUrl = media?.artUri?.toString() ?? widget.thumbnailUrl;
    final durationSeconds = media?.duration?.inSeconds ?? widget.durationSeconds;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            FluentIcons.chevron_down_24_regular,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              "Lyrics",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            Text(
              "$title • $artist",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Blur
          Positioned.fill(
            child: thumbnailUrl != null
                ? Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.black),
                  )
                : Container(color: Colors.black),
          ),
          Positioned.fill(
            child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), // Reduced for 60fps scrolling
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.6), // Darkened for text contrast
                    ),
                  ),
          ),

          // Content
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: SpotifySpinner(color: Colors.white),
                  )
                : _lyrics == null
                ? _buildNotFound()
                : LyricsView(
                    lyrics: _lyrics!,
                    onClose: () {},
                    positionStream: audioHandler.player.positionStream,
                    totalDuration:
                        Duration(seconds: durationSeconds),
                    isEmbedded: false,
                    accentColor: () {
                      final palette = ref
                          .watch(currentPaletteProvider)
                          .asData
                          ?.value;
                      if (palette != null) {
                        return (palette.darkVibrantColor?.color ??
                            palette.darkMutedColor?.color ??
                            palette.dominantColor?.color);
                      }
                      return null;
                    }(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.text_quote_24_regular,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            "Lyrics not found",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            "We couldn't find lyrics for this song.",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
