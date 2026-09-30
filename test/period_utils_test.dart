import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/utils/period_utils.dart';

void main() {
  group('DiscoveryPeriod', () {
    test('currentMonth returns correct boundaries (UTC)', () {
      final now = DateTime.utc(2026, 3, 15, 12, 30);
      final p = currentMonth(now);
      expect(p.year, 2026);
      expect(p.month, 3);
      expect(p.startDate, DateTime.utc(2026, 3, 1));
      expect(p.endDate.isBefore(DateTime.utc(2026, 4, 1)), isTrue);
      expect(p.label, 'March 2026');
    });

    test('currentMonth handles December rollover', () {
      final now = DateTime.utc(2026, 12, 25);
      final p = currentMonth(now);
      expect(p.startDate, DateTime.utc(2026, 12, 1));
      expect(p.endDate.isBefore(DateTime.utc(2027, 1, 1)), isTrue);
      expect(p.label, 'December 2026');
    });

    test('previousMonth returns correct boundaries (UTC)', () {
      final now = DateTime.utc(2026, 3, 15);
      final p = previousMonth(now);
      expect(p.year, 2026);
      expect(p.month, 2);
      expect(p.startDate, DateTime.utc(2026, 2, 1));
      expect(p.endDate.isBefore(DateTime.utc(2026, 3, 1)), isTrue);
      expect(p.label, 'February 2026');
    });

    test('previousMonth handles January rollover', () {
      final now = DateTime.utc(2026, 1, 10);
      final p = previousMonth(now);
      expect(p.year, 2025);
      expect(p.month, 12);
      expect(p.startDate, DateTime.utc(2025, 12, 1));
      expect(p.label, 'December 2025');
    });

    test('last7Days spans exactly 7 days', () {
      final now = DateTime.utc(2026, 3, 15, 12);
      final p = last7Days(now);
      expect(p.startDate, DateTime.utc(2026, 3, 8, 12));
      expect(p.endDate, now);
      expect(p.duration.inDays, 7);
      expect(p.label, 'Last 7 days');
    });

    test('last30Days spans exactly 30 days', () {
      final now = DateTime.utc(2026, 3, 15, 12);
      final p = last30Days(now);
      expect(p.startDate, DateTime.utc(2026, 2, 13, 12));
      expect(p.endDate, now);
      expect(p.duration.inDays, 30);
      expect(p.label, 'Last 30 days');
    });

    test('contains is inclusive of boundaries', () {
      final now = DateTime.utc(2026, 3, 15);
      final p = currentMonth(now);
      expect(p.contains(DateTime.utc(2026, 3, 1)), isTrue);
      expect(p.contains(DateTime.utc(2026, 3, 31, 23, 59, 59)), isTrue);
      expect(p.contains(DateTime.utc(2026, 2, 28)), isFalse);
      expect(p.contains(DateTime.utc(2026, 4, 1)), isFalse);
    });

    test('json round-trip preserves fields', () {
      final p = previousMonth(DateTime.utc(2026, 6, 1));
      final restored = DiscoveryPeriod.fromJson(p.toJson());
      expect(restored.id, p.id);
      expect(restored.label, p.label);
      expect(restored.startDate, p.startDate);
      expect(restored.endDate, p.endDate);
      expect(restored.year, p.year);
      expect(restored.month, p.month);
    });
  });
}
