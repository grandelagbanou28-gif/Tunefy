import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/providers/explore_provider.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

class LibraryMadeForYouScreen extends ConsumerWidget {
  const LibraryMadeForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPicksAsync = ref.watch(topOnMuzoProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    const SpotifyBackButton(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        l10n.madeForYou,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: spotifyWhite),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            topPicksAsync.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: SpotifySpinner(color: Color(0xFF1DDA63))),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(l10n.errorLoadingContent, style: TextStyle(color: spotifyLightGrey)),
                ),
              ),
              data: (songs) {
                if (songs.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(l10n.noRecommendationsYet, style: TextStyle(color: spotifyLightGrey)),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = songs[index];
                        final img = song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';
                        return SpotifySongChip(
                          imageUrl: img,
                          songTitle: song.title,
                          singerName: song.displayArtist,
                          size: 47,
                          videoId: song.videoId,
                          result: song,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            openArtistForSong(context, song);
                          },
                        );
                      },
                      childCount: songs.length,
                    ),
                  ),
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
          ],
        ),
      ),
    );
  }
}
