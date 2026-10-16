import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/services/deezer_api_service.dart';

/// Les rayons « Rap FR », « Hip-hop », « Afro Rap », « Afrobeats », « Afro Hits
/// » doivent un classement du PAYS et de la SCÈNE demandés. Ces deux fonctions
/// sont la seule décision prise sur du texte : le reste (les pistes) vient de
/// Deezer tel quel.
void main() {
  const frTokens = <String>['hip-hop', 'hip hop', 'rap', 'drill', 'trap', 'grime'];
  const usTokens = <String>['hip-hop', 'hip hop', 'rap', 'drill', 'trap'];
  const afroTokens = <String>['afro', 'african', 'amapiano'];

  group('sceneRadioMatch : une radio ne couvre une ligne que si elle cite le pays', () {
    test('« French Rap » remplit la ligne fr-rap', () {
      expect(DeezerApiService.sceneRadioMatch('French Rap', ['fr'], frTokens), isTrue);
    });

    test('« Rap US » remplit la ligne us-rap et JAMAIS la ligne française', () {
      expect(DeezerApiService.sceneRadioMatch('Rap US', ['us'], usTokens), isTrue);
      expect(DeezerApiService.sceneRadioMatch('Rap US', ['fr'], frTokens), isFalse);
    });

    test('« Hip-hop » tout court ne remplit aucune ligne pays', () {
      // C'est la radio mondiale : acceptée, elle remet du rap US dans « Rap FR ».
      expect(DeezerApiService.sceneRadioMatch('Hip-hop', ['fr'], frTokens), isFalse);
      expect(DeezerApiService.sceneRadioMatch('Hip-hop', ['us'], usTokens), isFalse);
      expect(DeezerApiService.sceneRadioMatch('Rap', ['us', 'ca'], usTokens), isFalse);
    });

    test('les accents ne cassent pas la reconnaissance du pays', () {
      expect(DeezerApiService.sceneRadioMatch('Rap Français', ['fr'], frTokens), isTrue);
      expect(DeezerApiService.sceneRadioMatch('Drill FR', ['fr'], frTokens), isTrue);
    });

    test('un mot pays se compare en mot entier, pas en sous-chaîne', () {
      expect(DeezerApiService.sceneRadioMatch('Future Rap', ['us'], usTokens), isFalse);
      expect(DeezerApiService.sceneRadioMatch('Gustave Rap', ['us'], usTokens), isFalse);
      expect(DeezerApiService.sceneRadioMatch('Rap USA', ['us'], usTokens), isTrue);
    });

    test('une scène sans mot commun avec la radio est refusée', () {
      expect(DeezerApiService.sceneRadioMatch('French Jazz', ['fr'], frTokens), isFalse);
      expect(
          DeezerApiService.sceneRadioMatch('South Africa', ['za'], afroTokens), isFalse);
    });

    test('un code pays inconnu de la table ne peut rien couvrir', () {
      expect(DeezerApiService.sceneRadioMatch('Rap Japon', ['jp'], ['rap']), isFalse);
    });
  });

  group('pickScenePlaylist : le nom de la scène demandé passe avant le volume', () {
    test('« Afrobeats Hits » gagne sur une Best Of deux fois plus fournie', () {
      final rows = <({String title, int nbTracks})>[
        (title: 'Best Of 2020', nbTracks: 80),
        (title: 'Afrobeats Hits', nbTracks: 49),
      ];
      expect(DeezerApiService.pickScenePlaylist(rows, ['afrobeats']), 1);
    });

    test('le mot de scène se compare en mot entier', () {
      // « afro » seul ne doit pas faire choisir « New Afro » quand la scène
      // demandée est l\'afrobeats.
      final rows = <({String title, int nbTracks})>[
        (title: 'New Afro', nbTracks: 74),
        (title: 'Afrobeats Hits', nbTracks: 49),
      ];
      expect(DeezerApiService.pickScenePlaylist(rows, ['afrobeats']), 1);
      expect(DeezerApiService.pickScenePlaylist(rows, ['afro']), 0);
    });

    test('aucun nom de scène en face : la première assez fournie', () {
      final rows = <({String title, int nbTracks})>[
        (title: 'Best Of', nbTracks: 80),
        (title: 'Hits', nbTracks: 50),
      ];
      expect(DeezerApiService.pickScenePlaylist(rows, ['afrobeats']), 0);
    });

    test('une mini-liste de 4 pistes n\'est pas un classement', () {
      final rows = <({String title, int nbTracks})>[
        (title: 'Afrobeats', nbTracks: 4),
        (title: 'Afrobeats Hits', nbTracks: 49),
      ];
      expect(DeezerApiService.pickScenePlaylist(rows, ['afrobeats']), 1);
    });

    test('rien d\'assez fourni : la première reste mieux qu\'une ligne vide', () {
      final rows = <({String title, int nbTracks})>[
        (title: 'Afro Miel', nbTracks: 3),
      ];
      expect(DeezerApiService.pickScenePlaylist(rows, ['afrobeats']), 0);
    });

    test('aucune playlist → -1', () {
      expect(DeezerApiService.pickScenePlaylist(const [], ['rap']), -1);
    });
  });
}
