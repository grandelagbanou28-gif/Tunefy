import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:muzo/utils/net_guard.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/category_providers.dart';
import 'package:muzo/services/audius_api_service.dart';
import 'package:muzo/services/category_curator.dart';
import 'package:muzo/services/curated_artists_service.dart';
import 'package:muzo/services/genre_catalog.dart';
import 'package:muzo/services/sub_category_seeds.dart';
import 'package:muzo/services/jamendo_api_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/strict_category_filter.dart';
import 'package:muzo/services/category_resolution_service.dart';
import 'package:muzo/services/category_resolvers.dart';
import 'package:muzo/services/category_content_service.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/itunes_api_service.dart';
import 'package:muzo/services/trending_service.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/services/relevance_engine.dart';
import 'package:muzo/services/search_relevance.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/musicbrainz_service.dart';
import 'package:muzo/services/youtube_api.dart';
final searchControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

final searchFocusNodeProvider = Provider<FocusNode>((ref) {
  final focusNode = FocusNode();
  ref.onDispose(() => focusNode.dispose());
  return focusNode;
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchFilterProvider = StateProvider<String>((ref) => 'all');

final searchResultsProvider =
    StateNotifierProvider<SearchResultsNotifier, AsyncValue<List<MuzoItem>>>(
      (ref) {
        return SearchResultsNotifier(ref);
      },
    );


class SearchResultsNotifier
    extends StateNotifier<AsyncValue<List<MuzoItem>>> {
  final Ref ref;



  late final MuzoApiService _api = ref.read(muzoApiServiceProvider);
  String? _continuationToken;
  bool _isLoadingMore = false;

  SearchResultsNotifier(this.ref) : super(const AsyncValue.data([])) {
    // Listen to query and filter changes
    ref.listen(searchQueryProvider, (previous, next) {
      if (next.isNotEmpty) {
        _search(next, ref.read(searchFilterProvider));
      } else {
        state = const AsyncValue.data([]);
      }
    });
    ref.listen(searchFilterProvider, (previous, next) {
      final query = ref.read(searchQueryProvider);
      if (query.isNotEmpty) _search(query, next);
    });
  }

  Future<void> _search(String query, String filter) async {
    state = const AsyncValue.loading();
    _continuationToken = null;
    // ─── CHIEN DE GARDE ───
    // Mesuré sur l'appareil (2026-10-15) : les 6 rayons répondaient 200 avec
    // des résultats et l'écran restait malgré tout en rotation des minutes.
    // Plus AUCUNE étape ne peut laisser `loading` : au bout de 20 s on sort
    // sur un état affichable au lieu d'une rotation éternelle.
    // Évolué le même jour : « la barre de recherche ne filtre rien ». Le
    // watchdog rendait une liste VIDE, donc l'écran « aucun résultat » ; alors
    // que la dernière réponse réseau de cette requête dort dans le cache
    // local. Il la sert désormais, et il ne se déclenche plus dès qu'un rayon
    // a publié (l'état n'est plus `loading`).
    final watchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted || !state.isLoading) return;
      debugPrint('SearchResultsNotifier: WATCHDOG — "$query" ($filter) '
          'bloquée depuis 20 s, sortie forcée sur le cache local');
      unawaited(_rescueFromCache(query, filter));
    });
    // Offline: never wait on the network. Search the local library plus the
    // last results this query produced while online, exactly like Spotify's
    // offline search keeps showing titles instead of an error.
    if (await ContentCacheService.isOffline()) {
      watchdog.cancel();
      state = AsyncValue.data(await _offlineResults(query, filter));
      return;
    }
    try {
      debugPrint('SearchResultsNotifier: en ligne "$query" ($filter)');
      if (filter == 'all') {
        await _primeFromCache(query, filter);
        // Run each category search independently and NEVER let one failing
        // or slow sibling abort the whole merge (otherwise a flaky
        // videos/channels call could wipe out the artists that were fetched
        // fine). A failed sub-search simply contributes nothing.
        // Each bucket is ranked against the query so weak backend hits for
        // that category never outrank a real title/artist match.
        // Les six rayons étaient attendus ENSEMBLE (`Future.wait`) : le plus
        // lent — souvent le worker qui relance un scrape — faisait taire les
        // cinq autres pendant toute sa latence, et le watchdog de 20 s
        // transformait cette attente en écran « aucun résultat ». Chaque rayon
        // publie donc dès qu'il répond, dans un ordre de catégorie fixe pour
        // que la liste ne saute pas d'une publication à l'autre.
        const buckets = <(String, String)>[
          ('songs', 'Songs'),
          ('videos', 'Videos'),
          ('albums', 'Albums'),
          ('artists', 'Artists'),
          ('playlists', 'Playlists'),
          ('channels', 'Channels'),
        ];
        final byIndex = <int, List<MuzoItem>>{};
        final clock = Stopwatch()..start();
        void publishArrived() {
          if (!mounted) return;
          // Une frappe plus récente tient l'écran : ne rien publier pour elle.
          if (ref.read(searchQueryProvider) != query ||
              ref.read(searchFilterProvider) != filter) {
            return;
          }
          final indices = byIndex.keys.toList()..sort();
          final arrived = indices.expand((i) => byIndex[i]!).toList();
          if (arrived.isEmpty) return;
          state = AsyncValue.data(_dedupeSongs(arrived));
        }

        final futures = <Future<void>>[];
        for (var i = 0; i < buckets.length; i++) {
          final filterName = buckets[i].$1;
          final category = buckets[i].$2;
          futures.add(
              _api
                  .search(query, filter: filterName)
                  .then((res) {
                    final tagged = res.results
                        .map((x) => x.copyWith(category: category))
                        .toList();
                    byIndex[i] = SearchRelevance.rank(tagged, query, filterName);
                    debugPrint('SearchResultsNotifier: rayon $filterName = '
                        '${byIndex[i]!.length} résultat(s) '
                        'à +${clock.elapsedMilliseconds} ms');
                    publishArrived();
                  })
                  .catchError((Object e) {
                    debugPrint('search <all> $filter failed: $e');
                    byIndex[i] = const <MuzoItem>[];
                  }));
        }
        await Future.wait(futures);
        debugPrint('SearchResultsNotifier: 6 rayons terminés '
            'en ${clock.elapsedMilliseconds} ms');
        _continuationToken = null;
        // Newest-first re-rank used to run here and buried exact matches;
        // relevance is decided per-category above (age is only a tie-break).
        final resultsArray = [
          for (var i = 0; i < buckets.length; i++)
            byIndex[i] ?? const <MuzoItem>[],
        ];
        var merged = resultsArray.expand((i) => i).toList();

        // ─── AFFICHE D'ABORD ───
        // Les 6 rayons contiennent déjà de vrais titres : on les publie tout
        // de suite. Mesuré sur l'appareil le 2026-10-15 : chaque rayon avait
        // répondu 200 avec des résultats, mais la rotation continuait des
        // MINUTES car un `await` de l'enrichissement ci-dessous ne se
        // terminait jamais — la liste ne doit donc JAMAIS dépendre de ces
        // extras optionnels.
        final baseSnapshot = _dedupeSongs(merged);
        // Une réponse réseau vide ne doit pas effacer ce que le cache venait
        // de resservir : `publishArrived()` a déjà peint l'écran dès qu'un
        // rayon a répondu, ici on ne peint que si le merge a des lignes.
        if (baseSnapshot.isNotEmpty) {
          state = AsyncValue.data(baseSnapshot);
          unawaited(ContentCacheService.instance
              .write('search|$filter|$query', baseSnapshot));
        }
        debugPrint('SearchResultsNotifier: ${baseSnapshot.length} titres '
            'publiés (avant enrichissement)');

        // The backend's album bucket is its weakest one, so real catalog
        // albums are merged into every "All" answer. Chaque étape est
        // BORNÉE : une source qui ne répond plus ne peut plus figer le
        // pipeline (l'état étant déjà peint, le pire cas est l'absence
        // des extras).
        try {
          merged = _withCatalogAlbums(
            merged,
            await _catalogAlbums(query).timeout(const Duration(seconds: 10)),
          );
          debugPrint('SearchResultsNotifier: catalogue albums -> ${merged.length}');
        } catch (e) {
          debugPrint('SearchResultsNotifier: catalogue albums échoué: $e');
        }

        // When the YouTube backend is thin, discover extra titles from the
        // working keyless APIs (MusicBrainz / Spotify / iTunes) and
        // resolve them to playable YouTube tracks.
        if (merged.length < 20 && query.trim().isNotEmpty) {
          try {
            final multi = ref.read(multiApiServiceProvider);
            final discovered = await multi
                .discover(query)
                .timeout(const Duration(seconds: 15));
            final playable = await multi
                .resolveToPlayable(discovered)
                .timeout(const Duration(seconds: 20));
            final known = merged
                .map((r) => r.title.toLowerCase().trim())
                .toSet();
            for (final p in playable) {
              final key = p.title.toLowerCase().trim();
              if (known.add(key) && p.videoId != null) {
                merged = [...merged, p];
              }
            }
          } catch (e) {
            debugPrint('MultiApi search enrichment failed: $e');
          }
        }

        // Une frappe plus récente possède désormais l'écran : ne pas
        // écraser SON état avec celui-ci.
        if (!mounted ||
            ref.read(searchQueryProvider) != query ||
            ref.read(searchFilterProvider) != filter) {
          return;
        }
        if (merged.isNotEmpty) {
          state = AsyncValue.data(merged);
        }
      } else if (filter == 'videos') {
        // Videos chip → real video results for the query (NOT an artist's
        // whole discography).
        await _primeFromCache(query, filter);
        final response = await _api.search(query, filter: 'videos');
        _continuationToken = response.continuationToken;
        final viewable = response.results
            .where((r) => r.videoId != null && r.videoId!.isNotEmpty)
            .map((r) => r.copyWith(resultType: 'video'))
            .toList();
        if (!_ownsScreen(query, filter)) return;
        state = AsyncValue.data(SearchRelevance.rank(viewable, query, filter));
      } else {
        // Songs / Albums / Artists / Playlists chips → a real TYPED search for
        // the query, gated by relevance. The old behaviour treated the query as
        // an ARTIST NAME (artistSongs/Albums/Playlists providers): searching a
        // song title dumped some loosely-matched artist's entire discography
        // into "Songs" and re-labelled loose rows as Albums/Playlists. This is
        // the same per-category path the working "All" tab uses.
        await _primeFromCache(query, filter);
        final response = await _api.search(query, filter: filter);
        _continuationToken = response.continuationToken;
        var results = _normalizeEntityTypes(response.results, filter);
        if (filter == 'albums') {
          results = _withCatalogAlbums(results, await _catalogAlbums(query));
        }
        // Type-gate + score against the query (age only breaks ties) so a chip
        // never shows off-topic backend hits.
        if (!_ownsScreen(query, filter)) return;
        state = AsyncValue.data(
          SearchRelevance.rank(results, query, filter),
        );
      }
      state = AsyncValue.data(_dedupeSongs(state.value ?? []));
      final snapshot = state.value ?? const <MuzoItem>[];
      if (snapshot.isNotEmpty) {
        // Remember the answer so this exact query still resolves offline.
        unawaited(ContentCacheService.instance
            .write('search|$filter|$query', snapshot));
      }
    } catch (e, st) {
      // Network failure with a device that still holds content: show the
      // local answer instead of a bare error page.
      List<MuzoItem> fallback = const <MuzoItem>[];
      try {
        // Borné : une recherche locale qui ne répond pas ne doit pas non
        // plus laisser la rotation en place — l'état d'erreur plus bas est
        // la fin sûre.
        fallback = await _offlineResults(query, filter)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (fallback.isNotEmpty) {
        state = AsyncValue.data(fallback);
        return;
      }
      // Des lignes sont peut-être déjà à l'écran (cache resservi au tap de
      // puce) : les effacer au profit d'une page d'erreur était pire que
      // l'absence de réponse réseau.
      final onScreen = state.value;
      if (onScreen != null && onScreen.isNotEmpty) return;
      state = AsyncValue.error(e, st);
    } finally {
      watchdog.cancel();
    }
  }

  /// L'écran appartient-il encore à CETTE requête ? Une frappe ou un tap de
  /// puce parti pendant l'appel réseau a la main, et ses résultats à lui
  /// arrivent par son propre appel.
  bool _ownsScreen(String query, String filter) {
    return mounted &&
        ref.read(searchQueryProvider) == query &&
        ref.read(searchFilterProvider) == filter;
  }

  /// Le tap sur une puce doit tout de suite montrer quelque chose : la
  /// dernière réponse réseau de ce couple requête/filtre est resservie
  /// pendant que l'appel en cours répond. Mesuré sur l'appareil le
  /// 2026-10-15 : le worker met 20-40 s à relancer un scrape, et pendant ce
  /// temps l'écran affichait « aucun résultat ».
  Future<void> _primeFromCache(String query, String filter) async {
    if (!mounted || !state.isLoading) return;
    List<MuzoItem> cached = const <MuzoItem>[];
    try {
      cached = (await ContentCacheService.instance
              .readStale('search|$filter|$query')) ??
          const <MuzoItem>[];
    } catch (_) {}
    if (cached.isEmpty || !_ownsScreen(query, filter) || !state.isLoading) {
      return;
    }
    debugPrint('SearchResultsNotifier: "$query" ($filter) — ${cached.length} '
        'résultat(s) du cache servis en attendant le réseau');
    state = AsyncValue.data(cached);
  }

  /// Le chien de garde a la parole : 20 s se sont écoulées sans qu'aucun
  /// rayon n'ait publié. Rendu du cache réseau, puis de la bibliothèque
  /// locale, et ce n'est qu'au pire une liste vide — plus jamais une
  /// rotation, et plus jamais « la recherche ne filtre rien ».
  Future<void> _rescueFromCache(String query, String filter) async {
    await _primeFromCache(query, filter);
    if (!mounted || !state.isLoading) return;
    try {
      final local = await _offlineResults(query, filter)
          .timeout(const Duration(seconds: 3));
      if (local.isNotEmpty && _ownsScreen(query, filter) && state.isLoading) {
        debugPrint('SearchResultsNotifier: "$query" ($filter) — secours sur '
            'la bibliothèque locale (${local.length} élément(s))');
        state = AsyncValue.data(local);
        return;
      }
    } catch (_) {}
    if (!_ownsScreen(query, filter) || !state.isLoading) return;
    state = const AsyncValue.data(<MuzoItem>[]);
  }

  /// Everything already on the device that matches [query]: downloads,
  /// favourites, playlist songs and history — plus the last online results
  /// for this exact query/filter, so a title browsed once stays findable
  /// without a network.
  /// Real albums for [query] from Deezer's catalogue. The YouTube backend's
  /// album bucket answers with loose singles, compilations and cover versions
  /// (or nothing at all), which is why the Albums tab never showed real
  /// albums — and a `dz:` browseId opens AlbumScreen's Deezer tracklist, so
  /// these rows are fully browsable, not decoration.
  Future<List<MuzoItem>> _catalogAlbums(String query) async {
    if (query.trim().isEmpty) return const <MuzoItem>[];
    try {
      final albums = await ref
          .read(deezerApiServiceProvider)
          .searchAlbums(query, limit: 12)
          .timeout(const Duration(seconds: 9));
      return albums
          .map((a) => a.copyWith(category: 'Albums'))
          .toList();
    } catch (e) {
      debugPrint('Deezer catalog albums failed for "$query": $e');
      return const <MuzoItem>[];
    }
  }

  /// Append catalog albums to backend albums, dropping catalog duplicates.
  /// Only real album entities occupy that namespace, so a single that shares
  /// a name with an album cannot evict the album card.
  List<MuzoItem> _withCatalogAlbums(
    List<MuzoItem> results,
    List<MuzoItem> catalog,
  ) {
    final known = results
        .where((r) => (r.browseId ?? '').isNotEmpty && r.videoId == null)
        .map(_albumKey)
        .toSet();
    return [...results, ...catalog.where((a) => known.add(_albumKey(a)))];
  }

  Future<List<MuzoItem>> _offlineResults(String query, String filter) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <MuzoItem>[];
    final storage = ref.read(storageServiceProvider);

    bool matches(MuzoItem item) {
      final album = item.album?.name ?? '';
      final hay = '${item.title} ${item.displayArtist} $album'.toLowerCase();
      return hay.contains(q);
    }

    final downloaded = <MuzoItem>[];
    for (final d in storage.getDownloads()) {
      try {
        downloaded.add(
            MuzoItem.fromJson(Map<String, dynamic>.from(d['result'])));
      } catch (_) {}
    }
    final favorites = storage.getFavorites();
    final history = storage.getHistory();
    final fromPlaylists = <MuzoItem>[];
    for (final p in storage.playlistsListenable.value) {
      fromPlaylists.addAll(p.songs);
    }
    final library = <MuzoItem>[...downloaded, ...favorites, ...fromPlaylists];
    final localSongs = <MuzoItem>[
      for (final s in library)
        if (matches(s)) s,
      for (final s in history)
        if (matches(s)) s,
    ];

    final remembered = <MuzoItem>[
      ...await ContentCacheService.instance.readStale(
            'search|$filter|$query',
            maxAge: ContentCacheService.offlineCeiling,
          ) ??
          const <MuzoItem>[],
      // Et au-delà de la recherche exacte : tout ce qui a déjà été affiché
      // quelque part dans l'app et qui correspond au texte cherché.
      ...await ContentCacheService.instance.cachedSongsMatching(q),
    ];

    if (filter == 'artists') {
      final out = <MuzoItem>[];
      final seen = <String>{};
      for (final a in remembered) {
        if ((a.resultType == 'artist' || a.resultType == 'channel') &&
            seen.add(a.title.trim().toLowerCase())) {
          out.add(a);
        }
      }
      // Derive the artists of the local library so an artist the user owns
      // music from is still reachable offline (the artist page itself has a
      // 365-day cache + download merge).
      for (final s in library) {
        final artist = s.displayArtist.trim();
        if (artist.isEmpty || artist == 'Unknown') continue;
        if (!artist.toLowerCase().contains(q)) continue;
        if (!seen.add(artist.trim().toLowerCase())) continue;
        out.add(MuzoItem(
          title: artist,
          thumbnails: s.thumbnails,
          resultType: 'artist',
          isExplicit: false,
        ));
      }
      return out;
    }

    if (filter == 'albums') {
      final out = <MuzoItem>[];
      final seen = <String>{};
      for (final a in remembered) {
        if (a.resultType == 'album' && seen.add(a.title.trim().toLowerCase())) {
          out.add(a);
        }
      }
      for (final s in library) {
        final album = s.album?.name.trim() ?? '';
        if (album.isEmpty) continue;
        if (!album.toLowerCase().contains(q)) continue;
        if (!seen.add(album.trim().toLowerCase())) continue;
        out.add(MuzoItem(
          title: album,
          thumbnails: s.thumbnails,
          resultType: 'album',
          isExplicit: false,
          artists: s.artists,
          channelName: s.channelName,
        ));
      }
      return out;
    }

    if (filter == 'playlists') {
      final out = <MuzoItem>[];
      final seen = <String>{};
      for (final p in remembered) {
        if (p.resultType == 'playlist' &&
            seen.add(p.title.trim().toLowerCase())) {
          out.add(p);
        }
      }
      for (final p in storage.playlistsListenable.value) {
        if (!p.name.toLowerCase().contains(q)) continue;
        if (!seen.add(p.name.trim().toLowerCase())) continue;
        // 'local:' marks a playlist stored on this device: the search screens
        // route those to the local playlist page instead of a YouTube id.
        out.add(MuzoItem(
          title: p.name,
          thumbnails: const [],
          resultType: 'playlist',
          isExplicit: false,
          browseId: 'local:${p.name}',
        ));
      }
      return out;
    }

    final out = <MuzoItem>[];
    if (filter != 'videos') out.addAll(localSongs);
    for (final r in remembered) {
      if (filter == 'videos' && r.resultType != 'video') continue;
      if (filter == 'songs' &&
          (r.resultType == 'artist' ||
              r.resultType == 'album' ||
              r.resultType == 'playlist' ||
              r.resultType == 'channel')) {
        continue;
      }
      out.add(r);
    }
    return _dedupeSongs(out);
  }

  Future<void> loadMore() async {
    if (_continuationToken == null || _isLoadingMore) return;

    _isLoadingMore = true;
    final currentResults = state.value ?? [];
    final query = ref.read(searchQueryProvider);
    final filter = ref.read(searchFilterProvider);

    try {
      final response = await _api.search(
        query,
        filter: filter,
        continuationToken: _continuationToken,
      );
      _continuationToken = response.continuationToken;
      state = AsyncValue.data(SearchRelevance.rank(
        _dedupeSongs([...currentResults, ...response.results]),
        query,
        filter,
      ));
    } catch (e) {
      debugPrint('Error loading more search results: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  bool get hasMore => _continuationToken != null;
}

final searchSuggestionsProvider = FutureProvider.family<List<String>, String>((
  ref,
  query,
) async {
  if (query.isEmpty) return [];
  // Offline suggestions come from what is actually on the device: history,
  // favourites and downloads, so the type-ahead keeps working without a net.
  if (await ContentCacheService.isOffline()) {
    final storage = ref.read(storageServiceProvider);
    final seen = <String>{};
    final out = <String>[];
    void add(String title) {
      final t = title.trim();
      if (t.isEmpty || !t.toLowerCase().contains(query.trim().toLowerCase())) {
        return;
      }
      if (seen.add(t.toLowerCase()) && out.length < 8) out.add(t);
    }

    for (final h in storage.getHistory()) {
      add(h.title);
    }
    for (final f in storage.getFavorites()) {
      add(f.title);
    }
    for (final d in storage.getDownloads()) {
      try {
        add(MuzoItem.fromJson(Map<String, dynamic>.from(d['result'])).title);
      } catch (_) {}
    }
    return out;
  }
  final apiService = ref.read(muzoApiServiceProvider);
  return await apiService.getSearchSuggestions(query);
});

/// Real songs for a Search "Browse All" category.
///
/// Genre-first engine (keyless multi-source):
///   * If the query resolves to a [GenrePlan], the section is filled with real
///     genre-exact content: Jamendo genre tag + Audius trending-by-genre
///     (both directly playable, both exactly on genre) + a ytify search
///     scoped to the genre word + iTunes metadata for that genre. There is
///     NO generic "hits / trending / top songs" fallback any more — that's
///     what used to drop Bachata / Arabic Kuthu into Gospel sections.
///   * If the query is a seed artist name (no genre plan), we keep the
///     artist-scoped path (Jamendo exact-artist, ytify artist songs, iTunes)
///     which is already genre-correct because the seeds are editorial.
/// All queries bounded, junk-filtered, deduplicated and capped.
final categorySongsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
  if (query.isEmpty) return [];
  // Re-check once the 72h catalog load completes so the genre-first shelf
  // upgrades itself. The watch lives here (before the cache short-circuit) so
  // [ContentCacheService.shelfCached]'s body stays free of ref.watch-after-await.
  ref.watch(curatedArtistsServiceProvider);
  return ContentCacheService.shelfCached(
    // `v2` invalidates the two-day snapshots built from the hand-typed artist
    // catalog, so the chart-based genre rows appear on this install today
    // instead of after the old cache expires.
    'catsongs2|$query',
    () => _buildCategorySongs(ref, query),
  );
});

