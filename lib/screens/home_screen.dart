import 'package:muzo/screens/spotify_search_screen.dart';
import 'package:muzo/widgets/fade_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:muzo/providers/navigation_provider.dart';
import 'package:muzo/providers/content_identity.dart';
import 'package:muzo/screens/spotify_library_screen.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/screens/album_screen.dart';
import 'package:muzo/widgets/artist_avatar.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/quick_picks_section.dart';
import 'package:muzo/widgets/skeleton_loader.dart';
import 'package:muzo/widgets/main_layout.dart' show kBottomChromeHeight;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/update_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/providers/home_charts_provider.dart';
import 'package:muzo/providers/genre_chart_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/screens/settings_screen.dart';
import 'package:muzo/services/curated_artists_service.dart';
import 'package:muzo/services/trending_service.dart';
import 'package:muzo/services/itunes_api_service.dart';
import 'package:muzo/data/curated_new_releases_2026.dart';
import 'package:muzo/providers/search_provider.dart';

import 'package:muzo/screens/playlist_screen.dart';
import 'package:muzo/screens/dj_screen.dart';
import 'package:muzo/screens/discovery_screen.dart';
import 'package:muzo/providers/discovery_provider.dart';
import 'package:muzo/services/discovery_service.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/mix_providers.dart';
import 'package:muzo/services/navigator_key.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/taste_signals_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/services/stream_prewarmer.dart';
import 'dart:math';
import 'dart:async';
import 'package:muzo/utils/shelf_claim.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SHELF DEDUP lives in utils/shelf_claim.dart: a tile never appears twice
// inside its own row, and an artist never appears twice across the page — each
// row claims what it displays in [shownArtistsProvider] and the rows below take
// their next candidates. Pull-to-refresh empties the pool for a new page.
// ═══════════════════════════════════════════════════════════════════════════════

/// Compilation / karaoke / "playlist-as-album" junk that genre search and
/// storefront RSS sometimes return instead of a real release.
bool _looksLikeJunkRelease(MuzoItem item) {
  final t = item.title.toLowerCase();
  final artist = item.displayArtist.toLowerCase();
  const junk = <String>[
    'playlist',
    'best of',
    'greatest hits',
    'now that\'s what i call',
    'now thats what i call',
    'top 50',
    'top 40',
    'top 100',
    'karaoke',
    'tribute',
    'cover songs',
    'instrumental',
    'lo-fi beats',
    'study music',
    'relaxing',
    'meditation',
    'workout motivation',
    'tiktok hits',
    'viral hits',
    'mega mix',
    'non-stop',
    'anthology',
    'rhythms from',
    'tribal music',
  ];
  for (final j in junk) {
    if (t.contains(j)) return true;
  }
  // Deezer single-track "albums" (nb_tracks == 1), type=single / record_type
  // single are not real albums — drop them from the albums shelf.
  final meta = item.metadata;
  if (meta != null) {
    final nb = meta['nb_tracks'];
    if (nb is int && nb <= 1) return true;
    final type = (meta['album_type'] ?? meta['record_type'] ?? meta['type'])
        ?.toString()
        .toLowerCase();
    if (type == 'single') return true;
  }
  if (artist.isEmpty || artist == 'unknown') {
    if (t.contains('rhythms from') || t.contains('tribal music')) return true;
  }
  return false;
}

/// "New" for the song shelf: a real release date inside the last [days] days,
/// plus the 7-day pre-release horizon (a Friday drop can already be dated).
///
/// Used at BUILD time and again on every READ of the cached shelf. Reading is
/// the part that matters: `ContentCacheService` replays a shelf snapshot for up
/// to `offlineCeiling` (365 days) when the device has no usable link, and the
/// phone spends most sessions offline. Without the read-time cut a row titled
/// "Nouvelles sorties" keeps serving whatever it last managed to build —
/// months-old songs still labelled brand new.
bool datedWithinReleaseWindow(MuzoItem item, {int days = 7}) {
  final rel = item.releaseDate;
  if (rel == null) return false;
  final now = DateTime.now();
  return !rel.isBefore(now.subtract(Duration(days: days))) &&
      !rel.isAfter(now.add(const Duration(days: 7)));
}

/// Same rule for the albums shelf, on the 30-day window the user asked for.
bool _isFreshAlbum(MuzoItem item) =>
    datedWithinReleaseWindow(item, days: 30);

/// Same dedup for name+image tuples (favorite-artist cards).
List<(String, String?)> claimFreshNames(
    Set<String> seen, List<(String, String?)> items) {
  final fresh = <(String, String?)>[];
  for (final (name, img) in items) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    fresh.add((name, img));
  }
  return fresh;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH-BASED HOME SECTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Approximate age in days of a song for "recent first" ordering. Uses a real
/// releaseDate when available, otherwise falls back to the relative `uploaded`
/// label from the search worker ("2 days/weeks/months/years ago"). Unknown
/// recency returns a mid value so it is kept (never empties a section) but
/// sorted below known-fresh songs.
int _songAgeDays(MuzoItem item) {
  final rd = item.releaseDate;
  if (rd != null) {
    return DateTime.now().difference(rd).inDays;
  }
  final up = (item.uploaded ?? '').toLowerCase();
  final n = int.tryParse(up.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  if (up.contains('year')) return n * 365;
  if (up.contains('month')) return n * 30;
  if (up.contains('week')) return n * 7;
  if (up.contains('day')) return n;
  return 9999; // unknown — kept, but below any song whose recency is known
}

final homeSearchProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
  return ContentCacheService.shelfCached('shelf|search|$query', () async {
  final api = ref.read(muzoApiServiceProvider);
  try {
    // One search answers with a handful of songs, so a single call could never
    // fill a 100-track shelf. Several phrasings of the same intent widen the
    // net; duplicates are dropped below.
    const variants = ['', ' 2026', ' hits', ' mix'];
    final collected = <MuzoItem>[];
    final seen = <String>{};
    for (final suffix in variants) {
      try {
        final res = await api.search('$query$suffix', filter: 'songs');
        for (final r in res.results) {
          final id = r.videoId;
          if (id == null || id.isEmpty || !seen.add(id)) continue;
          collected.add(r);
        }
        if (collected.length >= 100) break;
      } catch (_) {
        // One phrasing failing must not empty the shelf.
      }
    }
    final items = collected;
    // Re-order so fresh tracks (2026 → 2025) surface first in the rap/mix
    // sections, instead of always showing stale 2024/2025 hits. Songs whose
    // recency is unknown stay in place so a section never turns empty.
    items.sort((a, b) {
      final da = _songAgeDays(a);
      final db = _songAgeDays(b);
      if (da == db) return 0;
      if (da >= 9999 && db >= 9999) return 0;
      if (da >= 9999) return 1;
      if (db >= 9999) return -1;
      return da.compareTo(db);
    });
    return items.take(100).toList();
  } catch (_) {
    return <MuzoItem>[];
  }
  });
});

/// "Popular Songs {year}" — the REAL current hits of this year, straight from
/// Apple's public storefront RSS charts (no key, no quota). A plain text search
/// ("top songs 2026") is answered by the YouTube API with anything that merely
/// matches the phrase, which is why this shelf used to look random; chart feeds
/// are the authoritative source instead. Entries whose release year is known
/// must fall in the current year; undated chart rows are kept as a floor so the
/// shelf never empties when RSS omits `im:releaseDate`.
final homePopularSongsProvider =
    FutureProvider.family<List<MuzoItem>, int>((ref, year) async {
  return ContentCacheService.shelfCached('shelf|popular|$year', () async {
    final stores = await Future.wait([
      TrendingService.topSongs('fr'),
      TrendingService.topSongs('us'),
      TrendingService.topSongs('gb'),
    ]);
    final out = <MuzoItem>[];
    final seen = <String>{};
    // Round-robin the storefronts so the shelf blends FR/US/UK instead of
    // filling every slot from whichever feed returned first.
    final maxLen = stores.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < maxLen && out.length < 24; i++) {
      for (final list in stores) {
        if (i >= list.length) continue;
        final t = list[i];
        final k = '${t.title}|${t.artist}'.toLowerCase();
        if (t.title.isEmpty || t.artist.isEmpty || !seen.add(k)) continue;
        final rel = t.releaseDate;
        if (rel != null && rel.year != year) continue;
        out.add(MuzoItem(
          title: t.title,
          thumbnails: t.art.isNotEmpty
              ? [MuzoThumbnail(url: t.art, width: 600, height: 600)]
              : const [],
          resultType: 'song',
          isExplicit: false,
          artists: [MuzoArtist(name: t.artist)],
          category: t.genre,
          releaseDate: rel,
          source: 'itunes rss',
          sourceId: k,
          fetchedAt: DateTime.now(),
        ));
        if (out.length >= 24) break;
      }
    }
    // If the strict current-year filter starved the shelf (RSS with few dated
    // entries), backfill with undated chart rows so a real hits shelf shows.
    if (out.length < 8) {
      for (final list in stores) {
        for (final t in list) {
          if (out.length >= 24) break;
          final k = '${t.title}|${t.artist}'.toLowerCase();
          if (t.title.isEmpty || t.artist.isEmpty || !seen.add(k)) continue;
          out.add(MuzoItem(
            title: t.title,
            thumbnails: t.art.isNotEmpty
                ? [MuzoThumbnail(url: t.art, width: 600, height: 600)]
                : const [],
            resultType: 'song',
            isExplicit: false,
            artists: [MuzoArtist(name: t.artist)],
            category: t.genre,
            releaseDate: t.releaseDate,
            source: 'itunes rss',
            sourceId: k,
            fetchedAt: DateTime.now(),
          ));
        }
      }
    }
    return out;
  });
});

