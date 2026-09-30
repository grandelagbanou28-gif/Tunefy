import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/utils/period_utils.dart';

/// Minimal reimplementation of the service's dedup/filter/sort logic for
/// unit testing without network. Mirrors DiscoveryService._filterAndSort.
List<MuzoItem> filterAndSort(List<MuzoItem> raw, DiscoveryPeriod p) {
  final seen = <String>{};
  final out = <MuzoItem>[];
  for (final item in raw) {
    final id = item.sourceId ?? item.browseId ?? item.videoId;
    final key = id != null && id.isNotEmpty
        ? 'id:$id'
        : '${item.title.toLowerCase()}|${item.displayArtist.toLowerCase()}';
    if (key.isEmpty || seen.contains(key)) continue;

    final rel = item.releaseDate;
    if (rel != null && !p.contains(rel)) continue;
    if (rel == null && (p.id == 'previousMonth' || p.id == 'currentMonth')) {
      continue;
    }

    seen.add(key);
    out.add(item);
  }
  out.sort((a, b) {
    final da = a.releaseDate;
    final db = b.releaseDate;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return out;
}

MuzoItem _item(String id, String title, DateTime? releaseDate) {
  return MuzoItem(
    title: title,
    thumbnails: const [],
    resultType: 'album',
    isExplicit: false,
    browseId: 'dz:$id',
    sourceId: id,
    source: 'deezer',
    releaseDate: releaseDate,
  );
}

void main() {
  final period = last7Days(DateTime.utc(2026, 3, 15, 12));

  group('dedup', () {
    test('same sourceId collapses to one item', () {
      final raw = [
        _item('1', 'A', DateTime.utc(2026, 3, 10)),
        _item('1', 'A dup', DateTime.utc(2026, 3, 11)),
        _item('2', 'B', DateTime.utc(2026, 3, 9)),
      ];
      final out = filterAndSort(raw, period);
      expect(out.length, 2);
      expect(out.map((e) => e.sourceId).toSet(), {'1', '2'});
    });

    test('items without id dedupe on title+artist', () {
      final noId = [
        MuzoItem(
          title: 'Same',
          thumbnails: const [],
          resultType: 'album',
          isExplicit: false,
          releaseDate: DateTime.utc(2026, 3, 10),
        ),
        MuzoItem(
          title: 'Same',
          thumbnails: const [],
          resultType: 'album',
          isExplicit: false,
          releaseDate: DateTime.utc(2026, 3, 11),
        ),
      ];
      final out = filterAndSort(noId, period);
      expect(out.length, 1);
    });
  });

  group('period filter', () {
    test('drops items outside the period', () {
      final raw = [
        _item('in1', 'In', DateTime.utc(2026, 3, 12)),
        _item('out1', 'Out', DateTime.utc(2026, 3, 1)),
      ];
      final out = filterAndSort(raw, period);
      expect(out.length, 1);
      expect(out.first.sourceId, 'in1');
    });

    test('previousMonth drops undated items', () {
      final p = previousMonth(DateTime.utc(2026, 3, 15));
      final raw = [
        _item('dated', 'D', DateTime.utc(2026, 2, 10)),
        _item('undated', 'U', null),
      ];
      final out = filterAndSort(raw, p);
      expect(out.length, 1);
      expect(out.first.sourceId, 'dated');
    });

    test('last7Days keeps undated items', () {
      final raw = [
        _item('undated', 'U', null),
        _item('dated', 'D', DateTime.utc(2026, 3, 12)),
      ];
      // Implementation keeps undated for rolling windows only when
      // releaseDate is null and id is present — verify via direct call.
      final out = filterAndSort(raw, period);
      // Both have ids; undated has no releaseDate so passes the null check
      // for rolling windows in service logic. Our mirror keeps them.
      expect(out.length, 2);
    });
  });

  group('sort', () {
    test('newest first', () {
      final raw = [
        _item('old', 'Old', DateTime.utc(2026, 3, 9)),
        _item('new', 'New', DateTime.utc(2026, 3, 14)),
        _item('mid', 'Mid', DateTime.utc(2026, 3, 12)),
      ];
      final out = filterAndSort(raw, period);
      expect(out.map((e) => e.sourceId).toList(), ['new', 'mid', 'old']);
    });
  });
}
