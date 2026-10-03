import 'package:muzo/screens/spotify_search_screen.dart';
import 'package:muzo/widgets/fade_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:muzo/providers/navigation_provider.dart';
import 'package:muzo/screens/spotify_library_screen.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/screens/album_screen.dart';
import 'package:muzo/widgets/artist_avatar.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/update_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/providers/home_charts_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/screens/settings_screen.dart';
import 'package:muzo/services/curated_artists_service.dart';
import 'package:muzo/services/trending_service.dart';
import 'package:muzo/services/itunes_api_service.dart';
import 'package:muzo/data/curated_new_releases_2026.dart';
import 'package:muzo/services/musicbrainz_service.dart';
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
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/services/stream_prewarmer.dart';
import 'dart:math';
import 'dart:async';

// ═══════════════════════════════════════════════════════════════════════════════
// SHELF DEDUP — shelves dedupe their own content locally (by song/album/
// playlist id) so one section can never starve another out of the home.
// Only the favorite-artist CARDS keep a shared name pool so the same person
// is not shown twice in a row.
// ═══════════════════════════════════════════════════════════════════════════════

final homeShownArtistsProvider = StateProvider<Set<String>>((ref) => {});

/// Canonical key of a song/album/playlist tile, used to dedupe it WITHIN its
/// own shelf. Same video/album never appears twice in a single row; the global
/// pool is not involved so sections never vanish because somebody else claimed
/// "their" artist first.
String _contentKey(MuzoItem item) {
  final id = item.videoId ?? item.browseId;
  if (id != null && id.isNotEmpty) return id.toLowerCase();
  return '${item.title}|${item.displayArtist}'.toLowerCase();
}

/// Removes duplicate content within one shelf, keeping order.
List<MuzoItem> dedupeShelfItems(List<MuzoItem> items) {
  final seen = <String>{};
  final out = <MuzoItem>[];
  for (final item in items) {
    final key = _contentKey(item);
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    out.add(item);
  }
  return out;
}

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
  final key = '${args.genres.join('+')}|${args.offset}|${args.country}';
  // Building this shelf costs ~100 searches (one per artist, to honour "no
  // repeated artist"), and six genre shelves run on the same home page. Paying
  // that on every launch is not acceptable, and an in-memory memo only survives
  // the session — so the result is cached on disk for a day.
  //
  // It is also what stops the shelf from reshuffling under the user: the
  // catalog service notifies on every reload, which used to re-run this whole
  // loop and re-search every artist.
  final cacheKey = 'genre_shelf_$key';
  final memo = _homeSectionMemo[key];
  if (memo != null) return memo;
  final cached = await ContentCacheService.instance.readIfFresh(
    cacheKey,
    maxAge: ContentCacheService.dailyTtl,
  );
  if (cached != null && cached.isNotEmpty) {
    _homeSectionMemo[key] = cached;
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
    for (var i = 0; i < pool.length; i++) pool[(args.offset + i) % pool.length],
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
    _homeSectionMemo[key] = result;
    unawaited(ContentCacheService.instance.write(cacheKey, result));
  }
  return result;
});

/// Session-scoped memo in front of the disk cache: a rebuild must never cost a
/// Hive read, and within one session the shelf is immutable anyway.
final _homeSectionMemo = <String, List<MuzoItem>>{};

final homeSearchArtistsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
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

final homeSearchAlbumsProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
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
  final dailySeed = _dailySeed();
  try {
    final storage = ref.read(storageServiceProvider);
    final counts = <String, int>{};
    for (final item in storage.getHistory()) {
      final name = item.displayArtist;
      if (name.isEmpty || name == 'Unknown') continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    var topArtists = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Rotate which artists lead the search each day so the same top list does
    // not always produce the same tracks.
    if (topArtists.isNotEmpty) {
      topArtists = ContentCacheService.rotate(topArtists, dailySeed);
      topArtists = topArtists.take(5).toList();
    }

    final dz = ref.read(deezerApiServiceProvider);
    final discovered = <MuzoItem>[];
    for (final entry in topArtists.take(3)) {
      // Vary the search scope slightly by day for fresher results.
      final query = _dailyQuery(entry.key, dailySeed);
      final batch = await dz.searchTracks(query, limit: 6);
      discovered.addAll(batch.isEmpty
          ? await dz.searchTracks(entry.key, limit: 6)
          : batch);
      if (discovered.length >= 16) break;
    }
    if (discovered.isNotEmpty) {
      final playable = await ref
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
  final charts = await ref.watch(homeChartsProvider.future);
  final fallback =
      _seededShuffle<MuzoItem>(dedupeMuzoSongs(charts.tracks), dailySeed);
  if (fallback.isEmpty) return <MuzoItem>[];
  // Auto-chargement du son sans vider la section : on enrichit les items avec
  // un audioUrl quand c'est possible, mais on garde TOUS les items de toute
  // façon — la lecture retentera la cascade au clic pour ceux sans URL directe.
  final playable = await StreamExtractionService.resolvePlayableUrls(
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

/// Stable integer that changes once per day (device clock), used to rotate and
/// shuffle the daily recommendations deterministically.
int _dailySeed() =>
    DateTime.now().toUtc().difference(DateTime.utc(2024, 1, 1)).inDays;

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

/// Deezer albums released within the last 30 days, genre-targeted album
/// searches (rap FR/US, gospel, afrobeats), Apple RSS storefront tops with
/// real release dates (FR/US/NG/BJ), and albums from the priority curated
/// catalogs — so "Nouveaux albums" always has a full, real shelf.
final deezerRecentAlbumsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final deezer = ref.read(deezerApiServiceProvider);
  final api = ref.read(muzoApiServiceProvider);
  final catalog = ref.watch(curatedArtistsServiceProvider);

  Future<List<MuzoItem>> safeAlbums(Future<List<MuzoItem>> f) async {
    try {
      return await f.timeout(const Duration(seconds: 12));
    } catch (_) {
      return const <MuzoItem>[];
    }
  }

  final base = await safeAlbums(deezer.recentAlbums(days: 30, limit: 40));
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final now = DateTime.now();

  bool inWindow(MuzoItem a) {
    final rel = a.releaseDate;
    if (rel == null) return false;
    // Pre-releases + date-only timezone skew: allow a 7-day future horizon.
    final horizon = now.add(const Duration(days: 7));
    return !rel.isBefore(cutoff) && !rel.isAfter(horizon);
  }

  const queries = <String>[
    // FR / US rap & urban
    'rap français',
    'rap francais',
    'rap us',
    'hip-hop',
    'drill',
    'trap',
    'R&B',
    'pop',
    // Afrique de l'Ouest / Centre — toutes catégories
    'gospel',
    'afrobeats',
    'afro rap',
    'amapiano',
    'musique béninoise',
    'nigerian music',
    'ghana music',
    'congolese rumba',
    'rumba congolaise',
    'coupé-décalé',
    'zouk',
    'dancehall',
    'reggae',
    'mbalax',
    'highlife',
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
  for (var i = 0; i < queries.length; i += 4) {
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
    'for KING & COUNTRY',
    'Cory Asbury',
    'Anthony Brown',
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
    'Ezra Collective',
    'Orville Peck',
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
  final uniqueArtistNames = <String>{...priorityNames}.take(64).toList();
  for (var i = 0; i < uniqueArtistNames.length; i += 4) {
    final chunk = uniqueArtistNames.skip(i).take(4).toList();
    final batches = await Future.wait(
        chunk.map((name) => safeAlbums(deezer.albumsForArtist(name, limit: 10))));
    for (final b in batches) {
      artistAlbums.addAll(b);
    }
  }

  // Apple RSS tops across AF / FR / US storefronts (real im:releaseDate).
  final rssStores = <String>[
    'fr', 'us', 'ng', 'bj', 'ci', 'cd', 'cm', 'sn', 'gh', 'za',
  ];
  final rssBatches = await Future.wait(
      rssStores.map((cc) => TrendingService.topAlbums(cc)));
  final rssQueries = <(String, String, String?, DateTime?)>[];
  final rssSeen = <String>{};
  for (final batch in rssBatches) {
    for (final a in batch) {
      final k = '${a.title}|${a.artist}'.toLowerCase();
      if (a.title.isEmpty || rssSeen.add(k) == false) continue;
      final rel = a.releaseDate;
      // RSS reissues of 1995 catalog must not appear under "new albums";
      // pre-releases up to +7 days are allowed (date-only timezone skew).
      if (rel == null ||
          rel.isBefore(cutoff) ||
          rel.isAfter(now.add(const Duration(days: 7)))) {
        continue;
      }
      rssQueries.add((a.title, a.artist, a.cover, rel));
      if (rssQueries.length >= 16) break;
    }
    if (rssQueries.length >= 16) break;
  }

  // MusicBrainz first-release calendar for the 30-day window — free, dated,
  // daily disk cache. Fills genres RSS/Deezer may miss.
  final mbReleases = await safeAlbums(ref
      .read(musicBrainzServiceProvider)
      .releasesBetween(cutoff, now, limit: 60));
  final mbQueries = <(String, String, String?, DateTime?)>[];
  final mbSeen = <String>{...rssSeen};
  for (final a in mbReleases) {
    if (!inWindow(a) || _looksLikeJunkRelease(a)) continue;
    final k = _contentKey(a);
    if (k.isEmpty || mbSeen.add(k) == false) continue;
    mbQueries.add((a.title, a.displayArtist, null, a.releaseDate));
    if (mbQueries.length >= 12) break;
  }

  final rssAlbums = <MuzoItem>[];
  final resolvePairs = <(String, String, String?, DateTime?, String)>[
    for (final t in rssQueries) (t.$1, t.$2, t.$3, t.$4, 'itunes rss'),
    for (final t in mbQueries) (t.$1, t.$2, t.$3, t.$4, 'musicbrainz'),
  ];
  for (var i = 0; i < resolvePairs.length; i += 5) {
    final chunk = resolvePairs.skip(i).take(5).toList();
    final resolved = await Future.wait(chunk.map((t) async {
      final (title, artist, cover, rel, source) = t;
      try {
        final resp = await api
            .search('$title $artist', filter: 'albums')
            .timeout(const Duration(seconds: 9));
        final hit = resp.results.firstWhere(
          (r) => (r.browseId ?? r.videoId) != null,
          orElse: () => resp.results.isEmpty
              ? MuzoItem(
                  title: title,
                  thumbnails: const [],
                  resultType: 'album',
                  isExplicit: false,
                  artists: [MuzoArtist(name: artist)],
                  releaseDate: rel,
                  source: source,
                )
              : resp.results.first,
        );
        var item = hit.copyWith(
          releaseDate: rel,
          source: source,
        );
        if (item.thumbnails.isEmpty && cover != null && cover.isNotEmpty) {
          item = item.copyWith(thumbnails: [
            MuzoThumbnail(url: cover, width: 600, height: 600)
          ]);
        }
        return item;
      } catch (_) {
        return null;
      }
    }));
    rssAlbums.addAll(resolved.whereType<MuzoItem>());
  }

  // Prefer dated releases (RSS / artist / curated) over undated genre noise,
  // then drop playlist-style junk so "Nouveaux albums" stays editorial.
  final merged = <MuzoItem>[];
  final seenAlbums = <String>{};
  void push(MuzoItem a) {
    if (!inWindow(a)) return;
    if (_looksLikeJunkRelease(a)) return;
    final k = _contentKey(a);
    if (k.isEmpty || seenAlbums.add(k) == false) return;
    merged.add(a);
  }

  // Deezer's live dated pool first — genuinely fresh discographies (real
  // release_date from the last 30 days) win the dedupe against the RSS /
  // curated copies of the same album, so a playable album card leads.
  for (final a in base) {
    push(a);
  }
  // RSS next — real storefront tops with release dates.
  for (final a in rssAlbums) {
    push(a);
  }
  // Curated albums (web-verified dates) — seed first so New Albums is never
  // empty and shows the real 18–23/09 drops even when live feeds are thin.
  for (final c in curatedNewReleases2026) {
    if (c.event != 'album') continue;
    if (c.title.trim().isEmpty || c.title.trim() == c.artist.trim()) continue;
    if (!curatedIsFresh(c, window: const Duration(days: 14))) continue;
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
  // Dated genre hits next (undated ones were dropped by inWindow).
  for (final a in genreAlbums) {
    push(a);
  }

  // Always top up with Deezer's honest 7-day new releases — the freshest
  // drops of the week — instead of only when the shelf looks thin, so a
  // release published today reaches the shelf on the very next refresh.
  final freshReleases = await safeAlbums(deezer.newReleases(days: 7, limit: 20));
  for (final a in freshReleases) {
    push(a);
    if (merged.length >= 24) break;
  }

  // Curated seeds store title/artist/date only (no artwork) and the RSS
  // fallback can miss the cover too — those tiles would render as a bare
  // placeholder. Resolve a real cover for the first artless albums.
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
            .searchAlbums(query, limit: 1)
            .timeout(const Duration(seconds: 8));
        if (hits.isNotEmpty && hits.first.thumbnails.isNotEmpty) {
          return hits.first.thumbnails.first.url;
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

/// Vraies nouvelles sorties — sons des 7 derniers jours (Deezer dates +
/// albums prioritaires curated + iTunes current tops résolus YouTube).
/// Priorité rap FR/US/afro, hits Bénin, afrobeats, régions AF.
final deezerNewSongsProvider = FutureProvider<List<MuzoItem>>((ref) async {
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

  // 1) Deezer lead tracks of albums released in the last 7 days.
  seeds.addAll(await safe(deezer.newTracks(days: 7, limit: 30)));

  // 2) Curated FR / priority releases (editorial list → real titles).
  // Skip placeholders where title == artist (no real song name known yet)
  // and anything older than the 14-day shelf window (auto-expiring list).
  // Albums feed New Albums via deezerRecentAlbumsProvider; singles feed this
  // song shelf. Album entries still seed here only when no live lead track
  // was found (search by album title can resolve the lead single).
  final curatedSeeds = <MuzoItem>[];
  for (final c in curatedNewReleases2026) {
    if (c.title.trim().isEmpty || c.title.trim() == c.artist.trim()) continue;
    if (!curatedIsFresh(c, window: const Duration(days: 14))) continue;
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
    'for KING & COUNTRY',
    'Cory Asbury',
    'Anthony Brown',
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
  // Wider than 7 days so last-Friday drops (Tiakola…) still make the shelf;
  // /search/album never carries release_date — use albumsForArtist.
  final cutoffLead = DateTime.now().subtract(const Duration(days: 21));
  final leadFutures = <Future<List<MuzoItem>>>[];
  final uniquePriority = <String>{...priorityArtists}.take(16).toList();
  for (var i = 0; i < uniquePriority.length; i += 3) {
    final chunk = uniquePriority.skip(i).take(3).toList();
    leadFutures.addAll(chunk.map((name) async {
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
  }
  // Resolve lead-track batches sequentially to stay under Deezer rate limits.
  final leadOut = <MuzoItem>[];
  for (final f in leadFutures) {
    leadOut.addAll(await f);
  }
  seeds.addAll(leadOut);

  // 4) Apple current tops FR/US/NG/BJ/CI — real hits, resolved to playable YT.
  // One slice per storefront (4 each, 16 total): the old loop filled its 16
  // slots from the FR list alone, so the Benin / CI / Nigeria charts were
  // fetched and thrown away and the shelf kept repeating French tops.
  final topStores = await Future.wait([
    TrendingService.topSongs('fr'),
    TrendingService.topSongs('us'),
    TrendingService.topSongs('ng'),
    TrendingService.topSongs('bj'),
    TrendingService.topSongs('ci'),
  ]);
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
    // Fallback: direct YT search for a few priority titles.
    final direct = <MuzoItem>[];
    for (final s in ordered.take(12)) {
      final artist = s.displayArtist;
      final q = (artist.isEmpty || artist == 'Unknown')
          ? s.title
          : '${s.title} $artist';
      try {
        final resp = await api
            .search(q, filter: 'songs')
            .timeout(const Duration(seconds: 8));
        final hit = resp.results.where((r) => r.videoId != null).firstOrNull;
        if (hit != null) {
          // Stamp the seed's real release date: undated hits are filtered
          // out by the shelf's date window (they used to always disappear).
          direct.add(hit.copyWith(
            releaseDate: hit.releaseDate ?? s.releaseDate,
            source: hit.source ?? s.source,
            sourceId: hit.sourceId ?? s.sourceId,
          ));
        }
      } catch (_) {}
    }
    return dedupeMuzoSongs(direct).take(20).toList();
  }
  return dedupeMuzoSongs(playable).take(24).toList();
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
  // 14-day window: last-Friday drops + timezone-skewed midnight stamps still
  // count as "new" without emptying the shelf when Deezer is thin.
  final cutoff = DateTime.now().subtract(const Duration(days: 14));
  Future<List<MuzoItem>> safe(Future<List<MuzoItem>> f) async {
    // 70s: the songs provider chains Deezer (16 lead artists × album detail)
    // + 48 YT resolutions + its own 45s resolution budget; at 50s it timed out
    // right in that window, returned [] and the shelf disappeared instead of
    // refreshing.
    try {
      return await f.timeout(const Duration(seconds: 70));
    } catch (_) {
      return const <MuzoItem>[];
    }
  }

  final batches = await Future.wait([
    safe(ref.read(deezerNewSongsProvider.future)),
    safe(() async {
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
      final rel = item.releaseDate;
      // "New" = dated inside the 14-day window. Undated chart seeds
      // (old iTunes tops) must never appear as new releases.
      if (rel == null) continue;
      if (rel.isBefore(cutoff)) continue;
      if (rel.isAfter(DateTime.now().add(const Duration(days: 7)))) {
        continue;
      }
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

/// Découverte de la semaine — de vrais sons du chart mondial Deezer
/// (`/chart/0/tracks`) résolus en YouTube jouable. Rien d'inventé.
final deezerWeeklyTracksProvider = FutureProvider<List<MuzoItem>>((ref) async {
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

/// Artistes populaires du mois — de vrais artistes du chart mondial Deezer
/// (`/chart/0/artists`), rotation mensuelle déterministe pour que le rayon
/// change de visage chaque mois.
final deezerTopArtistsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  try {
    final artists =
        await ref.read(deezerApiServiceProvider).topArtists(limit: 60);
    if (artists.isEmpty) return const [];
    final bucket = DateTime.now().year * 12 + DateTime.now().month;
    final rotated = ContentCacheService.rotate(artists, bucket);
    return dedupeShelfItems(rotated).take(12).toList();
  } catch (_) {
    return const [];
  }
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
        ref.invalidate(homeNewReleasesMergedProvider);
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
                ref.read(homeShownArtistsProvider.notifier).state = {};
                ref.invalidate(homeSearchProvider);
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
                ref.invalidate(deezerRecentAlbumsProvider);
                ref.invalidate(deezerNewSongsProvider);
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
                // Les rayons doivent repartir de zéro, pas rejouer leur ancien tri.
                ref.invalidate(categorySubSongsProvider);
                ref.invalidate(discoveryFeedProvider);
                ref.invalidate(homeCatalogSectionProvider);
                ref.read(homeChartsRefreshNonce.notifier).state++;
                ref.invalidate(homeChartsProvider);
                ref.invalidate(recommendedForYouProvider);
                ref.invalidate(homeNewReleasesMergedProvider);
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
                  // 9 — Rap FR
                  SliverToBoxAdapter(
                      child: _SearchSection(l10n.frRap,
                          genres: const ['fr rap', 'rap francais', 'afrobeats'], country: 'FR')),
                  // 10 — Rap US
                  SliverToBoxAdapter(
                      child: _SearchSection(l10n.usRap,
                          genres: const ['hip-hop'], offset: 6, country: 'US')),
                  // 11 — Rap Afro
                  SliverToBoxAdapter(
                      child: _SearchSection(l10n.afroRap,
                          genres: const ['afro rap', 'afrobeats'], offset: 5)),
                  // 12 — Afrobeats
                  SliverToBoxAdapter(
                      child: _SearchSection(l10n.afrobeats,
                          genres: const ['afrobeats'],)),
                  // 13 — Afro Hits
                  SliverToBoxAdapter(
                      child: _SearchSection(l10n.afroHits,
                          genres: const ['afrobeats', 'r&b'], offset: 6)),
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
            const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
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
        final fresh = dedupeShelfItems(unique.take(24).toList());
        if (fresh.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title),
            _AlbumRow(
              items: fresh.take(18).toList(),
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
      loading: () => const SizedBox.shrink(),
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
        final claimed = dedupeShelfItems(items);
        if (claimed.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title),
            _SongRow(
              items: claimed,
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
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// "Popular Songs {year}" — fresh songs of the current year surfaced from a
/// text search, a distinct source from the charts/DJ shelves.
class _YearSongsSection extends ConsumerWidget {
  final String title;
  const _YearSongsSection(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final data = ref.watch(homeSearchProvider('top songs $year'));
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
  final VoidCallback onTap;

  const _MusicCard({
    required this.title,
    this.subtitle,
    required this.imageUrl,
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

  const _SongRow({required this.items, required this.onTap});

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

/// Song shelf that claims its artists against [homeShownArtistsProvider]
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
  const _PlayableShelfGate({
    required this.title,
    required this.items,
    required this.onTap,
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
      _claimedCache = dedupeShelfItems(raw);
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
        ),
      ],
    );
  }
}

class _ClaimedSongRow extends ConsumerStatefulWidget {
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  const _ClaimedSongRow({required this.items, required this.onTap});

  @override
  ConsumerState<_ClaimedSongRow> createState() => _ClaimedSongRowState();
}

class _ClaimedSongRowState extends ConsumerState<_ClaimedSongRow> {
  List<MuzoItem>? _claimed;

  @override
  Widget build(BuildContext context) {
    final items = _claimed ??
        dedupeShelfItems(widget.items);
    _claimed = items;
    if (items.isEmpty) return const SizedBox.shrink();
    return _SongRow(items: items, onTap: widget.onTap);
  }
}

/// Album shelf with the same one-time claim guarantee as [_ClaimedSongRow].
class _ClaimedAlbumRow extends ConsumerStatefulWidget {
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  const _ClaimedAlbumRow({required this.items, required this.onTap});

  @override
  ConsumerState<_ClaimedAlbumRow> createState() => _ClaimedAlbumRowState();
}

class _ClaimedAlbumRowState extends ConsumerState<_ClaimedAlbumRow> {
  List<MuzoItem>? _claimed;

  @override
  Widget build(BuildContext context) {
    final items = _claimed ??
        dedupeShelfItems(widget.items);
    _claimed = items;
    if (items.isEmpty) return const SizedBox.shrink();
    return _AlbumRow(items: items, onTap: widget.onTap);
  }
}

class _AlbumRow extends StatelessWidget {
  final List<MuzoItem> items;
  final void Function(MuzoItem) onTap;

  const _AlbumRow({required this.items, required this.onTap});

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

class _SearchSection extends ConsumerWidget {
  final String title;

  /// Catalog genres this shelf draws from, in priority order. A list because
  /// the catalog ships broad genre keys, not editorial ones like `fr-rap`.
  final List<String>? genres;
  final int offset;
  final String? country;
  final String? query;

  const _SearchSection(
    this.title, {
    this.genres,
    this.offset = 0,
    this.country,
    this.query,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = query != null
        ? ref.watch(homeSearchProvider(query!))
        : genres != null
            ? ref.watch(homeCatalogSectionProvider(
                (genres: genres!, offset: offset, country: country)))
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
      loading: () => const SizedBox.shrink(),
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
      height: 120,
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