/// The real song pipeline behind a category's main "songs" strip: the genre
/// chart first, then the curated catalog artists, then
/// Jamendo/Audius/ytify. Runs online; offline (or on a
/// failed/empty fetch) the caller replays the last disk snapshot.
/// ─── Genre-first: whatever actually charts in that genre right now ───
/// When the query maps to a genre ([catalogGenreFor]), the shelf is filled from
/// Apple's per-country most-played charts filtered on each song's own genre
/// label, so the row is the genre's current hits rather than approximate
/// matches of a search phrase.
/// Falls through to the generic pipeline when there is no genre chart nor
/// catalog bucket for it.
Future<List<MuzoItem>> _buildCategorySongs(Ref ref, String query) async {
  final genreKey = catalogGenreFor(query);
  if (genreKey != null) {
    final cat = await ref.read(
      catalogTracksForGenreProvider(
        (genre: genreKey, offset: 0, country: null),
      ).future,
    );
    if (cat.isNotEmpty) {
      return cat.map((i) => i.copyWith(verified: true)).toList();
    }
  }

  final apiService = ref.read(muzoApiServiceProvider);
  final jamendo = ref.read(jamendoApiServiceProvider);

  final plan = genrePlanFor(query, query);
  final ambient = isAmbientQuery(query) || plan.ambient;

  final seen = <String>{};
  final songs = <MuzoItem>[];

  void addBatch(List<MuzoItem> batch, {bool genreExact = false}) {
    for (final song in batch) {
      if (!isActuallyPlayable(song)) continue;
      if (isJunkSong(song.title, isAmbient: ambient)) continue;
      final key =
          (song.videoId ?? '${song.title}|${song.displayArtist}').toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      if (!genreExact && !plan.isEmpty) {
        if (_conflictsGenre(song, plan)) continue;
      }
      seen.add(key);
      songs.add(song);
    }
  }

  // ─── Genre-driven section: source genre-exact music in parallel ───
  if (!plan.isEmpty) {
    // Fast layer: Jamendo tag + Audius genre — direct full audio, exact genre.
    final fast = <Future<List<MuzoItem>>>[
      if (plan.jamendoTag != null)
        jamendo
            .tracksByTag(plan.jamendoTag!, limit: 8)
            .then((t) => t.map((t2) => t2.toMuzoItem()).toList())
            .timeout(const Duration(seconds: 8), onTimeout: () => const []),
      for (final g in plan.audiusGenres)
        ref
            .read(audiusApiServiceProvider)
            .tracksByGenre(g, limit: 8)
            .then((t) => t.map((t2) => t2.toMuzoItem()).toList())
            .timeout(const Duration(seconds: 8), onTimeout: () => const []),
    ];
    for (final batch in await Future.wait(fast)) {
      addBatch(batch, genreExact: true);
    }

    // Top-up layer: ytify scoped to the genre word. Music is served by
    // muzoapi (YouTube) exclusively — iTunes song previews (30s clips) are
    // intentionally excluded from every music pipeline.
    if (songs.length < 10) {
      final topups = <Future<List<MuzoItem>>>[
        apiService
            .search(plan.ytifyTerm, filter: 'songs')
            .then((res) => _prioritizeWestern(res.results))
            .timeout(const Duration(seconds: 10), onTimeout: () => const []),
      ];
      for (final batch in await Future.wait(topups)) {
        addBatch(batch);
      }
    }

    // Last resort, still genre-scoped: re-run the ytify genre search once.
    if (songs.isEmpty) {
      try {
        final resp = await apiService
            .search(plan.ytifyTerm, filter: 'songs')
            .timeout(const Duration(seconds: 10));
        addBatch(_prioritizeWestern(resp.results));
      } catch (_) {}
    }
    return songs.take(15).toList();
  }

  // ─── Artist-driven section: a seed artist name — keep artist-scoped path ──
  final seeds = seedsFor(query);
  final sourceQueries = seeds.isNotEmpty
      ? seeds.take(5).toList()
      : <String>[query];

  Future<List<MuzoItem>> jamendoBatch(String q) async {
    final ql = q.trim().toLowerCase();
    List<JamendoTrack> tracks;
    final tag = jamendoTagFor(q);
    if (tag != null) {
      try {
        tracks = await jamendo.tracksByTag(tag, limit: 8).timeout(
              const Duration(seconds: 8),
            );
      } catch (_) {
        tracks = [];
      }
    } else {
      try {
        tracks = await jamendo.searchTracks(q, limit: 10).timeout(
              const Duration(seconds: 8),
            );
        tracks = tracks
            .where((t) =>
                t.artistName.toLowerCase().contains(ql) ||
                (t.artistName.isNotEmpty &&
                    ql.contains(t.artistName.toLowerCase())))
            .take(8)
            .toList();
      } catch (_) {
        tracks = [];
      }
    }
    return tracks.map((t) => t.toMuzoItem()).toList();
  }

  await Future.wait(sourceQueries.map((q) async {
    List<MuzoItem> batch = await jamendoBatch(q);
    if (batch.isEmpty) {
      try {
        final resp = await apiService
            .search(q, filter: 'songs')
            .timeout(const Duration(seconds: 10));
        batch = _prioritizeWestern(resp.results);
      } catch (_) {
        batch = [];
      }
    }
    addBatch(batch);
  }).toList());

  return songs.take(15).toList();
}

/// Loose conformance guard for ytify/iTunes results in a genre section: only
/// reject a song when its title/artist *explicitly* names a conflicting genre
/// far from the section's (e.g. an "Arabic Kuthu" video surfacing inside a
/// Gospel search would be dropped because it advertises Bollywood/Tamil).
/// Otherwise we keep it — a seed artist like "Kirk Franklin" legitimately
/// never says "gospel" in the title.
bool _conflictsGenre(MuzoItem song, GenrePlan plan) {
  final hay = '${song.title} ${song.displayArtist}'.toLowerCase();
  if (_strongPositiveGenreMatch(hay, plan.key)) return false;
  final conflicts = _genreConflictMarkers[plan.key];
  if (conflicts == null) return false;
  return conflicts.any(hay.contains);
}

const Map<String, Set<String>> _genreConflictMarkers = {
  'gospel': {
    'bollywood', 'tamil', 'punjabi', 'arabic', 'kuthu', 'hindi',
  },
  'gospel hits': {
    'bollywood', 'tamil', 'punjabi', 'arabic', 'kuthu', 'hindi',
  },
  'contemporary gospel': {
    'bollywood', 'tamil', 'punjabi', 'arabic', 'kuthu', 'hindi',
  },
  'salsa': {'reggaeton', 'bachata', 'cumbia', 'bollywood'},
  'bachata': {'reggaeton', 'salsa', 'cumbia', 'bollywood'},
  'reggaeton': {'salsa', 'bollywood', 'kuthu'},
  'classical': {'bollywood', 'rave', 'techno', 'edm'},
  'jazz': {'bollywood', 'edm', 'techno'},
  'country': {'bollywood', 'kuthu', 'punjabi'},
  'amapiano': {'bollywood', 'arabic', 'kuthu'},
  'kpop': {'bollywood', 'arabic', 'kuthu', 'tamil'},
};

/// True when the song explicitly belongs to the section genre: the genre word
/// (or its near synonyms) appears in title/artist. Used to accept a result even
/// when a stray conflict marker also appears.
bool _strongPositiveGenreMatch(String hay, String key) {
  switch (key) {
    case 'gospel':
    case 'gospel hits':
    case 'contemporary gospel':
      return hay.contains('gospel') ||
          hay.contains('worship') ||
          hay.contains('christian');
    case 'hip hop':
    case 'rap':
      return hay.contains('rap') || hay.contains('hip hop');
    case 'r&b':
      return hay.contains('rnb') || hay.contains('r&b');
    default:
      final kw = key
          .replaceAll('&', ' ')
          .replaceAll('-', ' ')
          .replaceAll('  ', ' ')
          .trim();
      return hay.contains(kw);
  }
}

/// True when a sub-section is ambient / spoken-word / long-form content where
/// the junk filter must stay off (Sleep Music, Deep Focus, Rain, ASMR...).
bool isAmbientSubCategory(String category, String sub) {
  if (isAmbientQuery(category) || isAmbientQuery(sub)) return true;
  final l = sub.toLowerCase();
  final ambientSubs = {
    'sleep music',
    'deep sleep',
    'white noise',
    'brown noise',
    'nature sounds',
    'rain',
    'ocean',
    'asmr',
    'meditation',
    'guided meditation',
    'breathing',
    'yoga',
    'sleep stories',
    'baby sleep',
    'whispers',
    'scary stories',
  };
  return ambientSubs.contains(l) ||
      l.contains('sleep') ||
      l.contains('meditation') ||
      l.contains('white noise') ||
      l.contains('asmr') ||
      l.contains('rain') ||
      l.contains('shadowing') ||
      l.contains('english') ||
      l.contains('pronunciation');
}

