import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/musicbrainz_service.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/spotify_unofficial_service.dart';
import 'package:muzo/services/itunes_api_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';

final multiApiServiceProvider = Provider<MultiApiService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return MultiApiService(storage);
});

/// Aggregator that queries WORKING keyless APIs in parallel to DISCOVER
/// extra song titles the YouTube backend search missed. Discovery is
/// metadata-only; callers resolve titles to playable YouTube tracks via
/// [resolveToPlayable].
class MultiApiService {
  final StorageService _storage;
  MultiApiService(this._storage);

  MusicBrainzService? _musicBrainz;
  SpotifyUnofficialService? _spotify;
  MuzoApiService? _api;

  MusicBrainzService get musicBrainz => _musicBrainz ??= MusicBrainzService();
  SpotifyUnofficialService get spotify => _spotify ??= SpotifyUnofficialService();
  MuzoApiService get api => _api ??= MuzoApiService(_storage);

  /// Discover song titles across working APIs in parallel.
  /// Never throws — each failing source returns []. Returned items may lack
  /// a [MuzoItem.videoId]; they are discovery entries only.
  Future<List<MuzoItem>> discover(String query) async {
    final futures = <Future<List<MuzoItem>>>[
      _safe(() => musicBrainz.searchTracks(query), 'MusicBrainz'),
      _safe(() => spotify.search(query), 'Spotify'),
      _safe(() => ItunesApiService().searchSongsFrUs(query, limit: 10),
          'iTunes'),
      _safe(() => DeezerApiService().searchTracks(query, limit: 10), 'Deezer'),
    ];

    final results = await Future.wait(futures, eagerError: false);
    final seen = <String>{};
    final merged = <MuzoItem>[];
    for (final batch in results) {
      for (final item in batch) {
        final key = item.title.toLowerCase().trim();
        if (item.title.isEmpty) continue;
        if (seen.add(key)) merged.add(item);
      }
    }
    debugPrint(
        'MultiApi.discover: "$query" -> ${merged.length} titles '
        '(${futures.length} sources)');
    return merged;
  }

  /// Resolve discovered titles to real, playable YouTube tracks using the
  /// main ytify search. Bounded to [max] resolutions, run in a small worker
  /// pool (the search endpoint can't absorb 60+ parallel bursts), deduplicated
  /// by videoId. Returns only playable items — in the input order.
  Future<List<MuzoItem>> resolveToPlayable(
    List<MuzoItem> discovered, {
    int max = 8,
  }) async {
    final items = discovered.take(max).toList();
    final playable = <MuzoItem>[];
    final seenIds = <String>{};
    var cursor = 0;
    const workers = 6;

    Future<void> runWorker() async {
      while (true) {
        final i = cursor++;
        if (i >= items.length) break;
        final resolved = await _resolveOne(items[i]);
        for (final item in resolved) {
          if (item.videoId != null && seenIds.add(item.videoId!)) {
            playable.add(item);
          }
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workers, (_) => runWorker()),
    );
    debugPrint('MultiApi.resolveToPlayable: ${playable.length} playable');
    return playable;
  }

  /// Resolves a single metadata seed to a playable YouTube track.
  /// Returns null when no playable match is found.
  Future<MuzoItem?> resolveSingle(MuzoItem item) async {
    final resolved = await _resolveOne(item);
    return resolved.isNotEmpty ? resolved.first : null;
  }

  Future<List<MuzoItem>> _resolveOne(MuzoItem item) async {
    final artist = item.displayArtist;
    final base = item.title.trim();
    if (base.isEmpty) return const <MuzoItem>[];

    final q =
        (artist.isEmpty || artist == 'Unknown') ? base : '$base $artist';
    // One retry: a transient search failure / empty first pass used to
    // drop the release entirely, leaving a hole in the shelf.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await api.search(q, filter: 'songs');
        final results = resp.results
            .where((r) => r.videoId != null)
            .toList();
        if (results.isEmpty) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            continue;
          }
          return const <MuzoItem>[];
        }
        final best = results.first;
        final existing = results.indexWhere(
          (r) => r.title.toLowerCase() == base.toLowerCase(),
        );
        var chosen = existing >= 0 ? results[existing] : best;
        // Preserve the original source cover art (e.g. the Deezer album art)
        // when the resolved YouTube item ships without any thumbnail, so the
        // release cards never show an empty placeholder.
        if (chosen.thumbnails.isEmpty) {
          chosen = chosen.copyWith(
            thumbnails: item.thumbnails.isNotEmpty
                ? item.thumbnails
                : chosen.thumbnails,
          );
        }
        // Keep seed provenance (release date / curated-RSS source) so
        // "Nouvelles sorties" can still filter by the real drop date after
        // YouTube resolution.
        if (chosen.releaseDate == null && item.releaseDate != null) {
          chosen = chosen.copyWith(releaseDate: item.releaseDate);
        }
        if (chosen.source == null || chosen.source == 'youtube') {
          if (item.source != null) {
            chosen = chosen.copyWith(
              source: item.source,
              sourceId: item.sourceId ?? chosen.sourceId,
            );
          }
        }
        return [chosen];
      } catch (e) {
        debugPrint(
            'MultiApi.resolve error for "$q" (attempt ${attempt + 1}): $e');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return const <MuzoItem>[];
      }
    }
    return const <MuzoItem>[];
  }

  Future<List<MuzoItem>> _safe(
    Future<List<MuzoItem>> Function() fn,
    String source,
  ) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('MultiApi[$source] error: $e');
      return [];
    }
  }
}