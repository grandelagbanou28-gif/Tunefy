import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/screens/channel_screen.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_search_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';

class LibraryPodcastsScreen extends ConsumerStatefulWidget {
  const LibraryPodcastsScreen({super.key});

  @override
  ConsumerState<LibraryPodcastsScreen> createState() =>
      _LibraryPodcastsScreenState();
}

class _LibraryPodcastsScreenState extends ConsumerState<LibraryPodcastsScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Podcast episodes (iTunes, it_pod_*) actually played, most recent first.
  List<MuzoItem> _playedEpisodes(StorageService storage) {
    final seen = <String>{};
    final out = <MuzoItem>[];
    for (final item in storage.getHistory()) {
      final vId = item.videoId ?? '';
      final isEpisode = (item.source == 'itunes podcast' || vId.startsWith('it_pod')) &&
          !vId.startsWith('it_podshow');
      if (!isEpisode) continue;
      final key = vId.isNotEmpty ? vId : (item.sourceId ?? item.title);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(item);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            storage.historyListenable,
            storage.subscriptionsListenable,
          ]),
          builder: (context, _) {
            final played = _playedEpisodes(storage);
            final subscriptions = storage.getSubscriptions();

            final q = _searchQuery.toLowerCase();
            final filteredEpisodes = _searchQuery.isEmpty
                ? played
                : played
                    .where((e) =>
                    e.title.toLowerCase().contains(q) ||
                    e.displayArtist.toLowerCase().contains(q))
                    .toList();
            final filteredShows = _searchQuery.isEmpty
                ? subscriptions
                : subscriptions
                    .where((c) => c.name.toLowerCase().contains(q))
                    .toList();

            final isEmpty =
            filteredEpisodes.isEmpty && filteredShows.isEmpty;

            return CustomScrollView(
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
                            l10n.podcastsShows,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: spotifyWhite,
                            ),
                          ),
                        ),
                        if (played.isNotEmpty)
                          Text(
                            '${played.length}',
                            style: const TextStyle(
                              color: spotifyLightGrey,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildSearchBar(l10n),
                  ),
                ),
                if (isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              FluentIcons.headphones_24_regular,
                              size: 64,
                              color: spotifyLightGrey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.podcastsShows,
                              style: const TextStyle(
                                color: spotifyWhite,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.podcastsEmptyHint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: spotifyLightGrey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (filteredEpisodes.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _sectionHeader(l10n.recentlyPlayedSort),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final episode = filteredEpisodes[index];
                            final img = episode.thumbnails.isNotEmpty
                                ? episode.thumbnails.last.url
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SpotifySongChip(
                                imageUrl: img,
                                songTitle: episode.title,
                                singerName: episode.displayArtist,
                                size: 47,
                                videoId: episode.videoId,
                                result: episode,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  ref
                                      .read(audioHandlerProvider)
                                      .playVideo(episode);
                                },
                              ),
                            );
                          },
                          childCount: filteredEpisodes.length,
                        ),
                      ),
                    ),
                  ],
                  if (filteredShows.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _sectionHeader(l10n.podcastsShows),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final channel = filteredShows[index];
                            final img = channel.avatar ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    SlidePageRoute(
                                      page: ChannelScreen(
                                        channelId: channel.channelId ?? '',
                                        title: channel.name,
                                        thumbnailUrl: img,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: img.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: img,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) =>
                                                    Container(
                                                  color: spotifyDarkGrey,
                                                  child: const Icon(
                                                    Icons.podcasts,
                                                    color: spotifyLightGrey,
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                color: spotifyDarkGrey,
                                                child: const Icon(
                                                  Icons.podcasts,
                                                  color: spotifyLightGrey,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            channel.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: spotifyWhite,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.podcast,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: spotifyLightGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: filteredShows.length,
                        ),
                      ),
                    ),
                  ],
                ],
                const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: spotifyWhite,
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return SpotifySearchBar(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      hintText: l10n.search,
      height: 40,
    );
  }
}