/// Real songs of the catalog's real artists for a genre.
///
/// Instead of searching a fake editorial phrase (which the search API
/// answers with approximate matches), this searches each actual artist name
/// from the curated catalog and keeps only results that mention that artist.
/// [offset] rotates which catalog artists a shelf covers so sibling sections
/// show different people; [country] optionally narrows to one country
/// (e.g. FR for "rap français"). Empty when the 72h catalog is not loaded.
///
/// At most one track per artist is picked so a shelf never repeats the same
/// person (the 10 visible cards are 10 different verified artists).
///
/// [genres] is a *list* of catalog genre keys, not one key: the catalog ships
/// broad genres (Afrobeats, Hip-Hop, Pop…) and the shelves used to ask for keys
/// like `fr-rap` that simply do not exist there. A single exact lookup therefore
/// returned nothing and the section silently vanished. Candidates are merged in
/// order, so a shelf keeps working when data is added later without a code
/// change.
final homeCatalogSectionProvider = FutureProvider.family<
    List<MuzoItem>,
    ({List<String> genres, int offset, String? country})>((ref, args) async {
  return ContentCacheService.shelfCached('shelf|catalog|${args.genres.join('+')}|${args.offset}|${args.country}', () async {
  // Namespaced per user: two accounts on one device must not read each other's
  // shelf, and the rotation offset must differ per person.
  final namespace = await ref.watch(userContentNamespaceProvider.future);
  final userSeed = await ref.watch(userDailySeedProvider.future);
  final key = '${args.genres.join('+')}|${args.offset}|${args.country}';
  final namespacedKey = '$namespace|$key';
  // Building this shelf costs ~100 searches (one per artist, to honour "no
  // repeated artist"), and six genre shelves run on the same home page. Paying
  // that on every launch is not acceptable, and an in-memory memo only survives
  // the session — so the result is cached on disk for a day.
  //
  // It is also what stops the shelf from reshuffling under the user: the
  // catalog service notifies on every reload, which used to re-run this whole
  // loop and re-search every artist.
  final cacheKey = 'genre_shelf_$namespacedKey';
  final memo = _homeSectionMemo[namespacedKey];
  if (memo != null) return memo;
  final cached = await ContentCacheService.instance.readIfFresh(
    cacheKey,
    maxAge: ContentCacheService.dailyTtl,
  );
  if (cached != null && cached.isNotEmpty) {
    _homeSectionMemo[namespacedKey] = cached;
    return cached;
  }

  final service = ref.watch(curatedArtistsServiceProvider);
  // Merge every candidate genre, in order, keeping the popularity-first order of
  // each and never repeating an artist across genres.
  final artists = <CuratedArtist>[];
  final seenArtists = <String>{};
  for (final genre in args.genres) {
    for (final a in service.artistsFor(genre)) {
      if (seenArtists.add(a.name.toLowerCase())) artists.add(a);
    }
  }
  // A country filter narrows only when the catalog actually carries one:
  // `country_code` is empty on most rows, and filtering on it would empty the
  // shelf instead of narrowing it.
  final scoped = (args.country != null &&
          artists.any((a) => (a.countryCode ?? '').isNotEmpty))
      ? artists
          .where((a) =>
              (a.countryCode ?? '').toUpperCase() == args.country!.toUpperCase())
          .toList()
      : artists;
  final pool = scoped.isNotEmpty ? scoped : artists;
  if (pool.isEmpty) return const <MuzoItem>[];
  final api = ref.read(muzoApiServiceProvider);
  final items = <MuzoItem>[];
  final seenIds = <String>{};
  const want = 100;
  // One track per artist: a shelf of 100 songs must be 100 different people.
  // Reaching 100 therefore costs ~100 searches, done in bounded parallel chunks
  // so the shelf fills in seconds instead of half a minute. Results are appended
  // in artist order, never in completion order, so the row stays deterministic.
  const chunk = 5;
  final ordered = <CuratedArtist>[
    for (var i = 0; i < pool.length; i++) pool[(args.offset + i + userSeed) % pool.length],
  ];
  for (var start = 0; start < ordered.length && items.length < want; start += chunk) {
    final batch = ordered.skip(start).take(chunk).toList();
    final found = await Future.wait(
      batch.map((artist) async {
        try {
          final res = await api
              .search(artist.name, filter: 'songs')
              .timeout(const Duration(seconds: 8));
          final aLow = artist.name.toLowerCase();
          for (final r in res.results) {
            if (r.videoId == null) continue;
            // Only accept hits that actually belong to this artist.
            if (!r.displayArtist.toLowerCase().contains(aLow)) continue;
            return r;
          }
        } catch (_) {
          // A single dead artist must never empty the shelf.
        }
        return null;
      }),
    );
    for (final r in found) {
      final id = r?.videoId;
      if (r == null || id == null || !seenIds.add(id)) continue;
      items.add(r);
      if (items.length >= want) break;
    }
  }
  items.sort((a, b) => _songAgeDays(a).compareTo(_songAgeDays(b)));
  final result = items.take(want).toList();
  if (result.isNotEmpty) {
    _homeSectionMemo[namespacedKey] = result;
    unawaited(ContentCacheService.instance.write(cacheKey, result));
  }
  return result;
  });
});

/// Session-scoped memo in front of the disk cache: a rebuild must never cost a
/// Hive read, and within one session the shelf is immutable anyway.
final _homeSectionMemo = <String, List<MuzoItem>>{};

/// A home shelf whose content is a REAL genre chart instead of a hand-written
/// artist list.
///
/// These urban shelves used to read the Supabase `artists_*` catalog: ~100 names
/// sorted by follower count, one song searched per name. That is what made them
/// feel fake — the afro table holds 15 hand-typed names (half of them UK drill),
/// the afrobeats table contains Queen, Madonna and Dire Straits, `country_code`
/// is empty on every row so the "US" scoping never applied, and a follower sort
/// buries every act that is not already famous, which is why no woman ever
/// reached the visible cards. A chart answers with whoever is actually playing
/// this genre in this country this week — women included, because they chart.
/// The catalog remains as a last-resort fallback so the shelf never vanishes
/// when both feeds are unreachable.
class _RealGenreSection extends ConsumerWidget {
  final String title;

  /// Any name [TrendingService.genreChartFor] resolves ("rap fr", "afro rap").
  final String genre;

  /// Catalog buckets used when no chart answers at all.
  final List<String> catalogGenres;
  final int offset;