/// Editorial seed artists for a specific sub-category. Walks three levels:
/// 1. Sub-category-specific seeds (e.g. Marc Anthony for "Salsa").
/// 2. Parent category seeds (from category_curator.dart) as fallback.
/// Always returns at most 6 artists to bound backend round-trips.
/// Lower-cased, accent-free, punctuation-free form of a category label, so
/// "Hits Bénin", "hit benin" and "Hit-Bénin" all compare equal.
String _foldCategoryKey(String value) {
  const accents = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
  };
  final buffer = StringBuffer();
  for (final raw in value.toLowerCase().split('')) {
    final ch = accents[raw] ?? raw;
    if (RegExp(r'[a-z0-9 ]').hasMatch(ch)) buffer.write(ch);
  }
  return buffer.toString().trim();
}

List<String> seedsForSubCategory(String category, String sub) {  final specific = subCategorySeeds(category, sub);
  if (specific != null && specific.isNotEmpty) return specific.take(6).toList();
  final parent = seedsFor(category);
  if (parent.isNotEmpty) return parent.take(6).toList();
  return const [];
}

/// Composite search term for a term-driven sub-category that has no dedicated
/// artist seeds. Combines the sub-category name with the parent genre so the
/// backend returns on-topic results (e.g. "Salsa" + "Latin" -> "salsa latin").
String queryForSubCategory(String category, String sub) {
  final subLower = sub.trim().toLowerCase();
  final catLower = category.trim().toLowerCase();
  if (subLower == catLower || subLower.contains(catLower)) {
    return sub.trim();
  }
  return '${sub.trim()} $category';
}

/// Per-sub-category editorial tuning for structural subs (Music category and
/// beyond). Each flag changes how candidate songs are filtered / ranked so a
/// section actually behaves like its name instead of being a generic list.
class _SubTuning {
  const _SubTuning({
    this.rejectOld = false,
    this.sortByViews = false,
    this.singlesOnly = false,
    this.albumTracksOnly = false,
  });

  /// Drop uploads older than ~1 year ("x years ago") and rank fresher first.
  final bool rejectOld;

  /// Rank most-viewed first (popularity proxy).
  final bool sortByViews;

  /// Keep single releases only: short tracks whose album is absent or named
  /// after the song (YouTube Music convention for singles).
  final bool singlesOnly;

  /// Keep album cuts only: track must carry an album distinct from its title.
  final bool albumTracksOnly;

  bool get isActive =>
      rejectOld || sortByViews || singlesOnly || albumTracksOnly;
}

/// Strategy table — extend as more structural subs are curated.
_SubTuning _tuningForSub(String sub) {
  switch (sub.trim().toLowerCase()) {
    case 'new music':
      return const _SubTuning(rejectOld: true);
    case 'trending':
      return const _SubTuning(rejectOld: true, sortByViews: true);
    case 'popular':
    case 'top songs':
    case 'music videos':
    case 'compilations':
      return const _SubTuning(sortByViews: true);
    case 'top albums':
    case 'albums':
      return const _SubTuning(albumTracksOnly: true, sortByViews: true);
    case 'singles':
      return const _SubTuning(singlesOnly: true, sortByViews: true);
    default:
      return const _SubTuning();
  }
}

