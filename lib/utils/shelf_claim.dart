import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/search_provider.dart' show primaryArtistName;

// ═══════════════════════════════════════════════════════════════════════════════
// SHELF CLAIM — the app-wide rule « un artiste une seule fois ».
//
// Every row of Home (and the Quick Picks / Discovery rows that sit inside it)
// claims the artists it displays into [shownArtistsProvider]; the rows below
// take their next candidates instead. Pull-to-refresh empties the pool so a new
// page redistributes them.
//
// It lives here rather than in home_screen.dart because three screens need it
// and a screen must not import another screen.
// ═══════════════════════════════════════════════════════════════════════════════

/// Artists already displayed by a shelf above on this page pass.
final shownArtistsProvider = StateProvider<Set<String>>((ref) => {});

/// Ceiling on the last-resort repeats of a shelf whose whole pool was claimed
/// by the rows above.
const int shelfRepeatCeiling = 6;

/// Canonical key of a song/album/playlist tile, used to dedupe it WITHIN its
/// own shelf. Same video/album never appears twice in a single row.
String contentKey(MuzoItem item) {
  final id = item.videoId ?? item.browseId;
  if (id != null && id.isNotEmpty) return id.toLowerCase();
  return '${item.title}|${item.displayArtist}'.toLowerCase();
}

/// Removes duplicate content within one shelf, keeping order.
List<MuzoItem> dedupeShelfItems(List<MuzoItem> items) {
  final seen = <String>{};
  final out = <MuzoItem>[];
  for (final item in items) {
    final key = contentKey(item);
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    out.add(item);
  }
  return out;
}

/// The tiles a claim kept, plus the artist keys the claim now owns.
class ArtistClaim<T> {
  const ArtistClaim({required this.items, required this.claimed});

  final List<T> items;
  final Set<String> claimed;
}

/// Cross-shelf artist claim for any tile type.
///
/// [release] must carry the artists the caller claimed from the PREVIOUS list:
/// a row that rebuilds over a new list without giving them back finds its own
/// artists « déjà montrés », pushes every tile into the repeat quota, and the
/// page shows the same artist twice — exactly the bug this file exists to stop.
///
/// A row whose whole pool was taken above still renders, but with at most
/// [shelfRepeatCeiling] repeats: a thin row is honest, a fully duplicated row
/// is not, and a silently disappearing ray is what reads to the user as
/// « je ne vois pas les catégories ».
ArtistClaim<T> claimArtists<T>(
  Set<String> shown,
  List<T> items, {
  required String Function(T item) artistOf,
  String Function(T item)? keyOf,
  Set<String> release = const <String>{},
}) {
  shown.removeAll(release);
  final kept = <T>[];
  final taken = <T>[];
  final mine = <String>{};
  final seenIds = <String>{};
  for (final item in items) {
    if (keyOf != null) {
      final id = keyOf(item);
      if (id.isEmpty || !seenIds.add(id)) continue;
    }
    final artist = artistOf(item).trim().toLowerCase();
    if (artist.isNotEmpty &&
        (shown.contains(artist) ||
            mine.contains(artist) ||
            shown.any((a) => artistNamed(artist, a)) ||
            mine.any((a) => artistNamed(artist, a)))) {
      taken.add(item);
      continue;
    }
    if (artist.isNotEmpty) mine.add(artist);
    kept.add(item);
  }
  if (kept.isEmpty) kept.addAll(taken.take(shelfRepeatCeiling));
  shown.addAll(mine);
  return ArtistClaim(items: kept, claimed: mine);
}

/// [claimArtists] specialised to the Home tile type: dedupes by content key and
/// takes the lead artist out of "Ninho, Niska (feat. X)" style strings.
ArtistClaim<MuzoItem> claimShelfItems(
  Set<String> shown,
  List<MuzoItem> items, {
  Set<String> release = const <String>{},
}) =>
    claimArtists<MuzoItem>(
      shown,
      items,
      keyOf: contentKey,
      artistOf: (item) => primaryArtistName(item.displayArtist),
      release: release,
    );

/// What [claimShelfItems] produced, kept under its old name shape so Home's
/// rows read naturally.
typedef ShelfClaim = ArtistClaim<MuzoItem>;

/// True when [display] names [artist] as a whole word.
///
/// The substring test this replaces merged different artists: « Jul » matched
/// « Julien Morin », so two unrelated people erased each other from a row.
/// Both sides go through [compactArtistName] first, which folds accents the
/// same way for each, so « Wezz Monté » still meets « Wezz Monté ».
bool artistNamed(String display, String artist) {
  final sequence = compactArtistName(artist)
      .split(' ')
      .where((t) => t.isNotEmpty)
      .toList();
  final have =
      compactArtistName(display).split(' ').where((t) => t.isNotEmpty).toList();
  if (sequence.isEmpty) return false;
  if (sequence.length == 1) return have.contains(sequence.first);
  for (var i = 0; i + sequence.length <= have.length; i++) {
    var matches = true;
    for (var j = 0; j < sequence.length; j++) {
      if (have[i + j] != sequence[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

/// Lead artist of a Home tile, in the form the claim keys on.
String shelfArtistOf(MuzoItem item) => primaryArtistName(item.displayArtist);

/// Runs [claimShelfItems] exactly once per delivered list and rebuilds with the
/// claimed subset — the stateful half of the rule, for rows that cannot hold
/// the bookkeeping themselves.
class ShelfClaimBuilder<T> extends ConsumerStatefulWidget {
  const ShelfClaimBuilder({
    super.key,
    required this.items,
    required this.builder,
    required this.artistOf,
    this.keyOf,
  });

  final List<T> items;
  final String Function(T item) artistOf;
  final String Function(T item)? keyOf;
  final Widget Function(BuildContext context, List<T> claimed) builder;

  @override
  ConsumerState<ShelfClaimBuilder<T>> createState() =>
      _ShelfClaimBuilderState<T>();
}

class _ShelfClaimBuilderState<T> extends ConsumerState<ShelfClaimBuilder<T>> {
  List<T>? _source;
  List<T> _claimed = <T>[];
  Set<String> _artists = <String>{};

  @override
  Widget build(BuildContext context) {
    if (!identical(_source, widget.items)) {
      _source = widget.items;
      final claim = claimArtists<T>(
        ref.read(shownArtistsProvider),
        widget.items,
        artistOf: widget.artistOf,
        keyOf: widget.keyOf,
        release: _artists,
      );
      _artists = claim.claimed;
      _claimed = claim.items;
    }
    return widget.builder(context, _claimed);
  }
}