  const _RealGenreSection(
    this.title, {
    required this.genre,
    this.catalogGenres = const [],
    this.offset = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charted =
        ref.watch(genreChartSongsProvider((genre: genre, offset: offset)));
    // Une catégorie en erreur est une catégorie vide : le bucket du catalogue
    // prend le relais, sinon la rangée disparaissait de l'accueil.
    final chartedList = charted.valueOrNull;
    final chartedEmpty = chartedList != null && chartedList.isEmpty;
    final needsCatalog = chartedEmpty || charted.hasError;
    final data = needsCatalog && catalogGenres.isNotEmpty
        ? ref.watch(homeCatalogSectionProvider(
            (genres: catalogGenres, offset: offset, country: null)))
        : charted;
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: title,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => _HomeShelfSkeleton(title),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

final homeSearchArtistsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
  return ContentCacheService.shelfCached('shelf|searchArtists|$query', () async {
  final api = ref.read(muzoApiServiceProvider);
  try {
    final res = await api.search(query, filter: 'all');
    final channels = res.results
        .where((i) => i.resultType == 'channel' || (i.browseId != null && i.browseId!.startsWith('UC')))
        .take(10)
        .toList();
    if (channels.isNotEmpty) return channels;
    final songs = res.results;
    final seen = <String>{};
    final artists = <MuzoItem>[];
    for (final song in songs) {
      final name = song.displayArtist;
      if (name.isEmpty || name == 'Unknown' || seen.contains(name.toLowerCase())) continue;
      seen.add(name.toLowerCase());
      artists.add(MuzoItem(
        title: name,
        thumbnails: song.thumbnails,
        resultType: 'artist',
        browseId: song.browseId,
        isExplicit: false,
      ));
    }
    return artists;
  } catch (_) {
    return <MuzoItem>[];
  }
  });
});

final homeSearchAlbumsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
  return ContentCacheService.shelfCached('shelf|searchAlbums|$query', () async {
  final api = ref.read(muzoApiServiceProvider);
  try {
    final res = await api.search(query, filter: 'all');
    return res.results
        .where((i) => i.resultType == 'album' || i.album != null)
        .take(10)
        .toList();
  } catch (_) {
    return <MuzoItem>[];
  }
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// DEZER BASED SHELVES — recommended + fresh releases, dated against the
// device's clock (DateTime.now) so "aujourd'hui" really means today.
// ═══════════════════════════════════════════════════════════════════════════════

/// "Recommandé pour vous": Deezer tracks matching your recently-played
/// artists, resolved to real playable YouTube songs. Falls back to the
/// top-on-Muzo chart when unused/offline so the shelf never stays empty.
///
/// The set CHANGE EVERY DAY: a deterministic daily seed (grain of the date)
/// rotates the artist order and shuffles the final songs, so each new day
/// leads with different artists and a different order — without making the
/// same "fresh releases" reappear day after day.
final recommendedForYouProvider = FutureProvider<List<MuzoItem>>((ref) async {
  return ContentCacheService.shelfCachedDaily('shelf|recommended', () async {
  final dailySeed = _dailySeed();
  try {
    // Graines personnelles : d'abord ce que l'utilisateur a CHERCHÉ, puis les
    // artistes qu'il joue le plus. Un rayon « Recommandé pour toi » qui
    // n'exploitait que l'historique de lecture ignorait la signal le plus
    // volontaire des deux.
    final seeds = ref
        .read(tasteSignalsProvider)
        .recommendationSeeds(max: 3, seed: dailySeed);

    final dz = ref.read(deezerApiServiceProvider);
    final discovered = <MuzoItem>[];
    for (final term in seeds) {
      // Une recherche Tap long (« nxamndo black cagnott ») est déjà une
      // requête valide : on ne lui accole pas « top hits ».
      final query = term.split(' ').length <= 2
          ? _dailyQuery(term, dailySeed)
          : term;
      final batch = await dz.searchTracks(query, limit: 6);
      discovered.addAll(batch.isEmpty
          ? await dz.searchTracks(term, limit: 6)
          : batch);
      if (discovered.length >= 16) break;
    }
    if (discovered.isNotEmpty) {
      final playable = _streamEnrichBlocked()
          ? discovered
          : await ref
              .read(multiApiServiceProvider)
              .resolveToPlayable(discovered, max: 12);
      var dedup = dedupeMuzoSongs(playable);
      if (dedup.isNotEmpty) {
        // Deterministic daily shuffle so the order (and therefore the first
        // visible tracks) differs from one day to the next.
        dedup = _seededShuffle(dedup, dailySeed);
        return dedup.take(10).toList();
      }
    }
  } catch (_) {}
  // Fallback fiable : charts FR+US (Apple RSS → YouTube) avec de vrais
  // titres/artistes. topOnMuzo (/api/trending) renvoie surtout des playlists
  // sans videoId ni artiste, inutilisables ici.
  final charts = await ref.read(homeChartsProvider.future);
  final fallback =
      _seededShuffle<MuzoItem>(dedupeMuzoSongs(charts.tracks), dailySeed);
  if (fallback.isEmpty) return <MuzoItem>[];
  // Auto-chargement du son sans vider la section : on enrichit les items avec
  // un audioUrl quand c'est possible, mais on garde TOUS les items de toute
  // façon — la lecture retentera la cascade au clic pour ceux sans URL directe.
  final playable = _streamEnrichBlocked()
      ? <MuzoItem>[]
      : await StreamExtractionService.resolvePlayableUrls(
          fallback,
          maxN: 10,
        ).then((r) => r.cast<MuzoItem>());
  final byVideo = <String, MuzoItem>{};
  for (final p in playable) {
    final id = p.videoId ?? p.title;
    if (id.isNotEmpty) byVideo[id] = p;
  }
  final merged = <MuzoItem>[
    for (final i in fallback) byVideo[i.videoId ?? i.title] ?? i,
  ];
  return merged.take(10).toList();
  });
});

/// Stable integer that changes once per day (device clock), used to rotate and
/// shuffle the daily recommendations deterministically.
int _dailySeed() =>
    DateTime.now().toUtc().difference(DateTime.utc(2024, 1, 1)).inDays +
    ContentCacheService.deviceSeed;

/// True when resolving a YouTube stream can never lead to playback: offline
/// mode, or the opt-in "downloaded titles only" rule. A shelf that resolves
/// inline must honour it, otherwise a Home pass spends ~20 s per track walking
/// the dead relay chain and the shelves still loading hit their deadline.
bool _streamEnrichBlocked() {
  final storage = StorageService();
  return storage.offlineMode || storage.playDownloadedOnly;
}

/// Rotates between a few query phrasings based on the day so the same artist's
/// search does not always return the identical top hits.
String _dailyQuery(String artist, int seed) {
  final variants = ['$artist top hits', '$artist best', '$artist popular'];
  return variants[seed % variants.length];
}

/// A deterministic Fisher–Yates shuffle seeded by the daily seed — same day ⇒
/// same order, different day ⇒ different order.
List<T> _seededShuffle<T>(List<T> items, int seed) {
  final copy = List.of(items);
  final rng = Random(seed);
  for (var i = copy.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = copy[i];
    copy[i] = copy[j];
    copy[j] = tmp;
  }
  return copy;
}

/// "Nouveaux albums": fresh albums from the country-scoped, genre-labelled
/// Apple charts (rap FR / rap US / afro — the exact specs the genre rows use,
/// see [TrendingService.genreChartFor]) first, then Deezer's in-genre new
/// releases, then — only when both feeds are thin — the Deezer genre queries
/// and priority artist catalogs. Everything is windowed on a real release date.
final deezerRecentAlbumsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final shelf = await ContentCacheService.shelfCachedDaily(
      'shelf|recentAlbums', () async {
  final deezer = ref.read(deezerApiServiceProvider);
  final catalog = ref.watch(curatedArtistsServiceProvider);

  Future<List<MuzoItem>> safeAlbums(Future<List<MuzoItem>> f) async {
    try {
      return await f.timeout(const Duration(seconds: 12));
    } catch (_) {
      return const <MuzoItem>[];
    }
  }

  const urbanGenreIds = <int>[
    DeezerApiService.genreRapHipHop,
    DeezerApiService.genreRnbSoul,
    DeezerApiService.genreAfricanMusic,
  ];
  // In-genre only: the user asked for rap FR / rap US / afro new albums, and
  // Deezer's worldwide pool is exactly where pop, rock and gospel leaked in
  // from. The per-genre charts (`/chart/{id}/tracks` → their albums) are the
  // one keyless feed that is genuinely genre-accurate.
  final base = await safeAlbums(
      deezer.newAlbumsInGenres(urbanGenreIds, days: 30, limit: 40));

  // Primary source: the same country-scoped, genre-labelled Apple chart pools
  // the rap FR / rap US / afro rows read, windowed on their real release dates.
  final chartAlbums = <MuzoItem>[];
  try {
    chartAlbums.addAll(await ref
        .read(chartNewAlbumsProvider.future)
        .timeout(const Duration(seconds: 30)));
  } catch (_) {}

  // The hand-typed Deezer queries and artist lists below are only a filler:
  // they run when the dated feeds above are thin, never in place of them.
  final needBackfill = base.length + chartAlbums.length < 14;

  const queries = <String>[
    // FR / US rap & urban
    'rap français',
    'rap francais',
    'rap us',
    'hip-hop',
    'drill',
    'trap',
    'R&B',
    // Afrique de l'Ouest / Centre — afro only (the app's target genres)
    'afrobeats',
    'afro rap',
    'amapiano',
    'musique béninoise',
    'nigerian music',
    'ghana music',
    // Artistes phares demandés (Fally, Tiakola…)
    'Fally Ipupa',
    'Tiakola',
    'Inoss’Bhay',
    'Favé',
    'SDM',
    'Werenoi',
    'Olodo',
    'Majeeed',
    'Rema',
    'Burna Boy',
    'Davido',
    'Ayra Starr',
    'Tems',
    'Diamond Platnumz',
  ];
  // Genre search never returns release_date — hydrate the head of each
  // batch via /album/{id} so only truly recent catalog survives.
  final genreAlbums = <MuzoItem>[];
  for (var i = 0; needBackfill && i < queries.length; i += 4) {
    final chunk = queries.skip(i).take(4).toList();
    final batches = await Future.wait(
        chunk.map((q) => safeAlbums(deezer.searchAlbums(q, limit: 6))));
    final flat = <MuzoItem>[];
    for (final b in batches) {
      flat.addAll(b);
    }
    genreAlbums.addAll(await safeAlbums(deezer.hydrateAlbumDates(flat, max: 24)));
  }

  // Priority curated artists → dated catalog via /artist/{id}/albums
  // (the only list endpoint that ships real release_date values).
  const catalogGenres = <String>[
    'fr-rap', 'us-rap', 'afro-rap', 'afrobeats', 'afro-hits',
  ];
  const mustHaveArtists = <String>[
    'Fally Ipupa',
    'Tiakola',
    'Grand Corps Malade',
    'Luther',
    'Zamdane',
    'Seyi Vibez',
    'Rema',
    'Burna Boy',
    'Davido',
    'AZ Chike',
    'Rakim',
    'Inoss’Bhay',
    'Gims',
    'Ninho',
    'Werenoi',
    'Favé',
    'SDM',
    'Ayra Starr',
    'Tems',
    'Diamond Platnumz',
    'Olodo',
    'Majeeed',
    // Week of 18–23/09/2026 (web-verified)
    'Fireboy DML',
    'Blaqbonez',
    'Black Sherif',
    'Phyno',
    'Frenna',
    'Chocolate City',
    'Balloranking',
    'Shoday',
    'MC Solaar',
    'Daguerre',
    'Nao',
    'Dremo',
    'Erigga',
    'Lojay',
    'Victor AD',
    // Bénin (demande utilisateur) — catalogues Deezer datés via
    // /artist/{id}/albums, seule source qui porte de vraies release_date.
    'Fanicko',
    'Crisba',
    'Nikanor',
    'Vano Baby',
    'OPA Officiel',
    'Bobo Wê',
    'Axel Merryl',
    'Manzor',
  ];
  final priorityNames = <String>[...mustHaveArtists];
  for (final g in catalogGenres) {
    for (final a in catalog.artistsFor(g).take(6)) {
      if (a.name.isNotEmpty) priorityNames.add(a.name);
    }
  }
  final artistAlbums = <MuzoItem>[];
  // Headroom for must-have + 8 Benin + week artists + 5 catalog genres
  // (52 used to truncate the list before the genre catalogs were reached).
  final uniqueArtistNames = <String>{...priorityNames}.take(100).toList();
  // Budget borné : sans lui, chaque chunk de 4 qui timeout (10 s pièce)
  // repoussait d'autant les rayons de genre qui tournent en parallèle.
  final backfillClock = Stopwatch()..start();
  for (var i = 0; needBackfill && i < uniqueArtistNames.length; i += 4) {
    if (backfillClock.elapsed > const Duration(seconds: 12)) break;
    final chunk = uniqueArtistNames.skip(i).take(4).toList();
    final batches = await Future.wait(
        chunk.map((name) => safeAlbums(deezer.albumsForArtist(name, limit: 10))));
    for (final b in batches) {
      artistAlbums.addAll(b);
    }
  }

  // The Apple-RSS storefront feed and MusicBrainz release calendar used to
  // fill this shelf. Both are genre-agnostic — they are what put pop, gospel
  // and rock under "Nouveaux albums" — so they are gone: everything here now
  // comes from the rap/R&B/afro genre charts, the genre search terms above and
  // the urban curated catalogs.

  // Prefer dated releases (artist / curated / genre chart) over undated genre
  // noise, then drop playlist-style junk so "Nouveaux albums" stays editorial.
  final merged = <MuzoItem>[];
  final seenAlbums = <String>{};
  void push(MuzoItem a) {
    if (!_isFreshAlbum(a)) return;
    if (_looksLikeJunkRelease(a)) return;
    final k = contentKey(a);
    if (k.isEmpty || seenAlbums.add(k) == false) return;
    merged.add(a);
  }

  // Chart albums lead: the same country-scoped, genre-labelled Apple pools the
  // rap/afro rows read, windowed on their real release dates. This is what
  // replaced hand-typed artist lists as the source of "Nouveaux albums".
  for (final a in chartAlbums) {
    push(a);
  }

  // In-genre chart albums first — genuinely fresh rap/R&B/afro discographies
  // (real release_date from the last 30 days) win the dedupe against the
  // curated copies of the same album, so a playable album card leads.
  for (final a in base) {
    push(a);
  }
  // Curated albums (web-verified dates) — seed first so New Albums is never
  // empty and shows the real 18–23/09 drops even when live feeds are thin.
  for (final c in curatedNewReleases2026) {
    if (c.event != 'album') continue;
    if (!isUrbanOrAfroRelease(c)) continue;
    if (c.title.trim().isEmpty || c.title.trim() == c.artist.trim()) continue;
    if (!curatedIsFresh(c, window: const Duration(days: 30))) continue;
    push(MuzoItem(
      title: c.title,
      thumbnails: const [],
      resultType: 'album',
      isExplicit: false,
      artists: [MuzoArtist(name: c.artist)],
      releaseDate: c.releasedAt,
      source: 'curated',
      sourceId: '${c.artist}|${c.title}',
      fetchedAt: DateTime.now(),
    ));
  }
  // Then priority artist albums (dated catalog from curated lists).
  for (final a in artistAlbums) {
    push(a);
  }
  // Dated genre hits next (undated ones were dropped by the 30-day window).
  for (final a in genreAlbums) {
    push(a);
  }

  // Curated seeds store title/artist/date only (no artwork) — those tiles
  // would render as a bare placeholder. Resolve a real cover for the first
  // artless albums.
  final itunes = ItunesApiService();
  final artless = <int>[];
  for (var i = 0; i < merged.length && artless.length < 16; i++) {
    if (merged[i].thumbnails.isEmpty) artless.add(i);
  }
  for (var c = 0; c < artless.length; c += 4) {
    final chunk = artless.skip(c).take(4).toList();
    final urls = await Future.wait(chunk.map((i) async {
      final item = merged[i];
      final artist =
          item.artists?.isNotEmpty == true ? item.artists!.first.name : '';
      final query = artist.isEmpty ? item.title : '${item.title} $artist';
      try {
        final hits = await itunes
            .searchAlbums(query, limit: 4)
            .timeout(const Duration(seconds: 8));
        // iTunes répond lui aussi « le plus proche », pas « le bon » : la
        // pochette d'un autre album se retrouvait collée sur une vraie sortie,
        // ce qui se lit comme un faux album. Aucune entité vérifiée ⇒ aucune
        // pochette, la tuile garde son emplacement réservé au lieu de mentir.
        for (final h in hits) {
          if (h.thumbnails.isEmpty) continue;
          if (!matchesNamedEntity(h, item.title, artist)) continue;
          return h.thumbnails.first.url;
        }
      } catch (_) {}
      return null;
    }));
    for (var k = 0; k < chunk.length; k++) {
      final url = urls[k];
      if (url == null || url.isEmpty) continue;
      final i = chunk[k];
      merged[i] = merged[i].copyWith(thumbnails: [
        MuzoThumbnail(url: url, width: 600, height: 600),
      ]);
    }
  }
  return merged;
  });
  // Re-cut on read, exactly as the song shelf does: a cached snapshot ages
  // while the device stays offline, and an album can leave the 30-day window
  // long before the shelf is rebuilt.
  final keptAlbums = shelf.where(_isFreshAlbum).toList();
  debugPrint('HomeNewAlbums kept=${keptAlbums.length}/${shelf.length} '
      '(30d window, device clock)');
  return keptAlbums;
});

/// Vraies nouvelles sorties — sons des 7 derniers jours (Deezer dates +
/// albums prioritaires curated + iTunes current tops résolus YouTube).
/// Priorité rap FR/US/afro, hits Bénin, afrobeats, régions AF.
final deezerNewSongsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  return ContentCacheService.shelfCachedDaily('shelf|newSongs', () async {
  final deezer = ref.read(deezerApiServiceProvider);
  final multi = ref.read(multiApiServiceProvider);
  final api = ref.read(muzoApiServiceProvider);
  final catalog = ref.watch(curatedArtistsServiceProvider);

  Future<List<MuzoItem>> safe(Future<List<MuzoItem>> f) async {
    try {
      return await f.timeout(const Duration(seconds: 14));
    } catch (_) {
      return const <MuzoItem>[];
    }
  }

  final seeds = <MuzoItem>[];

  // 1) Lead tracks of the albums that just dropped in rap / R&B / afro.
  // lançée ici, attendue plus bas : en série elle mangeait 26 s du budget
  // global AVANT la moindre recherche YouTube, et le merge de l'accueil
  // (`homeNewReleasesMergedProvider`, 70 s par branche) coupait alors tout →
  // `HomeNewReleases kept=0/0`, le rayon « Nouvelles sorties » vide.
  final genreNewTracksFuture = deezer
      .newTracksInGenres(const <int>[
        DeezerApiService.genreRapHipHop,
        DeezerApiService.genreRnbSoul,
        DeezerApiService.genreAfricanMusic,
      ], days: 7, limit: 30)
      .timeout(const Duration(seconds: 26))
      .catchError((Object _) => const <MuzoItem>[]);
  // 4) Apple current tops FR/US/NG/BJ/CI — eux aussi lancés en parallèle des
  // appels Deezer ci-dessous, et bornés (ils ne l'étaient pas du tout).
  // Chaque storefront est piégé séparément : un flux RSS qui JETTE faisait
  // échouer tout le `Future.wait`, le provider mourait en cours de route et
  // `shelfCached` rendait l'ancien instantané — ou rien du tout (`branche
  // newSongs -> 0 titre(s) en 20014 ms`, mesuré 2026-10-15).
  Future<List<TrendSong>> topsOf(String store) => TrendingService.topSongs(store)
      .catchError((Object e) {
    debugPrint('HomeNewReleases: tops "$store" en erreur: $e');
    return const <TrendSong>[];
  });
  final topStoresFuture = Future.wait([
    topsOf('fr'),
    topsOf('us'),
    topsOf('ng'),
    topsOf('bj'),
    topsOf('ci'),
  ]).timeout(const Duration(seconds: 20),
      onTimeout: () => const <List<TrendSong>>[]);

  // 2) Curated FR / priority releases (editorial list → real titles).
  // Skip placeholders where title == artist (no real song name known yet)
  // and anything older than the 14-day shelf window (auto-expiring list).
  // Albums feed New Albums via deezerRecentAlbumsProvider; singles feed this
  // song shelf. Album entries still seed here only when no live lead track
  // was found (search by album title can resolve the lead single).
  final curatedSeeds = <MuzoItem>[];
  for (final c in curatedNewReleases2026) {
    if (c.title.trim().isEmpty || c.title.trim() == c.artist.trim()) continue;
    if (!isUrbanOrAfroRelease(c)) continue;
    if (!curatedIsFresh(c, window: const Duration(days: 7))) continue;
    curatedSeeds.add(MuzoItem(
      title: c.title,
      thumbnails: const [],
      resultType: 'song',
      isExplicit: false,
      artists: [MuzoArtist(name: c.artist)],
      releaseDate: c.releasedAt,
      source: 'curated',
      sourceId: '${c.artist}|${c.title}',
      fetchedAt: DateTime.now(),
    ));
  }
  seeds.addAll(curatedSeeds);

  // Priority curated artists → recent albums / lead tracks.
  // ALL home genres + heads the user asked for (Fally, Tiakola…).
  const catalogGenres = <String>['fr-rap', 'us-rap', 'afro-rap', 'afrobeats', 'afro-hits'];
  const mustHaveHeads = <String>[
    'Fally Ipupa',
    'Tiakola',
    'Grand Corps Malade',
    'Luther',
    'Zamdane',
    'Seyi Vibez',
    'Rema',
    'Burna Boy',
    'Davido',
    'AZ Chike',
    'Rakim',
    'Inoss’Bhay',
    'Gims',
    'Ninho',
    'Werenoi',
    'Favé',
    'SDM',
    'Ayra Starr',
    'Tems',
    'Olodo',
    'Majeeed',
    'Diamond Platnumz',
    // Week of 18–23/09/2026 (web-verified)
    'Fireboy DML',
    'Blaqbonez',
    'Black Sherif',
    'Phyno',
    'Frenna',
    'Chocolate City',
    'Balloranking',
    'Shoday',
    'MC Solaar',
    'Daguerre',
    'Nao',
  ];
  // Bénin — le suivi live des heads est plafonné à 16 artistes plus bas et le
  // Bénin en était totalement exclu : les sorties béninoises n'arrivaient
  // jamais dans "Nouvelles sorties".
  const beninHeads = <String>[
    'Fanicko',
    'Crisba',
    'Nikanor',
    'Vano Baby',
    'OPA Officiel',
    'Bobo Wê',
    'Axel Merryl',
    'Manzor',
  ];
  // 16 slots : 10 têtes mondiales + 6 têtes Bénin (coût réseau inchangé).
  final priorityArtists = <String>[...mustHaveHeads.take(10), ...beninHeads];
  for (final g in catalogGenres) {
    for (final a in catalog.artistsFor(g).take(4)) {
      if (a.name.isNotEmpty) priorityArtists.add(a.name);
    }
  }
  // MUST match the shelf's own window: `homeNewReleasesMergedProvider` cuts at
  // 7 days, so every lead track collected here on a wider window was fetched,
  // resolved and then thrown away by the merge — Deezer album detail calls that
  // only burned the phone's slow network. /search/album never carries
  // release_date, hence albumsForArtist.
  final cutoffLead = DateTime.now().subtract(const Duration(days: 7));
  final uniquePriority = <String>{...priorityArtists}.take(40).toList();
  // Trois artistes à la fois ET un budget total : les 40 requêtes partaient
  // d'un seul coup (mesuré le 2026-10-16 : ~28 `albumsForArtist` en
  // TimeoutException simultanées dans le même logcat), ce qui saturait l'uplink
  // et affamait les cinq rayons de genre du Home lancés au même instant.
  final leadClock = Stopwatch()..start();
  const leadBudget = Duration(seconds: 12);
  final leadOut = <MuzoItem>[];
  for (var i = 0; i < uniquePriority.length; i += 3) {
    if (leadClock.elapsed > leadBudget) break;
    final chunk = uniquePriority.skip(i).take(3).toList();
    final batches = await Future.wait(chunk.map((name) async {
      final albums = await safe(deezer.albumsForArtist(name, limit: 8));
      final recent = albums.where((a) {
        final rel = a.releaseDate;
        return rel != null && !rel.isBefore(cutoffLead);
      }).take(3);
      final out = <MuzoItem>[];
      for (final alb in recent) {
        final id = alb.sourceId ?? '';
        if (id.isEmpty) continue;
        try {
          final details = await deezer
              .albumDetails(id)
              .timeout(const Duration(seconds: 8));
          if (details == null || details.tracks.isEmpty) continue;
          out.add(details.tracks.first
              .copyWith(releaseDate: alb.releaseDate));
        } catch (_) {}
      }
      return out;
    }));
    for (final b in batches) {
      leadOut.addAll(b);
    }
  }
  seeds.addAll(leadOut);
  // Les pistes des genres venaient ici : collectées en parallèle des artistes
  // prioritaires, leur attente ne coutait plus de secondes au rayon.
  seeds.addAll(await genreNewTracksFuture);

  // 4) Apple current tops FR/US/NG/BJ/CI — real hits, resolved to playable YT.
  final topStores = await topStoresFuture;
  final topSeeds = <MuzoItem>[];
  final topSeen = <String>{};
  void addTop(TrendSong t) {
    final k = '${t.title}|${t.artist}'.toLowerCase();
    if (t.title.isEmpty || topSeen.add(k) == false) return;
    topSeeds.add(MuzoItem(
      title: t.title,
      thumbnails: t.art.isNotEmpty
          ? [MuzoThumbnail(url: t.art, width: 600, height: 600)]
          : const [],
      resultType: 'song',
      isExplicit: false,
      artists: [MuzoArtist(name: t.artist)],
      category: t.genre,
      // Real im:releaseDate — undated chart seeds are always dropped by
      // the shelf's date window, making real new hits invisible.
      releaseDate: t.releaseDate,
      source: 'itunes rss',
      sourceId: k,
      fetchedAt: DateTime.now(),
    ));
  }

  for (final list in topStores) {
    var taken = 0;
    for (final t in list) {
      final before = topSeeds.length;
      addTop(t);
      if (topSeeds.length > before && ++taken >= 4) break;
    }
    if (topSeeds.length >= 16) break;
  }
  // Backfill from the biggest storefront when a feed is empty (Apple has no
  // Benin storefront) so the shelf never ends up short of chart seeds.
  if (topSeeds.length < 16) {
    for (final t in topStores.first) {
      addTop(t);
      if (topSeeds.length >= 16) break;
    }
  }
  seeds.addAll(topSeeds);

  // Priority-score seeds before resolution so YT picks favour rap FR/US/afro.
  // Head artists (Tiakola, Fally…) float to the front even without a genre hit.
  // Curated (web-verified) seeds always resolve FIRST: they are the titles
  // the user actually expects to see, and score-0 pop/rock entries used to
  // fall below the resolution cap and vanish from the shelf.
  final curatedOrdered = curatedSeeds.toList()
    ..sort((a, b) => _newReleasePriority(b).compareTo(_newReleasePriority(a)));
  final restOrdered = [...seeds]..removeWhere(curatedSeeds.contains);
  // Date first, same as the albums shelf: resolveToPlayable only resolves the
  // FIRST 48 entries, so a priority-only order spent every slot on the same
  // curated/head titles and yesterday's drops never made it in — the shelf
  // looked frozen from one refresh to the next. Priority only breaks
  // same-day ties now.
  restOrdered.sort((a, b) {
    final da = a.releaseDate;
    final db = b.releaseDate;
    if (da != null && db != null && !da.isAtSameMomentAs(db)) {
      return db.compareTo(da);
    }
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    final pa = _newReleasePriority(a) + _headArtistBonus(a);
    final pb = _newReleasePriority(b) + _headArtistBonus(b);
    if (pa != pb) return pb.compareTo(pa);
    return 0;
  });
  // Curated (web-verified) titles still resolve first so the user's expected
  // releases never vanish, but capped: fresh Deezer/RSS drops must keep a
  // large share of the 48 resolution slots or the shelf repeats itself.
  final ordered = [
    ...curatedOrdered.take(20),
    ...restOrdered,
    ...curatedOrdered.skip(20),
  ];

  // Resolution is 40+ parallel YT searches — the generic 14s safe() used to
  // abort the whole batch and empty the shelf. Give it its own budget.
  List<MuzoItem> playable;
  try {
    playable = await multi
        .resolveToPlayable(ordered, max: 48)
        .timeout(const Duration(seconds: 45));
  } catch (_) {
    playable = const <MuzoItem>[];
  }
  if (playable.isEmpty) {
    // Fallback: direct YT search for a few priority titles. EN PARALLÈLE :
    // la boucle séquentielle (12 × 8 s, file d'attente comprise) pouvait à
    // elle seule dépasser le budget du merge et rendait [] — donc un rayon
    // « Nouvelles sorties » vide alors que les graines, elles, étaient là.
    Future<MuzoItem?> one(MuzoItem s) async {
      final artist = s.displayArtist;
      final q = (artist.isEmpty || artist == 'Unknown')
          ? s.title
          : '${s.title} $artist';
      try {
        final resp = await api
            .search(q, filter: 'songs')
            .timeout(const Duration(seconds: 8));
        // Pas de confiance au premier résultat : ce rayon tamponne la date de
        // sortie de la graine sur le hit, donc un homonyme se retrouve affiché
        // comme une nouveauté vérifiée. On exige que le hit nomme bien le titre
        // ET l'artiste de la graine, sinon on préfère n'avoir aucun titre.
        MuzoItem? hit;
        for (final r in resp.results) {
          if (r.videoId == null) continue;
          if (!matchesNamedEntity(
              r, s.title, (artist.isEmpty || artist == 'Unknown') ? '' : artist)) {
            continue;
          }
          hit = r;
          break;
        }
        if (hit == null) return null;
        // Stamp the seed's real release date: undated hits are filtered
        // out by the shelf's date window (they used to always disappear).
        return hit.copyWith(
          releaseDate: hit.releaseDate ?? s.releaseDate,
          source: hit.source ?? s.source,
          sourceId: hit.sourceId ?? s.sourceId,
        );
      } catch (_) {
        return null;
      }
    }

    final direct = (await Future.wait(ordered.take(12).map(one)))
        .whereType<MuzoItem>()
        .toList();
    if (direct.isNotEmpty) return dedupeMuzoSongs(direct).take(20).toList();
    // Dernier recours : les graines elles-mêmes. Elles portent une date de
    // sortie vérifiée (Deezer / Apple RSS / curated) et le merge de l'accueil
    // sait les afficher et les ouvrir (page artiste, extrait Deezer) — rendre
    // [] faisait au contraire disparaître tout le rayon.
    return dedupeMuzoSongs(ordered).take(20).toList();
  }
  return dedupeMuzoSongs(playable).take(24).toList();
  });
});

