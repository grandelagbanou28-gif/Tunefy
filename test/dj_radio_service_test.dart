import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muzo/services/dj_mood_tracker.dart';

void main() {
  group('DjMoodTracker AI Radio helpers', () {
    setUpAll(() async {
      Hive.init('./.dart_tool/test_hive_dj_radio');
      await Hive.openBox('dj_mood_feedback');
    });

    setUp(() async {
      await Hive.box('dj_mood_feedback').clear();
    });

    test('progress + score sur plusieurs pistes sans croisement', () async {
      final t = DjMoodTracker();
      t.setActiveMood('energetic');

      t.noteProgress(key: 'a', positionMs: 9000, durationMs: 10000);
      t.noteProgress(key: 'b', positionMs: 500, durationMs: 10000);
      await t.scorePreviousTrack(prevKey: 'a');
      await t.scorePreviousTrack(prevKey: 'b');

      expect(await t.scoreFor('energetic', 'a'), 1);
      expect(await t.scoreFor('energetic', 'b'), -1);

      await t.scorePreviousTrack(prevKey: 'a');
      expect(await t.scoreFor('energetic', 'a'), 1);
    });

    test('feedback négatif fort annule le like (+1 puis -4 → -3)', () async {
      final t = DjMoodTracker();
      await t.recordFeedback('sad', 'track', 1);
      expect(await t.scoreFor('sad', 'track'), 1);
      await t.recordFeedback('sad', 'track', -4);
      expect(await t.scoreFor('sad', 'track'), -3);
    });
  });
}
