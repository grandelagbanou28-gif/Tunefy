import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/category_artists_service.dart';
import 'package:muzo/services/gospel_artist_database.dart';
import 'package:muzo/services/strict_category_filter.dart';

MuzoItem song(String title, String artist, {String? album, int duration = 240}) {
  return MuzoItem(
    title: title,
    thumbnails: const [],
    resultType: 'video',
    isExplicit: false,
    videoId: 'v-$title-$artist',
    artists: [MuzoArtist(name: artist, id: null)],
    album: album != null ? MuzoAlbum(name: album, id: '') : null,
    durationSeconds: duration,
  );
}

void main() {
  group('constraint resolution', () {
    test('Gospel Benin -> genre gospel + geo benin', () {
      final c = categoryConstraintFor('Gospel', 'Benin Gospel');
      expect(c.genre, 'gospel');
      expect(c.geo, 'benin');
      expect(c.isGeoScoped, isTrue);
      expect(c.includeMarkers, contains('benin'));
      expect(c.includeMarkers, contains('cotonou'));
      expect(c.excludeMarkers, isNot(contains('benin')));
      expect(c.excludeMarkers, contains('lagos'));
      expect(c.excludeMarkers, contains('american'));
    });

    test('African Gospel -> geo africa, keeps same-region markers as includes',
        () {
      final c = categoryConstraintFor('Gospel', 'African Gospel');
      expect(c.geo, 'africa');
      expect(c.excludeMarkers, isNot(contains('nigerian')));
      expect(c.excludeMarkers, isNot(contains('lagos')));
      expect(c.excludeMarkers, contains('american'));
      expect(c.excludeMarkers, contains('bollywood'));
    });

    test('scoped search term is composite, never bare category name', () {
      expect(
        buildScopedSearchTerm('Gospel', 'Benin Gospel', 'gospel'),
        'gospel benin',
      );
      expect(
        buildScopedSearchTerm('Rap', 'Rap Français', 'rap'),
        'rap français',
      );
    });
  });

  group('a genre name is not a country', () {
    // Mesuré le 2026-10-11 sur l'appareil : la carte Amapiano rendait 8 rayons
    // vides, Reggae 11/12 et Dancehall 7/8, parce que le mot de genre figurait
    // dans la liste de marqueurs d'un pays et géo-scopait donc la section.
    test('scene words do not geo-scope their own card', () {
      expect(detectGeo('Amapiano', 'Amapiano Hits'), isNull);
      expect(detectGeo('Reggae', 'Roots Reggae'), isNull);
      expect(detectGeo('Dancehall', 'Bashment'), isNull);
      expect(detectGeo('House', 'Amapiano'), isNull);
      expect(detectGeo('Desi', 'Bollywood Classics'), isNull);
      expect(categoryConstraintFor('Amapiano', 'Log Drums').isGeoScoped, isFalse);
    });

    test('the genre word still scopes the search term, without a country', () {
      expect(buildScopedSearchTerm('Amapiano', 'Amapiano Hits', 'amapiano hits'),
          'amapiano');
    });

    test('an explicit country still geo-scopes', () {
      expect(detectGeo('Rap Français', 'Trap FR'), 'france');
      expect(detectGeo('Gospel', 'Benin Gospel'), 'benin');
      expect(detectGeo('Afrobeats', 'Nigerian Afrobeats'), 'nigeria');
      expect(detectGeo('Reggae', 'African Reggae'), 'africa');
      expect(detectGeo('Caribbean', 'Dancehall'), 'caribbean');
    });

    test('a country marker still vetoes a foreign track in a geo section', () {
      final c = categoryConstraintFor('Gospel', 'Benin Gospel');
      expect(acceptsForCategory(song('Hosanna', 'Sinach Lagos'), c), isFalse);
    });
  });

  group('gospel artist database', () {
    test('Fanicko is NOT gospel (R&B/afrobeat)', () {
      expect(gospelArtistGeo('Fanicko'), isNull);
      expect(gospelArtistGeo('Fanicko Officiel'), isNull);
    });

    test('Siano Bless is confirmed Beninese gospel', () {
      expect(gospelArtistGeo('Siano Bless'), 'benin');
      expect(gospelArtistGeo('Siano Bless Officiel'), 'benin');
    });

    test('Sinach is confirmed Nigerian gospel', () {
      expect(gospelArtistGeo('Sinach'), 'nigeria');
      expect(gospelArtistGeo('Sinach - Topic'), 'nigeria');
    });

    test('region containment', () {
      expect(regionContainsGeo('africa', 'nigeria'), isTrue);
      expect(regionContainsGeo('africa', 'usa'), isFalse);
      expect(regionContainsGeo('benin', 'nigeria'), isFalse);
      expect(regionContainsGeo('benin', 'benin'), isTrue);
    });
  });

  group('Gospel Benin strict validation', () {
    final c = categoryConstraintFor('Gospel', 'Benin Gospel');

    test('real Beninese gospel artists are ACCEPTED', () {
      expect(acceptsForCategory(song('Oh Merci Seigneur', 'Siano Bless'), c),
          isTrue);
      expect(acceptsForCategory(song('Dossou Idjè', 'Anna Tèko'), c), isTrue);
    });

    test('Fanicko (Beninese but R&B, not gospel) is REJECTED', () {
      expect(acceptsForCategory(song('Folies', 'Fanicko'), c), isFalse);
    });

    test('Nigerian gospel is REJECTED from Benin Gospel', () {
      expect(
        acceptsForCategory(song('Tobechukwu', 'Nathaniel Bassey'), c),
        isFalse,
      );
      expect(acceptsForCategory(song('Excess Love', 'Mercy Chinwo'), c),
          isFalse);
      expect(acceptsForCategory(song('Way Maker', 'Sinach'), c), isFalse);
    });

    test('US gospel is REJECTED', () {
      expect(
        acceptsForCategory(song('American Gospel Hits', 'Bethel Music'), c),
        isFalse,
      );
    });

    test('unknown artist: genre word AND country marker both required', () {
      // "Gospel" word + Cotonou marker in the ARTIST/CHANNEL context -> in.
      // (The marker must not come from the title alone: compilation videos
      // like "Rap du Benin 2024" featuring foreign artists must not pass.)
      expect(
        acceptsForCategory(
            song('Gospel Praise', 'Chorale Alleluia Cotonou'), c),
        isTrue,
      );
      // Genre word but no Benin marker -> out.
      expect(acceptsForCategory(song('Gospel Hymns', 'Unknown Choir'), c),
          isFalse);
      // No genre word, no country -> out.
      expect(acceptsForCategory(song('Folies', 'X-TIME'), c), isFalse);
    });
  });

  group('African Gospel (region) validation', () {
    final c = categoryConstraintFor('Gospel', 'African Gospel');

    test('Nigerian gospel is ACCEPTED inside the Africa region', () {
      expect(acceptsForCategory(song('Tobechukwu', 'Nathaniel Bassey'), c),
          isTrue);
      expect(acceptsForCategory(song('Excess Love', 'Mercy Chinwo'), c),
          isTrue);
    });

    test('Beninese gospel is ACCEPTED inside the Africa region', () {
      expect(acceptsForCategory(song('Oh Merci Seigneur', 'Siano Bless'), c),
          isTrue);
    });

    test('US gospel is REJECTED from African Gospel', () {
      expect(acceptsForCategory(song('Way Maker', 'Bethel Music'), c), isFalse);
    });
  });

  group('Ghana gospel validation', () {
    final c = categoryConstraintFor('Gospel', 'Ghana Gospel');

    test('Ghanaian gospel accepted, Nigerian rejected', () {
      expect(acceptsForCategory(song('Nhyira', 'Joe Mettle'), c), isTrue);
      expect(acceptsForCategory(song('Tobechukwu', 'Nathaniel Bassey'), c),
          isFalse);
    });
  });

  group('pure genre section (non-geo)', () {
    // Such a section is fetched under its own name ("gospel", "latin",
    // "drill"), so the query does the selecting: the gate only ranks, it never
    // deletes. Country strictness lives entirely in the geo-scoped groups.
    test('candidates are kept and ranked, never vetoed on the word', () {
      final c = categoryConstraintFor('Gospel', 'Gospel');
      expect(c.geo, isEmpty);
      expect(acceptsForCategory(song('Gospel Sunday Service', 'Kirk Franklin'), c),
          isTrue);
      // Confirmed gospel artist without "gospel" in the title.
      expect(acceptsForCategory(song('Way Maker', 'Sinach'), c), isTrue);
      // Plain song the same query returned: kept.
      expect(acceptsForCategory(song('Party All Night', 'DJ Random'), c),
          isTrue);
      // …but ranked below the genre-confirmed one.
      expect(
          categoryMatchScore(song('Gospel Sunday Service', 'Kirk Franklin'), c),
          greaterThan(
              categoryMatchScore(song('Party All Night', 'DJ Random'), c)));
    });
  });

  group('detectGeo', () {
    test('never guesses a country from a bare genre', () {
      expect(detectGeo('Gospel', 'Gospel'), isNull);
      expect(detectGeo('Rap', 'Gangster Rap'), isNull);
    });
  });

  group('curated seed authority (Priority 0)', () {
    setUp(() {
      CategoryArtistsService.instance.seedForTest({
        'Hit Benin > Top Benin': ['Fanicko', 'Angélique Kidjo'],
        'Hit Benin > Benin Rap': ['Gnonnas Pédro'],
      });
    });

    test('containsArtist matches with accent folding', () {
      expect(
        CategoryArtistsService.instance
            .containsArtist('benin hits', 'Top Benin', 'Angelique Kidjo'),
        isTrue,
      );
      expect(
        CategoryArtistsService.instance
            .containsArtist('Hit Benin', 'Top Benin', 'Fanicko'),
        isTrue,
      );
      expect(
        CategoryArtistsService.instance
            .containsArtist('benin hits', 'Top Benin', 'Wizkid'),
        isFalse,
      );
    });

    test('curated artist accepted despite missing country marker', () {
      final c = categoryConstraintFor('benin hits', 'Top Benin');
      expect(c.geo, 'benin');
      expect(acceptsForCategory(song('Folies', 'Fanicko'), c), isTrue);
    });

    test('non-curated artist still rejected by strict geo gate', () {
      final c = categoryConstraintFor('benin hits', 'Top Benin');
      expect(acceptsForCategory(song('Lagos Nights', 'Oxlade'), c), isFalse);
    });

    test('artist only in a different sub does not leak into this one', () {
      final c = categoryConstraintFor('benin hits', 'Top Benin');
      expect(acceptsForCategory(song('Akwaba', 'Gnonnas Pédro'), c), isFalse);
    });
  });
}