/// Boost score for "Nouvelles sorties": rap FR/US/afro, hits Bénin,
/// afrobeats and West/Central African regions rank first inside the 7-day
/// window (still newest-first within the same score tier).
int _newReleasePriority(MuzoItem item) {
  final hay =
      '${item.title} ${item.displayArtist} ${item.category ?? ''}'.toLowerCase();
  var score = 0;
  // Régions prioritaires (pays + marqueurs culturels) — Bénin / CI / NG d'abord.
  const regionHits = <String>[
    'bénin', 'benin', 'nigeria', 'nigerian', "côte d'ivoire", 'cote d\'ivoire',
    'ivorian', 'ivoirien', 'abidjan', 'lagos', 'lome', 'lomé', 'cotonou',
    'congo', 'congolais', 'rdc', 'drc', 'kinshasa',
    'lubumbashi', 'accra', 'cameroun', 'cameroon',
    'sénégal', 'senegal', 'mali', 'burkina', 'ghana', 'togo',
  ];
  const genreHits = <String>[
    'rap', 'hip-hop', 'hip hop', 'drill', 'trap', 'afro', 'afrobeats',
    'afrobeat', 'amapiano', ' mbalax', 'coupé-décalé', 'coupe-decale',
    'gospel', 'hits bénin', 'benin hits', 'street pop',
  ];
  var regionHit = false;
  for (final r in regionHits) {
    if (hay.contains(r)) {
      score += 55;
      regionHit = true;
      break;
    }
  }
  // Bénin / Côte d'Ivoire / Nigeria get an extra geo bump (user priority).
  if (hay.contains('bénin') ||
      hay.contains('benin') ||
      hay.contains("côte d'ivoire") ||
      hay.contains('cote d\'ivoire') ||
      hay.contains('ivoirien') ||
      hay.contains('ivorian') ||
      hay.contains('abidjan') ||
      hay.contains('nigeria') ||
      hay.contains('nigerian') ||
      hay.contains('lagos')) {
    score += 35;
  }
  var genreHit = false;
  for (final g in genreHits) {
    if (hay.contains(g)) {
      score += 40;
      genreHit = true;
      break;
    }
  }
  // Region + genre together (rap béninois, afro CI…) ranks above either alone.
  if (regionHit && genreHit) score += 30;
  // Marqueurs FR/US explicites.
  if (hay.contains('français') ||
      hay.contains('francais') ||
      hay.contains(' drill fr')) {
    score += 25;
  }
  if (hay.contains('us rap') ||
      hay.contains('american') ||
      hay.contains('usa ')) {
    score += 20;
  }
  return score;
}

