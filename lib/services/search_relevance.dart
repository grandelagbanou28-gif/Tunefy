import 'package:muzo/models/muzo_item.dart';

/// Client-side search relevance: type gate + text match ranking.
///
/// The backend returns category-scoped hits in rough relevance order, but
/// the app re-sorts by recency and never scores the query against title /
/// artist / album — so Albums/Artists tabs show weak or wrong hits and the
/// real match can be buried. This module:
///   1. Gates items to the active filter's result types;
///   2. Scores title / artist / album against the normalized query;
///   3. Drops zero-score noise when enough real matches exist;
///   4. Sorts by score (age as a light tie-break), keeping API order for ties.
class SearchRelevance {
  const SearchRelevance._();

  /// Lowercase, strip accents and punctuation, collapse whitespace.
  static String normalize(String input) {
    var s = input.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[àáâãäå]'), 'a');
    s = s.replaceAll(RegExp(r'[èéêë]'), 'e');
    s = s.replaceAll(RegExp(r'[ìíîï]'), 'i');
    s = s.replaceAll(RegExp(r'[òóôõö]'), 'o');
    s = s.replaceAll(RegExp(r'[ùúûü]'), 'u');
    s = s.replaceAll(RegExp(r'[ýÿ]'), 'y');
    s = s.replaceAll(RegExp(r'[ç]'), 'c');
    s = s.replaceAll(RegExp(r'[ñ]'), 'n');
    s = s.replaceAll(RegExp(r'''[^a-z0-9\s]'''), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  /// Whether [item] belongs under the active [filter] chip.
  /// Empty `resultType` falls back to shape (videoId → playable, browseId → entity).
  static bool matchesFilter(MuzoItem item, String filter) {
    final f = filter.toLowerCase();
    if (f.isEmpty || f == 'all') return true;
    final t = item.resultType.toLowerCase().trim();

    switch (f) {
      case 'songs':
        return t == 'song' ||
            t == 'video' ||
            t == 'user_track' ||
            t == 'track' ||
            (t.isEmpty && (item.videoId?.isNotEmpty ?? false));
      case 'videos':
        return t == 'video' || (t.isEmpty && (item.videoId?.isNotEmpty ?? false));
      case 'albums':
        return t == 'album' ||
            (t.isEmpty &&
                (item.browseId?.isNotEmpty ?? false) &&
                item.videoId == null);
      case 'artists':
        return t == 'artist' ||
            t == 'channel' ||
            (t.isEmpty &&
                (item.browseId?.isNotEmpty ?? false) &&
                item.videoId == null);
      case 'playlists':
        return t == 'playlist' ||
            (t.isEmpty &&
                (item.browseId?.isNotEmpty ?? false) &&
                item.videoId == null);
      case 'channels':
        return t == 'channel' || t == 'artist';
      default:
        return true;
    }
  }

  /// Relevance of one item for [query] under [filter]. Higher is better.
  static int score(MuzoItem item, String query, String filter) {
    final q = normalize(query);
    if (q.isEmpty) return 0;

    final title = normalize(item.title);
    final artist = normalize(item.displayArtist);
    final album = normalize(item.album?.name ?? '');
    final f = filter.toLowerCase();

    var s = 0;

    if (title == q) {
      s += 100;
    } else if (title.startsWith(q)) {
      s += 70;
    } else if (title.contains(q)) {
      s += 55;
    }

    if (artist == q) {
      s += f == 'artists' || f == 'channels' ? 100 : 75;
    } else if (artist.startsWith(q)) {
      s += 55;
    } else if (artist.contains(q)) {
      s += 45;
    }

    if (album == q) {
      s += f == 'albums' ? 90 : 35;
    } else if (album.isNotEmpty && album.contains(q)) {
      s += f == 'albums' ? 45 : 25;
    }

    final qTokens = q.split(' ').where((t) => t.length > 1).toList();
    if (qTokens.isNotEmpty) {
      final titleWords = title.split(' ').where((w) => w.isNotEmpty).toSet();
      final artistWords = artist.split(' ').where((w) => w.isNotEmpty).toSet();
      final albumWords = album.split(' ').where((w) => w.isNotEmpty).toSet();

      for (final tok in qTokens) {
        if (titleWords.contains(tok)) {
          s += 18;
        } else if (titleWords.any((w) => w.startsWith(tok))) {
          s += 10;
        }
        if (artistWords.contains(tok)) {
          s += 16;
        } else if (artistWords.any((w) => w.startsWith(tok))) {
          s += 9;
        }
        if (albumWords.contains(tok)) {
          s += 10;
        } else if (albumWords.any((w) => w.startsWith(tok))) {
          s += 5;
        }
      }

      // Full multi-word query spread across title+artist ("drake hotline bling").
      final haystack = '$title $artist $album'.trim();
      if (qTokens.every(
          (tok) => haystack.split(' ').any((w) => w == tok || w.startsWith(tok)))) {
        s += 30;
      }
    }

    return s;
  }

  /// Type-gate, score, drop noise, and rank [items] for [query] + [filter].
  static List<MuzoItem> rank(
    List<MuzoItem> items,
    String query,
    String filter, {
    int minMatchesToPrune = 3,
  }) {
    if (items.isEmpty) return items;

    // The type gate is authoritative: a chip that matches nothing shows
    // nothing. Restoring the whole page here is what used to make the
    // albums / playlists / artists chips look like no-ops.
    final gated = filter == 'all'
        ? items
        : items.where((i) => matchesFilter(i, filter)).toList();
    if (gated.isEmpty) return gated;

    final indexed = <({MuzoItem item, int score, int age, int order})>[];
    for (var i = 0; i < gated.length; i++) {
      final item = gated[i];
      indexed.add((
        item: item,
        score: score(item, query, filter),
        age: _ageDays(item),
        order: i,
      ));
    }

    final strong = indexed.where((e) => e.score > 0).length;
    final pool = strong >= minMatchesToPrune
        ? indexed.where((e) => e.score > 0).toList()
        : indexed;

    pool.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      if (a.age != b.age) {
        // Younger first only when both have a known date.
        if (a.age >= 9999 && b.age >= 9999) return 0;
        if (a.age >= 9999) return 1;
        if (b.age >= 9999) return -1;
        return a.age.compareTo(b.age);
      }
      return a.order.compareTo(b.order);
    });

    return [for (final e in pool) e.item];
  }

  static int _ageDays(MuzoItem item) {
    final rd = item.releaseDate;
    if (rd != null) return DateTime.now().difference(rd).inDays;
    final up = (item.uploaded ?? '').toLowerCase();
    if (up.isEmpty) return 9999;
    final n = int.tryParse(up.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (up.contains('hour') || up.contains('minute') || up.contains('second')) {
      return 0;
    }
    if (up.contains('day')) return n;
    if (up.contains('week')) return n * 7;
    if (up.contains('month')) return n * 30;
    if (up.contains('year')) return n * 365;
    return 9999;
  }
}
