import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/muzo_api_service.dart';

/// New-release clip queries — searched FIRST so the feed and the Browse-all
/// cards prioritize fresh drops, exactly like YouTube Shorts surfaces recent
/// videos. Every genre is covered afterwards.
const List<String> kNewReleaseClipQueries = [
  'new music video',
  'nouveau clip officiel',
  'new release clip',
  'new drop music video',
  'clip nouvelle chanson',
  'latest music video',
  'nouveau clip 2026',
  'new single music video',
];

/// Curated clip queries — short music videos across the app's genres. The
/// feed mixes every query so vertical swiping always lands on something new.
const List<String> kClipQueries = [
  ...kNewReleaseClipQueries,
  'rap clip officiel',
  'afrobeats music video',
  'amapiano video',
  'pop clip',
  'rumba congolaise clip',
  'gospel clip',
  'dancehall video',
  'rap francais clip',
  'musique arabe clip',
  'latin music video',
  'jazz live session',
  'electronic music video',
  'metal live clip',
  'reggae video',
  'soul live performance',
];

/// One query's station: its query text and the next continuation token to
/// page deeper into the same query (unlimited depth per query).
class _ClipStation {
  _ClipStation(this.query);

  final String query;
  String? token;
  int fetchedPages = 0;

  /// Bumped every time the backend has no more pages for [query]; the next
  /// pass searches a rotated variant so the feed keeps producing clips.
  int rotation = 0;
}

/// Appended to a query once it has been rotated, so the search engine is
/// asked for something new instead of replaying the same first page.
const List<String> kClipQueryVariants = [
  '',
  ' 2026',
  ' officiel',
  ' hd',
  ' live',
  ' remix',
  ' acoustic',
  ' lyrics',
];

String _rotatedQuery(_ClipStation station) {
  final suffix =
      kClipQueryVariants[station.rotation % kClipQueryVariants.length];
  return '${station.query}$suffix';
}

final clipsFeedProvider =
    StateNotifierProvider<ClipsFeedNotifier, AsyncValue<List<MuzoItem>>>(
        (ref) => ClipsFeedNotifier(ref));

class ClipsFeedNotifier extends StateNotifier<AsyncValue<List<MuzoItem>>> {
  ClipsFeedNotifier(this._ref) : super(const AsyncValue.loading()) {
    loadMore();
  }

  final Ref _ref;
  bool _fetching = false;
  static const int _batchStations = 3;
  static const int _maxPagesPerStation = 40;

  /// Unlimited stations: seeded from `kClipQueries`, then rotated forever so
  /// the scroll never runs dry. Each station pages deep via continuation
  /// tokens, so the worker keeps surfacing fresh clips for every query.
  final List<_ClipStation> _stations = [];
  int _cursor = 0;

  final List<MuzoItem> _all = [];
  final Set<String> _ids = {};

  /// Lazy seeding so construction stays cheap and the first call is fast.
  void _ensureStations() {
    if (_stations.isNotEmpty) return;
    _stations.addAll(kClipQueries.map((q) => _ClipStation(q)));
  }

  Future<void> loadMore() async {
    if (_fetching) return;
    _fetching = true;
    _ensureStations();
    try {
      final api = _ref.read(muzoApiServiceProvider);
      final added = <MuzoItem>[];

      for (var i = 0; i < _batchStations && _stations.isNotEmpty; i++) {
        final station = _stations[_cursor % _stations.length];
        _cursor++;
        try {
          final res = await api.search(
            _rotatedQuery(station),
            filter: 'videos',
            continuationToken: station.token,
            shortOnly: true,
          );
          for (final item in res.results) {
            // Keep it a "clip": real videos, roughly short-form, deduped.
            // Filter is intentionally loose (>= 0 keeps unknown durations):
            // a tight 15-55s window used to starve the shelf of clips.
            final dur = item.durationSeconds ?? 0;
            if (item.videoId == null) continue;
            if (dur > 360) continue;
            if (_ids.contains(item.videoId)) continue;
            _ids.add(item.videoId!);
            added.add(item);
          }
          // Page deeper into this station next time we land on it. When the
          // engine runs dry the station is re-seeded with a rotated query so
          // the feed is genuinely unbounded instead of stopping at the last
          // page the backend had.
          final next = res.continuationToken;
          station.fetchedPages++;
          if (next != null &&
              next.isNotEmpty &&
              station.fetchedPages < _maxPagesPerStation) {
            station.token = next;
          } else {
            station.rotation++;
            station.token = null;
            station.fetchedPages = 0;
          }
        } catch (_) {
          // One dead station must not kill the feed: rotate it and move on.
          station.rotation++;
          station.token = null;
          station.fetchedPages = 0;
        }
      }

      _all.addAll(added);
      if (added.isEmpty) return;
      state = AsyncValue.data(List<MuzoItem>.from(_all));
    } catch (e, st) {
      if (_all.isEmpty) {
        state = AsyncValue.error(e, st);
      }
    } finally {
      _fetching = false;
    }
  }

  /// True when the user swiped close to the end and more clips are needed.
  /// The buffer is generous (20, not 8): a burst of fast swipes must never
  /// outrun the fetch, or the feed would stop dead mid-scroll.
  bool get shouldLoadMore {
    final list = state.value;
    return list != null && list.length - _lastRequestedIndex < 20;
  }

  int _lastRequestedIndex = -1;

  void onPageChanged(int index) {
    // Idempotent per index: callers fire this from scroll listeners, and a
    // rebuild that asks again for the same index must not queue another fetch.
    if (index == _lastRequestedIndex) return;
    _lastRequestedIndex = index;
    if (shouldLoadMore) {
      // Keep topping up until the user is comfortably far from the end.
      unawaited(_fillBuffer());
    }
  }

  /// Chains fetches while the visible tail is still too close to the end.
  Future<void> _fillBuffer() async {
    for (var i = 0; i < 3 && shouldLoadMore; i++) {
      await loadMore();
    }
  }
}