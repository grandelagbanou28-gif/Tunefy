import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/services/dj_mood_service.dart';

/// Tunefy DJ — moteur de curation 100% local. Il pique UNIQUEMENT dans le vrai
/// catalogue (les titres du même artiste via [artistSongsProvider], puis les
/// catalogues des artistes « Fans also like ») : le DJ ne fabrique jamais une
/// chanson, il réordonne de vraies pistes jouables.
class DjEngine {
  final WidgetRef ref;
  final DjMoodService _mood = DjMoodService();

  DjEngine(this.ref);

  static String _key(MuzoItem s) =>
      (s.videoId ?? '${s.title}|${s.displayArtist}').toLowerCase();

  /// Nouvelle volée de morceaux pour prolonger le mix autour de [anchor].
  /// [seenKeys] = identifiants déjà dans la file / déjà écoutés : jamais
  /// reproposés. Les candidats retenus sont ajoutés à [seenKeys] pour que les
  /// pools suivants ne se télescopent pas.
  ///
  /// Ordre d'enchaînement : les titres du MÊME artiste restent prioritaires
  /// (même humeur garantie), puis les « Fans also like » sont triés par
  /// compatibilité d'humeur avec l'auteur du morceau courant.
  Future<List<MuzoItem>> suggest({
    required MuzoItem anchor,
    required Set<String> seenKeys,
    int count = 10,
  }) async {
    final primary = primaryArtistName(anchor.displayArtist);
    if (primary.isEmpty || count <= 0) return const [];

    final ownPicks = <MuzoItem>[];
    final relatedPicks = <MuzoItem>[];

    // 1) Toujours le même artiste d'abord — pool déjà rodé/caché par sa page.
    try {
      final own = await ref.read(artistSongsProvider(primary).future);
      ownPicks.addAll(
          _pick(own, anchor: anchor, used: seenKeys, count: count));
    } catch (_) {}

    // 2) Débordement : « Fans also like » → leurs propres titres, triés par
    //    humeur d'artiste (valence×énergie) la plus proche de l'auteur courant.
    if (ownPicks.length + relatedPicks.length < count) {
      try {
        final related = await ref.read(relatedArtistsProvider(primary).future);
        for (final ra in related.take(5)) {
          if (ra.title.trim().isEmpty) continue;
          try {
            final raSongs = await ref.read(artistSongsProvider(ra.title).future);
            relatedPicks.addAll(_pick(raSongs,
                anchor: anchor,
                used: seenKeys,
                count: count - ownPicks.length - relatedPicks.length));
          } catch (_) {}
          if (ownPicks.length + relatedPicks.length >= count) break;
        }
      } catch (_) {}
    }

    if (relatedPicks.length > 1) {
      try {
        final ordered = await _mood.orderForMood(
          relatedPicks,
          reference: anchor,
          mode: 'continuous',
        );
        relatedPicks
          ..clear()
          ..addAll(ordered);
      } catch (_) {}
    }

    final room = (count - ownPicks.length).clamp(0, count);
    return [...ownPicks, ...relatedPicks.take(room)];
  }

  /// Trie le pool réel par proximité de durée avec le morceau courant (proxy
  /// d'énergie fiable, jamais de données inventées), bars les doublons, et
  /// renvoie au plus [count] candidats. L'ordre fournisseur départage les
  /// égalités → résultat déterministe.
  List<MuzoItem> _pick(
    List<MuzoItem> pool, {
    required MuzoItem anchor,
    required Set<String> used,
    required int count,
  }) {
    if (count <= 0) return const [];
    final anchorSec = anchor.durationSeconds ?? 0;

    final candidates = <MuzoItem>[];
    for (final s in pool) {
      final k = _key(s);
      if (s.videoId == null || k.isEmpty || used.contains(k)) continue;
      used.add(k);
      candidates.add(s);
    }

    candidates.sort((a, b) {
      if (anchorSec <= 0) return 0;
      final ad = a.durationSeconds == null
          ? anchorSec
          : (a.durationSeconds! - anchorSec).abs();
      final bd = b.durationSeconds == null
          ? anchorSec
          : (b.durationSeconds! - anchorSec).abs();
      return ad.compareTo(bd);
    });
    return candidates.take(count).toList();
  }
}