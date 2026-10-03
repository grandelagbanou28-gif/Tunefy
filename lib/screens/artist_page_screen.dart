import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/category_providers.dart';
import 'package:muzo/providers/download_provider.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/screens/concert_video_screen.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/providers/concert_provider.dart';
import 'package:muzo/providers/connectivity_provider.dart';
import 'package:muzo/services/concert_service.dart';
import 'package:muzo/models/concert_event.dart';
import 'package:muzo/screens/album_screen.dart';
import 'package:muzo/screens/concert_detail_screen.dart';
import 'package:muzo/screens/playlist_screen.dart';
import 'package:muzo/widgets/skeleton_loader.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_spinner.dart';
import 'package:share_plus/share_plus.dart';

/// A full Spotify-style artist page opened from a category or sub-category:
/// large cover header, verified badge, monthly listeners, Play / Shuffle,
/// then "Populaires" (100+ songs), "Concerts" (upcoming first), discography,
/// and similar artists — mirroring the real Spotify artist screen.

final _artistPlaylistsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artistName) async {
  final api = ref.read(muzoApiServiceProvider);
  try {
    // filter 'all' only returns songs on this worker — ask for playlists
    // explicitly or the shelf below the titles stays empty.
    final res = await api.search('$artistName playlist', filter: 'playlists');
    return res.results
        .where((i) =>
            (i.resultType == 'playlist' || i.browseId != null) &&
            i.browseId != null &&
            i.browseId!.isNotEmpty)
        .take(10)
        .toList();
  } catch (_) {
    return <MuzoItem>[];
  }
});

final _artistAlbumsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artistName) async {
  final api = ref.read(muzoApiServiceProvider);
  try {
    final res = await api.search('$artistName album', filter: 'albums');
    return res.results
        .where((i) =>
            (i.resultType == 'album' || i.browseId != null) &&
            i.browseId != null &&
            i.browseId!.isNotEmpty)
        .take(10)
        .toList();
  } catch (_) {
    return <MuzoItem>[];
  }
});

/// Counts for the "Concerts" tab: past concerts + every watchable video
/// found for them, and the total runtime of those videos. The video lists
/// come from [concertVideosProvider] so the detail screen reuses the exact
/// same cache instead of paying for a second search.
class _ConcertStats {
  const _ConcertStats({
    required this.concerts,
    required this.videos,
    required this.videoSeconds,
  });

  final int concerts;
  final int videos;
  final int videoSeconds;
}

final _concertStatsProvider =
    FutureProvider.family<_ConcertStats, String>((ref, artistName) async {
  final events = await ref.watch(artistConcertsProvider(artistName).future);
  final past = events
      .where((e) => !e.isUpcoming && e.date != null)
      .toList()
    ..sort((a, b) =>
        (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)));
  final capped = past.take(8).toList();
  if (capped.isEmpty) {
    return const _ConcertStats(concerts: 0, videos: 0, videoSeconds: 0);
  }

  final lists = await Future.wait(capped.map((e) async {
    try {
      return await ref
          .read(concertVideosProvider(concertVideoQuery(e)).future);
    } catch (_) {
      return const <MuzoItem>[];
    }
  }));
  var videos = 0;
  var seconds = 0;
  for (final list in lists) {
    videos += list.length;
    for (final v in list) {
      seconds += v.durationSeconds ?? 0;
    }
  }
  return _ConcertStats(
    concerts: past.length,
    videos: videos,
    videoSeconds: seconds,
  );
});

/// "1 h 07 min" / "42 min" — used by both section counters.
String _fmtTotal(int seconds) {
  if (seconds <= 0) return '0 min';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h <= 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}

class ArtistPageScreen extends ConsumerStatefulWidget {
  const ArtistPageScreen({
    super.key,
    required this.artistName,
    this.imageUrl,
    this.color = const Color(0xFF1DDA63),
    this.showConcerts = true,
  });

  final String artistName;
  final String? imageUrl;
  final Color color;

  /// Les catégories de l'onglet Search affichent l'artiste sans sa section
  /// concerts ; partout ailleurs (découverte, library…) la section reste.
  final bool showConcerts;

  @override
  ConsumerState<ArtistPageScreen> createState() => _ArtistPageScreenState();
}

class _ArtistPageScreenState extends ConsumerState<ArtistPageScreen> {
  String get artistName => widget.artistName;

  Color get color => widget.color;

  String? get imageUrl => widget.imageUrl;

  int _selectedSongIndex = -1;