/// Numeric view count from labels like "1,234,567 views" (0 when unknown).
int _viewsCount(MuzoItem s) => int.tryParse(
      (s.views ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    ) ??
    0;

/// Upload age bucket — lower is fresher; unknown uploads rank worst (99).
int _uploadFreshness(String? uploaded) {
  if (uploaded == null || uploaded.isEmpty) return 99;
  final l = uploaded.toLowerCase();
  final n = int.tryParse(l.split(' ').first) ?? 99;
  if (l.contains('hour')) return n;
  if (l.contains('day')) return 10 + n;
  if (l.contains('week')) return 100 + n;
  if (l.contains('month')) return 1000 + n;
  if (l.contains('year')) return 10000 + n;
  return 99;
}

bool _isOldUpload(MuzoItem s) =>
    (s.uploaded ?? '').toLowerCase().contains('year');

bool _normStartsWith(String a, String b) =>
    a.startsWith(b) || b.startsWith(a);

/// Single release: short track, no album or album named after the song.
bool _looksLikeSingle(MuzoItem s) {
  final dur = s.durationSeconds;
  if (dur != null && dur > 360) return false;
  final album = s.album?.name.trim().toLowerCase() ?? '';
  if (album.isEmpty) return true;
  final title = s.title.trim().toLowerCase();
  return album == title || _normStartsWith(title, album);
}

/// Album cut: carries an album clearly distinct from the song title.
bool _looksLikeAlbumTrack(MuzoItem s) {
  final album = s.album?.name.trim().toLowerCase() ?? '';
  if (album.isEmpty) return false;
  final title = s.title.trim().toLowerCase();
  return album != title && !_normStartsWith(title, album);
}

/// Applies the sub-category strategy to a raw candidate batch: filters by
/// shape (singles / album cuts / freshness) then ranks (views or freshness).
List<MuzoItem> _tuneBatchForSub(String sub, List<MuzoItem> batch) {
  final t = _tuningForSub(sub);
  if (!t.isActive) return batch;
  var out = batch.where((s) {
    if (t.rejectOld && _isOldUpload(s)) return false;
    if (t.singlesOnly && !_looksLikeSingle(s)) return false;
    if (t.albumTracksOnly && !_looksLikeAlbumTrack(s)) return false;
    return true;
  }).toList();
  if (t.sortByViews) {
    out.sort((a, b) => _viewsCount(b).compareTo(_viewsCount(a)));
  } else if (t.rejectOld) {
    out.sort((a, b) =>
        _uploadFreshness(a.uploaded).compareTo(_uploadFreshness(b.uploaded)));
  }
  return out;
}

/// Up to 7 real songs for a category sub-category (e.g. "Salsa" inside "Latin",
/// "French Pop" inside "Pop", or "Drill FR" inside "Rap Français").
///
/// Editorial & Conformance Logic:
/// 1. Uses subcategory-specific seed anchors when available (e.g. Marc Anthony for Salsa,
///    Stromae for French Pop, Gazo for Drill FR).
/// 2. Generates composite queries (queryForSubCategory) when term-driven.
/// 3. Applies strict artist diversity (max 1 track per artist per subcategory row).
/// 4. Respects ambient/spoken-word exceptions (sleep, rain, white noise, focus).
/// 5. Top-ups come strictly from the parent category before any global fallbacks.
/// 6. Structural subs get dedicated strategies (_tuningForSub): New/Trending
///    favour fresh uploads, Popular/Top Songs/Music Videos rank by views,
///    Singles keep only single-shaped releases, Albums keep real album cuts.
/// Categories whose content is spoken-word (shows, episodes) rather than
/// music — they get their own iTunes podcast-episode source in addition to
/// the regular music pipeline.
bool _isSpokenWordCategory(String category, String sub) {
  const spoken = {'podcasts', 'comedy', 'news & politics', 'live events'};
  final catKey = category.trim().toLowerCase();
  final subKey = sub.trim().toLowerCase();
  if (spoken.contains(catKey)) return true;
  // Any branch under a podcast category, or any podcast-titled branch, is a
  // genuine spoken-word section: it must NEVER fall through to the music
  // pipeline (which would surface genre songs / repeated content).
  if (catKey.contains('podcast')) return true;
  if (subKey.contains('podcast')) return true;
  return false;
}

/// iTunes search term for a podcast subcategory: generic "podcasts" sections
/// map to a broad directory search, everything else becomes "`genre` podcast".
String _podcastTermFor(String sub) {
  final s = sub.trim().toLowerCase();
  if (s.isEmpty || s == 'all' || s == 'all podcasts') {
    return 'podcast';
  }
  if (s == 'trending podcasts' || s == 'trending') return 'popular podcast';
  if (s == 'new podcasts' || s == 'new') return 'new podcast';
  if (s == 'popular podcasts' || s == 'popular') return 'top podcast';
  if (s == 'news') return 'news podcast';
  if (s == 'true crime') return 'true crime podcast';
  if (s == 'comedy') return 'comedy podcast';
  if (s == 'business') return 'business podcast';
  if (s == 'technology') return 'technology podcast';
  if (s == 'education') return 'education podcast';
  if (s == 'sports') return 'sports podcast';
  if (s == 'culture') return 'culture podcast';
  if (s == 'music') return 'music podcast';
  if (s == 'society') return 'society podcast';
  if (s == 'history') return 'history podcast';
  if (s == 'science') return 'science podcast';
  if (s == 'stories') return 'stories podcast';
  if (s == 'interviews') return 'interviews podcast';
  if (s == 'religion & spirituality') return 'religion spirituality podcast';
  if (s.contains('podcast')) return s;
  return '$s podcast';
}

final categorySubSongsProvider =
    FutureProvider.family<List<MuzoItem>, ({String category, String sub, Set<String>? excludedArtists})>(
  (ref, args) async {
    // Hard global budget: a stalled upstream dependency (seed provider,
    // resolver, chart/RSS fetch, Deezer fallback) must never leave a category
    // section hanging forever. Whatever was already resolved is returned, or
    // the section simply ends empty and refills on the next visit.
    final cacheKey = 'catsub|${args.category}|${args.sub}';
    // Last-known-good content, bounded to 7 days. Used ONLY when the live
    // attempt produced nothing, so a saturated backend (every Home section
    // firing at launch) can never leave a shelf empty.
    Future<List<MuzoItem>> lastKnown({Duration? maxAge}) async {
      try {
        final stale = await ContentCacheService.instance
            .readStale(cacheKey, maxAge: maxAge);
        if (stale != null && (stale.length >= 2 || maxAge != null)) {
          return stale;
        }
      } catch (_) {}
      return const <MuzoItem>[];
    }

    // Offline: replay the last snapshot right away instead of starting a
    // 100-second fetch that can only end on that very same fallback.
    if (await ContentCacheService.isOffline()) {
      return await lastKnown(maxAge: ContentCacheService.offlineCeiling);
    }

    // Le pipeline complet peut légitimement mettre 40-60 s (passes successives
    // + file d'attente de recherches). L'écran, lui, doit montrer quelque chose
    // tout de suite : on laisse courir la construction quelques secondes, sinon
    // on sert le dernier instantané. Le futur abandonné va jusqu'au bout et
    // écrit dans le cache (~ligne 1770), donc la prochaine visite tombe sur la
    // version fraîche — page remplie immédiatement ET contenu qui rajeunit,
    // comme Spotify.
    final cachedUpFront = await lastKnown();
    final live = _buildCategorySubSongs(ref, args);
    // Démarrage à froid : le chart de genre Deezer est le seul flux sans clé
    // qui répond en ~2 s avec de vraies pochettes. Il remplit le rayon pendant
    // que le pipeline complet (35-80 s) tourne dans le dos et rafraîchit le
    // cache pour la visite suivante — un rayon vide n'est jamais acceptable.
    Future<List<MuzoItem>> coldGenreChart() async {
      try {
        final genreId = DeezerApiService.chartGenreFor('${args.sub} ${args.category}');
        if (genreId == null) return const <MuzoItem>[];
        final chart = await ref
            .read(deezerApiServiceProvider)
            .chartTracksInGenre(genreId, limit: 20)
            .timeout(const Duration(seconds: 6),
                onTimeout: () => const <MuzoItem>[]);
        debugPrint('[ColdChart] ${args.category} > ${args.sub} '
            'genre=$genreId tracks=${chart.length}');
        return chart;
      } catch (_) {
        return const <MuzoItem>[];
      }
    }
    // Mesuré sur l'appareil (18:16:03→18:16:29) : le worker répond en ~1 s par
    // requête mais la file de 6 créneaux fait attendre chaque rayon. À 20 s de
    // budget froid, Charts > Trending TIMEOUT systématiquement et Home reste
    // vide. Porté à 35 s : assez pour que 6-8 recherches passent (une rangée
    // visible), et le futur abandonné continue d'écrire le cache pour la
    // visite suivante. Quand le cache existe déjà, 8 s suffisent — inchangé.
    final budget = cachedUpFront.isNotEmpty
        ? const Duration(seconds: 8)
        : const Duration(seconds: 35);
    try {
      final fast = await live.timeout(budget);
      if (fast.isNotEmpty) return fast;
      debugPrint('[Pipe] ${args.category} > ${args.sub} EMPTY, using cache');
      if (cachedUpFront.isNotEmpty) return cachedUpFront;
      // Nothing on disk either: show the genre chart now rather than an empty
      // row, and only then let the pipeline finish for the cache.
      final quick = await coldGenreChart();
      if (quick.isNotEmpty) return quick;
      return await live
          .timeout(const Duration(seconds: 80))
          .catchError((_) => const <MuzoItem>[]);
    } catch (_) {
      debugPrint('[Pipe] ${args.category} > ${args.sub} TIMEOUT');
      // Stale-while-revalidate: only now, with the live fetch having failed,
      // may the last-known content be shown.
      if (cachedUpFront.isNotEmpty) return cachedUpFront;
      // Première visite, rien sur le disque : le chart de genre remplit le
      // rayon immédiatement ; la construction continue d'écrire le cache.
      final quick = await coldGenreChart();
      if (quick.isNotEmpty) return quick;
      return await live
          .timeout(const Duration(seconds: 60))
          .catchError((_) => const <MuzoItem>[]);
    }
  },
);

Future<List<MuzoItem>> _buildCategorySubSongs(
  Ref ref,
  ({String category, String sub, Set<String>? excludedArtists}) args,
) async {
    final stopwatch = Stopwatch()..start();
    void ts(String label) => debugPrint('[PipeTime] ${args.category} > ${args.sub} $label @${stopwatch.elapsedMilliseconds}ms');
    ts('ENTRY');

    final isAll = args.sub.trim().toLowerCase().startsWith('all ');
    final category = args.category.trim();
    final sub = args.sub.trim();
    final excluded = args.excludedArtists ?? <String>{};
    final isAmbient = isAmbientSubCategory(category, sub);
    final isSpokenCat = _isSpokenWordCategory(category, sub);

    // ─── Podcast categories: REAL podcast episodes only ───
    // iTunes' podcast directory serves full-length MP3 episodes (user_track)
    // that the player streams natively. These sections exist to surface SHOWS,
    // not songs, so they are served exclusively from iTunes episodes — the
    // generic 3-day cache below is never allowed to feed them old song lists.
    // A dedicated fresh cache keeps reopen cheap while guaranteeing real
    // episodes (never genre songs).
    // Rotation offset: refreshBucket porte déjà la graine par installation,
    // donc deux utilisateurs d'un même genre ne partent pas au même point alors
    // que le cache, lui, reste partagé.
    final bucket = ContentCacheService.refreshBucket;
    if (isSpokenCat) {
      final podCacheKey = 'podcat|$category|$sub';
      final podAudit = CategoryAudit(category: category, sub: sub);
      try {
        final pc = await ContentCacheService.instance
            .readIfFresh(podCacheKey, maxAge: ContentCacheService.browseTtl);
        if (pc != null && pc.length >= 2) {
          podAudit.report('episodes-cache');
          return ContentCacheService.rotate(pc, bucket);
        }
      } catch (_) {}
      try {
        final itunesPod = ref.read(itunesApiServiceProvider);
        // Rich search: several directory terms x FR+US storefronts so the
        // rows are long and varied. Generic sections ("All Podcasts", "New",
        // "Trending", "Popular") hit multiple broad terms; genre subs append
        // "podcast" to their own name for a targeted directory search.
        final s = sub.trim().toLowerCase();
        final base = _podcastTermFor(sub);
        // For genre subs the bare genre name (minus any "podcast" suffix) is
        // both a search term and a genre-purity hint for the result filter.
        final genreOnly = s
            .replaceAll('podcast', '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final terms = <String>{base};
        if (base == 'podcast') {
          // Generic rows: several broad directory terms so the list is long
          // and varied rather than a single top-Nc.
          terms.addAll(['new podcast', 'trending podcast', 'top podcast']);
        } else {
          // Genre subs: cover both "<genre> podcast" and the bare genre term
          // so sparse genres (news, technology, ...) still return real
          // episodes instead of an empty hard-gate section.
          if (genreOnly.isNotEmpty) terms.add(genreOnly);
          terms.addAll(['$s podcast', '$genreOnly podcast']);
        }
        final batches = <Future<List<MuzoItem>>>[];
        for (final t in terms.take(4)) {
          batches.add(itunesPod.searchPodcastEpisodesFrUs(t,
              limit: 12, maxPerShow: 2));
        }
        final episodeBatches = await Future.wait(batches)
            .timeout(const Duration(seconds: 24));
        var episodes = dedupeMuzoSongs([
          for (final batch in episodeBatches) ...batch,
        ]);
        // A genre section must stay genre-pure: drop episodes whose show name
        // doesn't mention the genre OR the generic "podcast" word, so the rows
        // never read as a recycled orchard of unrelated shows. Only applied to
        // actual genre subs (generic rows keep all broad-directory results).
        if (base != 'podcast') {
          final genreHints = <String>{
            genreOnly,
            s.replaceAll(RegExp(r'\s+'), ''),
          }..removeWhere((h) => h.isEmpty);
          if (genreHints.isNotEmpty) {
            episodes = episodes.where((e) {
              final show = (e.channelName ?? e.title).toLowerCase();
              return genreHints.any(show.contains) ||
                  show.contains('podcast');
            }).toList();
          }
        }
        // "New Podcasts" and friends: freshest episodes first so the section
        // actually looks like newly-released content (falls back to iTunes'
        // directory order for generic rows).
        if (episodes.length > 1) {
          final isFreshFirst = s == 'new podcasts' ||
              s == 'new' ||
              s == 'latest episodes';
          if (isFreshFirst) {
            episodes.sort((a, b) => (b.releaseDate?.millisecondsSinceEpoch ?? 0)
                .compareTo(a.releaseDate?.millisecondsSinceEpoch ?? 0));
          }
        }
        final podcastList = episodes
            .map((e) => e.copyWith(
                  verified: true,
                  relevanceScore: 100,
                  source: e.source ?? 'itunes podcast',
                ))
            .take(24)
            .toList();
        podAudit..onFetched(episodes.length)..onAccepted(podcastList.length);
        if (episodes.length >= 3) {
          unawaited(
              ContentCacheService.instance.write(podCacheKey, podcastList));
          podAudit.report('episodes');
          return ContentCacheService.rotate(podcastList, bucket);
        }
        podAudit.report('episodes');
      } catch (_) {
        podAudit.report('episodes-error');
      }

      // Nothing real from the directory: a hand-verified row from the static
      // catalog is still real content, so try it before ending the section.
      try {
        final statics =
            await CategoryContentService.instance.loadFor(category, sub);
        if (statics.isNotEmpty) {
          podAudit.report('episodes-static');
          return ContentCacheService.rotate(
            statics.map((s) => s.copyWith(verified: true)).toList(),
            bucket,
          );
        }
      } catch (_) {}

      // ─── HARD GATE: a spoken-word/podcast sub NEVER shows music tracks ───
      // When iTunes serves <3 real episodes (cache miss included) the section
      // returns empty — it must never fall through to the music pipeline and
      // surface genre songs inside "Podcasts / Comedy / News" browse rows.
      // Real episodes, or nothing. Nothing is fabricated to fill the gap.
      return const <MuzoItem>[];
    }

    // ─── Refresh cache (3-day browse window) ───
    // Only a FRESH entry may short-circuit the network: serving an expired one
    // here would pin the shelf to the same snapshot forever, which is exactly
    // what made a row look unchanged for days. The stale fallback now lives in
    // the provider wrapper and only kicks in if the live fetch fails.
    final cacheKey = 'catsub|$category|$sub';
    try {
      final cached = await ContentCacheService.instance
          .readIfFresh(cacheKey, maxAge: ContentCacheService.browseTtl);
      if (cached != null && cached.length >= 2) {
        return ContentCacheService.rotate(cached, bucket);
      }
    } catch (_) {}

    // ─── Static Supabase catalog (layer 2) ───
    // When no fresh cache exists, serve the manually curated `category_content`
    // rows BEFORE any live fetch: sub-sections that never yield verified live
    // content (e.g. "Hits Bénin > Benin Gospel") still display real tracks
    // instantly, with zero refresh. Falls through to the live pipeline when
    // the table has no rows for this (category, sub).
    try {
      final statics = await CategoryContentService.instance.loadFor(category, sub);
      if (statics.isNotEmpty) {
        debugPrint('[Catalog] "$category > $sub" static=${statics.length}');
        return ContentCacheService.rotate(
          statics.map((s) => s.copyWith(verified: true)).toList(),
          bucket,
        );
      }
    } catch (e) {
      debugPrint('[Catalog] "$category > $sub" unavailable: $e');
    }

// Strict category constraint (genre + country + language + region). A
    // geo-scoped section (e.g. "Gospel > Benin Gospel") must ONLY show content
    // that satisfies ALL its constraints — never generic parent-category music.
    final constraint = categoryConstraintFor(category, sub);
    final geoScoped = constraint.isGeoScoped;

    final audit = CategoryAudit(category: category, sub: sub);

    // ─── Hits Bénin: real Beninese artists ───
    // Apple has no Benin storefront (bj RSS returns zero rows), so the chart
    // path below surfaces nothing, and the YouTube worker rarely knows niche
    // Beninese artists — yielding wrong artists and songs that fail to play.
    // The curated Benin artist seeds (Bobo Wê, Fanicko, Vano Baby, Zeynab
    // Abib, ...) are searched on the real YouTube Data API (key from
    // youtube_api.dart), giving genuine full-length videos; iTunes previews
    // are the fallback when YouTube has nothing playable.
    final catKeyLower = category.trim().toLowerCase();
    // Accent- and punctuation-insensitive: the exact `== 'hit benin'` test
    // silently skipped this whole branch whenever the label carried an accent
    // or a variant spelling, and the shelf then fell through to the generic
    // pipeline and came back empty.
    final catKeyFolded = _foldCategoryKey(catKeyLower);
    if (catKeyFolded.contains('benin')) {
      final beninSeeds = seedsForSubCategory(category, sub);
      debugPrint('[Benin] gate="$catKeyFolded" seeds=${beninSeeds.length}');
      if (beninSeeds.isNotEmpty) {
        final yt = YoutubeApiService();
        final itunes = ref.read(itunesApiServiceProvider);
        // Both sources run CONCURRENTLY and each seed in parallel: the
        // sequential version cost 6 x 10s per phase, and chaining the two
        // phases pushed the shelf past the global budget so it came back
        // empty. iTunes is a different provider, so it is unaffected by the
        // YouTube worker being saturated by the other Home sections.
        final ytFuture = Future.wait(
          beninSeeds.take(6).map((seed) async {
            final seedItems = <MuzoItem>[];
            try {
              final raw = await yt
                  .search(query: seed, maxResults: 6)
                  .timeout(const Duration(seconds: 12));
              for (final m in raw.whereType<Map>()) {
                final vid = m['id']?.toString();
                if (vid == null || vid.isEmpty) continue;
                seedItems.add(MuzoItem(
                  title: (m['title'] ?? 'Unknown').toString(),
                  videoId: vid,
                  isExplicit: false,
                  resultType: 'song',
                  channelName: m['channel']?.toString(),
                  artists: [
                    MuzoArtist(name: m['channel']?.toString() ?? seed, id: ''),
                  ],
                  thumbnails: [
                    if (m['thumbnail'] != null)
                      MuzoThumbnail(
                          url: m['thumbnail'].toString(),
                          width: 480,
                          height: 360),
                  ],
                ));
              }
            } catch (_) {}
            final playable =
                dedupeMuzoSongs(seedItems).where(isActuallyPlayable).toList();
            debugPrint('[Benin-YT] seed="$seed" raw=${seedItems.length} playable=${playable.length}');
            return playable;
          }),
        );
        final itFuture = Future.wait(
          beninSeeds.take(6).map((seed) async {
            try {
              final tracks = await itunes
                  .searchArtistStreamTracks(seed, limit: 6)
                  .timeout(const Duration(seconds: 12));
              final playable =
                  dedupeMuzoSongs(tracks).where(isActuallyPlayable).toList();
              debugPrint('[Benin-iTunes] seed="$seed" playable=${playable.length}');
              return playable;
            } catch (_) {
              return const <MuzoItem>[];
            }
          }),
        );
        final ytList =
            _interleaveByArtist(await ytFuture, maxPerArtist: 1);
        debugPrint('[Benin-YT] "$category > $sub" seeds=${beninSeeds.length} playable=${ytList.length}');
        if (ytList.isNotEmpty) {
          final list = ytList
              .map((s) => s.copyWith(
                  verified: true, source: s.source ?? 'youtube data api'))
              .take(24)
              .toList();
          unawaited(ContentCacheService.instance.write(cacheKey, list));
          return ContentCacheService.rotate(list, bucket);
        }
        // 2) Fallback: real iTunes preview tracks for the same artists.
        final itList =
            _interleaveByArtist(await itFuture, maxPerArtist: 1);
        debugPrint('[Benin-iTunes] "$category > $sub" seeds=${beninSeeds.length} playable=${itList.length}');
        if (itList.isNotEmpty) {
          final list = itList
              .map((s) => s.copyWith(
                  verified: true, source: s.source ?? 'itunes benin'))
              .take(24)
              .toList();
          unawaited(ContentCacheService.instance.write(cacheKey, list));
          return ContentCacheService.rotate(list, bucket);
        }
      }
    }

    final seenArtists = <String, int>{};
    final seenIds = <String>{};
    final result = <MuzoItem>[];

    /// Items that passed every rule except "this artist already leads another
    /// section of the same page". The cross-section exclusion is what keeps a
    /// category free of repeats, but in a 15-section category the last rows
    /// (observed: Rap 90s, Trap FR) find all their artists already claimed and
    /// come back empty. Sharing an artist with one other row is the lesser
    /// evil; the salvage is only read when the section cannot reach the
    /// 3-items minimum on its own.
    final salvage = <MuzoItem>[];
    final salvageArtists = <String>{};

    /// MusicBrainz-confirmed artists (geo/genre evidence) that may bypass the
    /// text gate — the ONLY exception to the strict rule, backed by real
    /// database records, never a guess.
    final mbWhitelist = <String>{};

    void addUnique(
      List<MuzoItem> batch, {
      int maxPerArtist = 1,
      bool applyConstraint = true,
      bool sourceVerified = false,
    }) {
      audit.onFetched(batch.length);
      for (final song0 in _tuneBatchForSub(sub, batch)) {
        var song = song0;
        if (!isActuallyPlayable(song)) {
          audit.rejectedBecause(CategoryRejectReason.notPlayable);
          continue;
        }
        if (isJunkSong(song.title, isAmbient: isAmbient)) {
          audit.rejectedBecause(CategoryRejectReason.junkTitle);
          continue;
        }
        final idKey = (song.videoId ?? '${song.title}|${song.displayArtist}')
            .toLowerCase();
        if (applyConstraint && !acceptsForCategory(song, constraint)) {
          if (idKey.isNotEmpty && mbWhitelist.contains(idKey)) {
            song = song.copyWith(verified: true);
          } else {
            final score = categoryMatchScore(song, constraint);
            audit.rejectedBecause(
              score == 0
                  ? CategoryRejectReason.wrongCountry
                  : CategoryRejectReason.belowThreshold,
            );
            continue;
          }
        }
        if (idKey.isEmpty || seenIds.contains(idKey)) {
          audit.rejectedBecause(CategoryRejectReason.duplicate);
          continue;
        }
        final norm = normalizeContentKey(song);
        if (norm != null && seenIds.contains(norm)) {
          audit.rejectedBecause(CategoryRejectReason.duplicate);
          continue;
        }

        final artistKey =
            primaryArtistName(song.displayArtist).trim().toLowerCase();
        if (artistKey.isNotEmpty &&
            (seenArtists[artistKey] ?? 0) >= maxPerArtist) {
          audit.rejectedBecause(CategoryRejectReason.artistLimit);
          continue;
        }
        if (artistKey.isNotEmpty && excluded.contains(artistKey)) {
          audit.rejectedBecause(CategoryRejectReason.excludedArtist);
          if (artistKey.isNotEmpty &&
              salvageArtists.add(artistKey) &&
              salvage.length < 10) {
            salvage.add(song);
          }
          continue;
        }

        seenIds.add(idKey);
        if (norm != null) seenIds.add(norm);
        if (artistKey.isNotEmpty) {
          seenArtists[artistKey] = (seenArtists[artistKey] ?? 0) + 1;
        }
        song = song.copyWith(
          verified: applyConstraint || sourceVerified
              ? true
              : song.verified,
          relevanceScore: song.relevanceScore ??
              (applyConstraint
                  ? categoryMatchScore(song, constraint)
                  : null),
        );
audit.onAccepted();
        result.add(song);
        if (result.length >= 15) break;
      }
    }

    /// Returns the id-keys of [items] whose artist is geo/genre-confirmed by
    /// MusicBrainz — authoritative rescue for strict-gate rejections only.
    Future<Set<String>> mbApprovedIds(List<MuzoItem> items) async {
      if (!constraint.isGeoScoped || items.isEmpty) return const {};
      try {
        final approved = await ref
            .read(musicBrainzServiceProvider)
            .rescueMatches(
              items,
              geo: constraint.geo,
              genre: constraint.hasGenre ? constraint.genre : null,
            )
            .timeout(const Duration(seconds: 6), onTimeout: () => const []);
        return {
          for (final s in approved)
            (s.videoId ?? '${s.title}|${s.displayArtist}').toLowerCase(),
        };
      } catch (_) {
        return const {};
      }
    }

    // ─── Charts / Trending: real current tops from Apple's RSS charts ───
    // Each chart sub mirrors a real storefront (France → fr, Nigeria → ng...).
    // Trend entries carry no stream URL, so each pick is resolved to a
    // playable item with one YT search.
    final catLower = category.toLowerCase();
    final isChartCat = catLower == 'charts' ||
        catLower == 'trending' ||
        catLower == 'hit benin';
    // Curated sub-category seeds (non-chart, non-geo) run BEFORE algorithmic
    // resolution so curated artists always lead the section and resolution's
    // early-return (>=3 songs) can't override them (e.g. Rap charts leaking
    // into "Romance > French Love"). Specific seeds also cover structural
    // subs ("All Music" / "Top Songs"); parent seeds are the fallback.
    final subSeeds = seedsForSubCategory(category, sub);
    final useCuratedFirst = subSeeds.isNotEmpty && !isChartCat && !geoScoped;
    if (isChartCat && !isAmbient) {
      try {
        final countries = catLower == 'hit benin'
            ? const ['bj']
            : TrendingService.countriesForSub(sub);
        ts('before-pools');
        final pools =
            await Future.wait(countries.map(TrendingService.topSongs));
        ts('after-pools');
        final seenTrends = <String>{};
        final trends = <TrendSong>[];
        for (final pool in pools) {
          for (final t in pool) {
            final k = '${t.title}|${t.artist}'.toLowerCase();
            if (seenTrends.contains(k)) continue;
            seenTrends.add(k);
            trends.add(t);
          }
        }
        final api = ref.read(muzoApiServiceProvider);
        // Une recherche par tendance, L'UNE APRÈS L'AUTRE : 16 × 8 s = 130 s
        // avant le premier affichage (mesuré sur l'appareil, log
        // « service-ready @130014ms »). Toutes sont lancées d'un coup — le
        // plafond de 4 requêtes simultanées est déjà dans MuzoApiService — et
        // on consomme les réponses AU FIL DE L'EAU : la file d'attente ne doit
        // jamais faire perdre un lot déjà revenu. Pas de deadline ici : le
        // provider sert le cache au bout de 20 s et ce qui suit ne bloque
        // plus l'écran, il remplit juste le cache pour la prochaine visite.
        final wantedTrends = trends.take(6).toList();
        var trendsFetched = 0;
        final trendStream = Stream<MuzoSearchResponse>.fromFutures([
          for (final t in wantedTrends)
            api
                .search('${t.title} ${t.artist}', filter: 'songs')
                .timeout(const Duration(seconds: 15),
                    onTimeout: () => MuzoSearchResponse(results: const []))
                .catchError((_) => MuzoSearchResponse(results: const [])),
        ]);
        await for (final resp in trendStream) {
          trendsFetched += resp.results.length;
          addUnique(
            resp.results.take(2).toList(),
            applyConstraint: false,
            sourceVerified: true,
            maxPerArtist: 1,
          );
          if (result.length >= 15) break;
          // Le provider, lui, abandonne à 20 s. Sans plafond ici la passe reste
          // assise sur TOUTES les recherches : mesuré sur l'appareil
          // (17:18:20 → 17:20:59), 10 recherches espacées de ~6 s = 3 minutes,
          // donc Home affichait des rayons vides jusqu'à la visite d'après. Dès
          // 3 titres et le budget d'affichage passé, ce qui est déjà revenu est
          // rendu et écrit au cache — la règle du reste du pipeline.
          if (result.length >= 3 &&
              stopwatch.elapsed > const Duration(seconds: 13)) {
            break;
          }
        }
        ts('after-trends');
        debugPrint(
            '[Charts] "$category > $sub" trends=${trends.length} fetched=$trendsFetched result=${result.length}');
        if (result.length >= 3) {
          audit.report('charts');
          final chartList = result.take(15).toList();
          unawaited(ContentCacheService.instance.write(cacheKey, chartList));
          return ContentCacheService.rotate(chartList, bucket);
        }
        // Below the minimum → fall through to the regular pipeline rather
        // than showing nothing.
      } catch (_) {}
    }

    // ─── New resolver: dispatch by category type (genre, geo, decades, etc.) ───
    final service = CategoryResolutionService(ref);
    ts('service-ready');

    if (useCuratedFirst) {
      // Curated seeds open the section: rotate per 3-day bucket so each
      // refresh leads with different artists → genuinely different songs.
      final off = subSeeds.length > 1 ? bucket % subSeeds.length : 0;
      final orderedSeeds = ContentCacheService.rotate(subSeeds, off);
      final seedFutures = <Future<List<MuzoItem>>>[
        for (final seed in orderedSeeds.take(6))
          ref
              .watch(categorySongsProvider(seed).future)
              .timeout(const Duration(seconds: 22),
                  onTimeout: () => const <MuzoItem>[])
              .catchError((_) => const <MuzoItem>[]),
      ];
      ts('before-seed-wait');
      // Timeout PAR SEED : un `Future.wait` coupé à 15 s jetait aussi les
      // graines déjà revenues — la section entière repartait à zéro.
      final batches = await Future.wait(seedFutures);
      ts('after-seed-wait');
      for (final batch in batches) {
        addUnique(batch, maxPerArtist: 1);
        if (result.length >= 8) break;
      }
      debugPrint('[Pipe] $category > $sub curated-after-seeds=${result.length}');
      // Resolution only tops up when the curated seeds underfill; no
      // early-return so it can never displace the curated artists.
      if (result.length < 8) {
        ts('before-resolver');
        final resolutionResult = await service
            .resolve(
              category: category,
              sub: sub,
              excludedArtists: excluded,
            )
            .timeout(const Duration(seconds: 18), onTimeout: () =>
                CategoryResolutionResult(
                  songs: [], logs: const [], type: CategoryType.fallback,
                ));
        ts('after-resolver');
        if (resolutionResult.type != CategoryType.fallback) {
          addUnique(resolutionResult.songs);
          logResolution(resolutionResult);
        }
      }
    } else {
      ts('else-branch: before-resolver');
      final resolutionResult = await service
          .resolve(
            category: category,
            sub: sub,
            excludedArtists: excluded,
          )
          .catchError((_) => CategoryResolutionResult(
                songs: [], logs: const [], type: CategoryType.fallback,
              ))
          .timeout(const Duration(seconds: 18), onTimeout: () =>
              CategoryResolutionResult(
                songs: [], logs: const [], type: CategoryType.fallback,
              ));
      ts('else-branch: after-resolver');
      if (resolutionResult.type != CategoryType.fallback) {
          addUnique(resolutionResult.songs);
          logResolution(resolutionResult);
          if (resolutionResult.songs.length >= 3) {
          final resolved = resolutionResult.songs
              .map((s) => s.copyWith(
                  verified: true,
                  relevanceScore: s.relevanceScore ??
                      categoryMatchScore(s, constraint)))
              .take(15)
              .toList();
          audit
            ..onFetched(resolutionResult.songs.length)
            ..onAccepted(resolved.length)
            ..report('resolver');
          unawaited(ContentCacheService.instance.write(cacheKey, resolved));
          return ContentCacheService.rotate(resolved, bucket);
        }
      }

      // ─── Fallback: old pipeline for unresolved categories ───
      // Dedicated sub-category seeds are the fallback for geo-scoped and
      // chart sections that keep algorithmic resolution / charts as the
      // primary authority.
      ts('else-branch: before-fallback-seeds, subSeeds=${subSeeds.length}');
      if (subSeeds.isNotEmpty) {
        // Rotate the seed list on the 3-day bucket so each refresh leads with
        // different artists → genuinely different songs, not the same top hits.
        final off = subSeeds.length > 1 ? bucket % subSeeds.length : 0;
        final orderedSeeds = ContentCacheService.rotate(subSeeds, off);
        final seedFutures = <Future<List<MuzoItem>>>[
          for (final seed in orderedSeeds.take(6))
            ref
                .watch(categorySongsProvider(seed).future)
                .timeout(const Duration(seconds: 22),
                    onTimeout: () => const <MuzoItem>[])
                .catchError((_) => const <MuzoItem>[]),
        ];
        ts('fallback: before-seed-wait');
        final batches = await Future.wait(seedFutures);
        ts('fallback: after-seed-wait');
        for (final batch in batches) {
          try {
            addUnique(batch, maxPerArtist: 1);
          } catch (e, st) {
            debugPrint('[Pipe] $category > $sub addUnique CRASH: $e\n$st');
          }
          if (result.length >= 8) break;
        }
        debugPrint('[Pipe] $category > $sub fallback-after-seeds=${result.length}');
      } else {
        final subQuery = queryForSubCategory(category, sub);
        final futures = <Future<List<MuzoItem>>>[
          ref.watch(categorySongsProvider(subQuery).future)
              .catchError((_) => const <MuzoItem>[]),
          if (!isAll && subQuery.toLowerCase() != category.toLowerCase())
            ref.watch(categorySongsProvider(category).future)
                .catchError((_) => const <MuzoItem>[]),
        ];
        final batches = await Future.wait(futures);
        for (final batch in batches) {
          addUnique(batch);
          if (result.length >= 8) break;
        }
      }
    }

    // ─── Spoken-word categories ───
    // Dead code since the hard gate above: spoken-word subs are fully resolved
    // by the iTunes episode branch and can NEVER reach this music pipeline.

    // Strict Category-Scoped top-up.
    ts('topup: start, result.len=${result.length}, geoScoped=$geoScoped');
    if (result.length < 7) {
      final scopedPlan = genrePlanFor(category, sub);
      final scopedTerm = scopedPlan.isEmpty
          ? null
          : (subSeeds.isNotEmpty
              ? scopedPlan.ytifyTerm
              : queryForSubCategory(category, sub));
      final geoTerm = buildScopedSearchTerm(category, sub, scopedTerm ?? '');

      if (geoScoped) {
        Future<void> addScoped(List<MuzoItem> raw) async {
          final scoped = _prioritizeWestern(raw);
          // MusicBrainz rescue: real database evidence (artist country/region
          // + genre) may accept a candidate the strict text gate rejected.
          mbWhitelist.addAll(await mbApprovedIds(scoped));
          addUnique(scoped);
        }

        if (geoTerm.isNotEmpty) {
          try {
            final scopedBatch = await ref
                .read(muzoApiServiceProvider)
                .search(geoTerm, filter: 'songs')
                .timeout(const Duration(seconds: 12));
            await addScoped(scopedBatch.results);
          } catch (_) {}
        }
        if (result.length < 7) {
          try {
            final scopedBatch = await ref
                .read(muzoApiServiceProvider)
                .search(geoTerm, filter: 'songs')
                .timeout(const Duration(seconds: 12));
            await addScoped(scopedBatch.results);
          } catch (_) {}
        }
        if (result.length < 7 && geoTerm.split(' ').length > 1) {
          final flipped = geoTerm.split(' ').reversed.join(' ');
          try {
            final scopedBatch = await ref
                .read(muzoApiServiceProvider)
                .search(flipped, filter: 'songs')
                .timeout(const Duration(seconds: 12));
            await addScoped(scopedBatch.results);
          } catch (_) {}
        }
      } else {
        final categoryFuture = ref.watch(categorySongsProvider(category).future)
            .catchError((_) => const <MuzoItem>[]);
        if (geoTerm.isNotEmpty) {
          try {
            final scopedBatch = await ref
                .read(muzoApiServiceProvider)
                .search(geoTerm, filter: 'songs')
                .timeout(const Duration(seconds: 12));
            addUnique(_prioritizeWestern(scopedBatch.results));
          } catch (_) {}
        }
        if (result.length < 7) {
          final categoryBatch = await categoryFuture;
          addUnique(categoryBatch);
        }
      }
    }

    // Last resort: genre batch from real keyless sources, then a plain search.
    if (result.isEmpty) {
      final plan = genrePlanFor(category, sub);
      if (!plan.isEmpty) {
        final genreBatch = await fetchGenreBatch(
          ref,
          plan,
          perSource: 8,
        ).catchError((_) => const <MuzoItem>[])
            .timeout(const Duration(seconds: 14), onTimeout: () => const []);
        addUnique(genreBatch);
      }
      if (result.isEmpty) {
        try {
          final subTerm = isAll ? category : queryForSubCategory(category, sub);
          final resp = await ref
              .read(muzoApiServiceProvider)
              .search(subTerm, filter: 'songs')
              .timeout(const Duration(seconds: 10));
          addUnique(_prioritizeWestern(resp.results));
        } catch (_) {}
      }
    }

    // ─── Deezer genre-chart rescue ───
    // Deezer's `/chart/{genreId}/tracks` is the one keyless feed that answers
    // genuinely in-genre songs (its `/genre/{id}/…` sub-feeds ignore the id),
    // so a thin section is finished from that chart instead of staying a
    // keyword grab-bag. Seeds are metadata only; they are resolved to
    // full-length YouTube tracks before they reach the shelf.
    if (result.length < 7) {
      final genreId = DeezerApiService.chartGenreFor('$sub $category');
      if (genreId != null) {
        try {
          final chart = await ref
              .read(deezerApiServiceProvider)
              .chartTracksInGenre(genreId, limit: 25);
          final playable = await ref
              .read(multiApiServiceProvider)
              .resolveToPlayable(chart, max: 14);
          addUnique(playable, applyConstraint: false, maxPerArtist: 3);
          debugPrint('[GenreChart] "$category > $sub" genre=$genreId '
              'chart=${chart.length} resolved=${playable.length}');
        } catch (_) {}
      }
    }

    // ─── Modern boost: current chart-matching tracks in every music sub ───
    // A couple of TODAY's chart tracks (genre-matched via iTunes metadata)
    // are inserted near the front so even healthy sections feel current, and
    // every refresh cycle brings different ones.
    if (!isChartCat &&
        !useCuratedFirst &&
        !geoScoped &&
        !_isSpokenWordCategory(category, sub) &&
        result.length < 9) {
      try {
        final subOffset =
            (sub.trim().toLowerCase().hashCode.abs() % 5) * 3;
        final picks =
            await TrendingService.picksForCategory(catLower, bucket, 3,
                rotationOffset: subOffset);
        final startLen = result.length;
        if (picks.isNotEmpty) {
          final api = ref.read(muzoApiServiceProvider);
          for (final t in picks) {
            if (result.length >= 15) break;
            try {
              final resp = await api
                  .search('${t.title} ${t.artist}', filter: 'songs')
                  .timeout(const Duration(seconds: 8));
              addUnique(
                resp.results.take(1).toList(),
                // Modern boost: the pick itself is genre-matched from TODAY's
                // real Apple RSS chart, and the resolved track must ALSO pass
                // the strict category gate before it can be injected.
                applyConstraint: true,
                maxPerArtist: 1,
              );
            } catch (_) {}
          }
          // Surface the freshly added modern tracks within the visible first
          // cards instead of leaving them as an invisible tail.
          final modernCount = result.length - startLen;
          if (modernCount > 0) {
            final modern = result.sublist(startLen);
            result.removeRange(startLen, result.length);
            result.insertAll(result.length >= 2 ? 2 : 0, modern);
          }
        }
      } catch (_) {}
    }

    // ─── Minimum garanti : ≥5 vrais sons par sous-catégorie ───
    // Un client de musique ne montre jamais une ligne quasi vide. On complète
    // d'abord avec TOUS les artistes éditoriaux de la sous-catégorie, puis
    // ceux de la catégorie parente — jamais du contenu inventé. Le strict gate
    // (addUnique) conserve l'identité géo/genre de la section.
    const minSongs = 5;
    if (result.length < minSongs) {
      final seedPool = <String>[
        ...?subCategorySeeds(category, sub),
        ...seedsFor(category),
      ];
      final seenSeeds = <String>{};
      final seedOrder = <String>[
        for (final s in seedPool)
          if (s.trim().isNotEmpty && seenSeeds.add(s.trim().toLowerCase())) s.trim(),
      ];
      final off = seedOrder.length > 1
          ? (bucket + sub.trim().toLowerCase().hashCode.abs()) %
              seedOrder.length
          : 0;
      final rotatedSeeds = ContentCacheService.rotate(seedOrder, off);
      final fillFutures = <Future<List<MuzoItem>>>[
        for (final seed in rotatedSeeds.take(6))
          ref
              .watch(categorySongsProvider(seed).future)
              .timeout(const Duration(seconds: 22),
                  onTimeout: () => const <MuzoItem>[])
              .catchError((_) => const <MuzoItem>[]),
      ];
      final fillBatches = await Future.wait(fillFutures);
      for (final batch in fillBatches) {
        addUnique(batch, maxPerArtist: 1);
        if (result.length >= minSongs) break;
      }
      if (result.isNotEmpty && result.length < minSongs) {
        debugPrint('[Pipe] "$category > $sub" min-fill final=${result.length}');
      }
    }

    // Last resort, and the only way an artist can appear in two rows of the
    // same page: an empty section is what the user reads as "no content".
    if (result.length < 3 && salvage.isNotEmpty) {
      final had = result.length;
      for (final song in salvage) {
        if (result.length >= 6) break;
        result.add(song.copyWith(
          verified: true,
          relevanceScore:
              song.relevanceScore ?? categoryMatchScore(song, constraint),
        ));
      }
      if (result.length > had) {
        debugPrint(
            '[Pipe] $category > $sub SALVAGE=${result.length - had} (artistes déjà vus)');
      }
    }

    ts('before-audit');
    audit.report();
    // ─── Final safety: enforce 1 song max per artist in the output ───
    final seenFinalArtists = <String>{};
    final finalList = <MuzoItem>[];
    for (final song in result) {
      if (finalList.length >= 10) break;
      final artist = primaryArtistName(song.displayArtist).trim().toLowerCase();
      if (artist.isNotEmpty && seenFinalArtists.contains(artist)) continue;
      if (artist.isNotEmpty) seenFinalArtists.add(artist);
      finalList.add(song);
    }
    // TEMP (seed helper): dumps the accepted REAL videoIds so we can build
    // `insert into category_content ...` rows without inventing anything.
    if (finalList.isNotEmpty) {
      debugPrint('[Accepts] "$category > $sub" => '
          '${finalList.map((s) => '${s.videoId}|${s.title}|${s.displayArtist}').join(' ;; ')}');
    }
    // Cache only sections that meet the display minimum, so a transient
    // network failure is never frozen for 3 days.
    if (finalList.length >= 3) {
      unawaited(ContentCacheService.instance.write(cacheKey, finalList));
    }
    return ContentCacheService.rotate(finalList, bucket);
  }

/// 100+ real songs for an artist page.
///
/// Primary source: the artist's own "Top songs" playlist, resolved via
/// search(artist, filter: 'artists') -> getArtistDetails(browseId) ->
/// getPlaylistDetails(playlistId). That endpoint alone returns ~100 tracks.
/// If that path fails (or yields fewer than [minCount] songs) the provider
/// falls back to paging the plain search endpoint with continuation tokens,
/// which tops out around 40 songs. It never returns an empty list: a final
/// plain search for the artist name guarantees at least some tracks.
/// Tracks the artist page is expected to show. Below this the cache is treated
/// as thin and the top-up passes keep running until it is met (or the time
/// budget is spent).
const int kMinArtistTracks = 100;

/// Merges downloaded tracks matching [artistQuery] into [songs], matching on
/// the artist tokens like the network top-up does. Offline backbone of the
/// artist page: downloads always show, with or without network or cache, and a
/// row that already lists the same song under a non-downloaded identity is
/// rebound onto the copy whose bytes are on disk.
void _mergeDownloadedSongs(List<MuzoItem> songs, String artistQuery) {
  final seen = <String>{
    for (final s in songs) (s.videoId ?? '').toLowerCase(),
  }..remove('');
  // Le même morceau vit souvent sous deux identités : la graine Deezer `dz_…`
  // dans la liste réseau, le fichier `<videoId>.m4a` au registre. On ne veut ni
  // un doublon, ni garder l'identité sans octets — celle-là repart sur YouTube
  // et se prend le géo-blocage alors que le son est déjà sur l'appareil.
  final titleIndex = <String, int>{
    for (var i = 0; i < songs.length; i++)
      '${compactSongTitle(songs[i].title)}|${compactArtistName(songs[i].displayArtist)}': i,
  }..remove('|');
  final tokens = _artistTokens(primaryArtistName(artistQuery));
  var merged = 0;
  var rebound = 0;
  try {
    final box = Hive.box('downloads');
    // Toute la liste tient sous UNE clé ('list'), il n'y a pas une entrée par
    // téléchargement : parcourir `box.values` rendait la List elle-même, le
    // `as Map` levait, et le `catch (_) {}` avalait l'erreur — cette fusion n'a
    // donc jamais rien ajouté, et un son téléchargé restait invisible (et
    // injouable) sur la page artiste tant que la liste réseau ne le portait pas.
    final raw = box.get('list');
    if (raw is List) {
      for (final e in raw) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final r = m['result'];
          if (r is! Map) continue;
          final item = MuzoItem.fromJson(Map<String, dynamic>.from(r));
          final vid = item.videoId;
          if (vid == null || vid.isEmpty) continue;
          final names = (item.artists ?? const <MuzoArtist>[])
              .map((a) => a.name)
              .join(' ');
          final haystack = '${item.displayArtist} $names'.toLowerCase();
          if (!tokens.any(haystack.contains)) continue;
          final key = vid.toLowerCase();
          final titleKey =
              '${compactSongTitle(item.title)}|${compactArtistName(item.displayArtist)}';
          final at = titleKey == '|' ? null : titleIndex[titleKey];
          if (at != null) {
            // Déjà affiché sous une autre identité : on rebascule la ligne sur
            // l'exemplaire téléchargé, qui lui a un fichier à lire.
            if (songs[at].videoId?.toLowerCase() != key) {
              songs[at] = item;
              seen.add(key);
              rebound++;
            }
            continue;
          }
          if (seen.contains(key)) continue;
          seen.add(key);
          if (titleKey != '|') titleIndex[titleKey] = songs.length;
          songs.add(item);
          merged++;
        } catch (_) {}
      }
    }
  } catch (_) {}
  // Visible à dessein : c'est la seule trace qui prouve qu'un téléchargement a
  // bien été rattaché à la page artiste.
  debugPrint('ArtistSongs: "$artistQuery" merged $merged downloaded track(s), '
      '$rebound rebound onto an existing row (${songs.length} total)');
}

final artistSongsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artist) async {
  if (artist.trim().isEmpty) return <MuzoItem>[];

  // ─── 72h Hive cache ───
  final cacheKey = 'artist_songs_${artist.trim().toLowerCase()}';
  // Offline the network cannot refill anything, so an expired snapshot is
  // still served (up to a year) instead of an empty page.
  var offline = false;
  try {
    final conn = await safeConnectivity();
    offline = !conn.contains(ConnectivityResult.mobile) &&
        !conn.contains(ConnectivityResult.wifi) &&
        !conn.contains(ConnectivityResult.ethernet) &&
        !conn.contains(ConnectivityResult.vpn);
  } catch (_) {}
  try {
    final box = Hive.box('artist_songs_cache');
    final cached = box.get(cacheKey) as Map?;
    if (cached != null) {
      final ts = cached['ts'] as int? ?? 0;
      final jsonList = (cached['songs'] as List?) ?? [];
      // Un instantané — même en dessous de l'objectif de 100 titres — est
      // TOUJOURS servi tout de suite : la page se peint, et c'est
      // [artistSongsTopUpProvider] qui la fait grandir en arrière-plan et
      // réécrit ce même cache. Expirer un cache « mince » au bout de 3 h
      // re-plaquait le pipeline complet à chaque visite (25 s de squelettes).
      final maxAge = offline ? const Duration(days: 365) : const Duration(hours: 72);
      if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) <
          maxAge) {
        final cachedSongs =
            jsonList.map((j) => MuzoItem.fromJson(Map<String, dynamic>.from(j))).toList();
        // Downloads merged here too: a track downloaded after this snapshot
        // was saved must still show (and play) offline.
        _mergeDownloadedSongs(cachedSongs, artist);
        return cachedSongs;
      }
    }
  } catch (_) {}

  try {
  final apiService = ref.read(muzoApiServiceProvider);

  // Wall-clock budget for the top-up work. Generous on purpose: the page is
  // asked to show 100+ tracks, and the browse path already covers the common
  // case, so this budget is only ever spent on the artists that need topping
  // up. The skeleton shows meanwhile, so the page is never blank.
  final stopwatch = Stopwatch()..start();
  const budget = Duration(seconds: 25);
  bool outOfTime() => stopwatch.elapsed > budget;

  final seen = <String>{};
  final songs = <MuzoItem>[];
  String dedupeKey(MuzoItem song) =>
      (song.videoId ?? '${song.title}|${song.displayArtist}').toLowerCase();
  void addUnique(List<MuzoItem> batch) {
    for (final song in batch) {
      final key = dedupeKey(song);
      if (key.isEmpty || seen.contains(key)) continue;
      if (song.videoId == null && song.title.isEmpty) continue;
      seen.add(key);
      songs.add(song);
    }
  }

  /// Warms the 72h cache as soon as the page already has a usable track list,
  /// so a slow top-up that gets abandoned still leaves the next visit fast.
  Future<void> cacheNow() async {
    // Never poison the cache with an empty list (e.g. an offline visit):
    // an empty write would destroy the last good snapshot.
    if (songs.isEmpty) return;
    try {
      final box = Hive.box('artist_songs_cache');
      await box.put(cacheKey, {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'songs': songs.map((s) => s.toJson()).toList(),
      });
    } catch (_) {}
  }

  final searchQuery = primaryArtistName(artist);

  // Primary: artist browse playlist (~100 tracks).
  // Sauté quand le worker a déjà annoncé son amont mort dans cette session.
  // Lancé SANS être attendu : mesuré, `search(filter: artists)` coûte 3,7 s et
  // l'appel artiste 0,55 s de 500 — payés avant la recherche paginée qui, elle,
  // répond en 1,2 s pour 20 titres. En parallèle, ce chemin mort ne coûte plus
  // rien au premier affichage, et le jour où l'amont repart il arrive à temps
  // pour mener la liste (les titres sont insérés devant).
  Future<List<MuzoItem>> browseTracks() async {
    if (MuzoApiService.artistBrowseEndpointDown) return const <MuzoItem>[];
    try {
      final artistSearch = await apiService.search(searchQuery, filter: 'artists');
      final results = _prioritizeWestern(artistSearch.results);
      if (results.isEmpty) return const <MuzoItem>[];
      final match = results.firstWhere(
        (r) =>
            (r.browseId != null && r.browseId!.isNotEmpty) &&
            r.title.trim().toLowerCase() == searchQuery.trim().toLowerCase(),
        orElse: () => results.firstWhere(
          (r) => r.browseId != null && r.browseId!.isNotEmpty,
          orElse: () => results.first,
        ),
      );
      final browseId = match.browseId;
      if (browseId == null || browseId.isEmpty) return const <MuzoItem>[];
      final details = await apiService.getArtistDetails(browseId);
      final playlistId = details?.playlistId ?? '';
      if (playlistId.isEmpty) return const <MuzoItem>[];
      final playlist = await apiService.getPlaylistDetails(playlistId);
      return playlist?.tracks ?? const <MuzoItem>[];
    } catch (e) {
      debugPrint('Artist playlist path failed for "$artist": $e');
      return const <MuzoItem>[];
    }
  }

  final browseFuture = browseTracks();

  // Supplement / fallback: paged plain search. Only keep songs that are
  // actually by the artist (search is fuzzy and would otherwise mix in
  // unrelated tracks). Matches any individual artist token, not the whole
  // comma-joined string.
  final tokens = _artistTokens(searchQuery);
  String? token;
  var searchStalled = false;
  // The 100+ track goal is carried by [artistSongsTopUpProvider], NOT by this
  // path: here we stop as soon as the page has something real to show. Paging
  // up to 6 times waiting for 100 tracks cost 25 s of skeletons on every cold
  // visit (each page is a 1,5-15 s round trip through the worker, sequential).
  const firstPaintGoal = 25;
  const firstPaintBudget = Duration(seconds: 10);
  try {
    for (var page = 0; page < 3 && songs.length < firstPaintGoal; page++) {
      if (outOfTime() || stopwatch.elapsed > firstPaintBudget) break;
      // Une seule page peut coûter 24 s (2 essais × 12 s dans `search`) : le
      // test `elapsed > firstPaintBudget` ne s'évaluait qu'ENTRE deux appels,
      // donc un worker lent laissait ce futur en `isLoading` pendant plus
      // d'une minute — la page restait sur ses squelettes et se lisait comme
      // « cet artiste n'a aucun titre ». Le budget est maintenant une vraie
      // deadline sur l'appel lui-même.
      final remaining = firstPaintBudget - stopwatch.elapsed;
      final response = await apiService
          .search(searchQuery, filter: 'songs', continuationToken: token)
          .timeout(remaining > Duration.zero
              ? remaining
              : const Duration(milliseconds: 500));
      final batch = _prioritizeWestern(response.results)
          .where((s) {
            final names = (s.artists ?? const <MuzoArtist>[])
                .map((a) => a.name)
                .join(' ')
                .toLowerCase();
            final haystack = '${s.displayArtist} $names'.toLowerCase();
            return tokens.any(haystack.contains);
          })
          .toList();
      addUnique(batch);
      token = response.continuationToken;
      if (token == null || token.isEmpty) break;
      if (response.results.isEmpty) break;
    }
  } catch (e) {
    if (e.toString().contains('TimeoutException')) searchStalled = true;
    debugPrint('Artist paged search failed for "$artist": $e');
  }

  // Discographie Deezer lancée EN PARALLÈLE du browse, et plus seulement quand
  // la page est nue. Mesuré sur l'appareil (2026-10-15, « Fally Ipupa ») : le
  // browse rend 20 titres en 22 s, puis le top-up passe ~100 s à les compléter
  // UN PAR UN à travers un worker qui timeout — la page reste à 20 sons pendant
  // deux minutes alors que Deezer a déjà les 164 titres du même artiste en ~11 s
  // (« Tiakola -> 90 titles »). On les prend donc dès que la liste est sous la
  // cible, sans attendre le worker.
  final deezerFill = ref
      .read(deezerApiServiceProvider)
      .tracksForArtist(searchQuery)
      .timeout(const Duration(seconds: 15))
      .catchError((Object _) => const <MuzoItem>[]);

  // La page a déjà sa liste : le playlist-browse ne peut plus que l'enrichir,
  // et ses titres passent devant (ce sont les « top songs » de l'artiste).
  // Borné quand même : un futur gelé ici (canal méthode ou amont sans
  // réponse) laissait le provider en `isLoading` éternel et la page sur ses
  // squelettes — mesuré le 2026-10-13 : zéro `painted` en log pour toutes
  // les pages ouvertes, alors que chaque requête répondait en 1-2 s.
  // Les 20 s complètes ne sont accordées que si RIEN d'autre n'a abouti :
  // sinon ce chemin ne ferait que repousser un premier affichage déjà prêt.
  // 12 s quand la page est encore nue : au-delà, le plancher Deezer est prêt
  // et plus fourni que ce que le browse rendra.
  final browseWait = songs.isEmpty
      ? const Duration(seconds: 12)
      : const Duration(seconds: 15) - stopwatch.elapsed;
  final browse = await browseFuture.timeout(
      browseWait > const Duration(milliseconds: 300)
          ? browseWait
          : const Duration(milliseconds: 300),
      onTimeout: () => const <MuzoItem>[]);
  if (browse.isNotEmpty) {
    final head = <MuzoItem>[];
    for (final song in browse) {
      final key = dedupeKey(song);
      if (key.isEmpty || !seen.add(key)) continue;
      if (song.videoId == null && song.title.isEmpty) continue;
      head.add(song);
    }
    songs.insertAll(0, head);
  }

  // ─── Catalogue Deezer : la discographie réelle de l'artiste ───
  // Le worker YouTube peut tout rater (amont mort, quota, artiste non indexé)
  // alors que l'artiste a une vraie discographie. Ces lignes portent un id
  // `dz_` : la page les affiche et le lecteur les résout par titre, avec
  // l'extrait Deezer en dernier recours — jamais une ligne morte, et jamais un
  // artiste qui s'ouvre sans titres, téléchargé ou non.
  final deezerSeeds = await deezerFill;

  // Last resort: never return an empty page. A plain (unfiltered) search for
  // the artist name gives the page real content even when the artist is not
  // indexed as a browsable artist. Sauté dès que Deezer a de quoi remplir :
  // cet appel coûte 12 s de plus et, mesuré, il timeout comme les autres.
  if (songs.isEmpty && deezerSeeds.isEmpty) {
    try {
      final response = await apiService
          .search(searchQuery, filter: 'songs')
          .timeout(const Duration(seconds: 12));
      addUnique(_prioritizeWestern(response.results));
    } catch (e) {
      debugPrint('Artist fallback search failed for "$artist": $e');
    }
  }

  // Complément jusqu'à la cible : les titres YouTube déjà trouvés passent
  // devant, la discographie Deezer suit. Sans ça la page s'arrête à ce que le
  // browse veut bien rendre (20 titres) et met deux minutes à grandir.
  if (songs.length < kMinArtistTracks && deezerSeeds.isNotEmpty) {
    final before = songs.length;
    addUnique(deezerSeeds);
    debugPrint('ArtistSongs: "$artist" completed from the Deezer catalogue '
        '$before -> ${songs.length} titles');
  }

  // ─── External API fallbacks — top up to the 100-track goal ───
  // Seulement quand RIEN n'a été trouvé : dès qu'une liste tient, elle part au
  // page et c'est [artistSongsTopUpProvider] qui découvre la suite (Deezer +
  // iTunes) PENDANT que la page est déjà lisible. Faire ce travail ici aussi
  // faisait patienter l'utilisateur 25 secondes devant des squelettes avec un
  // compteur à « 0 chansons » — l'écran avait l'air planté.
  if (songs.isEmpty) {
    await cacheNow();
    final discovered = <String>[];
    // Discover titles from the iTunes catalog (fast, parallel). Resolved to
    // FULL YouTube tracks below (never 30s previews).
    try {
      final itunes = await ItunesApiService()
          .searchSongsFrUs(searchQuery, limit: 200)
          .timeout(const Duration(seconds: 15));
      for (final it in itunes) {
        final key = it.title.toLowerCase();
        if (!seen.contains(key) && it.title.isNotEmpty) {
          discovered.add('${it.title} ${primaryArtistName(it.displayArtist)}');
          seen.add(key);
        }
      }
    } catch (e) {
      debugPrint('Artist iTunes discovery failed for "$artist": $e');
    }
    // Resolve discovered titles → full YouTube tracks in parallel batches.
    // Bounded on purpose: each resolution is a network round trip through the
    // worker, and a batch that hangs would freeze the whole page. Three
    // batches of 12 is the most we spend on a top-up.
    if (discovered.isNotEmpty && !outOfTime()) {
      final pending = discovered.take(24).toList();
      for (var start = 0; start < pending.length; start += 12) {
        if (outOfTime() || songs.length >= kMinArtistTracks) break;
        final chunk = pending.skip(start).take(12).toList();
        // Each search writes its own rows in as it lands, so the deadline
        // below abandons the stragglers without throwing away what already
        // arrived. `Future.wait` used to be awaited with no deadline at all:
        // one stalled worker call parked the whole artist page on skeletons.
        final batchFutures = <Future<void>>[];
        for (final q in chunk) {
          batchFutures.add(
            apiService
                .search(q, filter: 'songs')
                .then((r) => addUnique(r.results.take(2).toList()))
                .catchError((_) {}),
          );
        }
        try {
          await Future.wait(batchFutures)
              .timeout(const Duration(seconds: 15), onTimeout: () => []);
        } catch (e) {
          debugPrint('Artist ytify resolve failed for "$artist": $e');
        }
      }
    }
  }

  // ─── Offline backbone: downloaded tracks by this artist are always
  // merged in, so the page lists (and plays) them with or without network
  // or cache.
  _mergeDownloadedSongs(songs, artist);

  // ─── Save to 72h cache ───
  if (songs.isNotEmpty) {
    try {
      final box = Hive.box('artist_songs_cache');
      await box.put(cacheKey, {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'songs': songs.map((s) => s.toJson()).toList(),
      });
    } catch (_) {}
  }

  // ─── Never an empty page ───
  // Network and cache both came up short: fall back to everything this artist
  // already has on the device (downloads, favourites, playlists, history).
  // Deliberately AFTER the cache write, so local titles are never persisted
  // as if they were a fetched catalogue.
  if (songs.isEmpty) {
    songs.addAll(
        localLibraryForArtist(ref.read(storageServiceProvider), artist));
  }

  // Une page artiste vide doit dire POURQUOI : sans cette ligne on ne peut pas
  // distinguer « worker mort », « recherche hors délai » et « artiste absent ».
  final whyEmpty = songs.isEmpty
      ? ' — VIDE: browse=${browse.length}, recherche paginée '
          '${searchStalled ? 'hors délai' : 'sans résultat'}, worker artiste '
          '${MuzoApiService.artistBrowseEndpointDown ? 'mort' : 'vivant'}'
      : '';
  debugPrint(
    'ArtistSongs: "$artist" painted ${songs.length} tracks in '
    '${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s$whyEmpty',
  );
  return songs;
  } catch (e) {
    debugPrint('artistSongsProvider crashed for "$artist": $e');
    return <MuzoItem>[];
  }
});

