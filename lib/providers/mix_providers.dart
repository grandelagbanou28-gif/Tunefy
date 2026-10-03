import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/providers/content_identity.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';

/// Days elapsed since the Unix epoch — the seed behind every daily rotation.
/// Same day → same mix for every launch, next day → a genuinely new one.

/// Top artists the listener actually spends time on, most frequent first.
/// Favourites count double: liking a track is a stronger signal than playing
/// it once. `listening_stats_service` is deliberately not used here — it
/// aggregates asynchronously and this has to stay synchronous for a provider.
List<String> _tasteArtists(StorageService storage, {int limit = 10}) {
  final counts = <String, int>{};
  void add(String? artist, int weight) {
    final name = (artist ?? '').trim();
    if (name.isEmpty) return;
    counts[name] = (counts[name] ?? 0) + weight;
  }

  for (final f in storage.getFavorites()) {
    add(f.displayArtist, 2);
  }
  for (final h in storage.getHistory()) {
    add(h.displayArtist, 1);
  }

  final ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return ranked.take(limit).map((e) => e.key).toList();
}

/// Recent tracks for [artist], cheapest source first. Returns an empty list
/// rather than throwing: a single dead artist must never break a whole shelf.
Future<List<MuzoItem>> _tracksForArtist(
  Ref ref,
  String artist, {
  int limit = 4,
}) async {
  try {
    final res = await ref
        .read(muzoApiServiceProvider)
        .search(artist, filter: 'songs');
    final songs = res.results
        .where((r) => r.resultType == 'song' || r.resultType == 'video')
        .toList();
    return songs.take(limit).toList();
  } catch (_) {
    return const [];
  }
}

/// **Release Radar** — the newest tracks by the artists the listener actually
/// plays, freshest first.
///
/// This is not a generic "new releases" shelf: the seed is the listener's own
/// taste (favourites + history), which is what makes the shelf feel personal.
/// With no history yet there is nothing personal to serve, so the section
/// stays empty rather than pretending: an empty shelf is honest, a shelf of
/// random hits is not.
final releaseRadarProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final storage = ref.read(storageServiceProvider);
  final artists = _tasteArtists(storage, limit: 8);
  if (artists.isEmpty) return const [];

  try {
    // Two tracks per artist keeps the shelf varied instead of one artist
    // dominating it just because they were played most often.
    final seeds = <MuzoItem>[];
    for (final artist in artists) {
      seeds.addAll(await _tracksForArtist(ref, artist, limit: 2));
    }
    if (seeds.isEmpty) return const [];

    final playable = await ref
        .read(multiApiServiceProvider)
        .resolveToPlayable(seeds, max: 16);

    // Newest first. `addedAt` is when *we* saw the track, `releaseDate` is
    // when it came out; either is better than the discovery order the API
    // happened to return.
    final sorted = dedupeMuzoSongs(playable).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a.addedAt ?? '') ?? a.releaseDate;
        final db = DateTime.tryParse(b.addedAt ?? '') ?? b.releaseDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    return sorted.take(20).toList();
  } catch (_) {
    return const [];
  }
});

/// **Daily Mix** — a long personalised queue built from the listener's taste,
/// re-rolled once a day (not once per app launch, which would be noise).
///
/// Unlike [releaseRadarProvider] this falls back to the public chart when the
/// listener has no history yet: a brand-new user still gets a playable shelf,
/// because a mix is an onboarding surface, not a personalised report.
final dailyMixProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final storage = ref.read(storageServiceProvider);
  final artists = _tasteArtists(storage, limit: 12);
  // Per-user daily seed: identical for a given user on a given day, different
  // for every user. A calendar-only seed gave the whole planet the same mix on
  // the same day, which is not a "Daily Mix" so much as a "Daily Mix for
  // everyone".
  final seed = await ref.watch(userDailySeedProvider.future);


  try {
    List<MuzoItem> seeds;
    if (artists.isNotEmpty) {
      seeds = <MuzoItem>[];
      for (var i = 0; i < artists.length; i++) {
        // Rotate the starting artist by the day so consecutive days do not
        // open on the same track.
        final artist = artists[(i + seed) % artists.length];
        seeds.addAll(await _tracksForArtist(ref, artist, limit: 3));
      }
    } else {
      final chart = await ref
          .read(deezerApiServiceProvider)
          .topTracks(limit: 40);
      seeds = chart;
    }
    if (seeds.isEmpty) return const [];

    final playable =
        await ref.read(multiApiServiceProvider).resolveToPlayable(seeds, max: 24);
    final deduped = dedupeMuzoSongs(playable);

    // Deterministic daily shuffle: same order for the whole day, a different
    // order tomorrow. Keeps the mix stable across restarts.
    final shuffled = List<MuzoItem>.from(deduped)
      ..sort((a, b) {
        final ka = (a.videoId ?? a.title).hashCode ^ seed;
        final kb = (b.videoId ?? b.title).hashCode ^ seed;
        return ka.compareTo(kb);
      });

    return shuffled.take(30).toList();
  } catch (_) {
    return const [];
  }
});
