import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/services/concert_service.dart';

void main() {
  group('Ticketmaster artist filter', () {
    test('a long artist name matches inside an event title', () {
      expect(ConcertService.debugNamesArtist(['Damso at Zenith'], 'Damso'),
          isTrue);
      expect(ConcertService.debugNamesArtist(['Damso'], 'Damso'), isTrue);
    });

    test('an unrelated venue is rejected', () {
      expect(ConcertService.debugNamesArtist(['Zenith Paris'], 'Damso'), isFalse);
    });

    test('a short name needs a whole word', () {
      // This is the real trap: Ticketmaster answers "Jul" with Oasis and
      // Bon Jovi, which would be shown on Jul's page as his own dates.
      expect(ConcertService.debugNamesArtist(['Oasis Live 27'], 'Jul'), isFalse);
      expect(ConcertService.debugNamesArtist(['JUL'], 'Jul'), isTrue);
      expect(ConcertService.debugNamesArtist(['Jul - Paris'], 'Jul'), isTrue);
      expect(ConcertService.debugNamesArtist(['Julius Caesar Live'], 'Jul'),
          isFalse);
      expect(ConcertService.debugNamesArtist(['Tour de Jules'], 'Jul'), isFalse);
    });

    test('accents and case do not matter', () {
      expect(ConcertService.debugNamesArtist(['GIMS au Zenith'], 'Gims'), isTrue);
      expect(ConcertService.debugNamesArtist(['aya'], 'Aya'), isTrue);
    });

    test('any of the fields may carry the name', () {
      expect(
        ConcertService.debugNamesArtist(
          ['Stade de France', 'Soprano, Jul'],
          'Jul',
        ),
        isTrue,
      );
    });

    test('an empty artist name never filters anything out', () {
      expect(ConcertService.debugNamesArtist(['Anything'], ''), isTrue);
    });
  });

  group('Setlist.fm date parsing', () {
    test('reads the dd-MM-yyyy format the API returns', () {
      // Dart cannot parse that format, and ConcertEvent.fromJson only takes
      // ISO, so the conversion has to happen here.
      expect(ConcertService.debugParseSetlistDate('12-07-2026'), DateTime(2026, 7, 12));
    });

    test('a festival range keeps its first day', () {
      expect(
        ConcertService.debugParseSetlistDate('24-06-2026/26-06-2026'),
        DateTime(2026, 6, 24),
      );
    });

    test('rejects what is not a date', () {
      expect(ConcertService.debugParseSetlistDate(''), isNull);
      expect(ConcertService.debugParseSetlistDate('TBD'), isNull);
      expect(ConcertService.debugParseSetlistDate('32-13-2026'), isNull);
    });
  });
}
