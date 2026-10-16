import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/genre_chart_provider.dart';
import 'package:muzo/services/category_curator.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/curated_artists_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/trending_service.dart';

const _timeout = Duration(seconds: 8);

/// The two most recent years (e.g. 2025 & 2026 today, 2026 & 2027 next year),
/// computed at runtime so the app always shows fresh content without code
/// changes in the years to come.
({int current, int previous}) _recentYears() {
  final now = DateTime.now();
  return (current: now.year, previous: now.year - 1);
}

/// True when the given release date falls in one of the two most recent years.
bool _isRecent(DateTime? date) {
  if (date == null) return false;
  final years = _recentYears();
  return date.year == years.current || date.year == years.previous;
}

/// Podcasts keep a release date only if it is one of the two most recent
/// years; podcasts without a date are kept so the section never empties.
bool _isRecentPodcast(DateTime? date) {
  if (date == null) return true;
  final years = _recentYears();
  return date.year == years.current || date.year == years.previous;
}

/// True for date-sensitive "new" queries (new releases / new music / nouveautés
/// / sorties / trending). These refresh daily instead of the default 3 days.
bool _isNewCategoryQuery(String term) {
  final t = term.toLowerCase();
  return t.contains('new') ||
      t.contains('nouveau') ||
      t.contains('nouveaute') ||
      t.contains('sortie') ||
      t.contains('release') ||
      t.contains('trending') ||
      t.contains('tendance') ||
      t.contains('hit') ||
      t.contains('top');
}

