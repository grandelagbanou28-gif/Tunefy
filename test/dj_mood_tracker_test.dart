import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muzo/services/dj_mood_tracker.dart';

void main() {
  late DjMoodTracker tracker;
  late Box box;

  setUpAll(() async {
    Hive.init('./.dart_tool/test_hive_dj');
    box = await Hive.openBox('dj_mood_feedback');
    tracker = DjMoodTracker();
  });

  setUp(() async {
    await box.clear();
    tracker.endSession();
  });

  test('setActiveMood / endSession', () {
    tracker.setActiveMood('energetic');
    expect(tracker.activeMood, 'energetic');
    tracker.setActiveMood('  ');
    expect(tracker.activeMood, null);
    tracker.setActiveMood('calm');
    tracker.endSession();
    expect(tracker.activeMood, null);
  });

  test('trackKey normalise videoId vs titre|artiste', () {
    expect(DjMoodTracker.trackKey('abc', 'T', 'A'), 'abc');
    expect(DjMoodTracker.trackKey('', 'Title', 'Artist'), 'title|artist');
  });

  test('scorePreviousTrack : ≥75% like, <25% dislike, milieu neutre',
      () async {
    tracker.setActiveMood('happy');

    tracker.noteProgress(key: 'k1', positionMs: 8000, durationMs: 10000);
    await tracker.scorePreviousTrack(prevKey: 'k1');
    expect(await tracker.scoreFor('happy', 'k1'), 1);

    tracker.noteProgress(key: 'k2', positionMs: 1000, durationMs: 10000);
    await tracker.scorePreviousTrack(prevKey: 'k2');
    expect(await tracker.scoreFor('happy', 'k2'), -1);

    tracker.noteProgress(key: 'k3', positionMs: 5000, durationMs: 10000);
    await tracker.scorePreviousTrack(prevKey: 'k3');
    expect(await tracker.scoreFor('happy', 'k3'), 0);
  });

  test('scorePreviousTrack sans humeur active → no-op', () async {
    tracker.endSession();
    tracker.noteProgress(key: 'kx', positionMs: 9000, durationMs: 10000);
    await tracker.scorePreviousTrack(prevKey: 'kx');
    expect(await tracker.scoreFor('happy', 'kx'), 0);
  });

  test('recordFeedback clampe à ±3', () async {
    await tracker.recordFeedback('focus', 't', 5);
    expect(await tracker.scoreFor('focus', 't'), 3);
    await tracker.recordFeedback('focus', 't', -10);
    expect(await tracker.scoreFor('focus', 't'), -3);
  });

  test('feedbackMap retourne les scores d une humeur', () async {
    await tracker.recordFeedback('calm', 'a', 1);
    await tracker.recordFeedback('calm', 'b', -2);
    final map = await tracker.feedbackMap('calm');
    expect(map['a'], 1);
    expect(map['b'], -2);
    expect(await tracker.feedbackMap('unknown'), isEmpty);
  });
}
