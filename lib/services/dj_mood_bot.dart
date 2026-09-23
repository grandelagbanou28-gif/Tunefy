import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/dj_mood_service.dart';
import 'package:muzo/services/dj_mood_tracker.dart';
import 'package:muzo/services/dj_taste_profile.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';

/// Tunefy DJ — chat d'humeur.
///
/// Le DJ lit le message de l'utilisateur (ex. « je suis triste », « energie ! »,
/// « enfantine »…), détecte une humeur parmi [DjMood], puis constitue une
/// sélection à partir du VRAI catalogue : chaque humeur est associée à des
/// recherches réelles (itunes/youtube/deezer via MuzoApiService), dédoublonnées,
/// et triées par proximité d'humeur d'artiste (DjMoodService/MusicBrainz).
/// Rien n'est inventé : le DJ ne fabrique jamais une chanson.
enum DjMood {
  energetic(0.8, 0.78),
  calm(0.55, 0.2),
  sad(0.3, 0.35),
  happy(0.85, 0.72),
  focus(0.5, 0.35),
  love(0.75, 0.45),
  nostalgia(0.5, 0.5),
  sleep(0.45, 0.1);

  /// Polarité de l'humeur `(valence, energy)` au sens DjMoodService, utilisée
  /// pour trier le pool réel par compatibilité émotionnelle.
  final double valence;
  final double energy;

  const DjMood(this.valence, this.energy);
}

class DjMoodBot {
  final WidgetRef ref;
  final DjMoodService _mood = DjMoodService();
  final DjMoodTracker tracker = DjMoodTracker();
  late final DjTasteProfile _taste =
      DjTasteProfile(ref.read(storageServiceProvider));

  DjMoodBot(this.ref);

  /// Nombre de morceaux pour une durée en minutes (scale Freedify) :
  /// 1h ≈ 15, 2h ≈ 30, 2.5h ≈ 37, 4h ≈ 60 → ~1 morceau / 4 minutes.
  static int trackCountForMinutes(int minutes) {
    final m = minutes.clamp(15, 240);
    return (m / 4).round().clamp(4, 60);
  }

  /// Durées prédéfinies (minutes) pour le duration picker.
  static const List<int> durationChoices = [30, 60, 90, 120, 150, 240];

