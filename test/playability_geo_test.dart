import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/playability_geo_service.dart';

// Le 2026-10-15, l'appareil sortait sur une IP béninoise (137.255.199.25,
// AS328228) et les uploads « - Topic » français portent la liste de pays du
// label, qui exclut le Bénin. Mesuré contre le relais yt-dlp local : 6 ids sur
// 6, corrélation parfaite entre « BJ absent d'availableCountries » et
// « Video unavailable ». Ces tests verrouillent la lecture de cette liste —
// sans réseau, sans YouTube.
void main() {
  group('countriesOf', () {
    test('lit la liste de pays du microformat', () {
      final json = <String, dynamic>{
        'microformat': <String, dynamic>{
          'playerMicroformatRenderer': <String, dynamic>{
            'availableCountries': <dynamic>['FR', 'BE', 'BJ'],
          },
        },
      };
      expect(PlayabilityGeoService.countriesOf(json), <String>['FR', 'BE', 'BJ']);
    });

    test('réponse sans microformat = liste vide, jamais un blocage', () {
      expect(PlayabilityGeoService.countriesOf(<String, dynamic>{}), isEmpty);
      expect(
        PlayabilityGeoService.countriesOf(<String, dynamic>{
          'microformat': <String, dynamic>{
            'playerMicroformatRenderer': <String, dynamic>{},
          },
        }),
        isEmpty,
      );
    });
  });

  group('verdictForCountries', () {
    test('pays de l\'appareil dans la liste = ouvert', () {
      expect(
        PlayabilityGeoService.verdictForCountries(<String>['FR', 'BJ'], 'BJ'),
        UploadGeo.open,
      );
    });

    test('pays absent = fermé', () {
      expect(
        PlayabilityGeoService.verdictForCountries(<String>['FR', 'BE'], 'BJ'),
        UploadGeo.closed,
      );
    });

    test('casse d\'insensible', () {
      expect(
        PlayabilityGeoService.verdictForCountries(<String>['bj'], 'BJ'),
        UploadGeo.open,
      );
    });

    test('liste vide = inconnu, jamais fermé (un titre ne doit pas être exilé)',
        () {
      expect(
        PlayabilityGeoService.verdictForCountries(const <String>[], 'BJ'),
        UploadGeo.unknown,
      );
    });

    test('pays de l\'appareil inconnu = inconnu', () {
      expect(
        PlayabilityGeoService.verdictForCountries(<String>['FR'], ''),
        UploadGeo.unknown,
      );
    });
  });

  group('scoreAlternate — le doublon ouvert le plus présentable', () {
    test('clip officiel de l\'artiste devant une parodie ralentie', () {
      final clip = MuzoItem(
        title: 'Ronisia, Rsko - Ennemi (Clip officiel)',
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        videoId: 'smrKejClj5M',
        channelName: 'Ronisia',
        durationSeconds: 200,
        views: '1 200 000',
      );
      final knockoff = MuzoItem(
        title: 'Ennemi (Lyrics) (Slowed)',
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        videoId: 'zzzzzzzzzzz',
        channelName: 'Hits Mixed',
        durationSeconds: 200,
        views: '500',
      );
      expect(PlayabilityGeoService.scoreAlternate(clip),
          greaterThan(PlayabilityGeoService.scoreAlternate(knockoff)));
    });

    test('chaîne VEVO / topic valorisée', () {
      final vevo = MuzoItem(
        title: 'Ninho - J\'suis V1 (Official Video)',
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        videoId: 'a',
        channelName: 'NinhoVEVO',
        durationSeconds: 180,
      );
      final random = MuzoItem(
        title: 'Ninho - J\'suis V1',
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        videoId: 'b',
        channelName: 'Music 24/7',
        durationSeconds: 180,
      );
      expect(PlayabilityGeoService.scoreAlternate(vevo),
          greaterThan(PlayabilityGeoService.scoreAlternate(random)));
    });

    test('un extrait de 20 s perd ses points de durée', () {
      final short = MuzoItem(
        title: 'Extrait',
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        videoId: 's',
        channelName: 'Canal',
        durationSeconds: 20,
      );
      final full = MuzoItem(
        title: 'Extrait',
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        videoId: 'f',
        channelName: 'Canal',
        durationSeconds: 200,
      );
      expect(PlayabilityGeoService.scoreAlternate(short),
          lessThan(PlayabilityGeoService.scoreAlternate(full)));
    });
  });
}