/// Phase 2 of the artist page: grow the track list to the 100+ goal.
///
/// [artistSongsProvider] tops out around 40-60 tracks because the YouTube
/// backend answers ~40 results per query and then stops handing out
/// continuation tokens. This provider waits for that first list, then
/// discovers the artist's real titles (Deezer discography + iTunes catalogue)
/// and resolves them to full YouTube tracks in wide parallel batches, and
/// returns only the extras. The page renders the core list immediately and
/// grows as this future completes.
///
/// Writes the merged snapshot back to the same 72h cache key, so the next
/// visit gets the full list from [artistSongsProvider] and this returns [].
final artistSongsTopUpProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artist) async {
  final core = await ref.watch(artistSongsProvider(artist).future);
  if (core.length >= kMinArtistTracks) return const <MuzoItem>[];

  var offline = false;
  try {
    final conn = await safeConnectivity();
    offline = !conn.contains(ConnectivityResult.mobile) &&
        !conn.contains(ConnectivityResult.wifi) &&
        !conn.contains(ConnectivityResult.ethernet) &&
        !conn.contains(ConnectivityResult.vpn);
  } catch (_) {}
  if (offline) return const <MuzoItem>[];

  final name = primaryArtistName(artist);
  final tokens = _artistTokens(name);
  final seenIds = <String>{
    for (final c in core) (c.videoId ?? '').toLowerCase(),
  }..remove('');
  final seenTitles = <String>{
    for (final c in core) c.title.toLowerCase().trim(),
  }..remove('');
  final discovered = <String>[];
  void addTitle(String title, String artistLabel) {
    // "(Remix)", "[Live]" suffixes only pollute the lookup query.
    final clean = title.split(' (').first.split(' [').first.trim();
    if (clean.isEmpty) return;
    final key = clean.toLowerCase();
    if (!seenTitles.add(key)) return;
    final q = artistLabel.trim();
    discovered.add(q.isEmpty ? '$clean $name' : '$clean $q');
  }

  // Deezer first: it is the artist's own discography, so every title is real.
  // Borné + capté : ces découvertes ne doivent JAMAIS empêcher ce futur de se
  // résoudre, sinon les extras n'arrivent jamais et le compteur de titres
  // reste figé sous les 100.
  final seeds = await ref
      .read(deezerApiServiceProvider)
      .tracksForArtist(name)
      .timeout(const Duration(seconds: 15), onTimeout: () => const [])
      .catchError((_) => <MuzoItem>[]);

  final extras = <MuzoItem>[];

  // Complément IMMÉDIAT depuis la discographie Deezer, avant toute résolution
  // YouTube. Le worker rend ~2 titres par requête et rate souvent l'artiste :
  // mesuré sur l'appareil (2026-10-15) « core=20 +extras=80 » après ~105 s,
  // alors que Deezer avait déjà 164 titres du même artiste en main. Ces seeds
  // portent un id `dz_` : la lecture les résout par titre et retombe sur
  // l'extrait Deezer, donc jamais une ligne muette — et la cible de 100 est
  // atteinte en une fois au lieu de deux minutes.
  if (core.length + extras.length < kMinArtistTracks && seeds.isNotEmpty) {
    final coreIds = <String>{
      for (final c in core) (c.videoId ?? '').toLowerCase(),
    }..remove('');
    final coreTitles = <String>{
      for (final c in core) c.title.toLowerCase().trim(),
    }..remove('');
    for (final s in seeds) {
      if (core.length + extras.length >= kMinArtistTracks) break;
      final id = (s.videoId ?? '').toLowerCase();
      final title = s.title.toLowerCase().trim();
      if (id.isEmpty || title.isEmpty) continue;
      if (coreIds.contains(id) || coreTitles.contains(title)) continue;
      coreTitles.add(title);
      extras.add(s);
    }
  }

  // La découverte YouTube ne sert plus qu'à combler un Deezer insuffisant.
  if (core.length + extras.length < kMinArtistTracks) {
    for (final s in seeds) {
      addTitle(s.title, primaryArtistName(s.displayArtist));
    }
    try {
      final itunes = await ItunesApiService()
          .searchSongsFrUs(name, limit: 200)
          .timeout(const Duration(seconds: 15));
      for (final it in itunes) {
        addTitle(it.title, primaryArtistName(it.displayArtist));
      }
    } catch (e) {
      debugPrint('Artist top-up iTunes discovery failed for "$artist": $e');
    }
  }

  final apiService = ref.read(muzoApiServiceProvider);
  final stopwatch = Stopwatch()..start();
  // Generous: this runs behind an already-rendered page, and the user asked
  // for 100+ titles. Two usable tracks land per lookup, so ~30-40 lookups
  // are enough — the budget only matters on a slow network.
  const budget = Duration(seconds: 100);
  final pending = discovered.take(80).toList();
  for (var start = 0; start < pending.length; start += 12) {
    if (stopwatch.elapsed > budget) break;
    if (core.length + extras.length >= kMinArtistTracks) break;
    final chunk = pending.skip(start).take(12).toList();
    final futures = chunk
        .map((q) => apiService
            .search(q, filter: 'songs')
            .then((r) => r.results)
            .catchError((_) => <MuzoItem>[]))
        .toList();
    List<List<MuzoItem>> batchResults;
    try {
      batchResults = await Future.wait(futures)
          .timeout(const Duration(seconds: 25), onTimeout: () => const []);
    } catch (e) {
      debugPrint('Artist top-up resolve failed for "$artist": $e');
      continue;
    }
    for (final batch in batchResults) {
      for (final s in batch.take(2)) {
        if (s.videoId == null || s.videoId!.isEmpty) continue;
        if (seenIds.contains(s.videoId!.toLowerCase())) continue;
        final names = (s.artists ?? const <MuzoArtist>[])
            .map((a) => a.name)
            .join(' ')
            .toLowerCase();
        final haystack = '${s.displayArtist} $names'.toLowerCase();
        if (!tokens.any(haystack.contains)) continue;
        seenIds.add(s.videoId!.toLowerCase());
        seenTitles.add(s.title.toLowerCase().trim());
        extras.add(s);
        if (core.length + extras.length >= kMinArtistTracks) break;
      }
    }
  }

  if (extras.isNotEmpty) {
    try {
      final box = Hive.box('artist_songs_cache');
      await box.put('artist_songs_${artist.trim().toLowerCase()}', {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'songs': [...core, ...extras].map((s) => s.toJson()).toList(),
      });
    } catch (_) {}
  }
  debugPrint(
      'Artist top-up "$artist": core=${core.length} +extras=${extras.length}');
  return extras;
});