  /// videoId → copy of the song carrying a pre-resolved audioUrl. Filled in
  /// the background (2 at a time) right after the list loads so Play/Shuffle
  /// start instantly and almost nothing is skipped for lack of a stream.
  final Map<String, MuzoItem> _enrichedByVideoId = {};
  bool _enrichmentScheduled = false;

  /// Active section tab: 0 = "Populaires" (tracks + discography),
  /// 1 = "Concerts" (past concerts with watchable videos), 2 = "À propos".
  int _tab = 0;

  /// Scroll offset of each tab, so switching back and forth returns to the
  /// same place instead of jumping to the top.
  final Map<int, double> _tabOffsets = {};

  static const int _popularTab = 0;
  static const int _concertsTab = 1;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_rememberOffset);
    // Remember this artist page so a cold app restart brings the user back
    // here instead of dropping them on Home/login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storageServiceProvider).setLastVisitedArtist(
            artistName,
            imageUrl: imageUrl,
          );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_rememberOffset);
    _scrollController.dispose();
    super.dispose();
  }

  void _rememberOffset() {
    if (!_scrollController.hasClients) return;
    _tabOffsets[_tab] = _scrollController.offset;
  }

  void _switchTab(int index) {
    if (_tab == index) return;
    HapticFeedback.selectionClick();
    _rememberOffset();
    setState(() => _tab = index);
    final target = _tabOffsets[index] ?? 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  /// The artist page is a real, already-localized duration, never a made-up
  /// listener count: the header shows what the catalogue actually holds.
  String _totalDurationLabel(AppLocalizations l10n, int seconds) {
    if (seconds <= 0) return '';
    final minutes = seconds ~/ 60;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return l10n.durationMinutes({'m': '$minutes'});
    if (m == 0) return l10n.durationHours({'h': '$h'});
    return l10n.durationHoursMinutes({'h': '$h', 'm': '$m'});
  }

  /// Pre-resolves a short head of the list with the full stream cascade so
  /// Play starts instantly. Deliberately capped: resolving the whole
  /// catalogue on open is what made this page slow (every track costs one
  /// round trip through the resolver chain).
  Future<void> _enrichSongs(List<MuzoItem> songs) async {
    const budget = 12;
    final target = songs.take(budget).toList();
    if (target.isEmpty) return;
    debugPrint('ArtistPage: enriching ${target.length} songs for $artistName');
    for (int i = 0; i < target.length; i += 2) {
      if (!mounted) return;
      final end = i + 2 < target.length ? i + 2 : target.length;
      final chunk = target.sublist(i, end);
      final results = await Future.wait(chunk.map((s) async {
        try {
          final url = await StreamExtractionService.getStreamUrl(
            s.videoId!,
            title: s.title,
            artist: s.displayArtist,
            durationSeconds: s.durationSeconds,
          );
          if (url != null && url.isNotEmpty) {
            return MapEntry(
              s.videoId!,
              s.copyWith(
                audioUrl: url,
                metadata: {
                  ...?s.metadata,
                  'streamFreshTs': DateTime.now().millisecondsSinceEpoch,
                },
              ),
            );
          }
        } catch (e) {
          debugPrint('ArtistPage: enrich failed for ${s.videoId}: $e');
        }
        return null;
      }));
      final newEntries = <String, MuzoItem>{};
      for (final r in results) {
        if (r != null) newEntries[r.key] = r.value;
      }
      if (newEntries.isNotEmpty && mounted) {
        setState(() {
          _enrichedByVideoId.addAll(newEntries);
        });
      }
    }
    debugPrint('ArtistPage: enriched ${_enrichedByVideoId.length} songs for $artistName');
  }

  /// Tapping a song on an artist page opens that song's artist page (the
  /// global "song → artist page" rule). When the song's artist IS the current
  /// page's artist there is nothing to open, so it is a no-op — importantly
  /// this never triggers a dead "Playback unavailable" toast for a track whose
  /// stream can't be resolved right now. Explicit playback stays on the
  /// Play / Shuffle buttons.
  void _openSongArtist(BuildContext context, MuzoItem song, String img) {
    final name = primaryArtistName(song.displayArtist);
    if (name.isEmpty) return;
    if (name.toLowerCase() == artistName.toLowerCase()) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPageScreen(
          artistName: name,
          imageUrl: img.isNotEmpty ? img : imageUrl,
          color: color,
        ),
      ),
    );
  }

  /// Counter line right under the tabs: tracks + total time on "Populaires",
  /// concerts + videos + total video time on "Concerts".
  Widget _tabStats(
    BuildContext context,
    WidgetRef ref,
    List<MuzoItem> playable, {
    required bool showConcerts,
    required int activeTab,
  }) {
    final l10n = AppLocalizations.of(context);
    final style = TextStyle(
      color: spotifyLightGrey.withValues(alpha: 0.9),
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );

    if (showConcerts && activeTab == 1) {
      final statsAsync = ref.watch(_concertStatsProvider(artistName));
      return statsAsync.when(
        loading: () => Text('${l10n.artistConcerts}…', style: style),
        error: (_, __) => Text(l10n.artistConcertsUnavailable, style: style),
        data: (s) {
          if (s.concerts == 0) return Text(l10n.artistNoPastConcert, style: style);
          final vids = s.videos > 0
              ? ' · ${s.videos == 1 ? l10n.videoCountOne : l10n.videoCount({'n': '${s.videos}'})}'
              : '';
          final time = s.videoSeconds > 0 ? ' · ${_fmtTotal(s.videoSeconds)}' : '';
          return Text(
            '${s.concerts == 1 ? l10n.concertCountOne : l10n.concertCount({'n': '${s.concerts}'})}$vids$time',
            style: style,
          );
        },
      );
    }

    final total = playable.fold<int>(0, (a, s) => a + (s.durationSeconds ?? 0));
    final time = total > 0 ? ' · ${_fmtTotal(total)}' : '';
    return Text('${l10n.songCounts(playable.length)}$time', style: style);
  }

  /// Section tabs with an animated underline, the way the big apps mark the
  /// active shelf without shouting with colour alone.
  Widget _buildTabBar(
    AppLocalizations l10n, {
    required bool showConcerts,
    required int activeTab,
  }) {
    final tabs = <({String label, int index})>[
      (label: l10n.artistPopular, index: _popularTab),
      if (showConcerts)
        (label: l10n.artistConcerts, index: _concertsTab),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          for (final tab in tabs)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _switchTab(tab.index),
              child: Padding(
                padding: const EdgeInsets.only(right: 26, top: 6, bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: activeTab == tab.index
                            ? spotifyWhite
                            : spotifyLightGrey.withValues(alpha: 0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      height: 3,
                      width: activeTab == tab.index ? 26 : 0,
                      decoration: BoxDecoration(
                        color: spotifyGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Freedify-inspired concert shelf: PAST concerts with watchable videos.
  /// Upcoming dates are hidden on purpose — this shelf is an archive.
  List<Widget> _concertSlivers(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final concertsAsync = ref.watch(artistConcertsProvider(artistName));
    return concertsAsync.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: SpotifySpinner(
                  strokeWidth: 2.5,
                  color: Color(0xFF1DDA63),
                ),
              ),
            ),
          ),
        ),
      ],
      error: (_, __) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.event_busy_outlined,
                    size: 18, color: spotifyLightGrey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.artistConcertsUnavailableNow,
                    style: const TextStyle(
                      color: spotifyLightGrey,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      data: (events) {
        // ALL of the artist's dates, not just the archive: the shelf used to
        // drop every upcoming concert, which is why an active artist showed
        // only two or three entries.
        final dated = events.where((e) => e.date != null).toList();
        final past = dated.where((e) => !e.isUpcoming).toList()
          ..sort((a, b) =>
              (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)));
        final upcoming = dated.where((e) => e.isUpcoming).toList()
          ..sort((a, b) =>
              (a.date ?? DateTime(2100)).compareTo(b.date ?? DateTime(2100)));
        final all = [...upcoming, ...past];
        if (all.isEmpty) {
          // Say WHY it is empty: without an event source configured there is
          // nothing to show, and a blank tab looks like a bug.
          final noSource = !ConcertService.isConfigured;
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      noSource
                          ? Icons.key_off_outlined
                          : Icons.confirmation_number_outlined,
                      size: 18,
                      color: spotifyLightGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        noSource
                            ? l10n.concertNoSourceConfigured
                            : l10n.artistNoConcertFound,
                        style: const TextStyle(
                          color: spotifyLightGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          // Watchable videos first: they read from the PAST dates only, since
          // a future concert has nothing to watch yet.
          ..._videoShelfSlivers(context, ref, past),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.artistAllConcerts,
                style: TextStyle(
                  color: spotifyLightGrey.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _concertCard(
                    context, ref, all[index], showCount: index < 8),
                childCount: all.length,
              ),
            ),
          ),
        ];
      },
    );
  }

  /// Vertical list of watchable concert videos right under the tabs — the
  /// videos are visible without opening every concert first. It reads
  /// [concertVideosProvider], so the detail screen shares the same cache.
  List<Widget> _videoShelfSlivers(
      BuildContext context, WidgetRef ref, List<ConcertEvent> past) {
    final l10n = AppLocalizations.of(context);
    final queries = <String>[
      for (final e in past.take(4)) concertVideoQuery(e),
      if (past.isEmpty) concertArtistVideoQuery(artistName),
    ];
    final asyncs = queries
        .map((q) => ref.watch(concertVideosProvider(q)))
        .toList();
    final videos = <MuzoItem>[];
    final seen = <String>{};
    var stillLoading = false;
    for (final a in asyncs) {
      final v = a.valueOrNull;
      if (v != null) {
        for (final item in v.take(3)) {
          final key = item.videoId ?? item.title;
          if (seen.add(key)) videos.add(item);
        }
      } else if (a.isLoading) {
        stillLoading = true;
      }
      if (videos.length >= 9) break;
    }

    if (videos.isEmpty) {
      if (!stillLoading) return const [];
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: SpotifySpinner(
                  strokeWidth: 2.5,
                  color: Color(0xFF1DDA63),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            l10n.concertVideos,
            style: TextStyle(
              color: spotifyLightGrey.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) =>
                _videoRow(context, ref, videos[index], index, videos),
            childCount: videos.length,
          ),
        ),
      ),
    ];
  }

  /// One concert video as a full-width row (vertical list, not a shelf).
  Widget _videoRow(
    BuildContext context,
    WidgetRef ref,
    MuzoItem video,
    int index,
    List<MuzoItem> all,
  ) {
    final thumb = video.thumbnails.isNotEmpty ? video.thumbnails.last.url : '';
    final dur = video.durationSeconds;
    final durLabel = dur != null && dur > 0
        ? '${(dur ~/ 60)}:${'${dur % 60}'.padLeft(2, '0')}'
        : '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        openConcertVideo(context, all, index);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 16:9 thumbnail with play overlay + duration chip.
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
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 32,
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
                    style: const TextStyle(
                      color: spotifyWhite,
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

  static const List<String> _frMonths = [
    'janv', 'févr', 'mars', 'avr', 'mai', 'juin',
    'juil', 'août', 'sept', 'oct', 'nov', 'déc',
  ];

  /// "3 vidéos" once the count is known, "Vidéo" while it loads. Reads the
  /// shared [concertVideosProvider] cache — no extra request per card.
  String _videoCountLabel(BuildContext context, WidgetRef ref, ConcertEvent e) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(concertVideosProvider(concertVideoQuery(e)));
    final n = async.valueOrNull?.length ?? 0;
    if (n == 0) return l10n.artistVideoLabel;
    return n == 1 ? l10n.videoCountOne : l10n.videoCount({'n': '$n'});
  }

  Widget _concertCard(BuildContext context, WidgetRef ref, ConcertEvent e,
      {bool showCount = false}) {
    final l10n = AppLocalizations.of(context);
    final d = e.date;
    final day = d != null ? '${d.day}'.padLeft(2, '0') : '??';
    final month = d != null ? _frMonths[d.month - 1] : '';

    return GestureDetector(
      // Whole card opens the full details screen (infos + watchable videos
      // of that past concert).
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          SlidePageRoute(
            page: ConcertDetailScreen(event: e),
          ),
        );
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: spotifyDarkGrey.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date chip
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: e.isUpcoming
                  ? const Color(0xFF1DDA63).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  day,
                  style: TextStyle(
                    color: e.isUpcoming ? const Color(0xFF1DDA63) : spotifyWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  month,
                  style: TextStyle(
                    color: e.isUpcoming
                        ? const Color(0xFF1DDA63)
                        : spotifyLightGrey,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (e.isUpcoming)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.event_available,
                      size: 12,
                      color: Color(0xFF1DDA63),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name.isNotEmpty ? e.name : artistName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (e.locationLabel.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: spotifyLightGrey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          e.locationLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: spotifyLightGrey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (e.priceLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.confirmation_number_outlined,
                        size: 13,
                        color: spotifyLightGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        e.priceLabel,
                        style: const TextStyle(
                          color: spotifyWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Past concert → direct shortcut to its watchable videos.
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1DDA63),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded,
                    size: 16, color: Colors.black),
                const SizedBox(width: 4),
                Text(
                  showCount
                      ? _videoCountLabel(context, ref, e)
                      : l10n.artistVideoLabel,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

  /// Content of the "Populaires" tab: a titled track list, then the albums
  /// and playlists shelves, each with a shimmer instead of a silent gap
  /// while loading.
  List<Widget> _popularContentSlivers(
    BuildContext context,
    WidgetRef ref,
    List<MuzoItem> playable,
    AppLocalizations l10n, {
    required bool offline,
  }) {
    final playlistsAsync = ref.watch(_artistPlaylistsProvider(artistName));
    final albumsAsync = ref.watch(_artistAlbumsProvider(artistName));

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            l10n.artistTopTracks,
            style: const TextStyle(
              color: spotifyWhite,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: playable.length,
          itemBuilder: (context, index) {
            final song = playable[index];
            final img =
                song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';
            // Rebuilt on every downloads-box write, so a finished download
            // unblurs its row immediately without reopening the page.
            return ValueListenableBuilder(
              valueListenable:
                  ref.read(storageServiceProvider).downloadsListenable,
              builder: (context, _, __) {
                final storage = ref.read(storageServiceProvider);
                final downloaded = song.videoId != null &&
                    storage.isDownloaded(song.videoId!);
                final locked = offline && !downloaded;
                final chip = SpotifySongChip(
                  imageUrl: img,
                  songTitle: song.title,
                  singerName: song.displayArtist,
                  size: 47,
                  videoId: song.videoId,
                  isExplicit: song.isExplicit,
                  result: song,
                  onSingerTap: () {
                    HapticFeedback.selectionClick();
                    _openSongArtist(context, song, img);
                  },
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (locked) {
                      showGlassSnackBar(
                        context,
                        AppLocalizations.of(context).offlineNotDownloaded,
                        error: true,
                      );
                      return;
                    }
                    setState(() {
                      _selectedSongIndex = index;
                    });
                    final handler = ref.read(audioHandlerProvider);
                    handler.isShuffleModeNotifier.value = false;
                    handler.playAll(playable, startIndex: index);
                  },
                );
                if (!locked) return chip;
                return Opacity(
                  opacity: 0.55,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: chip,
                  ),
                );
              },
            );
          },
        ),
      ),
      SliverToBoxAdapter(child: _albumsShelf(context, ref, albumsAsync, l10n)),
      SliverToBoxAdapter(
        child: _playlistsShelf(context, ref, playlistsAsync, l10n),
      ),
      // ─── Fans aussi l'aiment ───
      SliverToBoxAdapter(
        child: _RelatedArtistsSection(
          artistName: artistName,
          artistColor: color,
        ),
      ),
    ];
  }

  Widget _albumsShelf(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<MuzoItem>> albumsAsync,
    AppLocalizations l10n,
  ) {
    return albumsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 20),
        child: HomeSkeletonSection(
          showTitle: false,
          rowHeight: 180,
          forceDark: true,
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();
        return _horizontalShelf(
          title: l10n.totalAlbums,
          count: albums.length,
          height: 180,
          itemCount: albums.length,
          itemBuilder: (context, index) => _realAlbumCard(context, albums[index]),
        );
      },
    );
  }

  Widget _playlistsShelf(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<MuzoItem>> playlistsAsync,
    AppLocalizations l10n,
  ) {
    return playlistsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 20),
        child: HomeSkeletonSection(
          showTitle: false,
          rowHeight: 200,
          forceDark: true,
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (playlists) {
        if (playlists.isEmpty) return const SizedBox.shrink();
        return _horizontalShelf(
          title: l10n.totalPlaylists,
          count: playlists.length,
          height: 200,
          itemCount: playlists.length,
          itemBuilder: (context, index) =>
              _realPlaylistCard(context, playlists[index]),
        );
      },
    );
  }

  Widget _horizontalShelf({
    required String title,
    required int count,
    required double height,
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: spotifyWhite,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }

  /// Shimmer stand-in for the track list: the page shows its real shape
  /// immediately instead of a full-screen spinner over an empty header.
  List<Widget> _buildPopularSkeletonSlivers() {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: 8,
          itemBuilder: (context, index) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SkeletonLoader(
                  width: 47,
                  height: 47,
                  borderRadius: 4,
                  forceDark: true,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLoader(
                        width: 160,
                        height: 14,
                        borderRadius: 4,
                        forceDark: true,
                      ),
                      SizedBox(height: 6),
                      SkeletonLoader(
                        width: 100,
                        height: 12,
                        borderRadius: 4,
                        forceDark: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    try {
    final l10n = AppLocalizations.of(context);
    final songsAsync = ref.watch(artistSongsProvider(artistName));
    // Only keep playable tracks (non-null videoId) so tapping a row reliably
    // plays that exact song — playAll skips id-less items internally, which
    // used to shift the seek index and "play the wrong thing".
    final songs = (songsAsync.valueOrNull ?? [])
        .where((s) => s.videoId != null)
        .toList();
    if (songs.isNotEmpty && !_enrichmentScheduled) {
      _enrichmentScheduled = true;
      final snapshot = songs;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _enrichSongs(snapshot);
      });
    }
    // Merge pre-resolved copies so the rendered list plays streams it already
    // has in hand instead of resolving one-by-one at runtime (silent skips).
    final playable = songs
        .map((s) => _enrichedByVideoId[s.videoId] ?? s)
        .toList();
    // Offline the concerts tab disappears entirely (concerts need the
    // network) while every title stays visible: downloaded ones play from
    // the local file, the rest stay blurred until downloaded.
    final offline = ref.watch(isOfflineProvider);
    final showConcerts = widget.showConcerts && !offline;
    final activeTab = showConcerts ? _tab : _popularTab;
    final totalSeconds = playable.fold<int>(
      0,
      (sum, s) => sum + (s.durationSeconds ?? 0),
    );
    final durationLabel = _totalDurationLabel(l10n, totalSeconds);
    final headerStat = playable.isEmpty
        ? ''
        : '${l10n.songCounts(playable.length)}'
            '${durationLabel.isEmpty ? '' : ' · $durationLabel'}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // ─── Collapsing header ───
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: 240,
              backgroundColor: color,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: const SpotifyBackButton(),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                stretchModes: const [StretchMode.zoomBackground],
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 56,
                  end: 48,
                  bottom: 14,
                ),
                title: Text(
                  artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    _headerCover(songs),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.10),
                            Colors.black,
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 46,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            artistName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: spotifyWhite,
                              fontSize: 34,
                              height: 1.02,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (headerStat.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              headerStat,
                              style: TextStyle(
                                color: spotifyWhite.withValues(alpha: 0.85),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── Icons row (+ / share / download / shuffle / play) — sits
            // ABOVE the section tabs in both tabs, Hivefy layout. ───
            SliverToBoxAdapter(
              child: _buildActionBar(context, playable, ref),
            ),

            // ─── Tabs: "Populaires" | "Concerts" | "À propos" ───
            SliverToBoxAdapter(
              child: _buildTabBar(l10n,
                  showConcerts: showConcerts, activeTab: activeTab),
            ),

            // ─── Counts: tracks + total duration, or concerts + videos ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _tabStats(context, ref, playable,
                    showConcerts: showConcerts, activeTab: activeTab),
              ),
            ),

            if (showConcerts && activeTab == _concertsTab)
              // ─── Concerts: past dates + watchable videos ───
              ..._concertSlivers(context, ref)
            else if (songsAsync.isLoading)
              // ─── Shimmer while the track list loads ───
              ..._buildPopularSkeletonSlivers()
            else if (songsAsync.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildErrorState(context, ref),
              )
            else if (songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(context, ref),
              )
            else
              ..._popularContentSlivers(context, ref, playable, l10n,
                  offline: offline),

            const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
          ],
        ),
      ),
    );
    } catch (e, st) {
      debugPrint('ArtistPageScreen build error: $e\n$st');
      final errL10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                errL10n?.artistErrorLoading({'name': artistName}) ??
                    'Error loading $artistName',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(errL10n?.back ?? 'Back',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }


  /// Artist header image: the provided real image (iTunes / Supabase) when
  /// present, otherwise the artist's own top-song artwork (always real), and
  /// finally a neutral gradient placeholder. Never a category artwork.
  Widget _headerCover(List<MuzoItem> songs) {
    String? url = imageUrl;
    if (url == null || url.isEmpty) {
      for (final s in songs) {
        if (s.thumbnails.isNotEmpty) {
          url = s.thumbnails.last.url;
          break;
        }
      }
    }

    Widget placeholder() {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.9),
              Color.lerp(color, spotifyBlack, 0.55)!,
            ],
          ),
        ),
        child: Icon(
          Icons.person,
          color: spotifyWhite.withValues(alpha: 0.7),
          size: 90,
        ),
      );
    }

    if (url == null || url.isEmpty) return placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => placeholder(),
    );
  }

  Widget _buildActionBar(BuildContext context, List<MuzoItem> songs, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final storage = ref.watch(storageServiceProvider);
    final allDownloaded = songs.isNotEmpty &&
        songs.every((s) =>
            s.videoId != null && storage.isDownloaded(s.videoId!));
    final ui = ref.watch(playerUiStateProvider).valueOrNull;
    final currentMedia = ui?.currentMediaItem;
    final isCurrentInList = currentMedia != null &&
        songs.any((s) => s.videoId == currentMedia.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ─── Left: + (add), Share, Download, ⋮ ───
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // + (add all to favorites) — Hivefy add.png / tick.png
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: songs.isEmpty
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        final allFav = songs.isNotEmpty &&
                            songs.every((s) =>
                                s.videoId != null &&
                                storage.isFavorite(s.videoId!));
                        final playable = songs
                            .where((s) => s.videoId != null)
                            .toList();
                        storage.setFavoriteBatch(playable, favorite: !allFav);
                      },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: ValueListenableBuilder<List<MuzoItem>>(
                    valueListenable: storage.favoritesListenable,
                    builder: (context, favorites, _) {
                      final allFav = songs.isNotEmpty &&
                          songs.every((s) =>
                              s.videoId != null &&
                              storage.isFavorite(s.videoId!));
                      return Image.asset(
                        allFav
                            ? 'assets/icons/tick.png'
                            : 'assets/icons/add.png',
                        width: 32,
                        height: 32,
                        color: allFav
                            ? const Color(0xFF1DDA63)
                            : Colors.white70,
                      );
                    },
                  ),
                ),
              ),
              // share — Hivefy share.png
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  HapticFeedback.selectionClick();
                  // ignore: deprecated_member_use
                  Share.share(l10n.shareArtistViaApp({'name': artistName}));
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/icons/share.png',
                    width: 24,
                    height: 24,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              // download (all) — Hivefy download.png / complete_download.png
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: songs.isEmpty
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        if (allDownloaded) {
                          showGlassSnackBar(
                              context, l10n.alreadyDownloaded);
                          return;
                        }
                        // Download sequentially (bounded concurrency) so a
                        // huge artist list doesn't hammer extraction with
                        // hundreds of simultaneous requests.
                        final pending = songs
                            .where((s) =>
                                s.videoId != null &&
                                !storage.isDownloaded(s.videoId!))
                            .toList();
                        int count = pending.length;
                        showGlassSnackBar(
                            context,
                            l10n.downloadingSongs(
                                {'n': '$count'}));
                        for (final s in pending) {
                          ref
                              .read(downloadProvider.notifier)
                              .startDownload(s);
                          // Spread out extraction HTTP work.
                          await Future.delayed(
                            const Duration(milliseconds: 700),
                          );
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: ValueListenableBuilder(
                    // Rebuild when the downloads box changes so the icon
                    // flips to green as each song finishes downloading.
                    valueListenable: storage.downloadsListenable,
                    builder: (context, _, __) {
                      final allDone = songs.isNotEmpty &&
                          songs.every((s) =>
                              s.videoId != null &&
                              storage.isDownloaded(s.videoId!));
                      return Image.asset(
                        allDone
                            ? 'assets/icons/complete_download.png'
                            : 'assets/icons/download.png',
                        width: 32,
                        height: 32,
                        color: allDone
                            ? const Color(0xFF1DDA63)
                            : Colors.white70,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // ─── Right: Shuffle + Play (Hivefy layout) ───
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shuffle — Hivefy shuffle.png (green while shuffle is on)
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
                              // Turn shuffle off, keep current order.
                              handler.isShuffleModeNotifier.value = false;
                            } else {
                              handler.isShuffleModeNotifier.value = true;
                              final shuffled = [...songs]..shuffle();
                              await handler.playAll(shuffled);
                            }
                          },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: spotifyGreen,
                      ),
                      child: Image.asset(
                        'assets/icons/shuffle.png',
                        width: 24,
                        height: 24,
                        color: spotifyBlack,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              // Play (green circle) — driven by the REAL audio engine state
              // so the icon can never drift from what is actually audible.
              GestureDetector(
                onTap: songs.isEmpty
                    ? null
                    : () async {
                         HapticFeedback.selectionClick();
                         final handler = ref.read(audioHandlerProvider);
                         final enginePlaying = handler.player.playing;
                         if (isCurrentInList && enginePlaying) {
                           await handler.pause();
                         } else if (isCurrentInList) {
                           await handler.resume();
                         } else {
                           handler.isShuffleModeNotifier.value = false;
                           final startIdx = _selectedSongIndex >= 0 ? _selectedSongIndex : 0;
                           await handler.playAll(songs, startIndex: startIdx);
                         }
                       },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: spotifyGreen,
                  ),
                  child: StreamBuilder<bool>(
                    stream: ref
                        .read(audioHandlerProvider)
                        .player
                        .playerStateStream
                        .map((state) => state.playing),
                    initialData: ref
                        .read(audioHandlerProvider)
                        .player
                        .playing,
                    builder: (context, snap) {
                      final enginePlaying = snap.data ?? false;
                      return Icon(
                        isCurrentInList && enginePlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow,
                        color: spotifyBlack,
                        size: 30,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
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
              l10n.artistLoadFailed({'name': artistName}),
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
                ref.invalidate(artistSongsProvider(artistName));
                ref.invalidate(categoryAlbumsProvider(artistName));
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

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
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
              l10n.artistNoSongsFound({'name': artistName}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.invalidate(artistSongsProvider(artistName));
                ref.invalidate(categoryAlbumsProvider(artistName));
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

  Widget _realAlbumCard(BuildContext context, MuzoItem album) {
    final l10n = AppLocalizations.of(context);
    final thumbUrl = album.thumbnails.lastOrNull?.url;
    final title = album.title;
    final subtitle = album.displayArtist.isNotEmpty ? album.displayArtist : l10n.albumLabel;
    final bId = album.browseId;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (bId != null && bId.isNotEmpty) {
          Navigator.of(context).push(SlidePageRoute(
            page: AlbumScreen(
              albumId: bId,
              albumName: title,
              thumbnailUrl: thumbUrl,
            ),
          ));
        }
      },
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Round cover — bottom-of-page albums are circles (playlist
            // entries above stay rectangular cards).
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: thumbUrl != null && thumbUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _defaultAlbumIcon(),
                      )
                    : _defaultAlbumIcon(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.9),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _realPlaylistCard(BuildContext context, MuzoItem pl) {
    final l10n = AppLocalizations.of(context);
    final thumbUrl = pl.thumbnails.lastOrNull?.url;
    final title = pl.title;
    final subtitle = pl.displayArtist.isNotEmpty ? pl.displayArtist : l10n.playlistLabel;
    final bId = pl.browseId;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (bId != null && bId.isNotEmpty) {
          Navigator.of(context).push(SlidePageRoute(
            page: PlaylistScreen(
              playlistId: bId,
              title: title,
              thumbnailUrl: thumbUrl,
            ),
          ));
        }
      },
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumbUrl != null && thumbUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _defaultPlaylistIcon(),
                      )
                    : _defaultPlaylistIcon(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.9),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultPlaylistIcon() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, Colors.black, 0.5)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.queue_music_rounded, color: spotifyWhite.withValues(alpha: 0.9), size: 48),
      ),
    );
  }

  Widget _defaultAlbumIcon() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, Colors.black, 0.5)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.album_rounded,
            color: spotifyWhite.withValues(alpha: 0.9), size: 44),
      ),
    );
  }
}

