import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/dj_mood_bot.dart';
import 'package:muzo/services/dj_mood_service.dart';
import 'package:muzo/services/dj_taste_profile.dart';
import 'package:muzo/services/gemini_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';

final djSmartPlaylistProvider = Provider<DjSmartPlaylistService>((ref) {
  return DjSmartPlaylistService(ref);
});

/// Freedify « Smart Playlist Generator » via Gemini.
///
/// User describes a vibe / activity / genre; Gemini returns real catalog
/// search seeds + artist names (never fake titles). Seeds are resolved
/// through [MuzoApiService.search], deduped, mood-ordered when a mood is
/// classified, then taste-re-ranked. Falls back to empty on any failure.
class DjSmartPlaylistService {
  final Ref _ref;

  DjSmartPlaylistService(this._ref);

  /// Free-text that looks like a smart-playlist request rather than a
  /// simple mood chip (handled by [DjMoodBot.detect]).
  static bool looksLikeSmartPlaylist(String raw) {
    final t = raw.toLowerCase().trim();
    if (t.length < 8) return false;
    const cues = [
      'playlist',
      'mix pour',
      'mix de',
      'faire un mix',
      'génère',
      'genere',
      'generate',
      'create a playlist',
      'make me a playlist',
      'build a playlist',
      'songs for',
      'tracks for',
      'musique pour',
      'sons pour',
      'pour un',
      'pour une',
      'road trip',
      'séance',
      'seance',
      'party pour',
      'focus pour',
      'soirée',
      'soiree',
    ];
    return cues.any(t.contains);
  }

  Future<List<MuzoItem>> build({
    required String prompt,
    required int durationMinutes,
    required Set<String> seenKeys,
    int? targetCount,
  }) async {
    final gemini = _ref.read(geminiServiceProvider);
    if (!gemini.isConfigured) return const [];

    final storage = _ref.read(storageServiceProvider);
    final taste = DjTasteProfile(storage);
    final top = taste.topArtists(limit: 15);
    final want = targetCount ?? DjMoodBot.trackCountForMinutes(durationMinutes);

    final system = '''
You are Tunefy DJ's Smart Playlist engine (Freedify-style).
Given a user request, a duration, and a taste profile, propose REAL music
catalog search seeds. Do NOT invent track titles or claim songs exist.

Return ONLY a JSON object:
{
  "title": "short playlist title (max 6 words)",
  "mood": one of energetic|calm|sad|happy|focus|love|nostalgia|sleep|"",
  "searchQueries": ["3 to 6 short catalog search phrases", ...],
  "artistSeeds": ["2 to 8 real artist names fitting the vibe", ...],
  "reason": "one short sentence in the same language as the user"
}

Duration: $durationMinutes minutes (~$want tracks).
User taste (top artists from listening history): ${top.join(', ')}.
User request: $prompt
''';

    final json = await gemini.completeJson(system);
    if (json == null) {
      debugPrint('[SmartPlaylist] Gemini returned no JSON');
      return const [];
    }

    final queries = _stringList(json['searchQueries']);
    final artists = _stringList(json['artistSeeds']);
    if (queries.isEmpty && artists.isEmpty) return const [];

    final api = _ref.read(muzoApiServiceProvider);
    final raw = <MuzoItem>[];

    Future<void> runSearch(String q) async {
      try {
        final r = await api
            .search(q, filter: 'songs')
            .timeout(const Duration(seconds: 14));
        raw.addAll(r.results);
      } catch (_) {}
    }

    await Future.wait([
      ...queries.map(runSearch),
      ...artists.take(5).map((a) => runSearch(a)),
    ]);

    final uniq = <MuzoItem>[];
    final seenTitles = <String>{};
    for (final s in raw) {
      if (s.videoId == null) continue;
      final k = (s.videoId ?? '${s.title}|${s.displayArtist}').toLowerCase();
      if (seenKeys.contains(k)) continue;
      final t = '${s.title}|${s.displayArtist}'.toLowerCase();
      if (seenTitles.contains(t)) continue;
      seenTitles.add(t);
      uniq.add(s);
    }
    if (uniq.isEmpty) return const [];

    var ordered = uniq;
    final moodName = (json['mood'] as String?)?.trim() ?? '';
    if (moodName.isNotEmpty) {
      final mood = _parseMood(moodName);
      if (mood != null) {
        try {
          ordered = await DjMoodService().orderForMood(
            List.of(uniq),
            referenceMood: (mood.valence, mood.energy),
            mode: 'continuous',
          );
        } catch (_) {}
      }
    }

    // Taste-aware: boost frequently listened artists from history.
    try {
      final weights = taste.artistWeights();
      if (weights.isNotEmpty) {
        ordered = List.of(ordered)
          ..sort((a, b) {
            final wa = weights[_primaryLower(a)] ?? 0;
            final wb = weights[_primaryLower(b)] ?? 0;
            return wb.compareTo(wa);
          });
      }
    } catch (_) {}

    return ordered.take(want).toList();
  }

  DjMood? _parseMood(String name) {
    for (final m in DjMood.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  List<String> _stringList(dynamic v) {
    if (v is List) {
      return v
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _primaryLower(MuzoItem s) {
    final a = s.artists;
    if (a != null && a.isNotEmpty && a.first.name.isNotEmpty) {
      return a.first.name.trim().toLowerCase();
    }
    if (s.channelName != null && s.channelName!.isNotEmpty) {
      return s.channelName!.trim().toLowerCase();
    }
    return s.displayArtist.trim().toLowerCase();
  }
}
