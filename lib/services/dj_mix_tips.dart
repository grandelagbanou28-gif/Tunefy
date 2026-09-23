import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/dj_mood_service.dart';
import 'package:muzo/services/gemini_service.dart';

final djMixTipsProvider = Provider<DjMixTips>((ref) {
  return DjMixTips(gemini: ref.read(geminiServiceProvider));
});

/// Tunefy DJ — mix analysis locale (Freedify « Mix Analysis » / « DJ Mode »).
///
/// Compare les fingerprints d'humeur (valence, energy) de deux morceaux
/// consécutifs via [DjMoodService] (MusicBrainz genres, cache Hive) et
/// produit un conseil de transition 100% local : durée de crossfade conseillée,
/// type de transition, et un warning si le saut d'énergie est brutal.
///
/// Aucune donnée n'est inventée : si un mood manque, on renvoie null (pas de
/// tip bidon). Le tip est une heuristique — pas un vrai Camelot key/BPM.
class DjMixTips {
  final GeminiService? gemini;
  final DjMoodService _mood = DjMoodService();

  DjMixTips({this.gemini});

  /// Analyse la transition [from] → [to]. Essaie d'abord Gemini (si configuré),
  /// sinon fallback 100% local (MusicBrainz). Null si rien n'est fiable.
  Future<DjMixTip?> analyze(MuzoItem from, MuzoItem to) async {
    final ai = await _analyzeWithGemini(from, to);
    if (ai != null) return ai;
    return _analyzeLocal(from, to);
  }

  /// Freedify « AI-powered DJ tips » via Gemini. Returns null when the API
  /// is down, the JSON is invalid, or values are out of range — never invents.
  Future<DjMixTip?> _analyzeWithGemini(MuzoItem from, MuzoItem to) async {
    final g = gemini;
    if (g == null) return null;
    try {
      if (!g.isConfigured) return null;
      final local = await _analyzeLocal(from, to);
      if (local == null) return null;

      final json = await g.completeJson('''
You are Tunefy DJ. Analyze this transition between two real tracks.
Return ONLY JSON:
{
  "transitionType": one of blend|buildup|breakdown|harmonic_contrast|cut,
  "crossfadeSeconds": integer 1..8,
  "warningBrutalJump": true|false,
  "advice": "one short practical tip in French"
}
from: "${from.title}" by ${from.displayArtist} (local type=${local.transitionType}, energyDelta=${local.energyDelta})
to: "${to.title}" by ${to.displayArtist}
''');
      if (json == null) return null;
      final type = (json['transitionType'] as String?)?.trim() ?? '';
      const allowed = {
        'blend',
        'buildup',
        'breakdown',
        'harmonic_contrast',
        'cut',
      };
      if (!allowed.contains(type)) return null;
      final sec = (json['crossfadeSeconds'] as num?)?.round();
      if (sec == null) return null;
      final warning = json['warningBrutalJump'] == true;
      final advice = (json['advice'] as String?)?.trim();
      return DjMixTip(
        crossfadeSeconds: sec.clamp(1, 8),
        transitionType: type,
        energyDelta: local.energyDelta,
        moodDistance: local.moodDistance,
        warningBrutalJump: warning,
        fromMood: local.fromMood,
        toMood: local.toMood,
        aiAdvice: advice,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DjMixTip?> _analyzeLocal(MuzoItem from, MuzoItem to) async {
    try {
      final a = await _mood.artistMood(from.displayArtist);
      final b = await _mood.artistMood(to.displayArtist);
      if (a == null || b == null) return null;

      final dE = (b.$2 - a.$2).abs();
      final dV = (b.$1 - a.$1).abs();
      final energyDelta = b.$2 - a.$2; // + = montée, - = descente

      // Crossfade : plus les moods sont proches, plus on peut faire long.
      // 0.05 → ~1s ; 0.4+ → fondue courte ou cut.
      final crossfadeSec = (1.0 + (0.4 - dE.clamp(0, 0.4)) * 10).round();

      final type = _transitionType(dE, dV, energyDelta);
      final warning = dE >= 0.35;

      return DjMixTip(
        crossfadeSeconds: crossfadeSec.clamp(1, 8),
        transitionType: type,
        energyDelta: energyDelta,
        moodDistance: dE + dV,
        warningBrutalJump: warning,
        fromMood: a,
        toMood: b,
      );
    } catch (_) {
      return null;
    }
  }

  String _transitionType(double dE, double dV, double energyDelta) {
    if (dE < 0.12 && dV < 0.15) return 'blend'; // fondue douce
    if (energyDelta >= 0.25) return 'buildup'; // montée → filter/build-up
    if (energyDelta <= -0.25) return 'breakdown'; // descente → drop/outro
    if (dV >= 0.3) return 'harmonic_contrast'; // même énergie, autre polarité
    return 'cut'; // pas d'affinité forte → cut net
  }

  /// Texte localisé minimal pour l'instant (l10n côté UI).
  String labelOf(String type) {
    switch (type) {
      case 'blend':
        return 'Smooth blend';
      case 'buildup':
        return 'Energy build-up';
      case 'breakdown':
        return 'Smooth breakdown';
      case 'harmonic_contrast':
        return 'Contrast transition';
      default:
        return 'Clean cut';
    }
  }
}

class DjMixTip {
  final int crossfadeSeconds;
  final String transitionType;
  final double energyDelta;
  final double moodDistance;
  final bool warningBrutalJump;
  final (double, double) fromMood;
  final (double, double) toMood;
  final String? aiAdvice;

  const DjMixTip({
    required this.crossfadeSeconds,
    required this.transitionType,
    required this.energyDelta,
    required this.moodDistance,
    required this.warningBrutalJump,
    required this.fromMood,
    required this.toMood,
    this.aiAdvice,
  });
}
