import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/blend.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/supabase_store.dart';

/// A live Supabase client for Blend reads/writes. Null when Supabase was
/// never configured on this backend (local-only mode) — Blend then reports
/// itself unavailable instead of crashing.
SupabaseStore? _store(WidgetRef ref) =>
    ref.read(storageServiceProvider).supabase;

/// My own member identity inside blends: stable per-device uid + display name.
({String uid, String name}) _me(WidgetRef ref) {
  final storage = ref.read(storageServiceProvider);
  final uid = storage.supabase?.uid ?? '';
  final name = (storage.username ?? '').trim();
  return (uid: uid, name: name.isEmpty ? 'Moi' : name);
}

/// All blends this device created or joined (codes stored locally), fresh
/// from the server. Missing/deleted codes are skipped silently.
final myBlendsProvider = FutureProvider<List<Blend>>((ref) async {
  final storage = ref.read(storageServiceProvider);
  final store = storage.supabase;
  if (store == null) return const [];
  final out = <Blend>[];
  for (final code in storage.blendCodes) {
    try {
      final blend = await store.fetchBlend(code);
      if (blend != null) out.add(blend);
    } catch (_) {}
  }
  return out;
});

/// One blend by join code, live from the server.
final blendDetailProvider =
    FutureProvider.family<Blend?, String>((ref, code) async {
  final store = ref.read(storageServiceProvider).supabase;
  if (store == null) return null;
  try {
    return await store.fetchBlend(code);
  } catch (_) {
    return null;
  }
});

/// Short human-readable join code, e.g. "KORA-4821".
String newBlendCode([Random? random]) {
  const words = [
    'KORA', 'BALAFON', 'DJEMBE', 'SAHARA', 'LAGOS', 'COTONOU', 'ABIDJAN',
    'DAKAR', 'ACCRA', 'DOUALA', 'BAMAKO', 'LOME', 'GROOVE', 'MELODY',
  ];
  final rng = random ?? Random();
  final word = words[rng.nextInt(words.length)];
  final digits = (1000 + rng.nextInt(9000)).toString();
  return '$word-$digits';
}

/// Creates a blend owned by me, stores the code locally and returns it.
/// Throws when Supabase is unreachable so the UI can show the error.
Future<Blend> createBlend(
  WidgetRef ref,
  String name, {
  List<MuzoItem> seedSongs = const [],
}) async {
  final store = _store(ref);
  if (store == null) throw Exception('Supabase indisponible');
  final me = _me(ref);
  final now = DateTime.now().toIso8601String();
  final blend = Blend(
    code: newBlendCode(),
    name: name.trim().isEmpty ? 'Blend' : name.trim(),
    members: [BlendMember(uid: me.uid, name: me.name)],
    tracks: [
      for (final s in seedSongs)
        if (s.videoId != null && s.videoId!.isNotEmpty)
          BlendTrack(
            song: s,
            addedByUid: me.uid,
            addedByName: me.name,
            addedAt: now,
          ),
    ],
  );
  await store.saveBlend(blend);
  await ref.read(storageServiceProvider).addBlendCode(blend.code);
  ref.invalidate(myBlendsProvider);
  return blend;
}

/// Joins a blend by code: adds me as a member server-side and stores the code
/// locally. Returns null when the code does not exist.
Future<Blend?> joinBlend(WidgetRef ref, String code) async {
  final store = _store(ref);
  if (store == null) return null;
  final normalized = code.trim().toUpperCase();
  if (normalized.isEmpty) return null;
  final blend = await store.fetchBlend(normalized);
  if (blend == null) return null;
  final me = _me(ref);
  final members = List<BlendMember>.from(blend.members);
  if (!members.any((m) => m.uid == me.uid && me.uid.isNotEmpty)) {
    members.add(BlendMember(uid: me.uid, name: me.name));
    await store.saveBlend(Blend(
      code: blend.code,
      name: blend.name,
      members: members,
      tracks: blend.tracks,
    ));
  }
  await ref.read(storageServiceProvider).addBlendCode(blend.code);
  ref.invalidate(myBlendsProvider);
  ref.invalidate(blendDetailProvider(blend.code));
  return blend;
}

/// Appends [song] to the blend as me. Returns false when the song is already
/// in the blend.
Future<bool> addSongToBlend(
  WidgetRef ref,
  String code,
  MuzoItem song,
) async {
  final store = _store(ref);
  if (store == null) return false;
  final blend = await store.fetchBlend(code);
  if (blend == null) return false;
  final vid = song.videoId;
  if (vid == null || vid.isEmpty) return false;
  if (blend.tracks.any((t) => t.song.videoId == vid)) return false;
  final me = _me(ref);
  final tracks = List<BlendTrack>.from(blend.tracks)
    ..add(BlendTrack(
      song: song,
      addedByUid: me.uid,
      addedByName: me.name,
      addedAt: DateTime.now().toIso8601String(),
    ));
  await store.saveBlend(Blend(
    code: blend.code,
    name: blend.name,
    members: blend.members,
    tracks: tracks,
  ));
  ref.invalidate(blendDetailProvider(blend.code));
  ref.invalidate(myBlendsProvider);
  return true;
}

/// Removes my own [videoId] entries from the blend (only mine).
Future<void> removeMySongFromBlend(
  WidgetRef ref,
  String code,
  String videoId,
) async {
  final store = _store(ref);
  if (store == null) return;
  final blend = await store.fetchBlend(code);
  if (blend == null) return;
  final me = _me(ref);
  final tracks = blend.tracks
      .where((t) =>
          !(t.song.videoId == videoId &&
              (t.addedByUid == me.uid || me.uid.isEmpty)))
      .toList();
  if (tracks.length == blend.tracks.length) return;
  await store.saveBlend(Blend(
    code: blend.code,
    name: blend.name,
    members: blend.members,
    tracks: tracks,
  ));
  ref.invalidate(blendDetailProvider(blend.code));
  ref.invalidate(myBlendsProvider);
}

/// Leaves a blend (drops the code locally; the shared document stays for the
/// other members).
Future<void> leaveBlend(WidgetRef ref, String code) async {
  await ref.read(storageServiceProvider).removeBlendCode(code);
  ref.invalidate(myBlendsProvider);
}