/// Keyless iTunes Search API helper shared by the category providers.
///
/// Stale-while-revalidate: a fresh disk snapshot short-circuits the network; a
/// hit goes to iTunes and is cached; an offline read (or a failed/empty
/// network call) replays the last snapshot up to [ContentCacheService.offlineCeiling]
/// so every category — and the songs inside it — stays browsable offline, the
/// way Spotify keeps a once-seen catalogue visible on a flight. Only a genuine
/// online failure with nothing cached throws, so callers can still show an
/// error state. Returns [] when iTunes truly has no results for the term.
  Future<List<Map<String, dynamic>>> _itunesSearch(
    String term,
    String entity,
    int limit, {
    int offset = 0,
  }) async {
    final cache = ContentCacheService.instance;
    final cacheKey = 'itunes|$entity|$limit|$offset|$term';
    // Categories refresh every 3 days; "new releases / new music" style queries
    // renew daily.
    final freshWindow = _isNewCategoryQuery(term)
        ? ContentCacheService.dailyTtl
        : ContentCacheService.browseTtl;
    List<Map<String, dynamic>>? toRows(List<dynamic>? raw) => raw
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final fresh = toRows(await cache.readJsonIfFresh(cacheKey, maxAge: freshWindow));
    if (fresh != null) return fresh;

    if (await ContentCacheService.isOffline()) {
      return toRows(await cache.readJsonStale(cacheKey,
              maxAge: ContentCacheService.offlineCeiling)) ??
          const <Map<String, dynamic>>[];
    }

    try {
      final uri = Uri.parse('https://itunes.apple.com/search').replace(
        queryParameters: {
          'term': term,
          'entity': entity,
          'limit': '$limit',
          if (offset > 0) 'offset': '$offset',
        },
      );
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) {
        throw Exception('iTunes search failed (HTTP ${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = ((data['results'] as List?) ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      if (results.isNotEmpty) unawaited(cache.writeJson(cacheKey, results));
      return results;
    } catch (_) {
      final stale = toRows(await cache.readJsonStale(cacheKey));
      if (stale != null && stale.isNotEmpty) return stale;
      rethrow;
    }
  }

  /// Pages iTunes until [target] rows are gathered. A single request tops out
  /// well below 100 results, so Top 100 charts need several pages.
  Future<List<Map<String, dynamic>>> _itunesSearchPaged(
    String term,
    String entity,
    int target, {
    int pageSize = 100,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (var offset = 0; offset < target; offset += pageSize) {
      final want = target - offset > pageSize ? pageSize : target - offset;
      final page = await _itunesSearch(term, entity, want, offset: offset);
      if (page.isEmpty) break;
      out.addAll(page);
      if (page.length < want) break;
    }
    return out;
  }


/// True when a [haystack] (title, artist or album) contains every word of
/// [needle], so generic results that only matched one stray word are dropped.
bool _containsEveryWord(String haystack, String needle) {
  final text = haystack.toLowerCase();
  return needle
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && w.length > 1)
      .every(text.contains);
}

String _hd(String? url) =>
    (url == null || url.isEmpty) ? '' : url.replaceFirst('100x100bb', '600x600bb');

/// Maps a Browse query to a catalog genre key when the query corresponds to
/// one of the genres in the curated artists catalog (12k artists, refreshed
/// every 72h). Returns null when there is no such genre, so the iTunes
/// editorial path stays authoritative for uncatalogued queries.
String? catalogGenreFor(String query) {
  if (query.isEmpty) return null;
  final key = query.trim().toLowerCase();
  const aliases = {
    'rap francais': 'fr-rap',
    'french rap': 'fr-rap',
    'rap fr': 'fr-rap',
    'rap france': 'fr-rap',
    'rap': 'us-rap',
    'hip hop': 'us-rap',
    'hip-hop': 'us-rap',
    'us rap': 'us-rap',
    'drill': 'us-rap',
    'afro rap': 'afro-rap',
    'african rap': 'afro-rap',
    'afrobeats': 'afrobeats',
    'afro hits': 'afro-hits',
  };
  final genre = aliases[key] ?? key;
  // Only map when something real exists for that genre: the curated catalog
  // bucket or one of the genre charts. Without this check a query would fall
  // through to a generic term search and answer with off-genre music.
  if (TrendingService.genreChartFor(genre) != null) return genre;
  return CuratedArtistsService.instance.artistsFor(genre).isNotEmpty
      ? genre
      : null;
}

/// Seed artists for a genre category: whoever charts in it right now, falling
/// back to the curated catalog's hand-typed names only when no chart covers the
/// genre. The catalog is ranked by followers and frozen between refreshes, so
/// on its own it repeats the same famous names — and for the afro buckets it
/// lists acts that are not that genre at all.
Future<List<String>> genreSeedArtists(String? catalogGenre) async {
  if (catalogGenre == null) return const <String>[];
  final charted = await genreChartArtists(catalogGenre, limit: 8);
  if (charted.isNotEmpty) return charted;
  await CuratedArtistsService.instance.whenReady();
  return CuratedArtistsService.instance
      .artistsFor(catalogGenre)
      .take(8)
      .map((a) => a.name)
      .toList();
}

/// Real songs of the catalog's real artists for a genre — the same catalog
/// pipeline the Home shelves use.
///
/// Searches each artist by its exact name (results are filtered to only keep
/// hits that mention that artist), so a genre row is filled with real music
/// from real verified artists instead of generic search matches.
/// [offset] rotates which artists a shelf covers; [country] narrows to one
/// country (e.g. FR for "rap français"). Returns [] while the catalog is empty.
/// At most one track per artist so the row never repeats the same person.
final catalogTracksForGenreProvider = FutureProvider.family<
    List<MuzoItem>,
    ({String genre, int offset, String? country})>((ref, args) async {
  // Watching the catalog service re-runs this shelf once the 72h load
  // completes, so genre rows fill automatically instead of staying hidden.
  final service = ref.watch(curatedArtistsServiceProvider);
  // Charts first. The catalog below is a hand-typed list ranked by follower
  // count, so it keeps showing the same famous names (and, for the afro
  // buckets, names that are not that genre at all). A genre chart answers with
  // whoever actually plays it this week, which is also what puts women rappers
  // on a rap row instead of leaving them out of the list.
  final charted = await ref
      .read(genreChartSongsProvider((genre: args.genre, offset: args.offset))
          .future);
  if (charted.isNotEmpty) return charted.take(10).toList();
  if (!service.hasData) return const <MuzoItem>[];
  final artists = service.artistsWhere(args.genre, country: args.country);
  if (artists.isEmpty) return const <MuzoItem>[];
  final api = ref.read(muzoApiServiceProvider);
  final items = <MuzoItem>[];
  final seenIds = <String>{};
  final want = 10;
  for (var i = 0; i < artists.length && items.length < want; i++) {
    final artist = artists[(args.offset + i) % artists.length];
    try {
      final res = await api
          .search(artist.name, filter: 'songs')
          .timeout(const Duration(seconds: 12));
      final aLow = artist.name.toLowerCase();
      for (final r in res.results) {
        if (r.videoId == null) continue;
        if (!r.displayArtist.toLowerCase().contains(aLow)) continue;
        final id = r.videoId!;
        if (seenIds.contains(id)) continue;
        seenIds.add(id);
        items.add(r);
        break; // one track per artist → different people in the row
      }
    } catch (_) {
      // A single artist failure never kills the row; keep going.
    }
  }
  items.sort((a, b) => _ageDays(a).compareTo(_ageDays(b)));
  return items.take(want).toList();
});

int _ageDays(MuzoItem item) {
  final rd = item.releaseDate;
  if (rd != null) return DateTime.now().difference(rd).inDays;
  final up = (item.uploaded ?? '').toLowerCase();
  final n = int.tryParse(up.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  if (up.contains('year')) return n * 365;
  if (up.contains('month')) return n * 30;
  if (up.contains('week')) return n * 7;
  if (up.contains('day')) return n;
  return 9999;
}

/// A real album found on the iTunes Search API for a category.
class CategoryAlbum {
  const CategoryAlbum({
    required this.name,
    required this.artist,
    required this.coverUrl,
    this.releaseDate,
    this.trackCount = 0,
  });

  final String name;
  final String artist;
  final String coverUrl;
  final DateTime? releaseDate;
  final int trackCount;

  /// EPs are albums with 3-6 tracks.
  bool get isEp => trackCount >= 3 && trackCount <= 6;

  int get year => releaseDate?.year ?? 0;
}

/// A real artist found on the iTunes Search API for a category.
class CategoryArtist {
  const CategoryArtist({required this.name, required this.imageUrl});

  final String name;
  final String imageUrl;
}

/// A real single/track found on the iTunes Search API for a category.
class CategoryTrack {
  const CategoryTrack({
    required this.name,
    required this.artist,
    required this.coverUrl,
    required this.duration,
    this.releaseDate,
  });

  final String name;
  final String artist;
  final String coverUrl;
  final Duration duration;
  final DateTime? releaseDate;
}

/// A real podcast found on the iTunes Search API for a category.
class CategoryPodcast {
  const CategoryPodcast({
    required this.name,
    required this.host,
    required this.coverUrl,
  });

  final String name;
  final String host;
  final String coverUrl;
}

/// Real albums for a "Browse All" category (iTunes album entity, keyless).
///
/// Editorial logic: the section is driven by the category's curated seed
/// artists (internationally relevant hitmakers), each fetched for their
/// current releases, then deduplicated by collection id, filtered to the two
/// most recent years and sorted newest first. The raw category-term search is
/// only used to top things up. For uncatalogued queries (e.g. an artist name
/// from an artist page) the term path takes over on its own.
final categoryAlbumsProvider =
    FutureProvider.family<List<CategoryAlbum>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final year = DateTime.now().year;
  // Catalog-first seeds: the real top artists of the genre keep the shelf
  // fresh with the 72h catalog while still plumbing through iTunes metadata.
  final catalogGenre = catalogGenreFor(query);
  List<String> seeds;
  seeds = await genreSeedArtists(catalogGenre);
  if (seeds.isEmpty) seeds = seedsFor(query);
  final yearTerm = query.contains(year.toString())
      ? query
      : '$query $year';

  final seenIds = <String>{};
  final albums = <CategoryAlbum>[];

  Future<void> collect(String term, int limit, {bool strict = false}) async {
    final results = await _itunesSearch(term, 'album', limit);
    for (final r in results) {
      final name = r['collectionName'] as String?;
      final art = _hd(r['artworkUrl100'] as String?);
      final id = r['collectionId']?.toString() ?? '';
      final artist = (r['artistName'] as String?) ?? '';
      if (name == null || name.isEmpty || art.isEmpty) continue;
      if (strict && !_containsEveryWord(name, query) &&
          !_containsEveryWord(artist, query)) {
        continue;
      }
      if (id.isNotEmpty && seenIds.contains(id)) continue;
      final releaseDate =
          DateTime.tryParse((r['releaseDate'] as String?) ?? '');
      if (!_isRecent(releaseDate)) continue;
      if (id.isNotEmpty) seenIds.add(id);
      albums.add(
        CategoryAlbum(
          name: name,
          artist: artist,
          coverUrl: art,
          releaseDate: releaseDate,
          trackCount: (r['trackCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }
  }

  if (seeds.isNotEmpty) {
    for (final seed in seeds.take(6)) {
      await collect(seed, 4, strict: false);
    }
    await collect(yearTerm, 12, strict: true);
  } else {
    await collect(yearTerm, 30, strict: true);
  }

  albums.sort((a, b) {
    final d = (b.releaseDate?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.releaseDate?.millisecondsSinceEpoch ?? 0);
    if (d != 0) return d;
    return b.trackCount.compareTo(a.trackCount);
  });
  return albums.take(12).toList();
});

/// Real artists for a "Browse All" category (iTunes musicArtist entity).
///
/// The seed artists are the section: they are already the genre anchors an
/// editor would pick. Artwork is resolved from iTunes for each seed. For
/// uncatalogued queries (artist pages, raw terms) a plain artist search runs.
final categoryArtistsProvider =
    FutureProvider.family<List<CategoryArtist>, String>((ref, query) async {
  if (query.isEmpty) return [];

  // Genre-first: the artists charting in this genre right now, with artwork
  // resolved from iTunes. The curated catalog is only reached when no chart
  // covers the genre — its rows are hand-typed names ranked by followers, and
  // for the afro buckets those names are not that genre.
  final catalogGenre = catalogGenreFor(query);
  final chartSeeds = await genreChartArtists(catalogGenre ?? '', limit: 8);
  if (chartSeeds.isEmpty && catalogGenre != null) {
    await CuratedArtistsService.instance.whenReady();
    final catalog = CuratedArtistsService.instance.artistsFor(catalogGenre);
    if (catalog.isNotEmpty) {
      return catalog
          .take(100)
          .map((a) => CategoryArtist(
                name: a.name,
                imageUrl: a.imageUrl ?? '',
              ))
          .toList();
    }
  }

  final seeds = chartSeeds.isNotEmpty ? chartSeeds : seedsFor(query);
  if (seeds.isNotEmpty) {
    final artists = <CategoryArtist>[];
    final seen = <String>{};
    for (final seed in seeds.take(8)) {
      final key = seed.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      try {
        final results = await _itunesSearch(seed, 'musicArtist', 1);
        final r = results.isNotEmpty ? results.first : null;
        final name = (r?['artistName'] as String?) ?? seed;
        artists.add(
          CategoryArtist(
            name: name,
            imageUrl: _hd(r?['artworkUrl100'] as String?),
          ),
        );
      } catch (_) {
        artists.add(CategoryArtist(name: seed, imageUrl: ''));
      }
    }
    return artists;
  }
  final results = await _itunesSearch(query, 'musicArtist', 12);
  final artists = <CategoryArtist>[];
  for (final r in results) {
    final name = r['artistName'] as String?;
    if (name == null || name.isEmpty) continue;
    artists.add(CategoryArtist(name: name, imageUrl: _hd(r['artworkUrl100'] as String?)));
  }
  return artists;
});

/// Real singles/tracks for a "Browse All" category (iTunes song entity).
///
/// Same editorial pipeline as the albums provider: curated seed artists first,
/// raw term as a strict top-up, deduplicated by track id, filtered to the two
/// most recent years and sorted newest first.
final categoryTracksProvider =
    FutureProvider.family<List<CategoryTrack>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final year = DateTime.now().year;
  final catalogGenre = catalogGenreFor(query);
  List<String> seeds;
  seeds = await genreSeedArtists(catalogGenre);
  if (seeds.isEmpty) seeds = seedsFor(query);
  final yearTerm = query.contains(year.toString())
      ? query
      : '$query $year';

  final seenIds = <String>{};
  final tracks = <CategoryTrack>[];

  Future<void> collect(String term, int limit, {bool strict = false}) async {
    final results = await _itunesSearchPaged(term, 'song', limit);
    for (final r in results) {
      final name = r['trackName'] as String?;
      final art = _hd(r['artworkUrl100'] as String?);
      final id = r['trackId']?.toString() ?? '';
      final artist = (r['artistName'] as String?) ?? '';
      if (name == null || name.isEmpty || art.isEmpty) continue;
      if (strict && !_containsEveryWord(name, query) &&
          !_containsEveryWord(artist, query)) {
        continue;
      }
      if (id.isNotEmpty && seenIds.contains(id)) continue;
      final releaseDate =
          DateTime.tryParse((r['releaseDate'] as String?) ?? '');
      if (!_isRecent(releaseDate)) continue;
      if (id.isNotEmpty) seenIds.add(id);
      tracks.add(
        CategoryTrack(
          name: name,
          artist: artist,
          coverUrl: art,
          duration: Duration(milliseconds: (r['trackTimeMillis'] as num?)?.toInt() ?? 0),
          releaseDate: releaseDate,
        ),
      );
    }
  }

  if (seeds.isNotEmpty) {
    for (final seed in seeds.take(6)) {
      await collect(seed, 20, strict: false);
    }
    await collect(yearTerm, 60, strict: true);
  } else {
    await collect(yearTerm, 120, strict: true);
  }

  tracks.sort((a, b) => (b.releaseDate?.millisecondsSinceEpoch ?? 0)
      .compareTo(a.releaseDate?.millisecondsSinceEpoch ?? 0));
  // The Top 10 / 50 / 100 chips slice this list themselves, so it has to
  // hold more than the smallest of them.
  return tracks.take(100).toList();
});

/// Real podcasts for a "Browse All" category (iTunes podcast entity).
/// Podcasts whose latest episode is from one of the two most recent years.
final categoryPodcastsProvider =
    FutureProvider.family<List<CategoryPodcast>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final results = await _itunesSearch(query, 'podcast', 20);
  final podcasts = <CategoryPodcast>[];
  final seen = <String>{};
  for (final r in results) {
    final name = r['collectionName'] as String?;
    final releaseDate =
        DateTime.tryParse((r['releaseDate'] as String?) ?? '');
    if (name == null || name.isEmpty) continue;
    if (!_isRecentPodcast(releaseDate)) continue;
    if (seen.contains(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    podcasts.add(
      CategoryPodcast(
        name: name,
        host: (r['artistName'] as String?) ?? '',
        coverUrl: _hd(r['artworkUrl100'] as String?),
      ),
    );
  }
  return podcasts.take(10).toList();
});
