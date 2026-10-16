import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/content_identity.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/services/trending_service.dart';

/// Playable songs of a genre, taken from the charts that actually are that
/// genre rather than from a hand-typed artist list.
///
/// [args.genre] is any name [TrendingService.genreChartFor] understands — an
/// editorial shelf name ("rap fr"), a search phrase ("afro rap") or a catalog
/// key ("afrobeats"). Unknown genres return nothing so the caller keeps its own
/// fallback. The pool is one song per artist (a shelf of 20 is 20 different
/// people), rotated per user and day, then resolved to playable tracks.
final genreChartSongsProvider =
    FutureProvider.family<List<MuzoItem>, ({String genre, int offset})>(
        (ref, args) async {
  final spec = TrendingService.genreChartFor(args.genre);
  if (spec == null) return const <MuzoItem>[];
  final deezer = ref.read(deezerApiServiceProvider);
  final multi = ref.read(multiApiServiceProvider);
  return ContentCacheService.shelfCachedStaleFirst(
      'shelf|genrechart|${args.genre}|${args.offset}', () async {
    final userSeed = await ref.watch(userDailySeedProvider.future);
    // Borné : le flux Apple RSS peut se taire et la file de recherches
    // YouTube encombrée. Sans plafond, ce provider ne livrait jamais — et le
    // rayon de catégorie restait absent de l'accueil.
    final charts = await TrendingService.chartSongsFor(
      spec.countries,
      spec.tokens,
    ).timeout(const Duration(seconds: 20),
        onTimeout: () => const <TrendSong>[]);
    final chartSeeds = <MuzoItem>[];
    final seen = <String>{};
    for (final t in charts) {
      final k = '${t.title}|${t.artist}'.toLowerCase();
      if (!seen.add(k)) continue;
      chartSeeds.add(_chartSongSeed(t));
    }
    // Le classement NATIONAL de la scène (radio « French Rap » / « Rap US », à
    // défaut la sélection Deezer trouvée avec le nom de la scène) répond en
    // 2-4 s avec des sorties label du pays demandé. Sans lui, un magasin
    // injoignable faisait remplir la ligne par le chart Deezer MONDIAL :
    // mesuré le 2026-10-16, « Rap FR » n'avait que 2 titres étiquetés hip-hop
    // dans le top de ventes Apple et le reste venait de Lil Baby / Gunna, et
    // « Hip-hop » US montrait Booba et Tiakola.
    final scene = <MuzoItem>[];
    final seenArtist = <String>{};
    try {
      final rows = await deezer
          .sceneChart(spec.countries, spec.tokens,
              args.genre.replaceAll('-', ' '),
              limit: 30)
          .timeout(const Duration(seconds: 14));
      for (final s in rows) {
        final k = '${s.title}|${s.displayArtist}'.toLowerCase();
        if (!seen.add(k)) continue;
        // Un artiste par ligne, comme au-dessus : le rayon doit rester une
        // rangée d'artistes différents, pas le tracklist d'un seul album.
        final lead =
            s.displayArtist.split(RegExp(r'[,&#]')).first.trim().toLowerCase();
        if (lead.isNotEmpty && !seenArtist.add(lead)) continue;
        scene.add(s);
      }
    } catch (e) {
      debugPrint('[GenreChart] ${args.genre}: classement national indisponible: $e');
    }
    final seeds = <MuzoItem>[];
    // Le chart étiqueté du magasin reste le référent QUAND il répond assez : il
    // n'est remplacé que lorsqu'il est muet ou famélique.
    if (chartSeeds.length >= 12) {
      seeds.addAll(chartSeeds);
    } else {
      seeds.addAll(scene);
      seeds.addAll(chartSeeds);
    }
    // A storefront that answers with little of this genre (or is unreachable)
    // still must not fall back to generic search, so Deezer's genre chart
    // tops the row up. The threshold is a full row rather than a big pool:
    // the US rap chart only lists ~16 rappers in its top 100, and pulling the
    // worldwide Deezer rap chart for that would have mixed French rap back in.
    // Le chart MONDIAL ne sert plus que si la scène elle-même est muette : quand
    // un classement national existe déjà, c'est exactement lui qui importait du
    // rap US dans « Rap FR » (et de la rumba congolaise dans « Afrobeats »).
    if (seeds.length < 12 && scene.isEmpty) {
      try {
        final inGenre = await deezer
            .chartTracksInGenre(spec.deezerGenre, limit: 40)
            .timeout(const Duration(seconds: 18));
        for (final s in inGenre) {
          final k = '${s.title}|${s.displayArtist}'.toLowerCase();
          if (!seen.add(k)) continue;
          seeds.add(s);
        }
      } catch (_) {}
    }
    debugPrint('[GenreChart] ${args.genre}: scene=${scene.length} '
        'magasin=${chartSeeds.length} -> pool=${seeds.length}');
    if (seeds.isEmpty) return const <MuzoItem>[];
    final rotated = ContentCacheService.rotate(
        seeds, ContentCacheService.dayBucket + userSeed + args.offset * 7);
    List<MuzoItem> playable;
    try {
      playable = dedupeMuzoSongs(
        await multi
            .resolveToPlayable(rotated, max: 32)
            .timeout(const Duration(seconds: 35)),
      ).take(30).toList();
    } catch (e) {
      debugPrint('[GenreChart] ${args.genre}: résolution YouTube hors délai: $e');
      playable = const <MuzoItem>[];
    }
    debugPrint('[GenreChart] ${args.genre}: pool=${seeds.length} '
        'resolved=${playable.length}');
    // Rien de résolu n'empêche la catégorie de s'afficher : les graines du
    // chart (vrai titre, vrai artiste, vraie pochette) sont servies telles
    // quelles et un tap ouvre la page de l'artiste. Rendre [] faisait
    // disparaître le rayon entier de l'accueil.
    if (playable.isEmpty) return rotated.take(20).toList();
    return playable;
  });
});

