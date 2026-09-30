import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/services/dj_mood_bot.dart';
import 'package:muzo/services/dj_mood_tracker.dart';
import 'package:muzo/services/dj_taste_profile.dart';
import 'package:muzo/services/gemini_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';

final djRadioServiceProvider = Provider<DjRadioService>((ref) {
  return DjRadioService(ref);
});

/// Tunefy DJ — AI Radio infinie (Freedify « AI Radio »).
///
/// When the queue drops under [refillThreshold] tracks, the service picks a
/// new batch via [DjEngine] (same artist + Fans also like, mood-sorted) from
/// the LAST playing track, deduping keys already seen (queue + session
/// history). Goal: the queue never dies while radio mode is on — no genre
/// drift because we always restart from the real track and the same curation
/// engine. When Gemini is configured, taste-aware artist seeds from the
/// listening history are merged into the refill (still resolved in the real
/// catalog — never invented tracks).
class DjRadioService {
  final Ref _ref;
  final DjMoodTracker tracker = DjMoodTracker();

  DjRadioService(this._ref);

  bool _enabled = false;
  bool _refilling = false;
  final Set<String> _seen = {};

  bool get enabled => _enabled;

  /// Active/désactive uniquement le refill automatique. Le mood tracking
  /// reste opérable même hors radio (session humeur posée par le chat DJ).
  void setEnabled(bool value, {DjMood? mood}) {
    _enabled = value;
    if (value && mood != null) {
      tracker.setActiveMood(mood.name);
    } else if (!value) {
      _seen.clear();
    }
  }

  /// Passe l'humeur active (chat DJ / changement de mood).
  void setMood(DjMood? mood) {
    tracker.setActiveMood(mood?.name);
  }

  /// Alimente la progression du morceau courant (à brancher sur positionStream).
  void noteProgress(MediaItemLike? media, int positionMs) {
    if (media == null) return;
    final key = DjMoodTracker.trackKey(media.id, media.title, media.artist);
    final durMs = media.durationMs;
    if (durMs == null || durMs <= 0) return;
    tracker.noteProgress(key: key, positionMs: positionMs, durationMs: durMs);
  }

  /// Score le morceau qui vient de se terminer / être sauté.
  Future<void> scoreCurrentAsPrevious(MediaItemLike? media) async {
    if (media == null) return;
    final key = DjMoodTracker.trackKey(media.id, media.title, media.artist);
    await tracker.scorePreviousTrack(prevKey: key);
    _seen.add(key);
  }

  /// Appelé quand la file se raccourcit : si radio active et file basse,
  /// refill depuis le dernier morceau (ou le seed si rien en lecture).
  Future<void> maybeRefill({
    required MuzoItem? anchor,
    int remaining = 3,
    int fetch = 8,
  }) async {
    if (!_enabled || _refilling) return;
    if (remaining > refillThreshold) return;
    if (anchor == null) return;

    _refilling = true;
    try {
      final handler = _ref.read(audioHandlerProvider);
      final sequence = handler.player.sequenceState?.sequence ?? const [];
      for (final s in sequence) {
        if (s.tag is MediaItem) {
          final m = s.tag as MediaItem;
          _seen.add(DjMoodTracker.trackKey(m.id, m.title, m.artist ?? ''));
        }
      }

      final primary = _primaryArtist(anchor);
      final picks = <MuzoItem>[];
      if (primary.isNotEmpty) {
        try {
          final own =
              await _ref.read(artistSongsProvider(primary).future);
          picks.addAll(_filter(own, fetch));
        } catch (_) {}
      }
      if (picks.length < fetch) {
        try {
          final related =
              await _ref.read(relatedArtistsProvider(primary).future);
          for (final ra in related.take(4)) {
            if (ra.title.trim().isEmpty) continue;
            try {
              final songs =
                  await _ref.read(artistSongsProvider(ra.title).future);
              picks.addAll(_filter(songs, fetch - picks.length));
            } catch (_) {}
            if (picks.length >= fetch) break;
          }
        } catch (_) {}
      }

      // Taste-aware AI Radio: Gemini seeds from local taste profile, resolved
      // through the real catalog. Fails open to the local-only refill above.
      if (picks.length < fetch) {
        final ai = await _tasteSeeds(anchor, primary);
        if (ai.isNotEmpty) {
          final api = _ref.read(muzoApiServiceProvider);
          for (final q in ai) {
            try {
              final r = await api
                  .search(q, filter: 'songs')
                  .timeout(const Duration(seconds: 12));
              picks.addAll(_filter(r.results, fetch - picks.length));
            } catch (_) {}
            if (picks.length >= fetch) break;
          }
        }
      }

      if (picks.isEmpty) return;

      final mood = tracker.activeMood;
      if (mood != null) {
        // Tri humeur déjà géré par le moteur DJ côté génération initiale ;
        // ici on garde l'ordre catalogue (priorité même artiste d'abord).
      }

      final playable = picks.take(fetch).toList();
      if (playable.isEmpty) return;
      final n = await handler.enqueueSongs(playable);
      debugPrint('[TunefyDJ Radio] refilled +$n (remaining was $remaining)');
    } catch (e) {
      debugPrint('DjRadioService.maybeRefill: $e');
    } finally {
      _refilling = false;
    }
  }

