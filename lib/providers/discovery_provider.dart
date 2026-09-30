import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/discovery_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/discovery_service.dart';
import 'package:muzo/utils/period_utils.dart';

/// Aggregate discovery feed (4 sections), loaded in parallel.
final discoveryFeedProvider =
    FutureProvider.autoDispose<DiscoveryFeed>((ref) async {
  final svc = ref.read(discoveryServiceProvider);
  final results = await Future.wait<Object>([
    svc.fetchNewReleases(period: last7Days()),
    svc.fetchNewAlbums(period: last30Days()),
    svc.fetchPopularArtists(period: previousMonth()),
    svc.fetchPopularAlbums(period: previousMonth()),
  ]);
  return DiscoveryFeed(
    newReleases: results[0] as DiscoverySection<MuzoItem>,
    newAlbums: results[1] as DiscoverySection<MuzoItem>,
    popularArtists: results[2] as DiscoverySection<PopularArtist>,
    popularAlbums: results[3] as DiscoverySection<PopularAlbum>,
  );
});

/// Individual section providers for finer-grained loading / retry.
final discoveryNewReleasesProvider = FutureProvider.autoDispose<
    DiscoverySection<MuzoItem>>((ref) {
  final svc = ref.read(discoveryServiceProvider);
  return svc.fetchNewReleases(period: last7Days());
});

final discoveryNewAlbumsProvider =
    FutureProvider.autoDispose<DiscoverySection<MuzoItem>>((ref) {
  final svc = ref.read(discoveryServiceProvider);
  return svc.fetchNewAlbums(period: last30Days());
});

final discoveryPopularArtistsProvider = FutureProvider.autoDispose<
    DiscoverySection<PopularArtist>>((ref) {
  final svc = ref.read(discoveryServiceProvider);
  return svc.fetchPopularArtists(period: previousMonth());
});

final discoveryPopularAlbumsProvider = FutureProvider.autoDispose<
    DiscoverySection<PopularAlbum>>((ref) {
  final svc = ref.read(discoveryServiceProvider);
  return svc.fetchPopularAlbums(period: previousMonth());
});