  static String _stripAccents(String s) {
    const map = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'æ': 'ae',
      'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
    };
    var r = s;
    for (final e in map.entries) {
      r = r.replaceAll(e.key, e.value);
    }
    return r;
  }

  static String _norm(String s) =>
      _stripAccents(s.trim().toLowerCase()).replaceAll(RegExp(r"['’\-]"), '');

  /// Ordre de priorité pour départager les humeurs à score égal.
  static const List<DjMood> _priority = [
    DjMood.energetic,
    DjMood.happy,
    DjMood.calm,
    DjMood.sad,
    DjMood.love,
    DjMood.focus,
    DjMood.nostalgia,
    DjMood.sleep,
  ];

  /// Mots-clés d'humeur (normalisés, sans accents). Saisie libre en FR/EN plus
  /// quelques tournures orales — jamais de données fabriquées.
  static const Map<DjMood, List<String>> _keywords = {
DjMood.energetic: [
      'energie', 'energique', 'energizer', 'energy', 'energetic',
      'energised', 'energized', 'energising', 'booster', 'boost', 'booste',
      'sport', 'gym', 'workout', 'entrainement', 'entrainer', 'santrainer',
      'trainer', 'motivation', 'motive', 'motiver', 'bouger', 'danse',
      'danser', 'dechaine', 'pump', 'high', 'entrain', 'en feu', 'survolt',
      'foufou',
    ],
DjMood.calm: [
      'calme', 'calm', 'tranquille', 'relax', 'relaxer', 'relaxe', 'detente',
      'detendre', 'zen', 'doux', 'douce', 'soft', 'chill', 'pose', 'paisible',
      'repos', 'reposer', 'serenite', 'doucement', 'peace', 'apaisant',
      'apaisante',
    ],
    DjMood.sad: [
      'triste', 'tristesse', 'pleurer', 'pleure', 'pleurs', 'mal', 'deprim',
      'melancoliqu', 'melancolie', 'blesse', 'blessee', 'casse', 'cassee',
      'coeur brise', 'manque', 'sad', 'down', 'blue', 'tears', 'crying',
      'cry', 'vide', 'abandonne', 'seul', 'seule', 'chagrin', 'peine',
    ],
    DjMood.happy: [
      'heureux', 'heureuse', 'content', 'contente', 'joie', 'joyeux',
      'joyeuse', 'fete', 'feter', 'ambiance', 'party', 'fun', 'bonne humeur',
      'bonheur', 'gai', 'celebrer', 'anniversaire', 'mariage', 'happy',
      'joy', 'radieux', 'radieuse',
    ],
    DjMood.focus: [
      'focus', 'concentration', 'concentrer', 'concentre', 'concentree',
      'travailler', 'travail', 'bosser', 'bureau', 'etude', 'etudier',
      'etudie', 'reviser', 'revision', 'studying', 'study', 'homework',
      'pomodoro', 'lire', 'ecrire', 'au calme',
    ],
    DjMood.love: [
      'amour', 'love', 'romantique', 'romance', 'coeur', 'coup de coeur',
      'crush', 'je taime', 'couple', 'saint valentin', 'flirt', 'drague',
      'craquer', 'tendre',
    ],
DjMood.nostalgia: [
      'nostalgie', 'nostalgia', 'nostalgique', 'nostalgic', 'souvenirs',
      'souvenir', 'vieux', 'vieille ecole', 'old school', 'classique',
      'retro', 'back in the day', 'enfance', 'jeunesse', 'annees', 'retour',
      'rembobine', '90', '2000', 'bon vieux temps', 'ancien', 'ancienne',
    ],
    DjMood.sleep: [
      'dormir', 'sommeil', 'nuit', 'coucher', 'endormir', 'somnoler',
      'sleep', 'bedtime', 'insomnie', 'fatigue', 'fatiguee', 'tired',
      'epuise', 'epuisee', 'detendre avant dormir',
    ],
  };

  /// Recherches réelles du catalogue pour chaque humeur. Le DJ pioche donc
  /// dans de vraies pistes trouvées par ces termes sur iTunes/YouTube/Deezer.
  /// When [count] is large (50–60), extra query variants run so the pool can
  /// fill a full long mix without inventing tracks.
  static const Map<DjMood, List<String>> _queries = {
    DjMood.energetic: ['workout', 'electro', 'motivation'],
    DjMood.calm: ['chill', 'ambient', 'acoustic'],
    DjMood.sad: ['sad songs', 'melancholic', 'ballad'],
    DjMood.happy: ['happy', 'party', 'afrobeats'],
    DjMood.focus: ['focus', 'instrumental', 'lofi beats'],
    DjMood.love: ['love songs', 'romance', 'romantic'],
    DjMood.nostalgia: ['old school', 'classics', '2000s hits'],
    DjMood.sleep: ['sleep', 'deep sleep', 'night relaxing'],
  };

  /// Overflow queries used only when the primary set is too small for a
  /// long mix (50+). Still real catalog searches — nothing fabricated.
  static const Map<DjMood, List<String>> _overflowQueries = {
    DjMood.energetic: ['cardio', 'hype', 'dance fitness'],
    DjMood.calm: ['lofi chill', 'piano calm', 'nature sounds'],
    DjMood.sad: ['heartbreak', 'emotional', 'rain songs'],
    DjMood.happy: ['feel good', 'summer hits', 'good vibes'],
    DjMood.focus: ['study beats', 'deep focus', 'coding music'],
    DjMood.love: ['valentine', 'sweet love', 'acoustic love'],
    DjMood.nostalgia: ['90s hits', '2000s pop', 'oldies'],
    DjMood.sleep: ['white noise', 'sleep music', 'meditation'],
  };

  /// Détecte l'humeur dominante d'un message libre. Retourne null si aucune
  /// humeur n'est reconnaissable (le DJ demande alors de reformuler).
  DjMood? detect(String message) {
    final text = _norm(message);
    if (text.isEmpty) return null;

    var bestScore = 0;
    DjMood? best;
    for (final mood in _priority) {
      var score = 0;
      for (final kw in _keywords[mood]!) {
        if (text.contains(kw)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = mood;
      }
    }
    return best;
  }

  static String _key(MuzoItem s) =>
      (s.videoId ?? '${s.title}|${s.displayArtist}').toLowerCase();

  /// Construit une sélection réelle pour [mood] : recherche catalogue (3
  /// requêtes parallèles), dédoublonnage, puis tri par :
  /// 1. compatibilité d'humeur d'artiste (MusicBrainz),
  /// 2. score de mood tracking (liked + / disliked −) pour cette humeur,
  /// 3. affinité de goût (historique d'écoute).
  /// Rien d'inventé.
  Future<List<MuzoItem>> buildSet(
    DjMood mood, {
    required Set<String> seenKeys,
    int count = 12,
  }) async {
    if (count <= 0) return const [];

    final api = ref.read(muzoApiServiceProvider);
    Future<List<MuzoItem>> runQuery(String q) async {
      try {
        final r = await api
            .search(q, filter: 'songs')
            .timeout(const Duration(seconds: 14));
        return r.results;
      } catch (_) {
        return <MuzoItem>[];
      }
    }

    var batches = await Future.wait(_queries[mood]!.map(runQuery));

    final uniq = <MuzoItem>[];
    final seenTitles = <String>{};
    void absorb(List<MuzoItem> results) {
      for (final s in results) {
        if (s.videoId == null) continue;
        final k = _key(s);
        if (seenKeys.contains(k)) continue;
        final t = '${s.title}|${s.displayArtist}'.toLowerCase();
        if (seenTitles.contains(t)) continue;
        seenTitles.add(t);
        uniq.add(s);
      }
    }

    for (final r in batches) {
      absorb(r);
    }

    // Long mixes (50+) may need overflow catalog searches.
    if (uniq.length < count) {
      final overflow = await Future.wait(
        (_overflowQueries[mood] ?? const <String>[]).map(runQuery),
      );
      for (final r in overflow) {
        absorb(r);
      }
    }

    if (uniq.isEmpty) return const [];

    // 1) Base : tri par proximité d'humeur d'artiste.
    var ordered = await _mood.orderForMood(
      List.of(uniq),
      referenceMood: (mood.valence, mood.energy),
      mode: 'continuous',
    );

    // 2) Mood tracking : ban les disliked (-), boost léger les liked (+).
    try {
      final feedback = await tracker.feedbackMap(mood.name);
      if (feedback.isNotEmpty) {
        ordered = List.of(ordered)
          ..sort((a, b) {
            final sa = feedback[_key(a)] ?? 0;
            final sb = feedback[_key(b)] ?? 0;
            if (sa != sb) return sb.compareTo(sa); // + d'abord
            return 0;
          });
        ordered = ordered.where((s) => (feedback[_key(s)] ?? 0) > -3).toList();
      }
    } catch (_) {}

    // 3) Taste profile : boost les artistes fréquemment écoutés.
    try {
      final weights = _taste.artistWeights();
      if (weights.isNotEmpty) {
        ordered = List.of(ordered)
          ..sort((a, b) {
            final wa = weights[_primaryLower(a)] ?? 0;
            final wb = weights[_primaryLower(b)] ?? 0;
            return wb.compareTo(wa);
          });
      }
    } catch (_) {}

    return ordered.take(count).toList();
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
