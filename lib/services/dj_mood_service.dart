import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/musicbrainz_service.dart';

/// DJ Tunefy — enchaîne les morceaux selon l'humour de l'ARTISTE.
///
/// Chaque artiste reçoit un fingerprint d'humeur `(valence, energy)` calculé à
/// partir de ses genres MusicBrainz (gratuit, sans clé) mappés via une table
/// locale genre → émotion. Le fingerprint est mis en cache dans un Hive box
/// `artist_moods` (TTL 30 jours) pour ne pas re-frapper l'API.
///
/// Deux modes de mix :
/// - `continuous` : garder la même humeur (enchaînement sans cassure)
/// - `journey`    : évoluer progressivement vers une humeur cible (chill → drop)
class DjMoodService {
  static const String _boxName = 'artist_moods';
  static const int _ttlMs = 30 * 24 * 60 * 60 * 1000; // 30 jours

  // ── Table genre → (valence, energy) ────────────────────────────────────────
  // valence 0..1 : triste/doux → joyeux/club
  // energy  0..1 : calme/ambient → intense/explosif
  static const Map<String, List<double>> _genreMood = {
    'lofi': [0.45, 0.18],
    'lo-fi': [0.45, 0.18],
    'ambient': [0.45, 0.10],
    'atmospheric': [0.45, 0.15],
    'chill': [0.55, 0.22],
    'chillout': [0.55, 0.22],
    'downtempo': [0.5, 0.25],
    'trip hop': [0.45, 0.3],
    'trip-hop': [0.45, 0.3],
    'jazz': [0.55, 0.35],
    'soul': [0.65, 0.45],
    'r&b': [0.65, 0.5],
    'rnb': [0.65, 0.5],
    'funk': [0.75, 0.6],
    'disco': [0.8, 0.6],
    'pop': [0.8, 0.65],
    'dance pop': [0.85, 0.7],
    'dance': [0.85, 0.72],
    'edm': [0.85, 0.78],
    'electronic': [0.7, 0.7],
    'house': [0.8, 0.75],
    'techno': [0.6, 0.8],
    'trance': [0.7, 0.8],
    'dubstep': [0.45, 0.82],
    'phonk': [0.4, 0.8],
    'hip hop': [0.6, 0.68],
    'hip-hop': [0.6, 0.68],
    'rap': [0.55, 0.7],
    'trap': [0.45, 0.72],
    'drill': [0.35, 0.78],
    'grime': [0.5, 0.75],
    'reggae': [0.75, 0.55],
    'dancehall': [0.8, 0.7],
    'afrobeat': [0.8, 0.72],
    'afrobeats': [0.8, 0.72],
    'amapiano': [0.7, 0.6],
    'bongo flava': [0.75, 0.65],
    'soca': [0.85, 0.68],
    'latin': [0.85, 0.7],
    'reggaeton': [0.75, 0.75],
    'salsa': [0.85, 0.65],
    'kizomba': [0.65, 0.5],
    'zouk': [0.7, 0.55],
    'couper decaler': [0.85, 0.75],
    'coupé-décalé': [0.85, 0.75],
    'african': [0.78, 0.7],
    'afro': [0.78, 0.7],
    'rock': [0.6, 0.72],
    'indie rock': [0.6, 0.6],
    'indie': [0.65, 0.55],
    'alternative': [0.6, 0.62],
    'pop rock': [0.75, 0.68],
    'punk': [0.5, 0.85],
    'punk rock': [0.5, 0.85],
    'garage': [0.45, 0.8],
    'grunge': [0.35, 0.75],
    'metal': [0.3, 0.88],
    'heavy metal': [0.3, 0.88],
    'metalcore': [0.25, 0.92],
    'death metal': [0.2, 0.95],
    'black metal': [0.15, 0.9],
    'acoustic': [0.55, 0.3],
    'singer-songwriter': [0.5, 0.32],
    'folk': [0.55, 0.35],
    'country': [0.6, 0.45],
    'blues': [0.45, 0.4],
    'gospel': [0.7, 0.55],
    'christian': [0.7, 0.5],
    'classical': [0.5, 0.2],
    'orchestral': [0.5, 0.3],
    'instrumental': [0.5, 0.35],
    'k-pop': [0.8, 0.72],
    'j-pop': [0.8, 0.7],
    'bollywood': [0.8, 0.68],
    'bhangra': [0.75, 0.72],
    'afro-house': [0.78, 0.74],
    'comedy': [0.85, 0.4],
    'soundtrack': [0.5, 0.4],
    'video game': [0.6, 0.5],
  };

  Box? _box;
  final Map<String, (double, double)?> _memoryCache = {};

  Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  /// Mood (valence, energy) d'un artiste. Rapide si en cache Hive/mémoire,
  /// sinon résolu via MusicBrainz (genres) et mis en cache.
  Future<(double, double)?> artistMood(String artistName) async {
    final key = artistName.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_memoryCache.containsKey(key)) return _memoryCache[key];