/// Every song already on this device performed by [artist] — downloads,
/// favourites, playlist songs and history, fuzzy-matched on the artist
/// tokens. Last resort for pages that would otherwise open empty: an artist
/// the user already owns music from must always show it, online or not.
List<MuzoItem> localLibraryForArtist(StorageService storage, String artist) {
  final tokens = _artistTokens(primaryArtistName(artist));
  if (tokens.isEmpty) return const <MuzoItem>[];
  final out = <MuzoItem>[];
  final seen = <String>{};

  void consider(MuzoItem item) {
    final names =
        (item.artists ?? const <MuzoArtist>[]).map((a) => a.name).join(' ');
    final haystack = '${item.displayArtist} $names'.toLowerCase();
    if (!tokens.any(haystack.contains)) return;
    final key =
        (item.videoId ?? '${item.title}|${item.displayArtist}').toLowerCase();
    if (key.isEmpty || !seen.add(key)) return;
    out.add(item);
  }

  for (final d in storage.getDownloads()) {
    try {
      consider(MuzoItem.fromJson(Map<String, dynamic>.from(d['result'])));
    } catch (_) {}
  }
  for (final f in storage.getFavorites()) {
    consider(f);
  }
  for (final h in storage.getHistory()) {
    consider(h);
  }
  for (final p in storage.playlistsListenable.value) {
    for (final s in p.songs) {
      consider(s);
    }
  }
  return out;
}

/// Related artists for the artist page's "Fans also like" row: the backend
/// artist search for the same query, minus the artist himself.
final relatedArtistsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artist) async {
  final q = primaryArtistName(artist);
  if (q.trim().isEmpty) return [];
  return ContentCacheService.shelfCached('artrel|$artist', () async {
    final apiService = ref.read(muzoApiServiceProvider);
    try {
      final response = await apiService.search(q, filter: 'artists');
      final self = q.trim().toLowerCase();
      return response.results
          .where((r) => r.title.trim().toLowerCase() != self)
          .toList();
    } catch (e) {
      debugPrint('Related artists failed for "$artist": $e');
      return <MuzoItem>[];
    }
  });
});

/// Albums of the searched artist for the "Albums" chip: query the backend
/// with "[artist] album" and keep only real album entities.
final artistAlbumsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artistName) async {
  if (artistName.trim().isEmpty) return const <MuzoItem>[];
  return ContentCacheService.shelfCached('artalb|$artistName', () async {
    final api = ref.read(muzoApiServiceProvider);
    // Le worker ne renvoie des browseId (MPREb_…) que lorsqu'on lui demande
    // explicitement un type : sans filtre il ne répond qu'avec des morceaux, et
    // le garde-fou _isEntityOfType rejetait alors toute la page → chip vide.
    for (final q in [artistName, '$artistName album']) {
      try {
        final res = await api.search(q, filter: 'albums');
        // The worker tags loosely, so a type is also inferred from the query it
        // answered. Items are re-stamped with the type the chip asked for:
        // without it the search screen type gate rejects them and the chip looks
        // like a no-op.
        final albums = res.results
            .where((i) => _isEntityOfType(i, 'album'))
            .take(30)
            .map((i) => i.copyWith(resultType: 'album'))
            .toList();
        if (albums.isNotEmpty) return albums;
      } catch (e) {
        debugPrint('artistAlbumsProvider failed for "$q": $e');
      }
    }
    return const <MuzoItem>[];
  });
});

/// Playlists of the searched artist for the "Playlists" chip: the backend
/// "playlists" filter returns real playlist entities (VLPL…), which the
/// unfiltered endpoint never does.
final artistPlaylistsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, artistName) async {
  if (artistName.trim().isEmpty) return const <MuzoItem>[];
  return ContentCacheService.shelfCached('artpl|$artistName', () async {
    final api = ref.read(muzoApiServiceProvider);
    for (final q in [artistName, '$artistName playlist']) {
      try {
        final res = await api.search(q, filter: 'playlists');
        final playlists = res.results
            .where((i) => _isEntityOfType(i, 'playlist'))
            .take(30)
            .map((i) => i.copyWith(resultType: 'playlist'))
            .toList();
        if (playlists.isNotEmpty) return playlists;
      } catch (e) {
        debugPrint('artistPlaylistsProvider failed for "$q": $e');
      }
    }
    return const <MuzoItem>[];
  });
});

/// True when [item] is a browse entity (album / playlist / artist) that the
/// search worker either typed correctly or left untagged. Untagged entities
/// are accepted because the backend only sets a type on some of them.
bool _isEntityOfType(MuzoItem item, String type) {
  final browseId = item.browseId;
  if (browseId == null || browseId.isEmpty) return false;
  // An entity is never a playable track.
  if (item.videoId != null && item.videoId!.isNotEmpty) return false;
  final declared = item.resultType;
  if (declared == type) return true;
  if (declared.isNotEmpty) return false;
  // Untyped: only accept it as this entity type when the browseId prefix says
  // so (MPREb_ = album, PL/VL/OL/RD = playlist, UC = artist/channel). This
  // stops a loose song/channel row from being re-labelled as an album etc.
  return _browseIdMatchesType(browseId, type);
}

bool _browseIdMatchesType(String browseId, String type) {
  switch (type) {
    case 'album':
      return browseId.startsWith('MPREb_');
    case 'playlist':
      return browseId.startsWith('PL') ||
          browseId.startsWith('VL') ||
          browseId.startsWith('OL') ||
          browseId.startsWith('RD');
    case 'artist':
    case 'channel':
      return browseId.startsWith('UC');
    default:
      return false;
  }
}

/// The worker sometimes answers an entity filter with rows tagged as songs.
/// Re-stamping is safe ONLY when the browseId prefix proves the entity kind;
/// anything ambiguous is left untouched so [SearchRelevance.rank] can drop it
/// instead of forcing it into the wrong chip.
List<MuzoItem> _normalizeEntityTypes(List<MuzoItem> items, String filter) {
  const entityFilters = {'albums', 'album', 'playlists', 'playlist', 'artists', 'artist', 'channels'};
  final f = filter.toLowerCase();
  if (!entityFilters.contains(f)) return items;
  final target = switch (f) {
    'albums' || 'album' => 'album',
    'playlists' || 'playlist' => 'playlist',
    _ => 'artist',
  };
  return items.map((item) {
    if (item.resultType == target) return item;
    if (_isEntityOfType(item, target)) return item.copyWith(resultType: target);
    return item;
  }).toList();
}

/// Key for [collectionTracksProvider]: identifies one album or playlist from
/// the search grid precisely enough to fetch its EXACT track list.
typedef CollectionKey = ({
  String title,
  String artist,
  String browseId,
  bool isAlbum,
});

