/// Dynamic UTC periods used by the Tunefy discovery section.
///
/// All boundaries are computed in UTC so the same device shows consistent
/// labels regardless of local timezone. Callers pass an explicit `now` in
/// tests.
class DiscoveryPeriod {
  final String id;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final int year;
  final int month;

  const DiscoveryPeriod({
    required this.id,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.year,
    required this.month,
  });

  Duration get duration => endDate.difference(startDate);

  /// Inclusive window check. Rolling windows ([last7Days]/[last30Days])
  /// get timezone/pre-release slack; calendar months stay strict.
  bool contains(DateTime d) {
    final rolling = id == 'last7Days' || id == 'last30Days';
    if (d.isBefore(startDate)) {
      if (rolling &&
          !d.isBefore(startDate.subtract(const Duration(days: 1)))) {
        return true;
      }
      return false;
    }
    if (d.isAfter(endDate)) {
      if (rolling) {
        // Pre-releases + date-only local-midnight stamps past a "now" end.
        return !d.isAfter(endDate.add(const Duration(days: 7)));
      }
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'year': year,
        'month': month,
      };

  factory DiscoveryPeriod.fromJson(Map<String, dynamic> j) =>
      DiscoveryPeriod(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        startDate: DateTime.parse(j['startDate'] as String),
        endDate: DateTime.parse(j['endDate'] as String),
        year: j['year'] as int? ?? 0,
        month: j['month'] as int? ?? 0,
      );
}

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Returns the current calendar month as a [DiscoveryPeriod] (UTC).
DiscoveryPeriod currentMonth([DateTime? nowUtc]) {
  final n = (nowUtc ?? DateTime.now().toUtc());
  final start = DateTime.utc(n.year, n.month, 1);
  final end = DateTime.utc(n.month == 12 ? n.year + 1 : n.year,
      n.month == 12 ? 1 : n.month + 1, 1);
  return DiscoveryPeriod(
    id: 'currentMonth',
    label: '${_monthNames[n.month - 1]} ${n.year}',
    startDate: start,
    endDate: end.subtract(const Duration(seconds: 1)),
    year: n.year,
    month: n.month,
  );
}

/// Returns the previous calendar month as a [DiscoveryPeriod] (UTC).
DiscoveryPeriod previousMonth([DateTime? nowUtc]) {
  final n = (nowUtc ?? DateTime.now().toUtc());
  final prev = DateTime.utc(n.year, n.month - 1, 1);
  final start = DateTime.utc(prev.year, prev.month, 1);
  final end = DateTime.utc(prev.year, prev.month + 1, 1)
      .subtract(const Duration(seconds: 1));
  return DiscoveryPeriod(
    id: 'previousMonth',
    label: '${_monthNames[prev.month - 1]} ${prev.year}',
    startDate: start,
    endDate: end,
    year: prev.year,
    month: prev.month,
  );
}

/// Last 7 days ending now (local clock — matches Deezer/iTunes stamps).
DiscoveryPeriod last7Days([DateTime? now]) {
  final n = now ?? DateTime.now();
  final start = n.subtract(const Duration(days: 7));
  return DiscoveryPeriod(
    id: 'last7Days',
    label: 'Last 7 days',
    startDate: start,
    endDate: n,
    year: n.year,
    month: n.month,
  );
}

/// Last 30 days ending now (local clock — matches Deezer/iTunes stamps).
DiscoveryPeriod last30Days([DateTime? now]) {
  final n = now ?? DateTime.now();
  final start = n.subtract(const Duration(days: 30));
  return DiscoveryPeriod(
    id: 'last30Days',
    label: 'Last 30 days',
    startDate: start,
    endDate: n,
    year: n.year,
    month: n.month,
  );
}
