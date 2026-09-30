import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/screens/collection_screen.dart';
import 'package:muzo/screens/video_player_screen.dart';
import 'package:muzo/services/search_relevance.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/utils/video_playback.dart';
import 'package:muzo/services/stream_prewarmer.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_search_bar.dart';
import 'package:muzo/widgets/song_options_menu.dart';
import 'package:muzo/widgets/spotify_spinner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;
  List<String> _recentSearches = [];
  static const _filters = [
    'All',
    'Songs',
    'Albums',
    'Artists',
    'Playlists',
    'Videos',
  ];
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  int _filterIndexFromProvider(String f) {
    final i = _filters.indexWhere((x) => x.toLowerCase() == f.toLowerCase());
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _query = widget.initialQuery!;
      // The results notifier only listens to this provider, so a query that
      // only lives in the text field would render an empty result list
      // (deep links, QR scan, shared songs).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(searchQueryProvider.notifier).state =
              widget.initialQuery!.trim();
        }
      });
    }
    _loadRecent();
    _initSpeech();
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _startListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
      );
    }
    if (!_speechAvailable) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _isListening = true);
    _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        if (result.finalResult && words.trim().isNotEmpty) {
          _controller.text = words;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: words.length),
          );
          _onChanged(words);
          _saveRecent(words);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        listenMode: stt.ListenMode.search,
      ),
    );
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _recentSearches = prefs.getStringList('recent_searches') ?? []);
  }

  Future<void> _saveRecent(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 20) _recentSearches = _recentSearches.sublist(0, 20);
    await prefs.setStringList('recent_searches', _recentSearches);
    if (mounted) setState(() {});
  }

  Future<void> _clearRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
    if (mounted) setState(() => _recentSearches = []);
  }

  void _onChanged(String value) {
    final q = value.trim();
    _debounce?.cancel();
    setState(() => _query = q);
    if (q.isEmpty) {
      ref.read(searchQueryProvider.notifier).state = '';
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).state = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(searchResultsProvider);
    final selectedFilter =
        _filterIndexFromProvider(ref.watch(searchFilterProvider));

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Back + Search bar + Mic
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
              child: Row(
                children: [
                  const SpotifyBackButton(),
                  Expanded(
                    child: SpotifySearchBar(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      onSubmitted: (v) => _saveRecent(v),
                      hintText: AppLocalizations.of(context).whatToListen,
                      showMic: true,
                      onMicTap: _startListening,
                      isListening: _isListening,
                    ),
                  ),
                ],
              ),
            ),

            // Filter chips
            if (_query.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  itemCount: _filters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final selected = selectedFilter == i;
                    return GestureDetector(
                      onTap: () {
                        // Drive the shared provider filter so the backend
                        // re-queries with the right category (not only a
                        // client-side slice of an 'all' merge).
                        final f = _filters[i].toLowerCase();
                        if (ref.read(searchFilterProvider) != f) {
                          ref.read(searchFilterProvider.notifier).state = f;
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: selected ? spotifyWhite : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? spotifyWhite : spotifyLightGrey.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _filters[i],
                            style: TextStyle(
                              color: selected ? spotifyBlack : spotifyWhite,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Content
            Expanded(
              child: _query.isEmpty
                  ? _buildRecentSection()
                  : _buildSearchResults(searchAsync, selectedFilter),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection() {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, color: spotifyLightGrey.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).noRecentSearches,
              style: TextStyle(color: spotifyLightGrey.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context).recent,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: spotifyWhite),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _recentSearches.length,
            itemBuilder: (ctx, i) {
              final term = _recentSearches[i];
              return ListTile(
                onTap: () {
                  _controller.text = term;
                  _onChanged(term);
                  _saveRecent(term);
                },
                leading: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.history, color: spotifyLightGrey, size: 20),
                ),
                title: Text(term,
                    style: const TextStyle(color: spotifyWhite, fontSize: 15)),
                trailing: GestureDetector(
                  onTap: () {
                    setState(() => _recentSearches.removeAt(i));
                    SharedPreferences.getInstance().then(
                      (prefs) => prefs.setStringList('recent_searches', _recentSearches),
                    );
                  },
                  child: const Icon(Icons.close, color: spotifyLightGrey, size: 18),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GestureDetector(
            onTap: _clearRecent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppLocalizations.of(context).clearRecent,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(
      AsyncValue<List<MuzoItem>> searchAsync, int selectedFilter) {
    return searchAsync.when(
      data: (results) {
        if (results.isEmpty && _query.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, color: spotifyLightGrey.withValues(alpha: 0.4), size: 48),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).noResultsFor(_query),
                  style: TextStyle(color: spotifyLightGrey.withValues(alpha: 0.6), fontSize: 15),
                ),
              ],
            ),
          );
        }

        // Filter + rank against the live query so a chip never surfaces
        // off-topic backend hits (type gate first, then relevance score).
        const chipFilters = <int, String>{
          0: 'all',
          1: 'songs',
          2: 'albums',
          3: 'artists',
          4: 'playlists',
          5: 'videos',
        };
        final activeFilter = chipFilters[selectedFilter] ?? 'all';
        var filtered =
            SearchRelevance.rank(results, _query, activeFilter);

        // Warm the visible results before the tap. Search was the worst case:
        // nothing was resolved ahead of time, so the first press on any track
        // paid a full resolution and a dead source only surfaced on that press.
        StreamPrewarmer.instance.warm(filtered, limit: 10);

        // Strict dedupe: one artist = at most one song in a mixed result list,
        // even if several of his songs matched the query. Videos are tracked
        // separately so a video of the same artist is NOT dropped next to his
        // song — the All tab mixes songs AND videos.
        final seenSongArtists = <String>{};
        final seenVideoIds = <String>{};
        if (selectedFilter == 0) {
          filtered = filtered.where((r) {
            if (r.resultType == 'song') {
              final key = r.displayArtist.trim().toLowerCase();
              if (key.isEmpty) return true;
              if (seenSongArtists.contains(key)) return false;
              seenSongArtists.add(key);
            } else if (r.resultType == 'video') {
              final key = (r.videoId ?? r.title).trim().toLowerCase();
              if (key.isEmpty) return true;
              if (seenVideoIds.contains(key)) return false;
              seenVideoIds.add(key);
            }
            return true;
          }).toList();
        } else if (selectedFilter == 3) {
          final seenArtists = <String>{};
          filtered = filtered.where((r) {
            final key = r.title.trim().toLowerCase();
            if (key.isEmpty || seenArtists.contains(key)) return false;
            seenArtists.add(key);
            return true;
          }).toList();
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 130),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final item = filtered[i];
            final isArtist = item.resultType == 'artist';
            return ListTile(
              onTap: () {
                _saveRecent(_query);
                if (isArtist) {
                  HapticFeedback.selectionClick();
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistPageScreen(
                        artistName: item.title,
                        imageUrl: item.thumbnails.isNotEmpty
                            ? item.thumbnails.last.url
                            : null,
                        color: spotifyDarkGrey,
                      ),
                    ),
                  );
                } else if (item.resultType == 'album' ||
                    item.resultType == 'playlist') {
                  HapticFeedback.selectionClick();
                  // Albums & playlists open their EXACT track list page.
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => _CollectionScreen(
                        title: item.title,
                        artist: item.displayArtist,
                        browseId: item.browseId ?? '',
                        isAlbum: item.resultType == 'album',
                        coverUrl: _thumbUrl(item),
                      ),
                    ),
                  );
                } else if (isWatchableVideo(item)) {
                  Navigator.of(ctx).push(
                    SlidePageRoute(
                      page: VideoPlayerScreen(item: item),
                    ),
                  );
                } else {
                  // Song tap → play immediately and open the Now Playing
                  // screen, matching the album-screen behavior.
                  playSongAndOpenNowPlaying(ctx, item);
                }
              },
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(isArtist ? 24 : 4),
                child: SizedBox(
                  width: 48, height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _thumbUrl(item).isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _thumbUrl(item),
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _placeholderIcon(item),
                            )
                          : _placeholderIcon(item),
                      if (isWatchableVideo(item)) ...[
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                        if (formatVideoDuration(item.durationSeconds).isNotEmpty)
                          Positioned(
                            right: 3,
                            bottom: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                formatVideoDuration(item.durationSeconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              title: Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: spotifyWhite, fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(item.displayArtist.isNotEmpty ? item.displayArtist : item.resultType.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: spotifyLightGrey.withValues(alpha: 0.7), fontSize: 12)),
              trailing: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.more_vert, size: 18, color: spotifyLightGrey),
                onPressed: () => SongOptionsMenu.show(ref, item),
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: SpotifySpinner(color: Color(0xFF1DB954), strokeWidth: 2),
      ),
      error: (_, __) => Center(
        child: Text('Search error', style: TextStyle(color: spotifyLightGrey.withValues(alpha: 0.5))),
      ),
    );
  }

  Widget _placeholderIcon(MuzoItem item) {
    final isArtist = item.resultType == 'artist';
    return Container(
      color: spotifyDarkGrey,
      child: Icon(
        isArtist ? Icons.person : Icons.music_note,
        color: spotifyLightGrey,
        size: 24,
      ),
    );
  }

  String _thumbUrl(MuzoItem item) {
    return item.thumbnails.isNotEmpty ? item.thumbnails.last.url : '';
  }
}