/// Extra boost for artists the user explicitly tracks (Tiakola, Fally…).
int _headArtistBonus(MuzoItem item) {
  final hay = '${item.displayArtist} ${item.title}'.toLowerCase();
  const heads = <String>[
    // FR rap / slam
    'tiakola', 'fally', 'grand corps', 'luther', 'zamdane', 'inoss',
    'gims', 'ninho', 'werenoi', 'favé', 'fave', 'sdm', 'kololo',
    'jul', 'nekfeu', 'booba', 'pnl', 'lomeo', 'kaaris', 'mhd',
    // Afrique de l'Ouest / NG / BJ / CI
    'seyi vibez', 'rema', 'burna boy', 'davido', 'ayra starr', 'tems',
    'olodo', 'majeeed', 'diamond platnumz', 'wizkid', 'asake', 'omah lay',
    'black sherif', 'king promise', 'shatta', 'sarkodie',
    'sixu', 'tino', 'awoluss', 'zeynab', 'k-flow', 'dedaloo',
    'kiff no beat', 'serge beynaud', 'naga', 'smileys', 'betty aké',
    'dj arafat', 'meiway', 'awalé', 'awale',
    // US rap / gospel
    'az chike', 'rakim', 'for king', 'cory asbury', 'anthony brown',
    'beck', 'carly rae', 'miley',
    // Week 18–23/09/2026 heads
    'fireboy', 'blaqbonez', 'black sherif', 'phyno', 'frenna',
    'chocolate city', 'balloranking', 'shoday', 'mc solar', 'mc solaar',
    'daguerre', 'ezra collective', 'orville peck', 'dremo', 'erigga',
    'lojay', 'victor ad', 'nao ',
    // Têtes Bénin — départagent les sorties béninoises le même jour.
    'fanicko', 'crisba', 'nikanor', 'vano baby', 'opa officiel',
    'bobo wê', 'axel merryl', 'manzor', 'dibi dobo', 'siano bless',
  ];
  for (final h in heads) {
    if (hay.contains(h)) return 70;
  }
  return 0;
}

/// Merge Discovery 7-day releases with playable Deezer new tracks: one
/// "Nouvelles sorties" shelf (replaces the old separate Nouveautés row).
/// Filtered to the last 7 days (incl. today), priority-scored, newest first.
final homeNewReleasesMergedProvider =
    FutureProvider<List<MuzoItem>>((ref) async {
  final shelf = await ContentCacheService.shelfCachedDaily(
      'shelf|mergedReleases', () async {
  Future<List<MuzoItem>> safe(String label, Future<List<MuzoItem>> f) async {
    // 70s → 90s + chrono: the songs provider chains Deezer (16 lead artists ×
    // album detail) + 48 YT resolutions + its own 45s resolution budget; at
    // 50s it timed out right in that window, returned [] and the shelf
    // disappeared instead of refreshing. Mesuré le 2026-10-15 : la branche
    // rendait encore `HomeNewReleases kept=0/0`, donc chaque branche est
    // désormais chronométrée pour savoir laquelle mange le budget.
    final clock = Stopwatch()..start();
    try {
      final out = await f.timeout(const Duration(seconds: 90));
      debugPrint('HomeNewReleases: branche $label -> ${out.length} titre(s) '
          'en ${clock.elapsedMilliseconds} ms');
      return out;
    } catch (_) {
      debugPrint('HomeNewReleases: branche $label COUPÉE à '
          '${clock.elapsedMilliseconds} ms');
      return const <MuzoItem>[];
    }
  }

  final batches = await Future.wait([
    // Chart-first: brand-new singles that ARE rap FR / rap US / afro according
    // to the storefront genre labels, dated inside the window.
    safe('charts', ref.read(chartNewSongsProvider.future)),
    safe('newSongs', ref.read(deezerNewSongsProvider.future)),
    safe('discovery', () async {
      // Discovery "new releases" are albums — never merge them into the
      // song shelf (that branch always returned []). Songs come from
      // deezerNewSongsProvider (dated Deezer + curated + RSS).
      return const <MuzoItem>[];
    }()),
  ]);
  final seen = <String>{};
  final merged = <MuzoItem>[];
  for (final batch in batches) {
    for (final item in batch) {
      if (_looksLikeJunkRelease(item)) continue;
      // "New" = dated inside the 7-day window. Undated chart seeds
      // (old iTunes tops) must never appear as new releases.
      if (!datedWithinReleaseWindow(item)) continue;
      final id = item.videoId ?? item.browseId ?? item.sourceId;
      final key = id != null && id.isNotEmpty
          ? id.toLowerCase()
          : '${item.title}|${item.displayArtist}'.toLowerCase();
      if (key.isEmpty || seen.add(key) == false) continue;
      // Metadata-only seeds stay visible when they carry a verified release
      // date (curated / iTunes RSS): tapping opens the artist page. They used
      // to be dropped, which hid real releases YouTube had not indexed yet.
      merged.add(item);
    }
  }
  // Newest release first so today's drop always leads the shelf; priority
  // (rap FR/US/afro, Bénin/CI/NG, head artists) only breaks same-day ties.
  merged.sort((a, b) {
    final da = a.releaseDate;
    final db = b.releaseDate;
    if (da != null && db != null && !da.isAtSameMomentAs(db)) {
      return db.compareTo(da);
    }
    if (da == null) return db == null ? 0 : 1;
    if (db == null) return -1;
    final pa = _newReleasePriority(a) + _headArtistBonus(a);
    final pb = _newReleasePriority(b) + _headArtistBonus(b);
    if (pa != pb) return pb.compareTo(pa);
    return 0;
  });
  return merged.take(24).toList();
  });
  // The cache can hold a snapshot built days ago — offline the replay ceiling
  // is a full year — so the window is cut again against the DEVICE clock on
  // every read. Nothing stale may ever render under "Nouvelles sorties".
  final keptReleases = shelf.where(datedWithinReleaseWindow).toList();
  debugPrint('HomeNewReleases kept=${keptReleases.length}/${shelf.length} '
      '(7d window, device clock)');
  return keptReleases;
});

/// Découverte de la semaine — de vrais sons du chart mondial Deezer
/// (`/chart/0/tracks`) résolus en YouTube jouable. Rien d'inventé.
final deezerWeeklyTracksProvider = FutureProvider<List<MuzoItem>>((ref) async {
  return ContentCacheService.shelfCached('shelf|weekly', () async {
  try {
    final seeds =
        await ref.read(deezerApiServiceProvider).topTracks(limit: 40);
    if (seeds.isEmpty) return const [];
    final playable = await ref
        .read(multiApiServiceProvider)
        .resolveToPlayable(seeds, max: 12);
    return dedupeMuzoSongs(playable).take(10).toList();
  } catch (_) {
    return const [];
  }
  });
});

