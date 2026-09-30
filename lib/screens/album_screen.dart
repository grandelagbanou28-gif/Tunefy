import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/album_details.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/download_provider.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/skeleton_loader.dart';
import 'package:muzo/widgets/detail_page_chrome.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:share_plus/share_plus.dart';

/// Album page rebuilt on the ArtistPageScreen pattern: collapsing cover
/// header, Hivefy action bar (favorites / share / download / shuffle / play),
/// Spotify-style track list, skeletons + error/empty states — with real
/// album content (Deezer tracklist resolved to playable YouTube songs).
class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String? albumName;
  final String? thumbnailUrl;

  const AlbumScreen({
    super.key,
    required this.albumId,
    this.albumName,
    this.thumbnailUrl,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  Future<AlbumDetails?>? _albumFuture;
  Future<List<MuzoItem>>? _resolvedFuture;
  int _selectedSongIndex = -1;
  final ScrollController _scrollController = ScrollController();

  /// Deezer/Spotify seed ids shown on the rows -> the real YouTube id that
  /// ends up in `MediaItem.id` after resolution. Without this map the green
  /// "now playing" match always failed for seed albums, so no title ever
  /// turned green while playing.
  final Map<String, String> _playingIdBySeedId = {};

  @override
  void initState() {
    super.initState();
    _albumFuture = _loadAlbum();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Remembers how each row's seed id resolved, so the row can show the id
  /// the player actually reports as "current".
  void _rememberResolvedIds(List<MuzoItem> seeds, List<MuzoItem> resolved) {
    final byTitle = <String, MuzoItem>{
      for (final r in resolved) r.title.toLowerCase().trim(): r,
    };
    for (final s in seeds) {
      final seedId = s.videoId;
      final hit = byTitle[s.title.toLowerCase().trim()];
      if (seedId != null && hit?.videoId != null) {
        _playingIdBySeedId[seedId] = hit!.videoId!;
      }
    }
  }

  bool _enrichmentScheduled = false;
  final Map<String, MuzoItem> _enrichedByVideoId = {};

  bool get _isDeezer => widget.albumId.startsWith('dz:');

  Color get _color => const Color(0xFF1DDA63);

  Future<AlbumDetails?> _loadAlbum() {
    if (_isDeezer) {
      return ref.read(deezerApiServiceProvider).albumDetails(
            widget.albumId.substring(3),
            fallbackTitle: widget.albumName,
            fallbackThumb: widget.thumbnailUrl,
          );
    }
    return ref.read(muzoApiServiceProvider).getAlbumDetails(widget.albumId);
  }

  /// Deezer tracks are metadata seeds (`dz_` ids); resolve once to real
  /// playable YouTube songs so Play/Shuffle/download work for the whole album.
  /// A failed/timed-out resolution is NOT cached, so the user can retry.
  Future<List<MuzoItem>> _ensureResolved(List<MuzoItem> tracks) async {
    final future = _resolvedFuture ??= ref
        .read(multiApiServiceProvider)
        .resolveToPlayable(List.of(tracks), max: 64);
    final result = await future;
    if (result.isEmpty) {
      _resolvedFuture = null;
    }
    return result;
  }

  /// Pre-resolves stream URLs in the background (2 at a time) so Play starts
  /// instantly — same pattern as ArtistPageScreen._enrichSongs.
  Future<void> _enrichSongs(List<MuzoItem> songs) async {
    final target = songs.take(40).toList();
    for (int i = 0; i < target.length; i += 2) {
      final end = i + 2 < target.length ? i + 2 : target.length;
      final chunk = target.sublist(i, end);
      final results = await Future.wait(chunk.map((s) async {
        final vid = s.videoId;
        if (vid == null) return null;
        try {
          final url = await StreamExtractionService.getStreamUrl(
            vid,
            title: s.title,
            artist: s.displayArtist,
            durationSeconds: s.durationSeconds,
          );
          if (url != null && url.isNotEmpty) {
            return MapEntry(
              vid,
              s.copyWith(
                audioUrl: url,
                metadata: {
                  ...?s.metadata,
                  'streamFreshTs': DateTime.now().millisecondsSinceEpoch,
                },
              ),
            );
          }
        } catch (_) {}
        return null;
      }));
      final newEntries = <String, MuzoItem>{};
      for (final r in results) {
        if (r != null) newEntries[r.key] = r.value;
      }
      if (newEntries.isNotEmpty && mounted) {
        setState(() => _enrichedByVideoId.addAll(newEntries));
      }
    }
  }

  List<MuzoItem> _tracksWithArt(AlbumDetails album) {
    return album.tracks.map<MuzoItem>((track) {
      if (track.thumbnails.isEmpty && album.thumbnail.isNotEmpty) {
        return track.copyWith(
          thumbnails: [
            MuzoThumbnail(url: album.thumbnail, width: 500, height: 500),
          ],
        );
      }
      return track;
    }).toList();
  }

  Future<void> _playAlbum(List<MuzoItem> tracks,
      {int startIndex = 0, bool shuffle = false}) async {
    final l10n = AppLocalizations.of(context);
    var list = tracks;
    if (_isDeezer) {
      // Resolution takes a few seconds: no snackbar here (the user does not
      // want a message before every playback) — the row highlight and the
      // mini player are the feedback.
      final resolved = await _ensureResolved(tracks);
      if (!mounted) return;
      if (resolved.isEmpty) {
        showGlassSnackBar(context, l10n.albumPlayFailed, error: true);
        return;
      }
      list = resolved;
      // Rows keep the seed id: remember what each one resolved to, or the
      // "now playing" title never turns green while the album plays.
      if (mounted) setState(() => _rememberResolvedIds(tracks, resolved));
      // startIndex points into the SEED list; rows that failed to resolve
      // are dropped from `list`, so re-locate the start inside it — passing
      // the raw seed index could overflow and crash playAll.
      if (list.isNotEmpty) {
        final seedTitle = startIndex >= 0 && startIndex < tracks.length
            ? tracks[startIndex].title.toLowerCase().trim()
            : '';
        final j = seedTitle.isEmpty
            ? -1
            : list.indexWhere((s) => s.title.toLowerCase().trim() == seedTitle);
        startIndex = j >= 0 ? j : 0;
      }
    }
    if (shuffle) list = List.of(list)..shuffle();
    if (list.isNotEmpty) {
      startIndex = startIndex.clamp(0, list.length - 1);
    } else {
      startIndex = 0;
    }
    final handler = ref.read(audioHandlerProvider);
    handler.isShuffleModeNotifier.value = shuffle;
    await handler.playAll(list, startIndex: shuffle ? 0 : startIndex);
  }

  /// Tap on a row in "Titres" — same path as Home: plays the track through
  /// the audio handler and opens Now Playing. Avoids the whole-album queue
  /// machinery (which triggered intermittent app crashes). Seed ids
  /// (Deezer/Spotify/…) are resolved to a real stream first; if resolution
  /// fails we fall back to the artist page so a tap never crashes.
  Future<void> _playTitle(List<MuzoItem> playable, MuzoItem tapped) async {
    final l10n = AppLocalizations.of(context);
    var target = tapped;
    List<MuzoItem>? resolved;
    if (StreamExtractionService.isMetadataSeedId(tapped.videoId ?? '')) {
      // No "preparing playback" toast here either: it fired before every
      // single tap and the user asked for it to go away.
      resolved = await _ensureResolved(playable);
      if (!mounted) return;
      if (resolved.isEmpty) {
        showGlassSnackBar(context, l10n.albumTrackLoadFailed, error: true);
        return;
      }
      final i = resolved.indexWhere(
          (s) => s.title.toLowerCase() == tapped.title.toLowerCase());
      target = i >= 0 ? resolved[i] : resolved.first;
    }
    final index = playable.indexWhere((s) => s.videoId == tapped.videoId);
    if (mounted) {
      setState(() {
        if (resolved != null) _rememberResolvedIds(playable, resolved);
        if (index >= 0) _selectedSongIndex = index;
      });
    }
    // A row tap only starts the track: the mini player is already on screen,
    // and pushing Now Playing on top of the album was the "another page"
    // complaint. The header Play button is the gesture that opens the player.
    playSongAndOpenNowPlaying(context, target, openPlayer: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<AlbumDetails?>(
          future: _albumFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _AlbumSkeleton();
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _buildErrorState();
            }
            final album = snapshot.data!;
            final tracks = _tracksWithArt(album);
            if (tracks.isNotEmpty && !_enrichmentScheduled) {
              _enrichmentScheduled = true;
              final snapshot = tracks;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _enrichSongs(snapshot);
              });
            }
            final playable = tracks
                .map((s) => _enrichedByVideoId[s.videoId ?? ''] ?? s)
                .where((s) => s.videoId != null)
                .toList();

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildHeader(album),
                SliverToBoxAdapter(
                  child: _buildActionBar(context, album, playable),
                ),
                if (playable.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyTracks(l10n),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _albumStats(l10n, playable),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = playable[index];
final img = song.thumbnails.isNotEmpty
                            ? song.thumbnails.last.url
                            : album.thumbnail;
                          return SpotifySongChip(
                            imageUrl: img,
                            songTitle: song.title,
                            singerName: song.displayArtist,
                            size: 47,
                            // The player reports the RESOLVED id; show that
                            // one once known, or the row never lights green.
                            videoId: song.videoId == null
                                ? null
                                : (_playingIdBySeedId[song.videoId!] ??
                                    song.videoId!),
                            isExplicit: song.isExplicit,
                            result: song,
                            onSingerTap: () {
                              HapticFeedback.selectionClick();
                              openArtistForSong(context, song);
                            },
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _playTitle(playable, song);
                            },
                          );
                        },
                        childCount: playable.length,
                      ),
                    ),
                  ),
                ],
                const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Same counter line as the artist page: real track count plus the real
  /// total runtime, nothing invented.
  Widget _albumStats(AppLocalizations l10n, List<MuzoItem> playable) {
    final seconds =
        playable.fold<int>(0, (sum, s) => sum + (s.durationSeconds ?? 0));
    final minutes = seconds ~/ 60;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final duration = minutes <= 0
        ? ''
        : h == 0
            ? l10n.durationMinutes({'m': '$minutes'})
            : m == 0
                ? l10n.durationHours({'h': '$h'})
                : l10n.durationHoursMinutes({'h': '$h', 'm': '$m'});
    final count = l10n.albumTrackCount({'n': '${playable.length}'});
    return Text(
      duration.isEmpty ? count : '$count · $duration',
      style: TextStyle(
        color: spotifyLightGrey.withValues(alpha: 0.9),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildHeader(AlbumDetails album) {
    final l10n = AppLocalizations.of(context);
    final cover = album.thumbnail.isNotEmpty ? album.thumbnail : (widget.thumbnailUrl ?? '');
    final typeLabel = album.type.isNotEmpty
        ? (album.type[0].toUpperCase() + album.type.substring(1))
        : l10n.albumLabel;
    final meta = [
      if (album.year.isNotEmpty) album.year,
      l10n.albumTrackCount({'n': '${album.tracks.length}'}),
    ].join(' • ');

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 240,
      backgroundColor: _color,
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
          album.title,
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
            if (cover.isNotEmpty)
              CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _coverPlaceholder(),
              )
            else
              _coverPlaceholder(),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _color.withValues(alpha: 0.10),
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
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3D91F4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: spotifyWhite,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        typeLabel,
                        style: const TextStyle(
                          color: spotifyWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 30,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      final name = album.artist.trim();
                      if (name.isEmpty) return;
                      HapticFeedback.selectionClick();
                      Navigator.of(context).push(
                        SlidePageRoute(
                          page: ArtistPageScreen(
                            artistName: name,
                            imageUrl: cover.isNotEmpty ? cover : null,
                            color: _color,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: spotifyWhite.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor:
                            spotifyWhite.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: TextStyle(
                      color: spotifyWhite.withValues(alpha: 0.75),
                      fontSize: 13,
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

  Widget _coverPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _color.withValues(alpha: 0.9),
            Color.lerp(_color, spotifyBlack, 0.55)!,
          ],
        ),
      ),
      child: Icon(
        Icons.album,
        color: spotifyWhite.withValues(alpha: 0.7),
        size: 90,
      ),
    );
  }

  Widget _buildActionBar(
      BuildContext context, AlbumDetails album, List<MuzoItem> songs) {
    final l10n = AppLocalizations.of(context);
    final storage = ref.watch(storageServiceProvider);
    final allDownloaded = songs.isNotEmpty &&
        songs.every((s) => s.videoId != null && storage.isDownloaded(s.videoId!));
    final ui = ref.watch(playerUiStateProvider).valueOrNull;
    final currentMedia = ui?.currentMediaItem;
    final isCurrentInList = currentMedia != null &&
        songs.any((s) => s.videoId == currentMedia.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                        final playable =
                            songs.where((s) => s.videoId != null).toList();
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
                        allFav ? 'assets/icons/tick.png' : 'assets/icons/add.png',
                        width: 32,
                        height: 32,
                        color:
                            allFav ? const Color(0xFF1DDA63) : Colors.white70,
                      );
                    },
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                        HapticFeedback.selectionClick();
                        // ignore: deprecated_member_use
                        Share.share(l10n.shareArtistViaApp(
                            {'name': album.title}));
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
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: songs.isEmpty
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        if (allDownloaded) {
                          showGlassSnackBar(
                              context, l10n.djAlreadyDownloaded);
                          return;
                        }
                        var target = songs;
                        if (_isDeezer) {
                          final resolved =
                              await _ensureResolved(songs);
                          if (!context.mounted) return;
                          if (resolved.isEmpty) {
                            showGlassSnackBar(
                              context,
                              l10n.albumDownloadPrepareFailed,
                              error: true,
                            );
                            return;
                          }
                          target = resolved;
                        }
                        final pending = target
                            .where((s) =>
                                s.videoId != null &&
                                !storage.isDownloaded(s.videoId!))
                            .toList();
                        if (!context.mounted) return;
                        showGlassSnackBar(
                            context,
                            l10n.downloadingSongs(
                                {'n': '${pending.length}'}));
                        final downloader = ref.read(downloadProvider.notifier);
                        for (final s in pending) {
                          // The loop waits 700 ms per track: without this
                          // guard `ref` is touched after the page is closed.
                          if (!mounted) break;
                          downloader.startDownload(s);
                          await Future.delayed(
                              const Duration(milliseconds: 700));
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: ValueListenableBuilder(
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
                        color:
                            allDone ? const Color(0xFF1DDA63) : Colors.white70,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: ref.watch(shuffleModeNotifierProvider),
                builder: (context, shuffleOn, _) {
                  return RoundActionButton(
                    icon: Icons.shuffle,
                    onTap: songs.isEmpty
                        ? null
                        : () async {
                            final handler = ref.read(audioHandlerProvider);
                            if (shuffleOn) {
                              handler.isShuffleModeNotifier.value = false;
                            } else {
                              await _playAlbum(songs, shuffle: true);
                            }
                          },
                  );
                },
              ),
              const SizedBox(width: 10),
              StreamBuilder<bool>(
                stream: ref
                    .read(audioHandlerProvider)
                    .player
                    .playerStateStream
                    .map((s) => s.playing),
                initialData: ref.read(audioHandlerProvider).player.playing,
                builder: (context, snap) {
                  final enginePlaying = snap.data ?? false;
                  return PlayPauseButton(
                    isPlaying: isCurrentInList && enginePlaying,
                    enabled: songs.isNotEmpty,
                    onTap: () async {
                      final handler = ref.read(audioHandlerProvider);
                      if (isCurrentInList && enginePlaying) {
                        await handler.pause();
                      } else if (isCurrentInList) {
                        await handler.resume();
                      } else {
                        final startIdx =
                            _selectedSongIndex >= 0 ? _selectedSongIndex : 0;
                        await _playAlbum(songs, startIndex: startIdx);
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SpotifyBackButton(),
                const SizedBox(height: 24),
                const Icon(Icons.cloud_off, color: spotifyLightGrey, size: 48),
                const SizedBox(height: 14),
                Text(
                  l10n.albumLoadFailed(
                      {'name': widget.albumName ?? l10n.thisAlbum}),
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
                    setState(() {
                      _albumFuture = _loadAlbum();
                      _resolvedFuture = null;
                      _enrichmentScheduled = false;
                      _enrichedByVideoId.clear();
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 11),
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
        ),
      ),
    );
  }
}

class _AlbumSkeleton extends StatelessWidget {
  const _AlbumSkeleton();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: 240,
          backgroundColor: spotifyDarkGrey,
          surfaceTintColor: Colors.transparent,
          leading: const SpotifyBackButton(),
          flexibleSpace: const FlexibleSpaceBar(
            background: SkeletonLoader(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                SkeletonLoader(width: 32, height: 32, borderRadius: 16),
                SizedBox(width: 16),
                SkeletonLoader(width: 32, height: 32, borderRadius: 16),
                SizedBox(width: 16),
                SkeletonLoader(width: 32, height: 32, borderRadius: 16),
                Spacer(),
                SkeletonLoader(width: 32, height: 32, borderRadius: 16),
                SizedBox(width: 8),
                SkeletonLoader(width: 44, height: 44, borderRadius: 22),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, __) => const Padding(
                padding: EdgeInsets.only(bottom: 15),
                child: Row(
                  children: [
                    SkeletonLoader(width: 47, height: 47, borderRadius: 4),
                    SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLoader(
                              width: 160, height: 14, borderRadius: 4),
                          SizedBox(height: 6),
                          SkeletonLoader(
                              width: 100, height: 12, borderRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              childCount: 8,
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
      ],
    );
  }
}

class _EmptyTracks extends StatelessWidget {
  const _EmptyTracks(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, color: spotifyLightGrey, size: 48),
            const SizedBox(height: 14),
            Text(
              l10n.albumNoSongs,
              textAlign: TextAlign.center,
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
  }
}
