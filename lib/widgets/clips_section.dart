import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/clips_provider.dart';
import 'package:muzo/screens/clips_feed_screen.dart';
import 'package:muzo/providers/overlay_scenes.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Horizontal strip of 30s clip cards (like YouTube Shorts) shown at the top
/// of Browse All. Tapping a card opens the vertical clips feed — the video
/// plays full screen and you swipe up/down for the next one.
class ClipsSection extends ConsumerWidget {
  const ClipsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final clipsAsync = ref.watch(clipsFeedProvider);
    final clips = clipsAsync.value ?? const <MuzoItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill,
                  color: Color(0xFF1DDA63), size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.clipsTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: spotifyWhite,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (clips.isEmpty && clipsAsync.isLoading)
          SizedBox(
            height: 140,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: SpotifySpinner(
                  strokeWidth: 2.5,
                  color: spotifyGreen.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else if (clips.isEmpty)
          SizedBox(
            height: 140,
            child: Center(
              child: GestureDetector(
                onTap: () => ref.read(clipsFeedProvider.notifier).loadMore(),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, color: Colors.white54, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      clipsAsync.hasError
                          ? l10n.clipsUnavailableRetry
                          : l10n.clipsNoneRetry,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: clips.length > 5 ? 5 : clips.length,
              itemBuilder: (context, index) {
                return _ClipCard(
                  clip: clips[index],
                  index: index,
                  onTap: () {
                    HapticFeedback.selectionClick();
Navigator.of(context).push(
                         SlidePageRoute(
                           page: ClipsFeedScreen(initialIndex: index),
                           arguments: const SceneArg(PlayerScene.clips),
                         ),
                       );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ClipCard extends StatelessWidget {
  const _ClipCard({
    required this.clip,
    required this.index,
    required this.onTap,
  });

  final MuzoItem clip;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = clip.thumbnails.isNotEmpty
        ? clip.thumbnails.last.url
        : '';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: spotifyDarkGrey,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: thumb.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: spotifyDarkGrey,
                        child: const Center(
                          child: Icon(Icons.music_note,
                              color: spotifyGreen, size: 28),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: spotifyDarkGrey,
                        child: const Center(
                          child: Icon(Icons.music_note,
                              color: spotifyGreen, size: 28),
                        ),
                      ),
                    )
                  : Container(
                      color: spotifyDarkGrey,
                      child: const Center(
                        child: Icon(Icons.music_note,
                            color: spotifyGreen, size: 28),
                      ),
                    ),
            ),
            // Bottom gradient for legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),
            // Rank badge (kept subtle) + play affordance
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Duration badge
            if (clip.durationSeconds != null)
              Positioned(
                bottom: 44,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(clip.durationSeconds!),
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            // Overlay play icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: spotifyWhite,
                  size: 30,
                ),
              ),
            ),
            // Title + artist at the bottom
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    clip.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: spotifyWhite.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
