import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/dj_chat_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/dj_chat_history_service.dart';

MuzoItem _track(String id, String title) => MuzoItem(
      title: title,
      thumbnails: const [],
      resultType: 'song',
      isExplicit: false,
      videoId: id,
      artists: [MuzoArtist(name: 'Artist $id', id: id)],
    );

void main() {
  late DjChatHistoryService svc;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/tunefy_dj_chat_test');
  });

  setUp(() async {
    svc = DjChatHistoryService();
    final chat = await Hive.openBox('dj_chat_history');
    final mixes = await Hive.openBox('dj_generated_mixes');
    await chat.clear();
    await mixes.clear();
  });

  group('DjChatMessage', () {
    test('json round-trip keeps fields', () {
      final m = DjChatMessage.bot('hello', mixId: 'mix-1');
      final back = DjChatMessage.fromJson(m.toJson());
      expect(back.fromUser, isFalse);
      expect(back.text, 'hello');
      expect(back.mixId, 'mix-1');
      expect(back.id, m.id);
    });
  });

  group('DjGeneratedMix', () {
    test('json round-trip keeps tracks', () {
      final mix = DjGeneratedMix(
        id: 'm1',
        mood: 'energetic',
        title: 'Energy · Tunefy DJ',
        createdAt: DateTime.utc(2026, 3, 20, 12),
        durationMinutes: 240,
        tracks: [_track('a', 'One'), _track('b', 'Two')],
      );
      final back = DjGeneratedMix.fromJson(mix.toJson());
      expect(back.id, 'm1');
      expect(back.trackCount, 2);
      expect(back.tracks.first.videoId, 'a');
      expect(back.durationMinutes, 240);
    });
  });

  group('DjChatHistoryService', () {
    test('save + load messages preserves order', () async {
      await svc.saveMessages([
        DjChatMessage.user('je suis triste'),
        DjChatMessage.bot('Voici un mix', mixId: 'mx'),
      ]);
      final loaded = await svc.loadMessages();
      expect(loaded.length, 2);
      expect(loaded.first.fromUser, isTrue);
      expect(loaded.last.mixId, 'mx');
    });

    test('clearMessages empties history', () async {
      await svc.saveMessages([DjChatMessage.user('x')]);
      await svc.clearMessages();
      expect(await svc.loadMessages(), isEmpty);
    });

    test('saveMix + loadMix restores full track list (50+)', () async {
      final tracks = [for (var i = 0; i < 55; i++) _track('v$i', 'Track $i')];
      final mix = DjGeneratedMix(
        id: 'big',
        mood: 'happy',
        title: 'Happy · Tunefy DJ',
        createdAt: DateTime.now(),
        durationMinutes: 240,
        tracks: tracks,
      );
      await svc.saveMix(mix);
      final back = await svc.loadMix('big');
      expect(back, isNotNull);
      expect(back!.trackCount, 55);
      final list = await svc.listMixes();
      expect(list.any((m) => m.id == 'big'), isTrue);
    });

    test('saveMix prunes old mixes beyond maxMixes', () async {
      for (var i = 0; i < DjChatHistoryService.maxMixes + 5; i++) {
        await svc.saveMix(DjGeneratedMix(
          id: 'm$i',
          mood: 'calm',
          title: 'M$i',
          createdAt: DateTime.now().subtract(Duration(minutes: i)),
          durationMinutes: 60,
          tracks: [_track('t$i', 'T$i')],
        ));
      }
      final list = await svc.listMixes();
      expect(list.length, lessThanOrEqualTo(DjChatHistoryService.maxMixes));
    });
  });
}
