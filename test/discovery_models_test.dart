import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/discovery_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/utils/period_utils.dart';

MuzoItem _album(String id, String title, {DateTime? releaseDate}) {
  return MuzoItem(
    title: title,
    thumbnails: const [],
    resultType: 'album',
    isExplicit: false,
    browseId: 'dz:$id',
    sourceId: id,
    source: 'deezer',
    releaseDate: releaseDate,
    artists: [MuzoArtist(name: 'Artist $id', id: null)],
  );
}

void main() {
  group('DiscoverySection', () {
    test('default is available, not loading, no error', () {
      final s = DiscoverySection<MuzoItem>(
        title: 't',
        period: last7Days(DateTime.utc(2026, 3, 15)),
      );
      expect(s.availability, SectionAvailability.available);
      expect(s.isLoading, isFalse);
      expect(s.errorMessage, isNull);
      expect(s.isEmpty, isTrue);
      expect(s.showUnavailable, isFalse);
    });

    test('showUnavailable only when flagged and not loading', () {
      final s = DiscoverySection<MuzoItem>(
        title: 't',
        period: previousMonth(DateTime.utc(2026, 3, 15)),
        availability: SectionAvailability.dataUnavailable,
      );
      expect(s.showUnavailable, isTrue);
      final loading = s.copyWith(isLoading: true);
      expect(loading.showUnavailable, isFalse);
    });

    test('copyWith replaces items and keeps title', () {
      final s = DiscoverySection<MuzoItem>(
        title: 'Nouvelles sorties',
        period: last7Days(DateTime.utc(2026, 3, 15)),
      );
      final items = [_album('1', 'A', releaseDate: DateTime.utc(2026, 3, 10))];
      final updated = s.copyWith(items: items);
      expect(updated.title, 'Nouvelles sorties');
      expect(updated.items.length, 1);
      expect(updated.isEmpty, isFalse);
    });
  });

  group('PopularArtist / PopularAlbum', () {
    test('PopularArtist json round-trip', () {
      final a = PopularArtist(
        name: 'Jul',
        imageUrl: 'https://example.com/a.jpg',
        artistId: '42',
        popularityScore: 9.5,
      );
      final r = PopularArtist.fromJson(a.toJson());
      expect(r.name, 'Jul');
      expect(r.imageUrl, a.imageUrl);
      expect(r.artistId, '42');
      expect(r.popularityScore, 9.5);
    });

    test('PopularAlbum json round-trip', () {
      final a = PopularAlbum(
        title: 'Cœur Noir',
        artistName: 'Jul',
        coverUrl: 'https://example.com/c.jpg',
        albumId: '99',
        releaseDate: DateTime.utc(2026, 2, 1),
        popularityScore: 8.1,
      );
      final r = PopularAlbum.fromJson(a.toJson());
      expect(r.title, 'Cœur Noir');
      expect(r.artistName, 'Jul');
      expect(r.releaseDate, DateTime.utc(2026, 2, 1));
      expect(r.popularityScore, 8.1);
    });
  });

  group('DiscoveryFeed', () {
    test('isLoading true when any section loads', () {
      final p = previousMonth(DateTime.utc(2026, 3, 15));
      final feed = DiscoveryFeed(
        newReleases: DiscoverySection<MuzoItem>(
            title: 'a', period: last7Days(DateTime.utc(2026, 3, 15))),
        newAlbums: DiscoverySection<MuzoItem>(
            title: 'b', period: last30Days(DateTime.utc(2026, 3, 15))),
        popularArtists:
            DiscoverySection<PopularArtist>(title: 'c', period: p),
        popularAlbums:
            DiscoverySection<PopularAlbum>(title: 'd', period: p),
      );
      expect(feed.isLoading, isFalse);
      expect(feed.hasError, isFalse);

      final loading =
          feed.copyWith(newReleases: feed.newReleases.copyWith(isLoading: true));
      expect(loading.isLoading, isTrue);

      final errored = feed.copyWith(
        popularAlbums: feed.popularAlbums.copyWith(errorMessage: 'boom'),
      );
      expect(errored.hasError, isTrue);
    });
  });
}
