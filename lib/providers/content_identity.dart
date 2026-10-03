import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// Per-user seeds for everything that "rotates".
///
/// Without this, a rotation is a function of the calendar alone: every user on
/// every device gets the identical Daily Mix, the identical genre offset and the
/// identical shelf on the same day, and they all expire at the same moment the
/// first person opened the app. "My content refreshes for me" needs the user in
/// the seed, otherwise there is no "me".
///
/// The id is stored per install rather than read from the account on purpose:
/// guest mode has no account, and the value only has to be stable for the person
/// using the device. A signed-in user can later be switched to the Supabase uid
/// without changing anything else here.
final contentIdProvider = FutureProvider<String>((ref) async {
  const key = 'content_id';
  try {
    final box = Hive.isBoxOpen('settings')
        ? Hive.box('settings')
        : await Hive.openBox('settings');
    final existing = box.get(key) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _randomId();
    await box.put(key, generated);
    return generated;
  } catch (_) {
    // Never let content rotation depend on storage being healthy.
    return 'anonymous';
  }
});

/// Days since a fixed epoch — the calendar half of every daily rotation.
int calendarDay([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().difference(DateTime.utc(2024, 1, 1)).inDays;

/// Stable hash of [id], so the same account keeps the same "personal" ordering.
int userSeedOf(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// The per-user daily seed: same value for a given user on a given day, different
/// for every user, and different again tomorrow.
final userDailySeedProvider = FutureProvider<int>((ref) async {
  final id = await ref.watch(contentIdProvider.future);
  return userSeedOf(id) ^ calendarDay();
});

/// Cache namespace for the current user, so switching accounts on a shared
/// device never shows the previous one's shelves.
final userContentNamespaceProvider = FutureProvider<String>(
  (ref) async => 'u${userSeedOf(await ref.watch(contentIdProvider.future))}',
);

String _randomId() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(12, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