/// Artistes populaires du mois — de vrais artistes du chart mondial Deezer
/// (`/chart/0/artists`), rotation mensuelle déterministe pour que le rayon
/// change de visage chaque mois.
final deezerTopArtistsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  return ContentCacheService.shelfCached('shelf|topArtists', () async {
  try {
    final artists =
        await ref.read(deezerApiServiceProvider).topArtists(limit: 60);
    if (artists.isEmpty) return const [];
    final bucket = DateTime.now().year * 12 + DateTime.now().month +
        ContentCacheService.deviceSeed;
    final rotated = ContentCacheService.rotate(artists, bucket);
    return dedupeShelfItems(rotated).take(12).toList();
  } catch (_) {
    return const [];
  }
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _dailyRecoTimer;
  String _lastDailySeed = '';
  final ScrollController _homeScrollController = ScrollController();
  Timer? _scrollSaveDebounce;
  bool _scrollRestoreDone = false;

  @override
  void initState() {
    super.initState();
    _lastDailySeed = _dailySeed().toString();
    _homeScrollController.addListener(_maybeSaveScroll);
    // Edge case: if the app stays open past midnight, flip the daily
    // recommendations automatically instead of waiting for a restart.
    _dailyRecoTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final seed = _dailySeed().toString();
      if (seed != _lastDailySeed) {
        _lastDailySeed = seed;
        ref.invalidate(recommendedForYouProvider);
        // New day → also pull fresh songs/albums/artists so the Home
        // updates daily even if the app stays open past midnight.
        ref.invalidate(deezerRecentAlbumsProvider);
        ref.invalidate(deezerNewSongsProvider);
        ref.invalidate(chartNewSongsProvider);
        ref.invalidate(chartNewAlbumsProvider);
        ref.invalidate(homeNewReleasesMergedProvider);
        ref.invalidate(homePopularSongsProvider);
        ref.invalidate(deezerWeeklyTracksProvider);
        ref.invalidate(deezerTopArtistsProvider);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final storage = ref.read(storageServiceProvider);
      storage.refreshAll(silent: true);
      storage.fetchAndCacheUserAvatar();
      // Quit/return policy: relaunching the app always lands on Home.
      ref.read(navigationIndexProvider.notifier).state = 0;
      // Load the Supabase artist catalog in background once, then it
      // auto-refreshes every 72h (see CuratedArtistsService).
      CuratedArtistsService.instance.init();
      UpdateService().checkForUpdates(context);
      _restoreHomeScroll();
    });
  }

  /// Saves the Home scroll offset (debounced) so re-opening the app lands back
  /// where the user was instead of resetting to the top.
  void _maybeSaveScroll() {
    if (!_homeScrollController.hasClients) return;
    final offset = _homeScrollController.offset;
    _scrollSaveDebounce?.cancel();
    _scrollSaveDebounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(storageServiceProvider).setHomeScrollOffset(offset);
    });
  }

  /// Restores the last scroll offset once enough slivers are laid out. Kept
  /// retrying while content grows (shelves load lazily); stops once it reached
  /// the target or the list finished building around it.
  void _restoreHomeScroll() {
    if (_scrollRestoreDone || !_homeScrollController.hasClients) return;
    final storage = ref.read(storageServiceProvider);
    final target = storage.homeScrollOffset;
    if (target <= 0) {
      _scrollRestoreDone = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollRestoreDone || !mounted || !_homeScrollController.hasClients) {
        return;
      }
      final pos = _homeScrollController.position;
      if (pos.maxScrollExtent <= 0) return;
      final clamped = target.clamp(0.0, pos.maxScrollExtent).toDouble();
      _homeScrollController.jumpTo(clamped);
      if (target <= pos.maxScrollExtent) _scrollRestoreDone = true;
    });
  }

  @override
  void dispose() {
    _dailyRecoTimer?.cancel();
    _scrollSaveDebounce?.cancel();
    _homeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(navigationIndexProvider);
    // Persist the active tab whenever it changes (quit/return policy).
    ref.listen<int>(navigationIndexProvider, (previous, next) {
      if (next != previous) {
        ref.read(storageServiceProvider).setLastTabIndex(next);
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: FadeIndexedStack(
          index: selectedIndex,
          children: [
            _buildHomeTab(context, ref),
            const SpotifySearchScreen(),
            const SpotifyLibraryScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    _restoreHomeScroll();
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(context, ref),
          Expanded(
            child: RefreshIndicator(
              color: Theme.of(context).colorScheme.onSurface,
              backgroundColor: (Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).cardColor
                  : Colors.white),
              onRefresh: () async {
                ref.read(shownArtistsProvider.notifier).state = {};
                ref.invalidate(homeSearchProvider);
                ref.invalidate(homePopularSongsProvider);
                ref.invalidate(homeSearchArtistsProvider);
                ref.invalidate(homeSearchAlbumsProvider);
                ref.invalidate(homeCatalogSectionProvider);
                ref.read(homeChartsRefreshNonce.notifier).state++;
                ref.invalidate(homeChartsProvider);
                ref.invalidate(recommendedForYouProvider);
                ref.invalidate(discoveryFeedProvider);
                try {
                  ref.read(discoveryServiceProvider).invalidateNewContent();
                } catch (_) {}
                ref.invalidate(homeNewReleasesMergedProvider);
                ref.invalidate(homePopularSongsProvider);
                ref.invalidate(deezerRecentAlbumsProvider);
                ref.invalidate(deezerNewSongsProvider);
                ref.invalidate(chartNewSongsProvider);
                ref.invalidate(chartNewAlbumsProvider);
                ref.invalidate(genreChartSongsProvider);
                ref.invalidate(deezerWeeklyTracksProvider);
                ref.invalidate(deezerTopArtistsProvider);
                ref.invalidate(categorySubSongsProvider);
                // Les invalidations Riverpod seules ne suffisent pas : chaque
                // rayon relit son entrée disque et une entrée "fraîche" court-
                // circuite le réseau. On purge donc réellement le cache pour
                // que le pull-to-refresh recharge toutes les catégories.
                await ContentCacheService.instance.invalidatePrefix('catsub|');
                await ContentCacheService.instance.invalidatePrefix('podcat|');
                await ContentCacheService.instance.invalidatePrefix('discovery|');
                await ContentCacheService.instance.invalidatePrefix('trends|');
                await ContentCacheService.instance.invalidatePrefix('trendalb|');
                await ContentCacheService.instance.invalidatePrefix('trendpl|');
                await ContentCacheService.instance.invalidatePrefix('homecharts|');
                await ContentCacheService.instance.invalidatePrefix('mb|rel|');
                // The genre-chart shelves read their own cache keys, so a
                // pull-to-refresh must clear those too or they replay the
                // snapshot they took this morning.
                await ContentCacheService.instance
                    .invalidatePrefix('trendsm2|');
                await ContentCacheService.instance
                    .invalidatePrefix('shelf|genrechart|');
                await ContentCacheService.instance
                    .invalidatePrefix('shelf|chartnew');
                // Les trois rayons datés étaient les seuls à ne pas être purgés :
                // « Nouvelles sorties » (mergedReleases), ses graines Deezer
                // (newSongs) et « Nouveaux albums » (recentAlbums) rejouaient
                // leur instantané à chaque pull-to-refresh, ce qui faisait
                // relaisser les mêmes titres — y compris périmés — sous un
                // libellé de nouveautés.
                await ContentCacheService.instance
                    .invalidatePrefix('shelf|mergedReleases');
                await ContentCacheService.instance
                    .invalidatePrefix('shelf|newSongs');
                await ContentCacheService.instance
                    .invalidatePrefix('shelf|recentAlbums');
                // Les rayons doivent repartir de zéro, pas rejouer leur ancien tri.
                ref.invalidate(categorySubSongsProvider);
                ref.invalidate(discoveryFeedProvider);
                ref.invalidate(homeCatalogSectionProvider);
                ref.read(homeChartsRefreshNonce.notifier).state++;
                ref.invalidate(homeChartsProvider);
                ref.invalidate(recommendedForYouProvider);
                ref.invalidate(homeNewReleasesMergedProvider);
                ref.invalidate(homePopularSongsProvider);
                ref.invalidate(deezerRecentAlbumsProvider);
                ref.invalidate(deezerNewSongsProvider);
                ref.invalidate(deezerWeeklyTracksProvider);
                ref.invalidate(deezerTopArtistsProvider);
                await ref.read(storageServiceProvider).refreshAll();
              },
              child: CustomScrollView(
                controller: _homeScrollController,
                slivers: [
                  // 1 — Tunefy DJ — mix infini autour de votre écoute actuelle
                  const SliverToBoxAdapter(child: _DjHomeEntry()),
                  // 1b — Quick Picks : suggestions issues de l'historique
                  // (GET /api/feed du backend, section masquee si vide)
                  const SliverToBoxAdapter(child: QuickPicksSection()),
                  // 2 — Écoutés récemment
                  const SliverToBoxAdapter(child: _RecentlyListenedSection()),
                  // 3 — Reprendre l'écoute
                  const SliverToBoxAdapter(child: _ContinueListeningSection()),
                  // 4 — Nouvelles sorties (7j, fusion Nouveautés + Discovery)
                  const SliverToBoxAdapter(
                      child: _MergedNewReleasesSection()),
                  // 5 — Nouveaux albums (Deezer + genres rap/US/gospel)
                  SliverToBoxAdapter(
                      child: _NewAlbumsSection(l10n.newAlbums)),
                  // 6 — Découverte de la semaine
                  SliverToBoxAdapter(
                      child: _DiscoverWeeklySection(l10n.discoverWeekly)),
                  // 7b — Daily Mix : melange personnalise, renouvele chaque jour
                  const SliverToBoxAdapter(child: _DailyMixSection()),
                  // 7c — Release Radar :ouveautes des artistes ecoutes
                  const SliverToBoxAdapter(child: _ReleaseRadarSection()),
                  // 7 — Recommandé pour vous ce mercredi
                  const SliverToBoxAdapter(child: _RecommendedForYouSection()),
                  // 8 — Tendance du moment
                  SliverToBoxAdapter(
                      child: _SubCategorySongsSection(
                          l10n.trendingNow, 'Charts', 'Trending')),
                  // 9 — Rap FR: Apple FR most-played, kept to the rap genres.
                  SliverToBoxAdapter(
                      child: _RealGenreSection(
                          l10n.frRap,
                          genre: 'fr rap',
                          catalogGenres: const ['fr rap'])),
                  // 10 — Rap US (US + CA storefronts)
                  SliverToBoxAdapter(
                      child: _RealGenreSection(
                          l10n.usRap,
                          genre: 'hip-hop',
                          catalogGenres: const ['hip-hop'],
                          offset: 6)),
                  // 11 — Rap Afro: Nigerian, Ghanaian and Ivorian hip-hop,
                  // which is what afro rap is — not UK drill.
                  SliverToBoxAdapter(
                      child: _RealGenreSection(
                          l10n.afroRap,
                          genre: 'afro rap',
                          catalogGenres: const ['afro rap', 'afrobeats'],
                          offset: 5)),
                  // 12 — Afrobeats
                  SliverToBoxAdapter(
                      child: _RealGenreSection(
                          l10n.afrobeats,
                          genre: 'afrobeats',
                          catalogGenres: const ['afrobeats'])),
                  // 13 — Afro Hits (the southern/eastern African side, so the
                  // three afro rows do not repeat the same Nigerian tops)
                  SliverToBoxAdapter(
                      child: _RealGenreSection(
                          l10n.afroHits,
                          genre: 'afro hits',
                          catalogGenres: const ['afrobeats', 'r&b'],
                          offset: 6)),
                  // 14 — Gospel (query pipeline — no dedicated curated table)
                  SliverToBoxAdapter(
                      child: _SearchSection(l10n.homeGospel,
                          query: 'gospel songs')),
                  // 15 — Artistes populaires (Discovery, mois précédent)
                  const SliverToBoxAdapter(
                      child: DiscoveryHomeSection(DiscoveryHomePart.artists)),
                  // 16 — Albums populaires (Discovery, mois précédent)
                  const SliverToBoxAdapter(
                      child:
                          DiscoveryHomeSection(DiscoveryHomePart.popularAlbums)),
                  // 17 — Playlists populaires
                  SliverToBoxAdapter(
                      child: _ChartsPlaylistsSection(l10n.popularPlaylists)),
                  // 18 — Benin Hits (top du Bénin, seeds YT/iTunes)
                  SliverToBoxAdapter(
                      child: _SubCategorySongsSection(
                          l10n.beninHits, 'Hit Benin', 'Top Benin')),
                  // 19 — Chansons populaires 2026
                  SliverToBoxAdapter(
                      child: _YearSongsSection(l10n.popularSongs)),
                  // 20 — Recommandations personnalisées (basées sur vos favoris)
                  SliverToBoxAdapter(
                      child: _FavoritesSearchSection(
                          l10n.personalizedRecommendations)),
            const SliverPadding(
                padding: EdgeInsets.only(bottom: kBottomChromeHeight)),
          ],
        ),
      ),
    ),
  ],
),
);
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final username = ref.watch(usernameProvider);
    final l10n = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour >= 5 && hour < 12
        ? l10n.goodMorning
        : hour >= 12 && hour < 18
            ? l10n.goodAfternoon
            : hour >= 18 && hour < 22
                ? l10n.goodEvening
                : l10n.goodNight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              mainScaffoldKey.currentState?.openDrawer();
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Builder(
                  builder: (context) {
                    final localPhoto = storage.profilePhotoPath;
                    if (localPhoto != null && File(localPhoto).existsSync()) {
                      return Image.file(
                        File(localPhoto),
                        height: 34,
                        width: 34,
                        fit: BoxFit.cover,
                      );
                    }
                    return Image.asset(
                      'assets/icon.png',
                      height: 34,
                      width: 34,
                      fit: BoxFit.cover,
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: '$greeting, ',
                children: [
                  TextSpan(
                    text: username,
                    style: const TextStyle(
                      color: Color(0xFF1DDA63),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(text: ' !'),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  }

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// Rayon de l'accueil pendant qu'il se charge : titre + rangée de cartes en
/// squelette, à la géométrie exacte de [_MusicCard] (152 px, écart 14,
/// padding 20).
///
/// Les rayons de catégories rendaient `SizedBox.shrink()` tant que leur
/// provider travaillait. Sur le réseau mesuré ici (le worker YouTube relance
/// un scrape par graine, 32 graines par rayon), aucun des cinq rayons de
/// genre n'avait fini au bout de quatre minutes : « Rap FR », « Rap US »,
/// « Afro Rap », « Afrobeats », « Afro Hits », « Tendance » et « Gospel »
/// n'existaient simplement pas à l'écran. C'est la cause de « je ne vois pas
/// les autres catégories dans Home ». Une rangée en chargement est visible,
/// elle, et elle ne réclame aucun artiste — le remplissage reste géré par
/// le provider quand il livre.
class _HomeShelfSkeleton extends StatelessWidget {
  final String title;
  const _HomeShelfSkeleton(this.title);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title),
        SizedBox(
          height: 216,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 4,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(right: index == 3 ? 0 : 14),
              child: SizedBox(
                width: 152,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SkeletonLoader(width: 152, height: 152, borderRadius: 8),
                    SizedBox(height: 10),
                    SkeletonLoader(width: 120, height: 14, borderRadius: 4),
                    SizedBox(height: 6),
                    SkeletonLoader(width: 80, height: 12, borderRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ⭐ Recommandé pour vous — personalized from your listening history + Deezer.
class _RecommendedForYouSection extends ConsumerWidget {
  const _RecommendedForYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(recommendedForYouProvider);
    final title =
        AppLocalizations.of(context).recommendedForYou(DateTime.now().weekday);
    return data.when(
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : _PlayableShelfGate(
              title: title,
              items: items,
              onTap: (item) => openArtistForSong(context, item),
            ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// ⭐ Nouvelles sorties (fusion) — sons des 7 derniers jours, priorisés
/// rap FR/US/afro + hits Bénin + afrobeats + régions AF de l'Ouest/Centre.
/// Remplace l'ancienne section « Nouveautés » séparée.
class _MergedNewReleasesSection extends ConsumerWidget {
  const _MergedNewReleasesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeNewReleasesMergedProvider);
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: AppLocalizations.of(context).newReleases,
          items: items,
          claimsArtists: false,
          showDate: true,
          onTap: (item) {
            HapticFeedback.selectionClick();
            playSongAndOpenNowPlaying(context, item, openPlayer: false);
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// ⭐ Nouveaux albums — real albums from Deezer's recent chart (never a
/// fictional text query). Tap opens the REAL album with its full track list.
/// Merges the global pool with genre-targeted Deezer album searches so rap
/// FR / rap US / gospel / afrobeats releases actually appear.
class _NewAlbumsSection extends ConsumerWidget {
  final String title;
  const _NewAlbumsSection(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(deezerRecentAlbumsProvider);
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final unique = dedupeMuzoSongs(items);
        if (unique.isEmpty) return const SizedBox.shrink();
        // Newest-first first (title honesty), priority only as tiebreak —
        // otherwise a 30-day-old head-artist album buries today's release.
        unique.sort((a, b) {
          final da = a.releaseDate;
          final db = b.releaseDate;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          if (!db.isAtSameMomentAs(da)) return db.compareTo(da);
          // Same release day → rap FR/US/afro + BJ/CI/NG albums lead.
          final pa = _newReleasePriority(a) + _headArtistBonus(a);
          final pb = _newReleasePriority(b) + _headArtistBonus(b);
          if (pa != pb) return pb.compareTo(pa);
          return 0;
        });
        final candidates = unique.take(24).toList();
        // Les nouveautés sont exemptées de la règle d'artiste unique : leur
        // promesse est la sortie récente, pas la variété. Dédupliquées
        // seulement à l'intérieur du rayon.
        final fresh = dedupeShelfItems(candidates).take(18).toList();
        if (fresh.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title),
            _AlbumRow(
              items: fresh,
              showDate: true,
              onTap: (item) {
                HapticFeedback.selectionClick();
                final browseId = item.browseId ?? item.album?.id;
                if (browseId != null && browseId.isNotEmpty) {
                  Navigator.of(context).push(SlidePageRoute(
                    page: AlbumScreen(
                      albumId: browseId,
                      albumName: item.title,
                      thumbnailUrl: item.thumbnails.lastOrNull?.url,
                    ),
                  ));
                } else {
                  openArtistForAlbum(context, item);
                }
              },
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// ⭐ Découverte de la semaine — de vrais sons du chart mondial Deezer
/// (`/chart/0/tracks`), résolus en YouTube jouable. Tap = lecture immédiate.
class _DiscoverWeeklySection extends ConsumerWidget {
  final String title;
  const _DiscoverWeeklySection(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(deezerWeeklyTracksProvider);
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: title,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Daily Mix — a personalised long queue, re-rolled once a day.
class _DailyMixSection extends ConsumerWidget {
  const _DailyMixSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(dailyMixProvider);
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: l10n.dailyMix,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Release Radar — newest tracks by the artists the listener actually plays.
/// Stays hidden until there is a listening history to personalise it with.
class _ReleaseRadarSection extends ConsumerWidget {
  const _ReleaseRadarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(releaseRadarProvider);
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: l10n.releaseRadar,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Editorial song shelf sourced from a (category › sub) pair of the seeded
/// YT/iTunes pipeline (e.g. Hit Benin › Top Benin).
class _SubCategorySongsSection extends ConsumerWidget {
  final String title;
  final String category;
  final String sub;
  const _SubCategorySongsSection(this.title, this.category, this.sub);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(categorySubSongsProvider(
        (category: category, sub: sub, excludedArtists: null)));
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: title,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => _HomeShelfSkeleton(title),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// The current FR+US top songs (Apple RSS → YouTube). Backs the "Tunefy DJ"
/// shelf.
class _ChartsPlaylistsSection extends ConsumerWidget {
  final String title;
  const _ChartsPlaylistsSection(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeChartsProvider).when(
      data: (charts) => AsyncData<List<MuzoItem>>(charts.playlists),
      loading: () => const AsyncLoading<List<MuzoItem>>(),
      error: (e, st) => AsyncError<List<MuzoItem>>(e, st),
    );
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title),
            _ClaimedSongRow(
              items: items,
              onTap: (item) {
                HapticFeedback.selectionClick();
                final id = item.browseId ?? item.videoId;
                if (id == null) return;
                Navigator.of(context).push(SlidePageRoute(
                  page: PlaylistScreen(
                    playlistId: id,
                    title: item.title,
                    thumbnailUrl: item.thumbnails.lastOrNull?.url,
                  ),
                ));
              },
            ),
          ],
        );
      },
      loading: () => _HomeShelfSkeleton(title),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// "Popular Songs {year}" — real chart hits of the current year, sourced from
/// Apple storefront RSS via [homePopularSongsProvider] (a distinct, authoritative
/// source from the charts/DJ shelves).
class _YearSongsSection extends ConsumerWidget {
  final String title;
  const _YearSongsSection(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final data = ref.watch(homePopularSongsProvider(year));
    final sectionTitle = '$title $year';
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: sectionTitle,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}


class _MusicCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;

  /// Date de sortie affichée sous le titre (rayons « Nouveaux albums » /
  /// « Nouveautés ») — null ailleurs, la carte garde son aspect d'origine.
  final String? dateLabel;
  final VoidCallback onTap;

  const _MusicCard({
    required this.title,
    this.subtitle,
    required this.imageUrl,
    this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 152,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BrandBadged(
                    imageUrl: imageUrl,
                    badgeSize: 20,
                    child: imageUrl != null && imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _placeholder(context),
                          )
                        : _placeholder(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: spotifyLightGrey,
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ),
            if (dateLabel != null && dateLabel!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                child: Text(
                  dateLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: spotifyLightGrey,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(
        Icons.music_note,
        color: Colors.white38,
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final VoidCallback onTap;
  final Color color;

  const _ArtistCard({
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.color = const Color(0xFF7C4DFF),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtistAvatar(
              artistName: name,
              size: 88,
              imageUrl: imageUrl,
              circle: true,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  /// Affiche la date de sortie sous le titre de chaque carte (rayon
  /// « Nouveautés ») ; faux partout ailleurs.
  final bool showDate;

  const _SongRow({
    required this.items,
    required this.onTap,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          final imageUrl = item.thumbnails.lastOrNull?.url;
          return _MusicCard(
            title: item.title,
            subtitle: item.displayArtist,
            imageUrl: imageUrl,
            dateLabel: showDate ? releaseDateLabel(context, item.releaseDate) : null,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(item);
            },
          );
        },
      ),
    );
  }
}

/// Song shelf that claims its artists against [shownArtistsProvider]
/// exactly once. The claimed subset is remembered in state so rebuilding the
/// section (data refresh, theme change…) never drops its own artists nor
/// re-claims them — guaranteeing a section keeps the people it displayed.
/// Stability guard used by Tunefy DJ / the older search shelves: the section
/// must prove it can actually produce a stream today. Resolves a few candidate
/// tracks (cheap because ugl cuerpo caches + playlist fallback) and only then
/// claims artists + renders header & row.
class _PlayableShelfGate extends ConsumerStatefulWidget {
  final String title;
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  /// Les rayons de NOUVEAUTÉS passent `false` : leur promesse est « ce qui est
  /// sorti cette semaine », pas « un artiste qu'on n'a pas encore vu ». Leur
  /// retirer une sortie au profit d'un rayon de genre plus bas ferait disparaître
  /// la nouveauté elle-même.
  final bool claimsArtists;
  final bool showDate;
  const _PlayableShelfGate({
    required this.title,
    required this.items,
    required this.onTap,
    this.claimsArtists = true,
    this.showDate = false,
  });

  @override
  ConsumerState<_PlayableShelfGate> createState() => _PlayableShelfGateState();
}

class _PlayableShelfGateState extends ConsumerState<_PlayableShelfGate> {
  // null = origine pas encore enrichie ; sinon items avec audioUrl attachés
  // quand le son a été résolu (les items sans son restent affichés tels quels).
  List<MuzoItem>? _enriched;

  // Sous-ensemble d'artistes réclamés UNE SEULE FOIS. Mémoïsé pour que les
  // rebuilds (enrichissement, changement de thème…) ne re-claiment pas les
  // mêmes artistes — sinon une section finirait par se vider d'elle-même.
  // Doit être remis à null dès que le provider livre une NOUVELLE liste,
  // sinon la section affiche le tout premier résultat pour toute la durée de
  // vie du widget (c'était la cause des rayons figés après un pull-to-refresh).
  List<MuzoItem>? _claimedCache;
  List<MuzoItem>? _claimedSource;

  // Les artistes que CETTE section possède dans le pool partagé. Rendus à
  // chaque re-claim (paramètre `release`) : sans eux, un nouveau tirage se
  // comparait à lui-même et basculait toute la liste en repeats.
  Set<String> _claimedArtists = <String>{};

  @override
  void initState() {
    super.initState();
    _enrich();
  }

  @override
  void didUpdateWidget(_PlayableShelfGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _enrich();
    }
  }

  /// Auto-chargement du son, sans bloquer l'affichage : la section s'affiche
  /// immédiatement avec les items du provider ; en arrière-plan chaque carte
  /// qui a un son résolu se voit attachée son audioUrl (lecture directe au
  /// clic). Aucune section à contenu n'est masquée.
  Future<void> _enrich() async {
    final items = widget.items;
    if (items.isEmpty) return;
    // Downloaded-only (the default): a resolved stream can never start, the
    // queue refuses anything not on disk. Same rule as AlbumScreen and
    // ArtistPageScreen — without it a Home pass walks the dead relay chain for
    // every shelf and the shelves still loading time out.
    if (_streamEnrichBlocked()) {
      if (!mounted) return;
      setState(() => _enriched = items);
      return;
    }
    // Offline: no stream can be resolved and downloads play straight from
    // disk — render the cached shelf immediately instead of spending seconds
    // on resolutions that can only fail.
    if (await ContentCacheService.isOffline()) {
      if (!mounted) return;
      setState(() => _enriched = items);
      return;
    }
    // The rest of the shelf is warmed through the shared queue rather than here:
    // firing a dozen resolutions at once against the local server only makes
    // each of them slower, because it merges one clip at a time.
    StreamPrewarmer.instance.warm(items, limit: 12);
    final resolved = await StreamExtractionService.resolvePlayableUrls(
      items,
      maxN: 4,
    );
    if (!mounted) return;
    // Fusion : on garde tous les items d'origine, mais on remplace par la
    // copie avec audioUrl quand la résolution a réussi.
    final byVideo = <String, MuzoItem>{};
    for (final r in resolved) {
      final id = r.videoId ?? r.title;
      if (id.isNotEmpty) byVideo[id] = r;
    }
    final enriched = [
      for (final i in items)
        byVideo[i.videoId ?? i.title] ?? i,
    ];
    setState(() => _enriched = enriched);
  }

  @override
  Widget build(BuildContext context) {
    // Filtrage recherche-artiste appliqué AVANT l'affichage : si aucun item ne
    // reste (tous déjà réclamés ailleurs), on masque titre + cartes ensemble.
    // Le résultat est mémorisé pour les rebuilds à contenu IDENTIQUE, mais
    // recalculé dès que le provider renvoie une autre liste — sinon la
    // section garderait indéfiniment son premier tri.
    final raw = _enriched ?? widget.items;
    if (_claimedSource != raw) {
      _claimedSource = raw;
      if (!widget.claimsArtists) {
        _claimedArtists = <String>{};
        _claimedCache = dedupeShelfItems(raw);
      } else {
        final claim = claimShelfItems(
          ref.read(shownArtistsProvider),
          raw,
          release: _claimedArtists,
        );
        _claimedArtists = claim.claimed;
        _claimedCache = claim.items;
      }
    }
    final claimed = _claimedCache!;
    if (claimed.isEmpty) return const SizedBox.shrink();

    // Une fois l'enrichissement terminé, remplace chaque item réclamé par sa
    // copie enrichie (audioUrl résolu) — même artiste, lecture instantanée.
    final shown = [
      if (_enriched != null)
        for (final i in claimed)
          _enriched!.firstWhere(
            (e) => (e.videoId ?? e.title) == (i.videoId ?? i.title),
            orElse: () => i,
          )
      else
        ...claimed,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(widget.title),
        _SongRow(
          items: shown,
          onTap: widget.onTap,
          showDate: widget.showDate,
        ),
      ],
    );
  }
}

/// Song row that runs the Home artist claim for shelves without a stream gate
/// of their own (the chart-playlist ray).
class _ClaimedSongRow extends StatelessWidget {
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  const _ClaimedSongRow({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ShelfClaimBuilder<MuzoItem>(
      items: items,
      artistOf: shelfArtistOf,
      keyOf: contentKey,
      builder: (context, claimed) => claimed.isEmpty
          ? const SizedBox.shrink()
          : _SongRow(items: claimed, onTap: onTap),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  /// Affiche la date de sortie sous le titre de chaque carte (rayon
  /// « Nouveaux albums ») ; faux partout ailleurs.
  final bool showDate;

  const _AlbumRow({
    required this.items,
    required this.onTap,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          final imageUrl = item.thumbnails.lastOrNull?.url;
          return _MusicCard(
            title: item.title,
            subtitle: item.displayArtist,
            imageUrl: imageUrl,
            dateLabel: showDate ? releaseDateLabel(context, item.releaseDate) : null,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(item);
            },
          );
        },
      ),
    );
  }
}

/// Libellé de date de sortie compact (« 13 oct. 2026 ») dans la locale de
/// l'interface ; null quand l'item n'a pas de date — la carte n'affiche alors
/// rien de supplémentaire.
String? releaseDateLabel(BuildContext context, DateTime? date) {
  if (date == null) return null;
  final locale = Localizations.localeOf(context).toString();
  try {
    return DateFormat('d MMM yyyy', locale).format(date);
  } catch (_) {
    // Symboles de locale non chargés : format neutre plutôt qu'un plantage.
    return DateFormat('d MMM yyyy').format(date);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ── 1. Écoutés récemment ────────────────────────────────────────────────────

// ── ★ Tunefy DJ (accueil) ───────────────────────────────────────────────────

/// Bandeau d'accès rapide au studio DJ : continue un mix depuis la lecture en
/// cours, ou démarre depuis le dernier réellement écouté sinon.
class _DjHomeEntry extends ConsumerWidget {
  const _DjHomeEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          HapticFeedback.selectionClick();
          final storage = ref.read(storageServiceProvider);
          final playing = ref.read(currentMediaItemProvider).valueOrNull;
          MuzoItem? seed;
          if (playing == null) {
            final history = storage.getHistory();
            if (history.isNotEmpty) {
              seed = history.first;
            } else {
              final favs = storage.favoritesListenable.value;
              if (favs.isNotEmpty) seed = favs.first;
            }
          }
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DjScreen(seed: seed)),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F2E1A), Color(0xFF1DB954)],
              ),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.graphic_eq,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tunefyDj,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.djEmptyHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_circle_fill,
                    color: Colors.white, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 1. Écoutés récemment ────────────────────────────────────────────────────

class _RecentlyListenedSection extends ConsumerWidget {
  const _RecentlyListenedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    return ValueListenableBuilder<List<MuzoItem>>(
      valueListenable: storage.historyListenable,
      builder: (context, history, _) {
        final unique = <String, MuzoItem>{};
        for (final item in history) {
          if (item.videoId == null || unique.containsKey(item.videoId)) continue;
          unique[item.videoId!] = item;
        }
        final items = unique.values.take(10).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: AppLocalizations.of(context).recentlyListened,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
    );
  }
}

// ── 2. Continuer l'écoute ───────────────────────────────────────────────────

class _ContinueListeningSection extends ConsumerWidget {
  const _ContinueListeningSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    return ValueListenableBuilder<List<MuzoItem>>(
      valueListenable: storage.historyListenable,
      builder: (context, history, _) {
        final unique = <String, MuzoItem>{};
        for (final item in history) {
          if (item.videoId == null || unique.containsKey(item.videoId)) continue;
          unique[item.videoId!] = item;
        }
        final all = unique.values.toList();
        if (all.isEmpty) return const SizedBox.shrink();
        final items = all.take(10).toList();
        return _PlayableShelfGate(
          title: AppLocalizations.of(context).continueListening,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
    );
  }
}

// ── Generic search section ──────────────────────────────────────────────────

// ── Recommandé pour vous (Deezer + vos artistes écoutés) ────────────────────

/// A shelf whose songs come from one search phrase (gospel today). The urban
/// genre shelves moved to [_RealGenreSection]: searching a phrase returns
/// approximate matches, whereas a chart returns the genre's actual hits.
class _SearchSection extends ConsumerWidget {
  final String title;
  final String? query;

  const _SearchSection(
    this.title, {
    this.query,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = query != null
        ? ref.watch(homeSearchProvider(query!))
        : ref.watch(homeChartsProvider).when(
            data: (charts) => AsyncData<List<MuzoItem>>(charts.tracks),
            loading: () => const AsyncLoading<List<MuzoItem>>(),
            error: (e, st) => AsyncError<List<MuzoItem>>(e, st),
          );
    return data.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _PlayableShelfGate(
          title: title,
          items: items,
          onTap: (item) => openArtistForSong(context, item),
        );
      },
      loading: () => _HomeShelfSkeleton(title),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── 16. Parce que vous avez écouté ──────────────────────────────────────────

class _FavoritesSearchSection extends ConsumerWidget {
  final String title;
  const _FavoritesSearchSection(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    return ValueListenableBuilder<List<MuzoItem>>(
      valueListenable: storage.historyListenable,
      builder: (context, history, _) {
        if (history.isEmpty) return const SizedBox.shrink();
        final artists =
            history.map((e) => e.displayArtist).where((a) => a.isNotEmpty).toSet().toList();
        if (artists.isEmpty) return const SizedBox.shrink();
        final query = artists.first;
        final data = ref.watch(homeSearchProvider('$query songs'));
        return data.when(
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return _PlayableShelfGate(
              title: title,
              items: items.take(10).toList(),
              onTap: (item) => openArtistForSong(context, item),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }
}

// ── Favorite-artist cards claiming their names against the shared set exactly
/// once (kept in state so rebuilds never re-claim nor drop own artists).
class _ClaimedArtistRow extends ConsumerStatefulWidget {
  final List<(String, String?)> items;

  const _ClaimedArtistRow({required this.items});

  static const _colors = [
    Color(0xFF7C4DFF),
    Color(0xFF26A69A),
    Color(0xFF5C6BC0),
    Color(0xFFEF5350),
    Color(0xFF42A5F5),
    Color(0xFFEC407A),
    Color(0xFF66BB6A),
    Color(0xFFFFA726),
  ];

  @override
  ConsumerState<_ClaimedArtistRow> createState() => _ClaimedArtistRowState();
}

class _ClaimedArtistRowState extends ConsumerState<_ClaimedArtistRow> {
  List<(String, String?)>? _claimed;

  @override
  Widget build(BuildContext context) {
    // Le parent peut déjà avoir réclamé les items (sinon shrink à l'écran) ;
    // dans ce cas on affiche widget.items tels quels, sans re-filtrer (le
    // re-filtrage les éliminerait car ils sont déjà dans `seen`).
    final artists = _claimed ?? widget.items;
    _claimed = artists;
    if (artists.length > 10) artists.removeRange(10, artists.length);
    if (artists.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      // 88 avatar + 8 gap + two 11px lines ≈ 127: at 120 the card overflowed
      // its own row on the bottom for every two-line artist name. 142 ne
      // suffisait plus dès que le système agrandit le texte (lignes à ~16 px) :
      // la carte débordait de nouveau de sa rangée.
      height: 155,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: artists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final (name, imageUrl) = artists[index];
          return _ArtistCard(
            name: name,
            imageUrl: imageUrl,
            color: _ClaimedArtistRow._colors[index % _ClaimedArtistRow._colors.length],
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                SlidePageRoute(
                  page: ArtistPageScreen(
                    artistName: name,
                    imageUrl: imageUrl,
                    color:
                        _ClaimedArtistRow._colors[index % _ClaimedArtistRow._colors.length],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── 18. Vos chansons préférées ──────────────────────────────────────────────

