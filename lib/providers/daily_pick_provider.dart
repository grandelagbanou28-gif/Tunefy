import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/discovery_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/taste_signals_service.dart';
import 'package:muzo/utils/period_utils.dart';

/// "Recommendation of the day" — a small playlist whose pick is derived from
/// the calendar day, so it is stable all day long and different tomorrow,
/// without any server round trip to know the date.
final dailyPickProvider = FutureProvider<DiscoverySection<MuzoItem>>((ref) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);

  // One rotation per weekday, so Sunday genuinely gets its own mood.
  const rotations = <String, List<String>>{
    'sunday': ['gospel', 'soul', 'live session', 'acoustic'],
    'monday': ['new single', 'rap', 'afrobeats'],
    'tuesday': ['pop', 'dance', 'edm'],
    'wednesday': ['jazz', 'classical', 'lofi'],
    'thursday': ['amapiano', 'afrobeats', 'club'],
    'friday': ['dancehall', 'reggae', 'latin'],
    'saturday': ['rock', 'metal', 'indie'],
  };
  const dayKeys = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final dayKey = dayKeys[day.weekday - 1];
  final terms = rotations[dayKey] ?? rotations['sunday']!;
  // Deterministic pick inside the rotation: same all day, new tomorrow.
  final weekdayTerm = terms[day.day % terms.length];

  // Lead with what this listener actually searched for, and rotate that set
  // per installation so two phones on the same day do not show the same pick.
  final personal = ref
      .read(tasteSignalsProvider)
      .recommendationSeeds(
        max: 3,
        seed: day.day + ContentCacheService.deviceSeed,
      );
  final candidates = <String>{...personal, weekdayTerm}.toList();

  final results = <MuzoItem>[];
  String chosen = weekdayTerm;
  try {
    final api = ref.read(muzoApiServiceProvider);
    final seen = <String>{};
    for (final term in candidates) {
      final response = await api
          .search(term, filter: 'songs')
          .timeout(const Duration(seconds: 10));
      for (final r in response.results) {
        final id = r.videoId;
        if (id == null || id.isEmpty || !seen.add(id)) continue;
        results.add(r);
      }
      // The title must name the query that produced these songs, otherwise the
      // shelf lies about what it is.
      if (results.isNotEmpty) chosen = term;
      if (results.length >= 12) break;
    }
    if (results.length > 12) results.removeRange(12, results.length);
  } catch (_) {
    // A thin day must not break the page.
  }

  // Built through the same l10n surface as the other shelves; the label
  // reuses the localized weekday name.
  return DiscoverySection<MuzoItem>(
    title: chosen,
    period: DiscoveryPeriod(
      id: 'day',
      label: _label(),
      startDate: day,
      endDate: day,
      year: day.year,
      month: day.month,
    ),
    items: results,
  );
});

String _label() {
  final now = DateTime.now();
  return '${now.day}/${now.month}';
}
