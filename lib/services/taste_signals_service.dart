import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/storage_service.dart';

final tasteSignalsProvider = Provider<TasteSignals>((ref) {
  return TasteSignals(ref.read(storageServiceProvider));
});

/// Signaux de goût de l'écouteur : ce qu'il CHERCHE d'abord, ce qu'il JOUE
/// ensuite. Les recommandations de la page d'accueil partaient uniquement de
/// l'historique de lecture — un utilisateur qui cherche du rap FR depuis deux
/// semaines voyait passer les mêmes artistes écoutés une fois.
class TasteSignals {
  final StorageService _storage;

  TasteSignals(this._storage);

  /// Requêtes récentes de l'onglet Recherche, nettoyées (« X feat. Y (Live) »
  /// → « X ») et dédoublonnées, du plus récent au plus ancien.
  List<String> searchTerms({int max = 6}) {
    final out = <String>[];
    for (final raw in _storage.getSearchHistory()) {
      final term = cleanQuery(raw);
      if (term.isEmpty) continue;
      if (out.any((e) => e.toLowerCase() == term.toLowerCase())) continue;
      out.add(term);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Artistes les plus joués, favoris comptés double.
  List<String> topPlayedArtists({int max = 8}) {
    final counts = <String, int>{};
    void add(String? artist, int weight) {
      final name = (artist ?? '').trim();
      if (name.isEmpty || name == 'Unknown') return;
      counts[name] = (counts[name] ?? 0) + weight;
    }

    for (final f in _storage.getFavorites()) {
      add(f.displayArtist, 2);
    }
    for (final h in _storage.getHistory()) {
      add(h.displayArtist, 1);
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(max).map((e) => e.key).toList();
  }

  /// Graines de rayons perso : les recherches d'abord, puis les artistes
  /// joués. [seed] (journalier + propre à l'installation) décide quelle graine
  /// est en tête, donc deux utilisateurs ne voient pas la même selection.
  List<String> recommendationSeeds({int max = 4, int seed = 0}) {
    final terms = searchTerms(max: max + 2);
    final artists = topPlayedArtists(max: max + 2);
    final merged = <String>[];
    for (final t in terms) {
      if (!merged.any((e) => e.toLowerCase() == t.toLowerCase())) merged.add(t);
    }
    for (final a in artists) {
      if (!merged.any((e) => e.toLowerCase() == a.toLowerCase())) merged.add(a);
    }
    if (merged.isEmpty) return const [];
    return ContentCacheService.rotate(merged, seed).take(max).toList();
  }

  /// Les mots qui suivent un titre pour en demander autre chose que le titre.
  static const Set<String> _noise = {
    'paroles', 'lyrics', 'karaoke', 'type', 'beat', 'instrumental', 'live',
    'officiel', 'official', 'video', 'clip', 'remix',
  };

  /// « nxamndo black cagnott paroles » → « nxamndo black cagnott »;
  /// « Booba feat. Damso (Live) » → « Booba ».
  static String cleanQuery(String raw) {
    var q = raw.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
    q = q.split(
      RegExp(r'\s(?:feat\.?|ft\.?|featuring|with)\s', caseSensitive: false),
    ).first;
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    // Le bruit n'est retiré qu'en FIN de requête : « Live » est un artiste et
    // « Clip » un mot ordinaire au milieu d'un titre.
    while (words.isNotEmpty) {
      final last = words.last.toLowerCase();
      final year = int.tryParse(last);
      if (_noise.contains(last) || (year != null && year >= 2000 && year < 2100)) {
        words.removeLast();
      } else {
        break;
      }
    }
    return words.join(' ').trim();
  }
}
