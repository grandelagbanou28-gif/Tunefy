import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/services/dj_smart_playlist.dart';
import 'package:muzo/services/gemini_service.dart';

void main() {
  group('GeminiService.parseJsonObject', () {
    final g = GeminiService();

    test('plain object', () {
      final v = g.parseJsonObject('{"a":1,"b":"x"}');
      expect(v, isNotNull);
      expect(v!['a'], 1);
      expect(v['b'], 'x');
    });

    test('fenced object', () {
      final v = g.parseJsonObject('```json\n{"title":"mix"}\n```');
      expect(v?['title'], 'mix');
    });

    test('object with surrounding prose', () {
      final v = g.parseJsonObject('Here you go: {"mood":"calm"} done');
      expect(v?['mood'], 'calm');
    });

    test('invalid → null', () {
      expect(g.parseJsonObject('not json'), isNull);
      expect(g.parseJsonObject('[1,2]'), isNull);
    });
  });

  group('DjSmartPlaylistService.looksLikeSmartPlaylist', () {
    test('detects playlist requests', () {
      expect(
        DjSmartPlaylistService.looksLikeSmartPlaylist(
            'playlist afrobeat pour road trip de 2h'),
        isTrue,
      );
      expect(
        DjSmartPlaylistService.looksLikeSmartPlaylist(
            'create a playlist for studying'),
        isTrue,
      );
      expect(
        DjSmartPlaylistService.looksLikeSmartPlaylist(
            'mix pour soirée entre amis'),
        isTrue,
      );
    });

    test('rejects short mood chips', () {
      expect(DjSmartPlaylistService.looksLikeSmartPlaylist('triste'), isFalse);
      expect(DjSmartPlaylistService.looksLikeSmartPlaylist('énergie'), isFalse);
      expect(DjSmartPlaylistService.looksLikeSmartPlaylist(''), isFalse);
      expect(DjSmartPlaylistService.looksLikeSmartPlaylist('hello'), isFalse);
    });
  });

  group('GeminiService configured', () {
    test('default key is present', () {
      expect(GeminiService().isConfigured, isTrue);
    });
  });
}
