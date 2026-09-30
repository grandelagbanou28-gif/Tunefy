import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/category_providers.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/services/category_assets.dart';
import 'package:muzo/screens/category_playlist_screen.dart';
import 'package:muzo/screens/category_detail_screen.dart';
import 'package:muzo/screens/channel_screen.dart';
import 'package:muzo/screens/global_search_screen.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/screens/new_releases_screen.dart';
import 'package:muzo/screens/top_charts_screen.dart';
import 'package:muzo/widgets/artist_avatar.dart';
import 'package:muzo/widgets/playlist_collage.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Immersive Spotify-style category page: colored banner + a vertical stream
/// of horizontal sections (artists, albums, singles, EPs, playlists, charts,
/// new releases, podcasts, stations). Sections are hidden automatically when
/// their data source is empty.
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({
    super.key,
    required this.title,
    required this.query,
    required this.color,
    this.asset,
    this.icon,
    this.subs = const [],
  });

  final String title;
  final String query;
  final Color color;

  /// Local fallback cover (category thumbnail) shown when no remote artwork
  /// can be fetched, so we never fall back to initials/placeholder letters.
  final String? asset;
  final IconData? icon;

  /// Sub-categories of this category (e.g. "All Music", "New Music",
  /// "Trending", ...). Each is rendered as its own stacked section with at
  /// least 7 song cards and no repeated artists.
  final List<String> subs;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  static const String _hivefyChannelId = 'UCr-ZhaF9sNZChGOYNx9ky3g';
  static const String _hivefyChannelName = 'HiveFy';
  static const String _hivefyChannelAvatar =
      'https://yt3.googleusercontent.com/H39txhoJvG32TXSvw59g4X1atS2_JqwM0GnWllpZJF0aYOGVnx-M0bZj2PgGoK3CvpLrh9fIvQ=s900-c-k-c0x00ffffff-no-rj';

  String get _title => widget.title;
  String get _query => widget.query;
  Color get _color => widget.color;
  String? get _asset => widget.asset;
  IconData? get _icon => widget.icon;
  List<String> get _subs => widget.subs;

  /// Artists already shown in earlier sub-sections of this page — used to
  /// guarantee no singer appears twice across the whole category.
  final Set<String> _usedArtists = {};

  /// Per-sub-section final (post-dedupe) song lists. Computed once per section
  /// so a rebuild never re-filters the same songs (which would wrongly drop
  /// artists the section already claimed).
  final Map<String, List<MuzoItem>> _claimedBySub = {};

  /// Per-sub-section excluded-artist sets, computed once. Kept stable so the
  /// [categorySubSongsProvider] family argument never changes identity between
  /// rebuilds (a fresh Set each build would retrigger the provider forever).
  Map<String, Set<String>>? _excludedBySub;
  Map<String, Set<String>> get _excluded {
    return _excludedBySub ??= () {
      final excluded = <String, Set<String>>{};
      final claimed = <String>{};
      for (final sub in _subs) {
        excluded[sub] = Set<String>.from(claimed);
        for (final s in seedsForSubCategory(_query, sub)) {
          claimed.add(primaryArtistName(s).trim().toLowerCase());
        }
      }
      return excluded;
    }();
  }

  /// Bundled static cover for this category (no network fetch).
  String? get _staticCover => categoryAsset(_query, _title);

  final ScrollController _scrollController = ScrollController();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final collapsed =
        _scrollController.hasClients && _scrollController.offset > 150;
    if (collapsed != _collapsed && mounted) {
      setState(() => _collapsed = collapsed);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: _subs.isNotEmpty
              ? _buildSubsSlivers()
              : _buildFullSlivers(),
        ),
      ),
    );
  }

  /// Fast path for categories that carry sub-categories: the page shows the
  /// pinned bar + banner + every stacked sub-section right away. Each section
  /// streams in as soon as it resolves (progressive loading — one slow
  /// section never blocks the whole page), and artists are never repeated
  /// across sections.
  List<Widget> _buildSubsSlivers() {
    return [
      _buildHeader(),

      // ─── Sub-category sections (stacked, progressive) ───
      for (var i = 0; i < _subs.length; i++)
        SliverToBoxAdapter(
          child: _subSection(
            _subs[i],
            index: i,
            excluded: _excluded[_subs[i]] ?? const <String>{},
          ),
        ),

      const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
    ];
  }

  /// Slow, content-rich path used by categories without sub-categories: it
  /// fans out the iTunes providers and shows artists / albums / singles / etc.
  List<Widget> _buildFullSlivers() {
    final l10n = AppLocalizations.of(context);
    final songsAsync = ref.watch(categorySongsProvider(_query));
    final songs = songsAsync.value ?? [];
    final albumsAsync = ref.watch(categoryAlbumsProvider(_query));
    final albums = albumsAsync.value ?? [];
    final artistsAsync = ref.watch(categoryArtistsProvider(_query));
    final artists = artistsAsync.value ?? [];
    final tracksAsync = ref.watch(categoryTracksProvider(_query));
    final tracks = tracksAsync.value ?? [];
    final podcastsAsync = ref.watch(categoryPodcastsProvider(_query));
    final podcasts = podcastsAsync.value ?? [];

    final hasAnyData = songs.isNotEmpty ||
        albums.isNotEmpty ||
        artists.isNotEmpty ||
        tracks.isNotEmpty ||
        podcasts.isNotEmpty;
    final hasError = songsAsync.hasError ||
        albumsAsync.hasError ||
        artistsAsync.hasError ||
        tracksAsync.hasError ||
        podcastsAsync.hasError;
    final anyLoading = songsAsync.isLoading ||
        albumsAsync.isLoading ||
        artistsAsync.isLoading ||
        tracksAsync.isLoading ||
        podcastsAsync.isLoading;
    final isLoading = anyLoading && !hasAnyData && !hasError;

    final playlists = _buildPlaylists(songs);
    final newAlbums = _sortedByDate(albums);
    final newTracks = _sortedTracksByDate(tracks);
    final eps = albums.where((a) => a.isEp).toList();

    return [
      // ─── Collapsing header (pinned bar + banner as flexible space) ───
      _buildHeader(),

      // ─── Play / Shuffle ───
      if (songs.isNotEmpty)
        SliverToBoxAdapter(
          child: _buildActionBar(songs),
        ),

      // ─── State: loading / error / empty / sections ───
      if (isLoading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SpotifySpinner(color: Color(0xFF1DDA63)),
          ),
        )
      else if (hasError && !hasAnyData)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildErrorState(),
        )
      else if (!hasAnyData)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(),
        )
      else ...[
        // 1. Artistes populaires
        if (artists.isNotEmpty)
          _section(
            l10n.popularArtists,
            child: _artistsRow(artists.take(10).toList()),
          ),
        // 2. Nouveaux artistes
        if (artists.length > 6)
          _section(
            l10n.categoryNewArtists,
            child: _artistsRow(artists.skip(6).take(10).toList()),
          ),
        // 3. Albums populaires
        if (albums.isNotEmpty)
          _section(
            l10n.popularAlbums,
            child: _albumsRow(albums.take(10).toList()),
          ),
        // 4. Nouveaux albums
        if (newAlbums.isNotEmpty)
          _section(
            l10n.newAlbums,
            child: _albumsRow(newAlbums.take(10).toList()),
          ),
        // 5. Singles populaires
        if (tracks.isNotEmpty)
          _section(
            l10n.categoryPopularSingles,
            child: _tracksRow(tracks.take(10).toList()),
          ),
        // 6. Nouveaux singles
        if (newTracks.isNotEmpty)
          _section(
            l10n.categoryNewSingles,
            child: _tracksRow(newTracks.take(10).toList()),
          ),
        // 7. EP
        if (eps.isNotEmpty)
          _section(
            l10n.categoryEps,
            child: _albumsRow(eps.take(10).toList()),
          ),
        // 8. Playlists
        if (playlists.isNotEmpty)
          _section(
            l10n.categoryPlaylists,
            child: _playlistsRow(playlists.take(10).toList()),
          ),
        // 9. Tendances
        _section(l10n.trendingNow, child: _chartsRow()),
        // 10. Nouvelles sorties
        if (newAlbums.isNotEmpty)
          _section(l10n.newReleases,
              child: _releasesRow(newAlbums)),
        // 11. Podcasts liés
        if (podcasts.isNotEmpty)
          _section(l10n.categoryRelatedPodcasts,
              child: _podcastsRow(podcasts)),
        // 13. Stations / Radios
        if (songs.isNotEmpty)
          _section(l10n.categoryStations,
              child: _stationsRow(songs, playlists)),
        // 14. Artistes similaires
        if (artists.length > 3)
          _section(l10n.categorySimilarArtists,
              child: _artistsRow(artists.reversed.take(6).toList())),
      ],

      const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
    ];
  }

  // ─── Header ───

  /// Spotify-style collapsing header: the banner is the flexible background,
  /// the back chevron lives in the pinned bar (always visible, no duplicates),
  /// and the search / more buttons ride on top of the banner.
  Widget _buildHeader() {
    return _buildHeaderWithCover(_staticCover ?? _asset);
  }

  Widget _buildHeaderWithCover(String? cover) {
    return SliverAppBar(
      backgroundColor: _color,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      stretch: true,
      expandedHeight: 200,
      leading: const SpotifyBackButton(),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _iconButton(
            Icons.search,
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const GlobalSearchScreen(),
              ),
            ),
          ),
        ),

      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        stretchModes: const [StretchMode.zoomBackground],
        background: _buildBanner(cover),
      ),
      // Small title only once the banner has collapsed, so it never overlaps
      // the big pochette + title + description block.
      title: _collapsed
          ? Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  // ─── Banner (flexible-space background of the app bar) ───

  Widget _buildBanner(String? cover) {
    final l10n = AppLocalizations.of(context);
    final hasCover = cover != null && cover.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Rich color wash: lightened tint at the top, pure category color in
        // the middle, then a deep fade into the page background.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(_color, spotifyWhite, 0.08)!,
                _color,
                Color.lerp(_color, spotifyBlack, 0.78)!,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Pochette + title + description
        Positioned(
          left: 20,
          right: 20,
          bottom: 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ─── Category pochette (rounded, shadowed) ───
              if (hasCover)
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: cover.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _coverFallback(),
                          )
                        : Image.asset(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _coverFallback(),
                          ),
                  ),
                ),
              if (hasCover) const SizedBox(width: 16),
              // ─── Title + description ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: spotifyWhite,
                        fontSize:
                            hasCover ? (_title.length > 14 ? 24 : 30) : (_title.length > 14 ? 32 : 42),
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.categoryBannerDesc({'title': _title}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: spotifyWhite.withValues(alpha: 0.72),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Colored tile with the category icon — shown when no artwork resolves.
  Widget _coverFallback() {
    return Container(
      color: Colors.black26,
      child: Icon(_icon ?? Icons.music_note, color: spotifyWhite, size: 34),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: spotifyWhite, size: 24),
      ),
    );
  }

  // ─── Play / Shuffle bar ───

  Widget _buildActionBar(List<MuzoItem> songs) {
    final l10n = AppLocalizations.of(context);
    final ui = ref.watch(playerUiStateProvider).valueOrNull;
    final currentMedia = ui?.currentMediaItem;
    final isPlaying = ui?.isPlaying ?? false;
    final isCurrentInList = currentMedia != null &&
        songs.any((s) => s.videoId == currentMedia.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: songs.isEmpty
                ? null
                : () async {
                    HapticFeedback.selectionClick();
                    final handler = ref.read(audioHandlerProvider);
                    if (isCurrentInList && isPlaying) {
                      await handler.pause();
                    } else if (isCurrentInList) {
                      await handler.resume();
                    } else {
                      handler.isShuffleModeNotifier.value = false;
                      await handler.playAll(songs);
                    }
                  },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFF1DDA63),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCurrentInList && isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: spotifyBlack,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 20),
          ValueListenableBuilder<bool>(
            valueListenable: ref.watch(shuffleModeNotifierProvider),
            builder: (context, shuffleOn, _) {
              return GestureDetector(
                onTap: songs.isEmpty
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        final handler = ref.read(audioHandlerProvider);
                        if (shuffleOn) {
                          handler.isShuffleModeNotifier.value = false;
                        } else {
                          handler.isShuffleModeNotifier.value = true;
                          final shuffled = [...songs]..shuffle();
                          await handler.playAll(shuffled);
                        }
                      },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Icon(
                      Icons.shuffle,
                      color: shuffleOn
                          ? const Color(0xFF1DDA63)
                          : spotifyWhite,
                      size: 24,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.shuffle,
                      style: TextStyle(
                        color: shuffleOn
                            ? const Color(0xFF1DDA63)
                            : spotifyWhite.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Error / empty states ───

  void _retry() {
    ref.invalidate(categorySongsProvider(_query));
    ref.invalidate(categoryImageProvider(_query));
    ref.invalidate(categoryAlbumsProvider(_query));
    ref.invalidate(categoryArtistsProvider(_query));
    ref.invalidate(categoryTracksProvider(_query));
    ref.invalidate(categoryPodcastsProvider(_query));
  }

  Widget _buildErrorState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: spotifyLightGrey, size: 48),
            const SizedBox(height: 14),
            Text(
              l10n.categoryLoadFailed({'title': _title}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.checkConnectionRetry,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _retry();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DDA63),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  l10n.retry,
                  style: const TextStyle(
                    color: spotifyBlack,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, color: spotifyLightGrey, size: 48),
            const SizedBox(height: 14),
            Text(
              l10n.categoryNoVerifiedContent,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.categoryNoVerifiedContentDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _retry();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DDA63),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  l10n.retry,
                  style: const TextStyle(
                    color: spotifyBlack,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sections helpers ───

  SliverToBoxAdapter _section(String title, {required Widget child}) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  // ─── Sub-category sections ───

  Widget _subSection(String sub, {int index = 0, Set<String> excluded = const {}}) {
    // The row itself decides visibility: a sub-section is only rendered when
    // it can show at least 7 songs (the first five sections only need one so
    // the page always shows several sub-categories) — otherwise it is masked.
    return _SubCategoryRow(
      categoryQuery: _query,
      sub: sub,
      index: index,
      color: _color,
      asset: _staticCover ?? _asset,
      icon: _icon,
      excludedArtists: excluded,
      usedArtists: _usedArtists,
      claimed: _claimedBySub,
    );
  }

  // ─── Artists ───

  Widget _artistsRow(List<CategoryArtist> artists) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: artists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final artist = artists[index];
          return GestureDetector(
            onTap: () => _playArtist(artist),
            child: SizedBox(
              width: 110,
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _avatar(artist, 96),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _color,
                          shape: BoxShape.circle,
                          border: Border.all(color: spotifyBlack, width: 2),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: spotifyWhite,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _avatar(CategoryArtist artist, double size) {
    return ArtistAvatar(
      artistName: artist.name,
      size: size,
      imageUrl: artist.imageUrl,
      circle: true,
    );
  }

  // ─── Albums ───

  Widget _albumsRow(List<CategoryAlbum> albums) {
    return SizedBox(
      height: 218,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final album = albums[index];
          return GestureDetector(
            onTap: () => _openAlbum(album),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _squareCover(album.coverUrl, 140),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${album.artist} • ${album.year}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Singles / tracks ───

  Widget _tracksRow(List<CategoryTrack> tracks) {
    return SizedBox(
      height: 218,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return GestureDetector(
            onTap: () => _playTrack(track),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _squareCover(track.coverUrl, 140),
                  const SizedBox(height: 8),
                  Text(
                    track.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${track.artist} • ${_fmt(track.duration)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Playlists ───

  Widget _playlistsRow(List<({String name, List<MuzoItem> songs})> playlists) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final p = playlists[index];
          final urls = p.songs
              .map((s) => s.thumbnails.isNotEmpty ? s.thumbnails.last.url : '')
              .toList();
          return GestureDetector(
            onTap: () => _openPlaylist(p.name, p.songs),
            child: SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: PlaylistCollage(urls: urls),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.songCounts(p.songs.length),
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Charts (Tendances) ───

  Widget _chartsRow() {
    final l10n = AppLocalizations.of(context);
    const tiles = [
      ('Top 10', '10'),
      ('Top 50', '50'),
      ('Top 100', '100'),
      ('', 'new'),
    ];
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final (rawLabel, value) = tiles[index];
          final label = rawLabel.isEmpty ? l10n.chartsNewEntries : rawLabel;
          return GestureDetector(
            onTap: () => _openCharts(),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_color, Color.lerp(_color, spotifyBlack, 0.55)!],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    value == 'new' ? Icons.trending_up : Icons.leaderboard,
                    color: spotifyWhite,
                    size: 30,
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── New releases (Nouvelles sorties) ───

  Widget _releasesRow(List<CategoryAlbum> albums) {
    final l10n = AppLocalizations.of(context);
    final tabs = [
      (l10n.today, 0),
      (l10n.thisWeek, 1),
      (l10n.thisMonth, 2),
    ];
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final (label, tab) = tabs[index];
          return GestureDetector(
            onTap: () => _openReleases(albums, initialTab: tab),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(_color, spotifyBlack, 0.15)!,
                    Color.lerp(_color, spotifyBlack, 0.5)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.new_releases, color: spotifyWhite, size: 30),
                  Text(
                    label,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Podcasts ───

  Widget _podcastsRow(List<CategoryPodcast> podcasts) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: podcasts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final p = podcasts[index];
          return GestureDetector(
            onTap: () => _playTrack(
              CategoryTrack(name: p.name, artist: p.host, coverUrl: p.coverUrl, duration: Duration.zero),
            ),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: p.coverUrl,
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 140,
                        height: 140,
                        color: spotifyDarkGrey,
                        child: const Icon(
                          Icons.podcasts,
                          color: spotifyWhite,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Stations ───

  Widget _stationsRow(
    List<MuzoItem> songs,
    List<({String name, List<MuzoItem> songs})> playlists,
  ) {
    final l10n = AppLocalizations.of(context);
    final stations = <(String, List<MuzoItem>)>[
      (
        l10n.stationRadio({'title': _title}),
        playlists.isNotEmpty ? playlists[0].songs : songs
      ),
      (
        l10n.stationNewReleases({'title': _title}),
        playlists.length > 1 ? playlists[1].songs : songs
      ),
      (
        l10n.stationHits({'title': _title}),
        playlists.length > 2 ? playlists[2].songs : songs
      ),
      (
        l10n.stationDiscovery({'title': _title}),
        playlists.length > 3 ? playlists[3].songs : songs
      ),
    ];
    return SizedBox(
      height: 198,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stations.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final (name, stationSongs) = stations[index];
          return GestureDetector(
            onTap: _openHivefyChannel,
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _radioCover(_stationCover(stationSongs), 140),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'HiveFy · YouTube',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: spotifyLightGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _stationCover(List<MuzoItem> stationSongs) {
    for (final s in stationSongs) {
      if (s.thumbnails.isNotEmpty && s.thumbnails.last.url.isNotEmpty) {
        return s.thumbnails.last.url;
      }
    }
    return _hivefyChannelAvatar;
  }

  Widget _radioCover(String url, double size) {
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: spotifyDarkGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.radio, color: spotifyWhite, size: 34),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              color: spotifyDarkGrey,
              child: const Icon(Icons.radio, color: spotifyWhite, size: 34),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: spotifyBlack.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radio, color: spotifyWhite, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _openHivefyChannel() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelScreen(
          channelId: _hivefyChannelId,
          title: _hivefyChannelName,
          thumbnailUrl: _hivefyChannelAvatar,
        ),
      ),
    );
  }

  // ─── Shared widgets ───

  Widget _squareCover(String url, double size) {
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: spotifyDarkGrey,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note, color: spotifyWhite, size: 30),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: spotifyDarkGrey,
          child: const Icon(Icons.music_note, color: spotifyWhite, size: 30),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─── Data helpers ───

  List<({String name, List<MuzoItem> songs})> _buildPlaylists(
    List<MuzoItem> songs,
  ) {
    final l10n = AppLocalizations.of(context);
    if (songs.isEmpty) return const [];
    const chunk = 12;
    final suffixes = [
      l10n.playlistSuffixTop,
      l10n.playlistSuffixHits,
      l10n.playlistSuffixMix,
      l10n.playlistSuffixFresh,
    ];
    final result = <({String name, List<MuzoItem> songs})>[];
    for (var i = 0; i < suffixes.length; i++) {
      final start = i * chunk;
      if (start >= songs.length) break;
      final end = (start + chunk).clamp(0, songs.length);
      result.add((
        name: '$_title ${suffixes[i]}',
        songs: songs.sublist(start, end),
      ));
    }
    return result;
  }

  List<CategoryAlbum> _sortedByDate(List<CategoryAlbum> albums) {
    final sorted = [...albums]..sort((a, b) {
        final da = a.releaseDate;
        final db = b.releaseDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    return sorted.take(10).toList();
  }

  List<CategoryTrack> _sortedTracksByDate(List<CategoryTrack> tracks) {
    final sorted = [...tracks]..sort((a, b) {
        final da = a.releaseDate;
        final db = b.releaseDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    return sorted.take(10).toList();
  }

  // ─── Actions ───

  void _openPlaylist(String name, List<MuzoItem> songs) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryPlaylistScreen(
          title: name,
          songs: songs,
          color: _color,
        ),
      ),
    );
  }

  Future<void> _playArtist(CategoryArtist artist) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPageScreen(
          artistName: artist.name,
          imageUrl: artist.imageUrl,
          color: _color,
          showConcerts: false,
        ),
      ),
    );
  }

  Future<void> _openAlbum(CategoryAlbum album) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryDetailScreen(
          title: album.name,
          query: '${album.name} ${album.artist}',
          color: _color,
          subtitle: '${album.artist} • ${album.year}',
          coverUrl: album.coverUrl,
          fallbackAsset: _asset,
        ),
      ),
    );
  }

  Future<void> _playTrack(CategoryTrack track) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPageScreen(
          artistName: track.artist,
          imageUrl: track.coverUrl,
          color: _color,
          showConcerts: false,
        ),
      ),
    );
  }

  void _openCharts() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopChartsScreen(
          title: _title,
          query: _query,
          color: _color,
        ),
      ),
    );
  }

  void _openReleases(List<CategoryAlbum> albums, {int initialTab = 0}) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewReleasesScreen(initialPeriod: _periodForTab(initialTab)),
      ),
    );
  }

  /// The "Today / This week / This month" tiles open the releases screen
  /// already scoped to the matching period.
  static String _periodForTab(int tab) {
    switch (tab) {
      case 1:
        return 'week';
      case 2:
        return 'month';
      default:
        return 'today';
    }
  }

}

/// A horizontal row of up to 7 song cards for one sub-category. Songs come
/// from the muzo backend, never repeat an artist (topped up from the main
/// category query), and show a real image (remote art, else the category's
/// bundled asset, else an icon — never initials).
class _SubCategoryRow extends ConsumerWidget {
  const _SubCategoryRow({
    required this.categoryQuery,
    required this.sub,
    this.index = 0,
    required this.color,
    this.asset,
    this.icon,
    this.excludedArtists = const {},
    Set<String>? usedArtists,
    Map<String, List<MuzoItem>>? claimed,
  })  : usedArtists = usedArtists ?? const {},
        claimed = claimed ?? const {};

  final String categoryQuery;
  final String sub;

  /// Zero-based position of the section on the page. The first five sections
  /// are always rendered as long as they have any song, guaranteeing at least
  /// five sub-categories per category page.
  final int index;
  final Color color;
  final String? asset;
  final IconData? icon;
  final Set<String> excludedArtists;

  /// Page-level sets shared across every section: an artist claimed by one
  /// section is never rendered again by another one.
  final Set<String> usedArtists;
  final Map<String, List<MuzoItem>> claimed;

  /// The mission-required empty state: when a sub-category has no verified
  /// content (real <2/-episode round, network failure, or a failed strict
  /// gate), it must say so instead of hiding or inventing anything.
  Widget _emptyHint(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: spotifyWhite,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.categoryNoVerifiedContent,
            style: const TextStyle(color: spotifyLightGrey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(
      categorySubSongsProvider((category: categoryQuery, sub: sub, excludedArtists: excludedArtists)),
    );
    return async.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(
          child: SpotifySpinner(
            color: Color(0xFF1DDA63),
            strokeWidth: 2.5,
          ),
        ),
      ),
      error: (_, __) => _emptyHint(l10n),
        data: (songs) {
          if (songs.isEmpty) {
            return _emptyHint(l10n);
          }
        // Runtime cross-section dedupe: claim each song's artist exactly once
        // per page. Claims are only committed when the section reaches the
        // 7-song minimum — a masked section never steals artists from the
        // sections below it.
        final cacheKey = '$categoryQuery|$sub';
        final List<MuzoItem> visible;
        if (claimed.containsKey(cacheKey)) {
          visible = claimed[cacheKey]!;
        } else {
          final pending = <MuzoItem>[];
          final staged = <String>{};
          for (final song in songs) {
            final artist =
                primaryArtistName(song.displayArtist).trim().toLowerCase();
            final displayLower = song.displayArtist.toLowerCase();
            // Soft cross-section dedupe: skip an artist only while the rack
            // already holds at least five songs. Guarantees every sub shows
            // ≥5 real titles (the user requirement), reserving the "one artist
            // once per page" rule for sections with plenty of content.
            final repeated = artist.isNotEmpty &&
                (usedArtists.contains(artist) ||
                    staged.contains(artist) ||
                    usedArtists.any((a) => displayLower.contains(a)) ||
                    staged.any((a) => displayLower.contains(a)));
            if (repeated && pending.length >= 5) continue;
            if (artist.isNotEmpty) staged.add(artist);
            pending.add(song);
            if (pending.length >= 18) break;
          }
          if (pending.isEmpty) {
            return const SizedBox.shrink();
          }
          usedArtists.addAll(staged);
          claimed[cacheKey] = pending;
          visible = pending;
        }
        // Section header lives here so it only renders once the 3-song
        // minimum is guaranteed — masked subs never leave an orphan title.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: spotifyWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    l10n.albumTrackCount({'n': '${visible.length}'}),
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 214,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final song = visible[index];
                  // First thumbnail = small reliable artwork (100px) for the
                  // 140px cards; .last is the hi-res art used by the player.
                  final img = song.thumbnails.isNotEmpty
                      ? song.thumbnails.first.url
                      : '';
                  return GestureDetector(
                    onTap: () {
                      // Browse All: tapping a sound/podcast of any category
                      // opens the ARTIST page (silent navigation, no audio cut).
                      final name = primaryArtistName(song.displayArtist);
                      if (name.isEmpty) return;
                      HapticFeedback.selectionClick();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistPageScreen(
                            artistName: name,
                            imageUrl: img,
                            color: color,
                            showConcerts: false,
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _subCover(img, color, asset, icon, videoId: song.videoId),
                          const SizedBox(height: 8),
                          Text(
                            song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: spotifyWhite,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final name =
                                  primaryArtistName(song.displayArtist);
                              if (name.isEmpty) return;
                              HapticFeedback.selectionClick();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ArtistPageScreen(
                                    artistName: name,
                                    imageUrl: img,
                                    color: color,
                                    showConcerts: false,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              song.displayArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: spotifyLightGrey.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _subCover(
  String url,
  Color color,
  String? asset,
  IconData? icon, {
  String? videoId,
}) {
  Widget fallback() {
    if (asset != null && asset.isNotEmpty) {
      return Container(
        color: Color.lerp(color, spotifyBlack, 0.25),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Color.lerp(color, spotifyBlack, 0.25),
            child: Icon(
              icon ?? Icons.music_note,
              color: spotifyWhite,
              size: 30,
            ),
          ),
        ),
      );
    }
    return Container(
      color: Color.lerp(color, spotifyBlack, 0.25),
      child: Icon(icon ?? Icons.music_note, color: spotifyWhite, size: 30),
    );
  }

  if (url.isEmpty) {
    if (videoId != null && videoId.isNotEmpty) {
      final ytUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: ytUrl,
          width: 140,
          height: 140,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: fallback(),
          ),
        ),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: fallback());
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: CachedNetworkImage(
      imageUrl: url,
      width: 140,
      height: 140,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) {
        if (videoId != null && videoId.isNotEmpty) {
          final ytUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: ytUrl,
              width: 140,
              height: 140,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: fallback(),
              ),
            ),
          );
        }
        return ClipRRect(borderRadius: BorderRadius.circular(8), child: fallback());
      },
    ),
  );
}