/// Biography with a read-more expander. Reuses the Wikipedia provider the
/// Now Playing page already reads, so nothing extra is fetched.
/// "Fans also like" — the artists sitting next to this one, straight from the
/// related-artists provider the DJ engine already warms.
class _RelatedArtistsSection extends ConsumerWidget {
  const _RelatedArtistsSection({
    required this.artistName,
    required this.artistColor,
  });

  final String artistName;
  final Color artistColor;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final relatedAsync = ref.watch(relatedArtistsProvider(artistName));
    return relatedAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 22),
        child: HomeSkeletonSection(
          showTitle: false,
          rowHeight: 130,
          forceDark: true,
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (artists) {
        if (artists.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l10n.artistFansAlsoLike,
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: artists.length > 12 ? 12 : artists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    final url = artist.thumbnails.isNotEmpty
                        ? artist.thumbnails.last.url
                        : '';
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).push(
                          SlidePageRoute(
                            page: ArtistPageScreen(
                              artistName: artist.title,
                              imageUrl: url,
                              color: artistColor,
                            ),
                          ),
                        );
                      },

                      child: SizedBox(
                        width: 96,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: spotifyDarkGrey,
                              backgroundImage: url.isEmpty
                                  ? null
                                  : CachedNetworkImageProvider(url),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              artist.title,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: spotifyWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
          ),
        );
      },
    );
  }
}
