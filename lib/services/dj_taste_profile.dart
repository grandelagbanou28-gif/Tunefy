import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/storage_service.dart';

/// Tunefy DJ — profil de goût local (taste profile Freedify, 100% offline).
///
/// Échantillonne l'historique d'écoute (et non des stats inventées) pour
/// construire un set d'artistes fréquemment écoutés. Le DJ boost les
/// candidats dont l'artiste est dans ce profil quand il génère un set pour
/// une humeur — personnalisation dès la première utilisation, sans IA.
class DjTasteProfile {
  final StorageService _storage;

  DjTasteProfile(this._storage);

  static const int _historyScan = 200;
  static const int _topArtistLimit = 40;

  /// Artiste → nombre d'écoutes dans l'historique récent (dédup par titre+artiste).
  /// Map clé = nom d'artiste normalisé minuscules.
  Map<String, int> artistWeights() {
    final history = _storage.getHistory();
    if (history.isEmpty) return const {};

    final weights = <String, int>{};
    final seenTracks = <String>{};
    for (final item in history.take(_historyScan)) {
      final trackKey =
          '${item.title}|${item.displayArtist}'.toLowerCase();
      if (!seenTracks.add(trackKey)) continue;
      for (final name in _artistNames(item)) {
        final k = name.trim().toLowerCase();
        if (k.isEmpty || k == 'unknown') continue;
        weights[k] = (weights[k] ?? 0) + 1;
      }
    }
    return weights;
  }

  /// Top N artistes par poids (ordre décroissant).
  List<String> topArtists({int limit = _topArtistLimit}) {
    final entries = artistWeights().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  /// Score 0..1 : 0 = jamais écouté, 1 = top de l'historique.
  /// Sert à re-ranker les candidats du DJ par affinité de goût.
  double affinityScore(MuzoItem item) {
    final weights = artistWeights();
    if (weights.isEmpty) return 0;
    final maxW = weights.values.reduce((a, b) => a > b ? a : b);
    if (maxW <= 0) return 0;

    var best = 0;
    for (final name in _artistNames(item)) {
      final w = weights[name.trim().toLowerCase()] ?? 0;
      if (w > best) best = w;
    }
    return best / maxW;
  }

  Iterable<String> _artistNames(MuzoItem item) sync* {
    if (item.artists != null) {
      for (final a in item.artists!) {
        if (a.name.isNotEmpty) yield a.name;
      }
    }
    if (item.channelName != null && item.channelName!.isNotEmpty) {
      yield item.channelName!;
    }
    if (item.displayArtist.isNotEmpty) yield item.displayArtist;
  }
}