/// Full page for a searched album or playlist: loads the EXACT track list
/// through [collectionTracksProvider] and renders it in the Spotify-style
/// playlist screen (cover, play/shuffle, rows).
class _CollectionScreen extends ConsumerWidget {
  const _CollectionScreen({
    required this.title,
    required this.artist,
    required this.browseId,
    required this.isAlbum,
    this.coverUrl,
  });

  final String title;
  final String artist;
  final String browseId;
  final bool isAlbum;
  final String? coverUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      title: title,
      artist: artist,
      browseId: browseId,
      isAlbum: isAlbum,
    );
    final asyncValue = ref.watch(collectionTracksProvider(key));

    return asyncValue.when(
      loading: () => Scaffold(
        backgroundColor: spotifyBlack,
        appBar: AppBar(
          backgroundColor: spotifyBlack,
          elevation: 0,
          leading: const SpotifyBackButton(),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: spotifyWhite, fontSize: 16)),
        ),
        body: const Center(
          child: SpotifySpinner(color: Color(0xFF1DDA63)),
        ),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: spotifyBlack,
        appBar: AppBar(
          backgroundColor: spotifyBlack,
          elevation: 0,
          leading: const SpotifyBackButton(),
        ),
        body: Center(
          child: Text('Impossible de charger "$title"',
              style: TextStyle(
                  color: spotifyLightGrey.withValues(alpha: 0.8), fontSize: 14)),
        ),
      ),
      data: (songs) => CollectionScreen(
        title: title,
        artist: artist,
        tracks: songs,
        isAlbum: isAlbum,
        coverUrl: (coverUrl == null || coverUrl!.isEmpty) ? null : coverUrl,
      ),
    );
  }
}
