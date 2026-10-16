import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/services/muzo_api_service.dart';

// Le worker Vercel renvoie HTTP 500 des qu'un caractere non-ASCII reste dans
// `q` (mesure du 2026-10-11 : q=seul = 500). Ces requetes sont celles qui
// vidaient des rayons entiers (« Bande Originale », « Musique Arabe »).
void main() {
  group('workerQueryFor', () {
    test('plie les accents precedents', () {
      expect(MuzoApiService.workerQueryFor('Drill Français'), 'Drill Francais');
      expect(MuzoApiService.workerQueryFor('Séries TV bande originale'),
          'Series TV bande originale');
      expect(MuzoApiService.workerQueryFor('Égypte musique arabe'),
          'Egypte musique arabe');
    });

    test('retire les diacritiques deja decomposes (a + U+0300)', () {
      expect(MuzoApiService.workerQueryFor('Fille à Papa Vacra'),
          'Fille a Papa Vacra');
      expect(
          MuzoApiService.workerQueryFor('Cœur'), 'Coeur'); // œ
    });

    test('les requetes relevees en 500 sur lappareil deviennent ASCII', () {
      for (final q in [
        'Comédies Musicales bande originale',
        'Classiques du Cinéma bande originale',
        'Guitaristes Légendaires rumba congolaise',
        'Chansons Françaises chanson francaise',
      ]) {
        final folded = MuzoApiService.workerQueryFor(q);
        expect(RegExp(r'^[\x00-\x7F]*$').hasMatch(folded), isTrue,
            reason: '$q -> $folded garde un caractere non-ASCII');
      }
    });

    test('ne touche pas ce qui est deja ASCII', () {
      expect(MuzoApiService.workerQueryFor('afrobeats hits 2026'),
          'afrobeats hits 2026');
    });

    test('garde la langue originale si le pliage vide la requete', () {
      expect(MuzoApiService.workerQueryFor('موسيقى عربية'), 'موسيقى عربية');
      expect(MuzoApiService.workerQueryFor('   '), '');
    });
  });
}
