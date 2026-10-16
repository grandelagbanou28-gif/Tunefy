import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/concert_event.dart';
import 'package:muzo/services/concert_service.dart';

/// Day number used to stamp the Gemini quota marker.
int _today() => DateTime.now().difference(DateTime.utc(2020, 1, 1)).inDays;

/// Cached concert list for one artist, upcoming first.
///
/// Three rules keep this inside a 20-requests-per-day Gemini budget:
/// 1. one `searchEvents` call per page (the service itself runs the extra
///    angled passes) — never a second full call to "top up";
/// 2. empty answers are cached too, so an artist with no known dates does not
///    re-ask on every visit;
/// 3. once Gemini answers 429 the day is stamped in Hive, so the block
///    survives a restart instead of costing one wasted request per launch.
final artistConcertsProvider =
    FutureProvider.family<List<ConcertEvent>, String>((ref, artist) async {
  final name = artist.trim();
  if (name.isEmpty) return const [];

  final cacheKey = 'concerts_${name.toLowerCase()}';
  final quotaKey = 'concert_gemini_blocked_day';
  Box? box;
  try {
    box = Hive.box('artist_songs_cache');
    // Re-apply today's quota block before asking anything.
    if (box.get(quotaKey) == _today()) {
      ConcertService.geminiQuotaBlocked = true;
    } else {
      ConcertService.geminiQuotaBlocked = false;
    }

    final cached = box.get(cacheKey) as Map?;
    if (cached != null) {
      final ts = cached['ts'] as int? ?? 0;
      final list = (cached['events'] as List?) ?? [];
      // A full answer is worth a day. A thin one used to expire after an hour,
      // which re-asked immediately and burned the quota for nothing: six
      // hours is the shortest delay that still gives a real chance to change.
      final maxAgeHours = list.length < kMinConcerts ? 6 : 24;
      if (DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(ts))
              .inHours <
          maxAgeHours) {
        final events = list
            .whereType<Map>()
            .map((m) => ConcertEvent.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        if (events.isNotEmpty) return ConcertService.sortUpcomingFirst(events);
        if (list.isEmpty) return const []; // known-empty, do not re-ask
      }
    }
  } catch (_) {}

  var events = await ConcertService.instance.searchEvents(name, limit: 24);
  events = ConcertService.sortUpcomingFirst(events);

  if (box != null) {
    try {
      if (ConcertService.geminiQuotaBlocked) {
        await box.put(quotaKey, _today());
      }
      // An empty list is normally stored as the answer, not a failure. The one
      // exception: when no source was configured (build-time keys absent), an
      // empty result is meaningless and must NOT be cached, otherwise the
      // artist stays empty for hours even after the keys are injected.
      final worthCaching =
          events.isNotEmpty || ConcertService.isConfigured;
      if (worthCaching) {
        await box.put(cacheKey, {
          'ts': DateTime.now().millisecondsSinceEpoch,
          'events': events.map((e) => e.toJson()).toList(),
        });
      }
    } catch (_) {}
  }
  return events;
});