/// Exact track list of a searched album or playlist. Primary path uses the
/// browse id straight into the backend album/playlist endpoints so the page
/// shows the real tracklist. Falls back to an exact-name song search when the
/// browse id is missing or the endpoints fail — never an empty page.
final collectionTracksProvider =
    FutureProvider.family<List<MuzoItem>, CollectionKey>((ref, key) async {
  final cacheKey = 'coll|${key.browseId}|${key.isAlbum}|${key.title}';

  // Nothing on the wire? Fall back to the matching songs already on the
  // device so an album/playlist the user owns never opens empty.
  Future<List<MuzoItem>> localTracks() async {
    final storage = ref.read(storageServiceProvider);
    // 'local:<name>' = a playlist stored on this device: its songs are already
    // in hand, no search required.
    if (key.browseId.startsWith('local:')) {
      final songs = storage.getPlaylistSongs(key.browseId.substring(6));
      if (songs.isNotEmpty) return songs;
    }
    final q = key.title.trim().toLowerCase();
    if (q.isEmpty) return const <MuzoItem>[];
    bool matches(MuzoItem s) {
      final album = s.album?.name ?? '';
      return s.title.toLowerCase().contains(q) ||
          album.toLowerCase().contains(q) ||
          key.artist.isNotEmpty &&
              s.displayArtist.toLowerCase() ==
                  key.artist.trim().toLowerCase();
    }

    final out = <MuzoItem>[];
    for (final d in storage.getDownloads()) {
      try {
        final m = MuzoItem.fromJson(Map<String, dynamic>.from(d['result']));
        if (matches(m)) out.add(m);
      } catch (_) {}
    }
    for (final s in storage.getFavorites()) {
      if (matches(s)) out.add(s);
    }
    for (final p in storage.playlistsListenable.value) {
      for (final s in p.songs) {
        if (matches(s)) out.add(s);
      }
    }
    return _dedupeSongs(out);
  }

  // Offline: replay the exact track list fetched last time, else the local
  // library. The network is never touched, so the page opens instantly.
  if (key.browseId.startsWith('local:') || await ContentCacheService.isOffline()) {
    if (!key.browseId.startsWith('local:')) {
      final stale = await ContentCacheService.instance.readStale(cacheKey,
          maxAge: ContentCacheService.offlineCeiling);
      if (stale != null && stale.isNotEmpty) return stale;
    }
    return await localTracks();
  }

  try {
    final fresh = await _fetchCollectionTracks(ref, key);
    if (fresh.isNotEmpty) {
      unawaited(ContentCacheService.instance.write(cacheKey, fresh));
      return fresh;
    }
  } catch (e) {
    debugPrint('Collection "${key.title}" fetch failed: $e');
  }
  final stale =
      await ContentCacheService.instance.readStale(cacheKey);
  if (stale != null && stale.isNotEmpty) return stale;
  return await localTracks();
});

/// Network half of [collectionTracksProvider]: browse id straight into the
/// album/playlist endpoints, then an exact-name song search as a last resort.
Future<List<MuzoItem>> _fetchCollectionTracks(Ref ref, CollectionKey key) async {
  final apiService = ref.read(muzoApiServiceProvider);
  final id = key.browseId.trim();
  if (id.isNotEmpty && !id.startsWith('local:')) {
    try {
      if (key.isAlbum) {
        final album = await apiService.getAlbumDetails(id);
        if (album != null && album.tracks.isNotEmpty) return album.tracks;
      } else {
        final playlist = await apiService.getPlaylistDetails(id);
        if (playlist != null && playlist.tracks.isNotEmpty) {
          return playlist.tracks;
        }
      }
    } catch (e) {
      debugPrint(
          'Collection "${key.title}" browse fetch failed (${key.isAlbum ? 'album' : 'playlist'}): $e');
    }
  }
  // Fallback: exact-name search keeps the page on-topic.
  final q = '${key.title} ${key.artist}'.trim();
  final response = await apiService.search(q, filter: 'songs');
  return response.results.take(40).toList();
}

/// Identity of an album card: title + lead artist, so the same album served by
/// two catalogues is shown once.
String _albumKey(MuzoItem a) =>
    '${a.title.trim().toLowerCase()}|${a.displayArtist.trim().toLowerCase()}';

/// Best-guess primary artist from a display string like "Ninho, Niska" or
/// "Sécu - Franglish, Ninho" -> the first real artist name.
String primaryArtistName(String input) {
  var name = input.trim();
  if (name.isEmpty) return name;
  // Cut off separators: commas, " & ", " x ", " feat. ", " ft. ", "-"
  name = name.split(RegExp(r'[,]| & | x | feat\.? | ft\.? ')).first.trim();
  // Remove parenthetical suffixes like "(feat. Niska)"
  name = name.replaceAll(RegExp(r'\s*\(feat.*\)\s*'), '').trim();
  return name;
}

/// Individual artist tokens from a name, used for fuzzy matching.
List<String> _artistTokens(String name) {
  final tokens = <String>{};
  final lower = name.trim().toLowerCase();
  if (lower.isNotEmpty) tokens.add(lower);
  final split = lower
      .split(RegExp(r'[,]| & | x | feat\.? | ft\.? '))
      .map((t) => t.trim())
      .where((t) => t.length >= 2);
  tokens.addAll(split);
  return tokens.toList();
}


/// Heuristic: true when a search result is very likely Indian content
/// (Hindi/Tamil/Telugu/etc. film music) so it can be demoted below
/// French / US / Afro / Euro results in "All" searches.
bool _looksIndian(MuzoItem item) {
  final text = [
    item.title,
    item.displayArtist,
    item.channelName ?? '',
  ].join(' ').toLowerCase();

  // Devanagari, Bengali, Gurmukhi, Gujarati, Telugu, Kannada, Malayalam,
  // Tamil and Odia scripts.
  if (RegExp(
    r'[\u0900-\u097F\u0980-\u09FF\u0A00-\u0A7F\u0A80-\u0AFF'
    r'\u0B00-\u0B7F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF'
    r'\u0D00-\u0D7F]',
  ).hasMatch(text)) {
    return true;
  }

  const markers = [
    'bollywood',
    'hindi song',
    'punjabi',
    'tamil song',
    'telugu song',
    'malayalam song',
    'kannada song',
    'bhojpuri',
    't-series',
    'saregama',
    'zee music',
    'sony music india',
    'tips official',
    'speed records',
    'arijit singh',
    'neha kakkar',
    'dhvani bhanushali',
    'jubin nautiyal',
    'atif aslam',
    'sidhu moosewala',
    'yo yo honey singh',
    'diljit dosanjh',
    'karan aujla',
    'shreya ghoshal',
    'lata mangeshkar',
    'kishore kumar',
    'himesh reshammiya',
    'amitabh bachchan',
    'kabhi khushi',
    'devdas',
    'jab harry met sejal',
    'raanjhanaa',
    'dangal',
    'bajrangi',
    'dilwale',
    'ae dil hai mushkil',
    'tamasha',
    '(from "',
  ];
  return markers.any(text.contains);
}

/// Stable partition: non-Indian (French / US / Afro / Euro...) results first,
/// Indian results moved to the end, preserving original order within each
/// group so YouTube's own relevance ranking is untouched.
List<MuzoItem> _prioritizeWestern(List<MuzoItem> results) {
  final preferred = <MuzoItem>[];
  final indian = <MuzoItem>[];
  for (final item in results) {
    (_looksIndian(item) ? indian : preferred).add(item);
  }
  return [...preferred, ...indian];
}

/// Remove duplicate songs (same videoId, or title+artist when videoId is
/// null) so an artist's tracks never appear twice in one result list.
/// Non-song result types (artist / album / playlist / channel) are keyed by
/// their own type so they can never be collapsed against a song that happens
/// to share the same "title|artist" string.
List<MuzoItem> _dedupeSongs(List<MuzoItem> items) {
  final seen = <String>{};
  final out = <MuzoItem>[];
  for (final song in items) {
    final isArtist =
        song.resultType == 'artist' || song.resultType == 'channel';
    final String key;
    if (isArtist) {
      key = '${song.resultType}:${song.title.trim().toLowerCase()}';
    } else {
      key =
          (song.videoId ?? '${song.title}|${song.displayArtist}').toLowerCase();
    }
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    // Same song, second upload. The worker answers one search with re-uploads
    // and speed/version variants that each carry their own videoId, so the key
    // above cannot see them and the list shows the same track twice. Collapse
    // on the normalized title+artist identity, scoped to the result type so an
    // album or playlist can never vanish behind a song of the same name.
    final content = normalizeContentKey(song);
    if (content != null && !seen.add('${song.resultType}:$content')) continue;
    out.add(song);
  }
  return out;
}

/// Interleaves per-artist track streams round-robin while capping how many
/// tracks each artist may contribute. Used by curated sections (Hits Bénin)
/// so the same artist never repeats consecutively nor dominates the list.
List<MuzoItem> _interleaveByArtist(
  List<List<MuzoItem>> bySeed, {
  int maxPerArtist = 1,
  int maxTotal = 24,
}) {
  final out = <MuzoItem>[];
  final seenIds = <String>{};
  final artistCount = <String, int>{};
  var maxDepth = 0;
  for (final tracks in bySeed) {
    if (tracks.length > maxDepth) maxDepth = tracks.length;
  }
  for (var round = 0; round < maxDepth && out.length < maxTotal; round++) {
    for (final tracks in bySeed) {
      if (round >= tracks.length) continue;
      final item = tracks[round];
      final idKey = (item.videoId ?? item.title).toLowerCase();
      if (seenIds.contains(idKey)) continue;
      final artist = item.displayArtist.toLowerCase().trim();
      if ((artistCount[artist] ?? 0) >= maxPerArtist) continue;
      seenIds.add(idKey);
      artistCount[artist] = (artistCount[artist] ?? 0) + 1;
      out.add(item);
      if (out.length >= maxTotal) break;
    }
  }
  return out;
}

/// Real cover image for a Search "Browse All" category. Chains free artwork
/// providers (all keyless) until one returns an image:
/// iTunes -> MusicBrainz + Cover Art Archive -> Wikipedia -> Wikimedia Commons
/// -> Internet Archive -> Openverse -> Google Books -> muzo thumbnail.
/// Returns null only when every source fails -> the UI shows the bundled cover.
final categoryImageProvider =
    FutureProvider.family<String?, String>((ref, query) async {
  if (query.isEmpty) return null;
  final apiService = ref.read(muzoApiServiceProvider);

  final providers = <Future<String?> Function()>[
    () => _iTunesCover(query),
    () => _musicBrainzCover(query),
    () => _wikipediaCover(query),
    () => _commonsCover(query),
    () => _archiveCover(query),
    () => _openverseCover(query),
    () => _booksCover(query),
  ];
  for (final provider in providers) {
    try {
      final url = await provider();
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {}
  }

  // Last resort: muzo search thumbnail (may be a video/album thumb).
  try {
    final response =
        await apiService.search(query, filter: 'songs').timeout(
              const Duration(seconds: 10),
            );
    for (final item in response.results) {
      if (item.thumbnails.isNotEmpty && item.thumbnails.last.url.isNotEmpty) {
        return item.thumbnails.last.url;
      }
    }
  } catch (_) {}

  return null;
});

Future<String?> _iTunesCover(String query) async {
  final uri = Uri.parse('https://itunes.apple.com/search').replace(
    queryParameters: {'term': query, 'entity': 'album', 'limit': '1'},
  );
  final resp = await http.get(uri).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) return null;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final results = data['results'] as List?;
  if (results == null || results.isEmpty) return null;
  final art = (results.first as Map)['artworkUrl100'] as String?;
  if (art == null || art.isEmpty) return null;
  return art.replaceFirst('100x100bb', '300x300bb');
}

/// Fast single-lookup real cover for a Search "Browse All" tile: one iTunes
/// album request (not the 8-source [categoryImageProvider] chain), so the lazy
/// grid can afford to resolve the on-screen tiles. Returns null on any failure
/// or when offline -> the tile falls back to its bundled genre cover.
final categoryTileCoverProvider =
    FutureProvider.family<String?, String>((ref, query) async {
  if (query.isEmpty) return null;
  if (await ContentCacheService.isOffline()) return null;
  try {
    return await _iTunesCover(query);
  } catch (_) {
    return null;
  }
});

Future<String?> _musicBrainzCover(String query) async {
  final mbUri = Uri.parse('https://musicbrainz.org/ws/2/release/').replace(
    queryParameters: {'query': 'release:$query', 'fmt': 'json', 'limit': '1'},
  );
  final mbResp = await http.get(
    mbUri,
    headers: const {'User-Agent': 'Tunefy/3.9.0 (music app)'},
  ).timeout(const Duration(seconds: 8));
  if (mbResp.statusCode != 200) return null;
  final mbData = jsonDecode(mbResp.body) as Map<String, dynamic>;
  final releases = mbData['releases'] as List?;
  if (releases == null || releases.isEmpty) return null;
  final releaseId = (releases.first as Map)['id'] as String?;
  if (releaseId == null || releaseId.isEmpty) return null;
  final caResp = await http.head(
    Uri.parse('https://coverartarchive.org/release/$releaseId/front-500'),
  ).timeout(const Duration(seconds: 8));
  if (caResp.statusCode != 200) return null;
  return 'https://coverartarchive.org/release/$releaseId/front-500';
}

Future<String?> _wikipediaCover(String query) async {
  final uri = Uri.parse('https://en.wikipedia.org/w/api.php').replace(
    queryParameters: {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': query,
      'gsrnamespace': '0',
      'gsrlimit': '3',
      'prop': 'pageimages',
      'piprop': 'thumbnail',
      'pithumbsize': '300',
      'format': 'json',
    },
  );
  final resp = await http.get(
    uri,
    headers: const {'User-Agent': 'Tunefy/3.9.0 (music app)'},
  ).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) return null;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final pages = data['query']?['pages'];
  if (pages is! Map) return null;
  for (final page in pages.values) {
    final thumb = (page as Map)['thumbnail']?['source'] as String?;
    if (thumb != null && thumb.isNotEmpty) return thumb;
  }
  return null;
}

Future<String?> _commonsCover(String query) async {
  final uri = Uri.parse('https://commons.wikimedia.org/w/api.php').replace(
    queryParameters: {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': '$query music cover',
      'gsrnamespace': '6',
      'gsrlimit': '3',
      'prop': 'imageinfo',
      'iiprop': 'url',
      'iiurlwidth': '300',
      'format': 'json',
    },
  );
  final resp = await http.get(
    uri,
    headers: const {'User-Agent': 'Tunefy/3.9.0 (music app)'},
  ).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) return null;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final pages = data['query']?['pages'];
  if (pages is! Map) return null;
  for (final page in pages.values) {
    final imageinfo = (page as Map)['imageinfo'];
    if (imageinfo is List && imageinfo.isNotEmpty) {
      final thumb = (imageinfo.first as Map)['thumburl'] as String?;
      if (thumb != null && thumb.isNotEmpty) return thumb;
    }
  }
  return null;
}

Future<String?> _archiveCover(String query) async {
  final uri = Uri.parse('https://archive.org/advancedsearch.php').replace(
    queryParameters: {
      'q': '$query AND mediatype:audio',
      'fl[]': 'identifier',
      'rows': '1',
      'output': 'json',
    },
  );
  final resp = await http.get(uri).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) return null;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final docs = data['response']?['docs'] as List?;
  if (docs == null || docs.isEmpty) return null;
  final id = (docs.first as Map)['identifier'] as String?;
  if (id == null || id.isEmpty) return null;
  return 'https://archive.org/services/img/$id';
}

Future<String?> _openverseCover(String query) async {
  final uri = Uri.parse('https://api.openverse.org/v1/images/').replace(
    queryParameters: {'q': query, 'per_page': '1'},
  );
  final resp = await http.get(
    uri,
    headers: const {'User-Agent': 'Tunefy/3.9.0 (music app)'},
  ).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) return null;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final results = data['results'] as List?;
  if (results == null || results.isEmpty) return null;
  final url = (results.first as Map)['url'] as String?;
  if (url == null || url.isEmpty) return null;
  return url;
}

Future<String?> _booksCover(String query) async {
  final uri = Uri.parse('https://www.googleapis.com/books/v1/volumes').replace(
    queryParameters: {'q': '$query music', 'maxResults': '1'},
  );
  final resp = await http.get(uri).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) return null;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final items = data['items'] as List?;
  if (items == null || items.isEmpty) return null;
  final links = (items.first as Map)['volumeInfo']?['imageLinks'] as Map?;
  final thumb = links?['thumbnail'] as String?;
  if (thumb == null || thumb.isEmpty) return null;
  return thumb.replaceFirst('zoom=1', 'zoom=0');
}

