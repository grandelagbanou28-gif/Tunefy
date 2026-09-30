import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/releases_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/release_playback.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

class NewReleasesScreen extends ConsumerStatefulWidget {
  const NewReleasesScreen({super.key, this.initialPeriod = 'month'});

  /// Period the screen opens on: `today`, `week` or `month`.
  final String initialPeriod;

  @override
  ConsumerState<NewReleasesScreen> createState() => _NewReleasesScreenState();
}

class _NewReleasesScreenState extends ConsumerState<NewReleasesScreen> {
  String _selectedType = 'all';
  String _period = 'month';
  bool _loading = true;
  List<ReleaseItem> _allItems = [];
  String? _error;

  // Progressive loading: page 0 is the first batch, each "Charger plus" widens
  // every source by one more batch and appends what is new.
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  static const _filterTypes = [
    ('All', 'all'),
    ('Songs', 'track'),
    ('Albums', 'album'),
    ('Artists', 'artist'),
  ];

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });
    try {
      final resp = await ReleasesService.fetch(
        type: _selectedType,
        period: _period,
        limit: 100,
        searchHistory: ref.read(storageServiceProvider).getSearchHistory(),
      );
      if (!mounted) return;
      setState(() {
        _allItems = resp.data;
        _hasMore = resp.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final resp = await ReleasesService.fetch(
        type: _selectedType,
        period: _period,
        limit: 100,
        page: _page + 1,
        searchHistory: ref.read(storageServiceProvider).getSearchHistory(),
      );
      if (!mounted) return;
      final existing = _allItems.map((e) => _keyOf(e)).toSet();
      final fresh = resp.data.where((e) => existing.add(_keyOf(e))).toList();
      setState(() {
        _allItems = [..._allItems, ...fresh];
        _page += 1;
        _hasMore = resp.hasMore && fresh.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  String _keyOf(ReleaseItem r) =>
      '${r.contentType}|${r.id.isNotEmpty ? r.id : '${r.title}|${r.artistName}'}';

  List<ReleaseItem> _filterByPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _allItems.where((item) {
      final d = item.releaseDate;
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      switch (period) {
        case 'today':
          return day.isAtSameMomentAs(today);
        case 'week':
          return day.isAfter(today.subtract(const Duration(days: 7)));
        case 'month':
          return day.isAfter(today.subtract(const Duration(days: 30)));
        default:
          return true;
      }
    }).toList();
  }

  List<ReleaseItem> get _tracks =>
      _allItems.where((i) => i.contentType == 'track').toList()
        ..sort((a, b) {
          final da = a.releaseDate;
          final db = b.releaseDate;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });

  List<ReleaseItem> get _albums =>
      _allItems.where((i) => i.contentType == 'album').toList();

  List<ReleaseItem> get _artists =>
      _allItems.where((i) => i.contentType == 'artist').toList();

  @override
  Widget build(BuildContext context) {
    // Each section keeps its own type: the chip decides which ones are shown,
    // it never relabels one type's list with another's items.
    final showTracks = _selectedType == 'all' || _selectedType == 'track';
    final showAlbums = _selectedType == 'all' || _selectedType == 'album';
    final showArtists = _selectedType == 'all' || _selectedType == 'artist';
    final filteredTracks = _tracks;
    final filteredAlbums = _albums;
    final filteredArtists = _artists;
    final today = _filterByPeriod('today');
    final week = _filterByPeriod('week');
    final month = _filterByPeriod('month');

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildHeader(),
            _buildFilterChips(),
            _buildPlayBar(),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: SpotifySpinner(color: Color(0xFF1DB954)),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: _buildError(),
              )
            else ...[
              if (_selectedType == 'all') ...[
                if (_period == 'today') ...[
                  _sectionHeader('NEW TODAY'),
                  _horizontalCards(today, 'Aucune sortie aujourd\'hui'),
                ],
                if (_period == 'week') ...[
                  _sectionHeader('NEW THIS WEEK'),
                  _horizontalCards(week, 'Aucune sortie cette semaine'),
                ],
                if (_period == 'month') ...[
                  _sectionHeader('NEW THIS MONTH'),
                  _horizontalCards(month, 'Aucune sortie ce mois-ci'),
                ],
              ],
              if (showTracks && filteredTracks.isNotEmpty) ...[
                _sectionHeader('NEW SONGS'),
                _tracksList(filteredTracks),
              ],
              if (showAlbums && filteredAlbums.isNotEmpty) ...[
                _sectionHeader('NEW ALBUMS'),
                _albumGrid(filteredAlbums),
              ],
              if (showArtists && filteredArtists.isNotEmpty) ...[
                _sectionHeader('NEW ARTISTS'),
                _artistRow(filteredArtists),
              ],
              if (filteredTracks.isEmpty &&
                  filteredAlbums.isEmpty &&
                  filteredArtists.isEmpty &&
                  today.isEmpty &&
                  week.isEmpty &&
                  month.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Aucun contenu disponible',
                      style: TextStyle(
                        color: spotifyLightGrey.withValues(alpha: 0.9),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
            ],
            // End of the loaded batch: a spinner while the next page is on its
            // way, otherwise an explicit "Charger plus" so the feed never looks
            // silently truncated.
            if (_loadingMore || _hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: _loadingMore
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: spotifyGreen,
                            ),
                          )
                        : TextButton(
                            onPressed: _loadMore,
                            child: const Text(
                              'Charger plus',
                              style: TextStyle(
                                color: spotifyWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 16, 4),
        child: Row(
          children: [
            const SpotifyBackButton(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NEW RELEASES',
                    style: TextStyle(
                      color: spotifyWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Les dernieres sorties musicales',
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 13,
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

  /// Play / Shuffle for the visible list. Resolves the whole visible set once,
  /// then hands it to the handler: no page change, no blocking dialog.
  Widget _buildPlayBar() {
    final l10n = AppLocalizations.of(context);
    final tracks = _selectedType == 'all' || _selectedType == 'track'
        ? _tracks
        : _artists;
    final hasContent = _allItems.isNotEmpty;
    if (!hasContent) return const SizedBox.shrink();

    Future<void> run({required bool shuffle}) async {
      if (tracks.isEmpty) return;
      HapticFeedback.selectionClick();
      final overlay = ReleaseBusyOverlay.show(context);
      final resolved = <MuzoItem>[];
      for (final item in tracks.take(shuffle ? 8 : 25)) {
        final found = await resolveTracks(
          ref: ref,
          title: item.title,
          artist: item.artistName ?? '',
          limit: shuffle ? 1 : 1,
        );
        if (found.isEmpty) continue;
        resolved.add(found.first);
        if (shuffle) {
          _resolvedIds[item.title.toLowerCase()] = found.first.videoId ?? '';
        }
      }
      overlay();
      if (!mounted) return;
      if (resolved.isEmpty) {
        showGlassSnackBar(context, l10n.releaseTrackUnavailable, error: true);
        return;
      }
      await playReleaseTracks(context, ref, resolved, shuffle: shuffle);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          ReleaseRoundButton(
            icon: Icons.shuffle,
            color: spotifyWhite,
            size: 24,
            onTap: tracks.isEmpty ? null : () => run(shuffle: true),
          ),
          const SizedBox(width: 14),
          ReleaseRoundButton(
            icon: Icons.play_arrow_rounded,
            color: spotifyBlack,
            background: spotifyGreen,
            size: 30,
            onTap: tracks.isEmpty ? null : () => run(shuffle: false),
          ),
          const SizedBox(width: 14),
          Text(
            l10n.releaseTapToPlay,
            style: TextStyle(
              color: spotifyLightGrey.withValues(alpha: .8),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: _filterTypes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final (label, value) = _filterTypes[index];
            final selected = _selectedType == value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                if (_selectedType == value) return;
                setState(() => _selectedType = value);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? spotifyWhite : spotifyDarkGrey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? spotifyBlack : spotifyWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(
          title,
          style: const TextStyle(
            color: spotifyWhite,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _horizontalCards(List<ReleaseItem> items, String emptyText) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            emptyText,
            style: TextStyle(
              color: spotifyLightGrey.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) => _releaseCard(items[index]),
        ),
      ),
    );
  }

  Widget _releaseCard(ReleaseItem item) {
    return GestureDetector(
      onTap: () => _onItemTap(item),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: _coverImage(item.coverUrl, 140),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 50,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
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
              item.artistName ?? '',
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
  }

  SliverList _tracksList(List<ReleaseItem> tracks) {
    return SliverList.separated(
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final item = tracks[index];
        return SpotifySongChip(
          imageUrl: item.coverUrl ?? '',
          songTitle: item.title,
          singerName: item.artistName ?? '',
          size: 48,
          // Tapping a title plays it right here — no page change. The
          // playlist id is what turns the row green while it is the track
          // currently playing.
          videoId: _playingIdFor(item),
          onTap: () => playReleaseTitle(
            context,
            ref,
            title: item.title,
            artist: item.artistName ?? '',
          ),
        );
      },
    );
  }

  /// Identity used to highlight the row that is currently playing. Prefers the
  /// resolved YouTube id, falls back to a stable synthetic one so a freshly
  /// resolved track still lights up.
  String? _playingIdFor(ReleaseItem item) {
    final resolved = _resolvedIds[item.title.toLowerCase()];
    if (resolved != null) return resolved;
    final current = ref.read(currentMediaItemProvider).valueOrNull;
    final title = item.title.toLowerCase();
    if (current != null &&
        title.isNotEmpty &&
        current.title.toLowerCase() == title) {
      return current.id;
    }
    return null;
  }

  final Map<String, String> _resolvedIds = {};

  SliverGrid _albumGrid(List<ReleaseItem> albums) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.75,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = albums[index];
          return GestureDetector(
            onTap: () => _onItemTap(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _coverImage(item.coverUrl, double.infinity),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
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
                  item.artistName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: spotifyLightGrey.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        },
        childCount: albums.length,
      ),
    );
  }

  SliverToBoxAdapter _artistRow(List<ReleaseItem> artists) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: artists.length,
          separatorBuilder: (_, __) => const SizedBox(width: 18),
          itemBuilder: (context, index) {
            final item = artists[index];
            return GestureDetector(
              onTap: () => _onItemTap(item),
              child: SizedBox(
                width: 100,
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 90,
                        height: 90,
                        child: _coverImage(item.coverUrl, 90),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.artistName ?? item.title,
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
      ),
    );
  }

  Widget _coverImage(String? url, double size) {
    final placeholder = Container(
      width: size,
      height: size,
      color: spotifyDarkGrey,
      child: const Icon(Icons.music_note, color: spotifyLightGrey, size: 30),
    );
    final Widget image = (url == null || url.isEmpty)
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
    // The grid passes double.infinity for size, so the badge metrics fall back
    // to fixed values there.
    final finite = size.isFinite;
    return BrandBadged(
      imageUrl: url,
      badgeSize: finite ? size * 0.2 : 22,
      opacity: 0.9,
      inset: finite ? size * 0.06 : 6,
      child: image,
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: spotifyLightGrey, size: 48),
            const SizedBox(height: 14),
            const Text(
              'Erreur de chargement',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: spotifyWhite,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifiez votre connexion et reessayez.',
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
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Reessayer',
                  style: TextStyle(
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

  /// New Releases never navigates: whatever the row is (track, album or
  /// artist) the tap plays it right here. A page change would break the
  /// "release feed is a listening surface" behaviour.
  Future<void> _onItemTap(ReleaseItem item) async {
    await playReleaseTitle(
      context,
      ref,
      title: item.title,
      artist: item.artistName ?? '',
    );
  }
}
