import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/dj_mix_tips.dart';

MuzoItem _song(String artist) => MuzoItem(
      title: 't',
      thumbnails: const [],
      resultType: 'song',
      isExplicit: false,
      artists: [MuzoArtist(name: artist, id: '')],
    );

void main() {
  final tips = DjMixTips();

  setUpAll(() async {
    Hive.init('./.dart_tool/test_hive_dj_mix');
  });

  test('labelOf types connus', () {
    expect(tips.labelOf('blend'), 'Smooth blend');
    expect(tips.labelOf('buildup'), 'Energy build-up');
    expect(tips.labelOf('breakdown'), 'Smooth breakdown');
    expect(tips.labelOf('harmonic_contrast'), 'Contrast transition');
    expect(tips.labelOf('cut'), 'Clean cut');
    expect(tips.labelOf('other'), 'Clean cut');
  });

  test('analyze artistes inconnus → null (pas de tip inventé)', () async {
    final tip = await tips.analyze(_song('Zzz Unknown'), _song('Qqq Nobody'));
    expect(tip, null);
  });

  test('analyze artistes connus (cache Hive MusicBrainz) → tip ou null',
      () async {
    // Artistes réels : si MusicBrainz répond, on a un tip cohérent ;
    // si hors-ligne, null acceptable — jamais d'exception.
    final tip = await tips.analyze(_song('Daft Punk'), _song('Daft Punk'));
    if (tip != null) {
      expect(tip.crossfadeSeconds, inInclusiveRange(1, 8));
      expect(
        const {
          'blend',
          'buildup',
          'breakdown',
          'harmonic_contrast',
          'cut',
        },
        contains(tip.transitionType),
      );
      expect(tip.energyDelta, isA<double>());
      expect(tip.moodDistance, isA<double>());
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