    try {
      final box = await _getBox();
      final raw = box.get(key);
      if (raw is Map) {
        final ts = (raw['ts'] as num?)?.toInt() ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - ts < _ttlMs) {
          final v = (raw['v'] as num?)?.toDouble();
          final e = (raw['e'] as num?)?.toDouble();
          if (v != null && e != null) {
            final mood = (v, e);
            _memoryCache[key] = mood;
            return mood;
          }
        }
      }

      // MusicBrainz genres → mood moyen (neutre si aucun genre reconnu).
      final info = await MusicBrainzService().findArtist(artistName.trim());
      if (info == null || info.genres.isEmpty) {
        _memoryCache[key] = null;
        return null;
      }
      final mood = _moodFromGenres(info.genres);
      if (mood == null) {
        _memoryCache[key] = null;
        return null;
      }
      await box.put(key, {'v': mood.$1, 'e': mood.$2, 'ts': DateTime.now().millisecondsSinceEpoch});
      _memoryCache[key] = mood;
      return mood;
    } catch (e) {
      debugPrint('DjMood: artistMood($artistName) $e');
      return null;
    }
  }

  /// Moyenne des moods des genres reconnus (neutre [0.5, 0.5] si mélange).
  (double, double)? _moodFromGenres(List<String> genres) {
    var v = 0.0;
    var e = 0.0;
    var n = 0;
    for (final g in genres) {
      final mood = _matchGenre(g);
      if (mood != null) {
        v += mood.$1;
        e += mood.$2;
        n++;
      }
    }
    if (n == 0) return null;
    return (v / n, e / n);
  }

  (double, double)? _matchGenre(String genre) {
    final g = genre.toLowerCase().trim();
    final direct = _genreMood[g];
    if (direct != null) return (direct[0], direct[1]);
    // Sous-genre "heavy metal" est déjà en table ; pour "synthwave pop" on
    // cherche un token connu.
    for (final entry in _genreMood.entries) {
      if (g.contains(entry.key)) return (entry.value[0], entry.value[1]);
    }
    return null;
  }

  double _distance((double, double) a, (double, double) b) {
    final dv = a.$1 - b.$1;
    final de = a.$2 - b.$2;
    return dv * dv + de * de;
  }

  /// Trie [items] par compatibilité d'humeur avec [reference].
  ///
  /// [reference] : item dont on cherche les ressemblances d'humeur.
  /// [mode] :
  ///   - `continuous` : plus proche premier (même humeur)
  ///   - `journey`    : on monte/descend progressivement vers [target]
  ///                    (target null → monter en énergie: chill→club)
  Future<List<MuzoItem>> orderForMood(
    List<MuzoItem> items, {
    MuzoItem? reference,
    (double, double)? referenceMood,
    (double, double)? target,
    String mode = 'continuous',
  }) async {
    if (items.isEmpty) return items;
    final ref = referenceMood ??
        (reference != null
            ? await artistMood(reference.displayArtist)
            : null);
    if (ref == null) return items; // pas de signal → ordre d'origine

    // Récupère le mood de chaque artiste candidate.
    final moods = <MuzoItem, (double, double)?>{};
    for (final item in items) {
      moods[item] = await artistMood(item.displayArtist);
    }

    final sorted = List<MuzoItem>.of(items);
    if (mode == 'journey') {
      final goal = target ?? (ref.$2 < 0.7 ? (0.8, 0.78) : (0.4, 0.25));
      // On trie par projection sur l'axe ref→goal : les pistes qui continuent
      // la montée/descente sont jouées tôt, celles en contre-sens plus tard.
      sorted.sort((a, b) {
        final ma = moods[a];
        final mb = moods[b];
        final sa = ma == null ? 0.0 : _journeyScore(ma, ref, goal);
        final sb = mb == null ? 0.0 : _journeyScore(mb, ref, goal);
        return sb.compareTo(sa);
      });
    } else {
      // continuous : distance euclidienne à l'humeur de référence
      sorted.sort((a, b) {
        final da = moods[a] == null ? double.infinity : _distance(moods[a]!, ref);
        final db = moods[b] == null ? double.infinity : _distance(moods[b]!, ref);
        return da.compareTo(db);
      });
    }
    return sorted;
  }

  double _journeyScore((double, double) m, (double, double) from, (double, double) to) {
    final dx = to.$1 - from.$1;
    final dy = to.$2 - from.$2;
    final len = (dx * dx + dy * dy);
    if (len == 0) return 0;
    // Produit scalaire (m - from) · (to - from), normalisé : +1 = aligné,
    // -1 = contre-sens. La composante verticale (énergie) pèse plus lourd.
    final mx = m.$1 - from.$1;
    final my = m.$2 - from.$2;
    final dot = (mx * dx + 2.2 * my * dy) / (len * (1 + (mx.abs() + my.abs())));
    return dot;
  }

  /// Invalide le cache d'un artiste (après re-tag par l'utilisateur).
  Future<void> invalidate(String artistName) async {
    final key = artistName.trim().toLowerCase();
    if (key.isEmpty) return;
    _memoryCache.remove(key);
    try {
      final box = await _getBox();
      await box.delete(key);
    } catch (_) {}
  }
}