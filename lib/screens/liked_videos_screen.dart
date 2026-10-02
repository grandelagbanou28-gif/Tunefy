import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/screens/clips_feed_screen.dart';
import 'package:muzo/providers/overlay_scenes.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/spotify_back_button.dart';

/// "Liked videos" — a YouTube-style vertical feed of the clips behind every
/// track the user hearted. Reuses the clips player, so scrolling, muting and
/// the like / share / download rail behave exactly like the discovery feed.
class LikedVideosScreen extends ConsumerWidget {
  const LikedVideosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final storage = ref.watch(storageServiceProvider);
    final clips = <MuzoItem>[
      for (final song in storage.getFavorites())
        if ((song.videoId ?? '').isNotEmpty) song,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              child: Row(
                children: [
                  const SpotifyBackButton(),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.likedVideos,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (clips.isNotEmpty)
                    Text(
                      l10n.playlistSongsCount(clips.length),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: clips.isEmpty
                  ? _EmptyLikedVideos(message: l10n.likedVideosEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: clips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _LikedVideoRow(
                        clip: clips[index],
                        index: index,
                        total: clips.length,
                        clips: clips,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikedVideoRow extends StatelessWidget {
  const _LikedVideoRow({
    required this.clip,
    required this.index,
    required this.total,
    required this.clips,
  });

  final MuzoItem clip;
  final int index;
  final int total;
  final List<MuzoItem> clips;

  @override
  Widget build(BuildContext context) {
    final thumb = clip.thumbnails.isNotEmpty ? clip.thumbnails.last.url : '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
SlidePageRoute(
              page: ClipsFeedScreen(initialIndex: index, externalClips: clips),
              arguments: const SceneArg(PlayerScene.clips),
            ),
        );
      },
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 88,
              child: thumb.isEmpty
                  ? Container(
                      color: const Color(0xFF282828),
                      child: const Icon(Icons.music_note, color: Colors.white54),
                    )
                  : Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF282828),
                        child: const Icon(Icons.music_note, color: Colors.white54),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  clip.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.play_circle_fill, color: Color(0xFF1DDA63), size: 30),
        ],
      ),
    );
  }
}

class _EmptyLikedVideos extends StatelessWidget {
  const _EmptyLikedVideos({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_border, color: Colors.white38, size: 56),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
