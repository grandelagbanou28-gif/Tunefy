import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Tunefy DJ — mood tracking local (100% offline).
///
/// Reprend la feature Freedify « Mood Tracking » : un morceau écouté à plus
/// de 75 % est marqué `liked`, un morceau sauté early est marqué `disliked`
/// pour l'humeur active. Le DJ réutilise ensuite ces préférences pour
/// personnaliser les prochaines générations (boost liked, ban/disliked).
///
/// Persistance Hive box `dj_mood_feedback` : `{mood: {trackKey: +1|-1}}`.
class DjMoodTracker {
  static const String _boxName = 'dj_mood_feedback';
  static const int _likedThresholdPct = 75;

  Box? _box;

  /// Dernière position observée par trackKey (ms joués) — mémoire session.
  final Map<String, int> _playedMs = {};
  final Map<String, int> _durationMs = {};
  String? _activeMood;

  Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  /// Passe en session d'humeur [mood] (null = hors session DJ).
  void setActiveMood(String? mood) {
    _activeMood = mood?.trim().isEmpty == true ? null : mood;
    _playedMs.clear();
    _durationMs.clear();
  }

  String? get activeMood => _activeMood;

  static String trackKey(String videoId, String title, String artist) =>
      (videoId.isNotEmpty ? videoId : '$title|$artist').toLowerCase();

  /// Alimente la progression de lecture du morceau courant (appelé depuis le
  /// player / DJ screen sur `positionStream`).
  void noteProgress({
    required String key,
    required int positionMs,
    required int durationMs,
  }) {
    if (key.isEmpty || durationMs <= 0) return;
    final prev = _playedMs[key] ?? 0;
    if (positionMs > prev) _playedMs[key] = positionMs;
    _durationMs[key] = durationMs;
  }

  /// Appelé à chaque changement de piste : score la piste précédente.
  /// - position ≥ 75 % de la durée → liked
  /// - position < 25 % de la durée → disliked (skip early)
  /// - sinon neutre (jamais de faux signal).
  Future<void> scorePreviousTrack({
    required String prevKey,
    String? mood,
  }) async {
    final target = (mood ?? _activeMood)?.trim();
    if (target == null || target.isEmpty || prevKey.isEmpty) return;
    final played = _playedMs[prevKey] ?? 0;
    final total = _durationMs[prevKey] ?? 0;
    if (total <= 0 || played <= 0) return;

    final pct = (played * 100) ~/ total;
    int? delta;
    if (pct >= _likedThresholdPct) {
      delta = 1;
    } else if (pct < 25) {
      delta = -1;
    }
    if (delta == null) return;
    await recordFeedback(target, prevKey, delta);
    _playedMs.remove(prevKey);
    _durationMs.remove(prevKey);
  }

  /// Score brut (+1 liked, -1 disliked) pour [trackKey] sous [mood].
  Future<int> scoreFor(String mood, String trackKey) async {
    try {
      final box = await _getBox();
      final moodMap = box.get(mood) as Map?;
      if (moodMap == null) return 0;
      return (moodMap[trackKey] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Ajoute un feedback (clampe à ±3 pour éviter qu'un like devienne indestructible).
  Future<void> recordFeedback(String mood, String trackKey, int delta) async {
    if (mood.isEmpty || trackKey.isEmpty || delta == 0) return;
    try {
      final box = await _getBox();
      final raw = box.get(mood);
      final map = <String, dynamic>{
        if (raw is Map) ...Map<String, dynamic>.from(raw),
      };
      final prev = (map[trackKey] as num?)?.toInt() ?? 0;
      var next = prev + delta;
      if (next > 3) next = 3;
      if (next < -3) next = -3;
      if (next == 0) {
        map.remove(trackKey);
      } else {
        map[trackKey] = next;
      }
      await box.put(mood, map);
    } catch (e) {
      debugPrint('DjMoodTracker.recordFeedback: $e');
    }
  }

  /// Map trackKey → score pour [mood] (découpe les forgotten ones très négatifs).
  Future<Map<String, int>> feedbackMap(String mood) async {
    try {
      final box = await _getBox();
      final raw = box.get(mood);
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  /// Nettoie les sessions / maps en mémoire (appelé à la fermeture du DJ).
  void endSession() {
    _activeMood = null;
    _playedMs.clear();
    _durationMs.clear();
  }

  /// Full wipe of the learned humeur feedback (« Tout effacer » du DJ).
  Future<void> clearAll() async {
    try {
      final box = await _getBox();
      await box.clear();
    } catch (e) {
      debugPrint('DjMoodTracker.clearAll: $e');
    }
    endSession();
  }
}
