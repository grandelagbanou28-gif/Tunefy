import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/services/dj_mood_bot.dart';

void main() {
  group('DjMoodBot.trackCountForMinutes', () {
    test('scale Freedify : 1h ≈ 15, 2.5h ≈ 37, 4h ≈ 60', () {
      expect(DjMoodBot.trackCountForMinutes(60), 15);
      expect(DjMoodBot.trackCountForMinutes(150), 38); // round(150/4)=38 (≈37)
      expect(DjMoodBot.trackCountForMinutes(240), 60);
      expect(DjMoodBot.trackCountForMinutes(30), 8);
    });

    test('bornes : min 4, max 60, clamp minutes 15..240', () {
      expect(DjMoodBot.trackCountForMinutes(0), 4);
      expect(DjMoodBot.trackCountForMinutes(1), 4);
      expect(DjMoodBot.trackCountForMinutes(1000), 60);
      expect(DjMoodBot.trackCountForMinutes(15), 4);
    });
  });
}
