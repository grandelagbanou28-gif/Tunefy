import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/utils/shelf_claim.dart';

MuzoItem song(String title, String artist) => MuzoItem(
      title: title,
      thumbnails: const [],
      resultType: 'song',
      isExplicit: false,
      videoId: 'vid-$title',
      artists: <MuzoArtist>[MuzoArtist(name: artist, id: null)],
    );

void main() {
  group('claimShelfItems — un artiste une seule fois dans la page', () {
    test('le rayon du haut garde tout, celui du bas rend l\'artiste déjà montré',
        () {
      final shown = <String>{};
      final first =
          claimShelfItems(shown, <MuzoItem>[song('A', 'Ninho'), song('B', 'Jul')]);
      expect(first.items.length, 2);

      final second = claimShelfItems(shown, <MuzoItem>[
        song('C', 'Ninho'),
        song('D', 'Soso'),
      ]);
      expect(second.items.map((i) => i.title), <String>['D']);
    });

    test('deux titres du même artiste dans un seul rayon -> une carte', () {
      final shown = <String>{};
      final claim = claimShelfItems(shown, <MuzoItem>[
        song('A', 'Ninho'),
        song('B', 'Ninho, Damso'),
      ]);
      expect(claim.items.length, 1);
    });

    test('re-claim d\'une NOUVELLE liste ne répète pas ses propres artistes', () {
      final shown = <String>{};
      final first = claimShelfItems(shown, <MuzoItem>[
        song('A', 'Ninho'),
        song('B', 'Jul'),
      ]);
      // Le provider livre la même semaine de sons sous une nouvelle identité de
      // liste (enrichissement audio, tirage quotidien…).
      final again = claimShelfItems(
        shown,
        <MuzoItem>[song('A', 'Ninho'), song('B', 'Jul')],
        release: first.claimed,
      );
      expect(again.items.map((i) => i.title), <String>['A', 'B']);
      expect(shown, <String>{'ninho', 'jul'});
    });

    test('sans release, un re-claim ne peut plus inonder la page : 6 repeats max',
        () {
      final shown = <String>{};
      final list = <MuzoItem>[
        for (var i = 0; i < 10; i++) song('T$i', 'Artiste$i'),
      ];
      claimShelfItems(shown, list);
      final starved = claimShelfItems(shown, list);
      expect(starved.items.length, lessThanOrEqualTo(shelfRepeatCeiling));
    });

    test('un rayon dont tout a été pris ne disparaît pas', () {
      final shown = <String>{};
      claimShelfItems(shown, <MuzoItem>[song('A', 'Ninho')]);
      final lastResort =
          claimShelfItems(shown, <MuzoItem>[song('B', 'Ninho')]);
      expect(lastResort.items, isNotEmpty);
    });
  });

  group('artistNamed — le nom entier, pas un fragment', () {
    test('« Jul » ne réclame pas « Julien Morin »', () {
      expect(artistNamed('Julien Morin', 'Jul'), isFalse);
      expect(artistNamed('Jul', 'Julien Morin'), isFalse);
    });

    test('nom de duo reconnu dans un titre long', () {
      expect(artistNamed('Djadja & Dinaz - Coup de chaud', 'Djadja & Dinaz'),
          isTrue);
      expect(artistNamed('PNL - À l\'aube', 'pnl'), isTrue);
    });

    test('accents repliés identiquement des deux côtés', () {
      expect(artistNamed('Wezz Monté', 'Wezz Monté'), isTrue);
    });

    test('nom vide jamais revendiqué', () {
      expect(artistNamed('Ninho', ''), isFalse);
    });
  });

  group('dedupeShelfItems', () {
    test('même videoId deux fois = une carte, ordre conservé', () {
      final a = song('A', 'Ninho');
      final out = dedupeShelfItems(<MuzoItem>[a, song('B', 'Jul'), a]);
      expect(out.map((i) => i.title), <String>['A', 'B']);
    });
  });

  group('claimArtists<T> — les rayons qui ne sont pas des titres', () {
    test('une rangée d\'artistes revendique les noms qu\'elle affiche', () {
      final shown = <String>{};
      claimShelfItems(shown, <MuzoItem>[song('A', 'Ninho')]);
      final avatars = claimArtists<_Named>(
        shown,
        <_Named>[_Named('Ninho'), _Named('Soso')],
        artistOf: (a) => a.name,
        keyOf: (a) => a.name.toLowerCase(),
      );
      expect(avatars.items.map((a) => a.name), <String>['Soso']);
    });

    test('un rayon albums exempté ne touche pas au pool', () {
      final shown = <String>{};
      final albums = dedupeShelfItems(<MuzoItem>[song('A', 'Ninho')]);
      expect(albums.length, 1);
      expect(shown, isEmpty);
      // Le rayon de titres qui suit garde donc sa chance sur le même artiste.
      final songs = claimShelfItems(shown, <MuzoItem>[song('B', 'Ninho')]);
      expect(songs.items.map((i) => i.title), <String>['B']);
    });
  });
}

class _Named {
  const _Named(this.name);
  final String name;
}