  int get refillThreshold => 3;

  /// Gemini taste-aware seeds for AI Radio. Returns [] when Gemini is
  /// unavailable or the reply is not valid JSON. Artist names only — the
  /// catalog search that follows never invents titles.
  Future<List<String>> _tasteSeeds(MuzoItem anchor, String primary) async {
    try {
      final gemini = _ref.read(geminiServiceProvider);
      if (!gemini.isConfigured) return const [];
      final storage = _ref.read(storageServiceProvider);
      final top = DjTasteProfile(storage).topArtists(limit: 12);
      final json = await gemini.completeJson('''
You power Tunefy DJ AI Radio. Propose catalog search seeds to refill the queue
around the current track without inventing songs.

Return ONLY JSON:
{"artistSeeds": ["2 to 6 real artist names", ...], "searchQueries": ["1 to 3 short phrases", ...]}

Current track: "${anchor.title}" by $primary
User taste top artists: ${top.join(', ')}
Active mood: ${tracker.activeMood ?? 'none'}
''');
      if (json == null) return const [];
      final out = <String>[];
      for (final key in ['artistSeeds', 'searchQueries']) {
        final v = json[key];
        if (v is List) {
          for (final s in v.whereType<String>()) {
            final t = s.trim();
            if (t.isNotEmpty) out.add(t);
          }
        }
      }
      return out.take(8).toList();
    } catch (e) {
      debugPrint('[Radio] tasteSeeds: $e');
      return const [];
    }
  }

  List<MuzoItem> _filter(List<MuzoItem> pool, int take) {
    final out = <MuzoItem>[];
    for (final s in pool) {
      if (out.length >= take) break;
      final k = DjMoodTracker.trackKey(
          s.videoId ?? '', s.title, s.displayArtist);
      if (k.isEmpty || _seen.contains(k)) continue;
      _seen.add(k);
      out.add(s);
    }
    return out;
  }

  String _primaryArtist(MuzoItem s) {
    final a = s.artists;
    if (a != null && a.isNotEmpty && a.first.name.isNotEmpty) {
      return a.first.name;
    }
    if (s.channelName != null && s.channelName!.isNotEmpty) {
      return s.channelName!;
    }
    final d = s.displayArtist;
    if (d.isEmpty || d.toLowerCase() == 'unknown') return '';
    final comma = d.indexOf(',');
    return comma > 0 ? d.substring(0, comma).trim() : d.trim();
  }

  void dispose() {
    tracker.endSession();
    _seen.clear();
    _enabled = false;
  }

  /// « Tout effacer » du DJ : radio off, session humeur et mémoire vue
  /// remises à zéro (les feedbacks appris restent dans Hive jusqu'au
  /// clearAll du tracker, appelé par l'écran).
  void reset() {
    _enabled = false;
    _refilling = false;
    _seen.clear();
    tracker.endSession();
  }
}

/// Minimal media info to avoid importing just_audio_background everywhere.
class MediaItemLike {
  final String id;
  final String title;
  final String artist;
  final int? durationMs;

  const MediaItemLike({
    required this.id,
    required this.title,
    required this.artist,
    this.durationMs,
  });
}