/// The labels the urban "Nouveauté" / "New albums" rows are built from: rap FR,
/// rap US and the afro storefronts, i.e. exactly the specs the genre shelves
/// use, only windowed on release date instead of chart position.
const List<String> _urbanChartLabels = <String>[
  'fr rap',
  'hip-hop',
  'afro rap',
  'afrobeats',
  'afro hits',
];

/// Brand-new singles from the genre charts, resolved to playable YouTube
/// tracks. Same countries, same genre tokens and same real release dates as the
/// genre rows, so "Nouveauté" cannot show a 2010 reissue.
final chartNewSongsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final multi = ref.read(multiApiServiceProvider);
  return ContentCacheService.shelfCachedDaily('shelf|chartnewsongs', () async {
    List<TrendSong> fresh;
    try {
      fresh = await TrendingService.newSongsFor(_urbanChartLabels, days: 7)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[ChartNewSongs] flux de nouveautés hors délai/erreur: $e');
      fresh = const <TrendSong>[];
    }
    if (fresh.isEmpty) return const <MuzoItem>[];
    final seeds = <MuzoItem>[];
    for (final t in fresh) {
      seeds.add(_chartSongSeed(t));
    }
    List<MuzoItem> playable;
    try {
      playable = dedupeMuzoSongs(await multi
          .resolveToPlayable(seeds, max: 28)
          .timeout(const Duration(seconds: 30)));
    } catch (e) {
      debugPrint('[ChartNewSongs] résolution YouTube hors délai: $e');
      playable = const <MuzoItem>[];
    }
    debugPrint('[ChartNewSongs] pool=${seeds.length} '
        'resolved=${playable.length}');
    // Graines du chart servies telles quelles si YouTube n'a pas suivi : elles
    // portent une vraie date de sortie et leur pochette, et « Nouvelles
    // sorties » les accepte. Rendre [] faisait disparaître le rayon.
    if (playable.isEmpty) return seeds.take(24).toList();
    return playable.take(24).toList();
  });
});

/// The albums equivalent: fresh, genre-correct records with artwork from the
/// storefront, so the "Nouveaux albums" row leads with what actually came out
/// this month in rap FR / rap US / afro.
final chartNewAlbumsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  return ContentCacheService.shelfCachedDaily('shelf|chartnewalbums', () async {
    final fresh =
        await TrendingService.newAlbumsFor(_urbanChartLabels, days: 30);
    final out = <MuzoItem>[];
    for (final a in fresh) {
      out.add(MuzoItem(
        title: a.title,
        thumbnails: a.cover.isNotEmpty
            ? [MuzoThumbnail(url: a.cover, width: 600, height: 600)]
            : const [],
        resultType: 'album',
        isExplicit: false,
        artists: [MuzoArtist(name: a.artist)],
        category: a.genre,
        releaseDate: a.releaseDate,
        source: 'apple chart',
        sourceId: '${a.title}|${a.artist}'.toLowerCase(),
        fetchedAt: DateTime.now(),
      ));
    }
    debugPrint('[ChartNewAlbums] ${out.length} fresh albums');
    return out;
  });
});

MuzoItem _chartSongSeed(TrendSong t) => MuzoItem(
      title: t.title,
      thumbnails: t.art.isNotEmpty
          ? [MuzoThumbnail(url: t.art, width: 600, height: 600)]
          : const [],
      resultType: 'song',
      isExplicit: false,
      artists: [MuzoArtist(name: t.artist)],
      category: t.genre,
      releaseDate: t.releaseDate,
      source: 'apple chart',
      sourceId: '${t.title}|${t.artist}'.toLowerCase(),
      fetchedAt: DateTime.now(),
    );

/// The artists currently charting in [genre] — the honest replacement for the
/// curated catalog's hand-written names on artist strips and album seeds.
Future<List<String>> genreChartArtists(String genre, {int limit = 10}) async {
  final spec = TrendingService.genreChartFor(genre);
  if (spec == null) return const <String>[];
  final charts =
      await TrendingService.chartSongsFor(spec.countries, spec.tokens);
  final out = <String>[];
  final seen = <String>{};
  for (final t in charts) {
    // Apple credits features in `artistName`; the strip is about the lead act.
    final name = t.artist.split(RegExp(r'[,&#]')).first.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    out.add(name);
    if (out.length >= limit) break;
  }
  return out;
}
