import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/utils/period_utils.dart';

/// Availability flag for a discovery section: real data vs. intentionally
/// empty (no trustworthy popularity stats for the period).
enum SectionAvailability { available, dataUnavailable }

/// One artist entry in the discovery feed. Carries only real catalog data;
/// never invents popularity numbers.
class PopularArtist {
  final String name;
  final String? imageUrl;
  final String? artistId;
  final double? popularityScore;

  const PopularArtist({
    required this.name,
    this.imageUrl,
    this.artistId,
    this.popularityScore,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'imageUrl': imageUrl,
        'artistId': artistId,
        'popularityScore': popularityScore,
      };

  factory PopularArtist.fromJson(Map<String, dynamic> j) => PopularArtist(
        name: j['name'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        artistId: j['artistId'] as String?,
        popularityScore: (j['popularityScore'] as num?)?.toDouble(),
      );
}

/// One album entry in the discovery feed.
class PopularAlbum {
  final String title;
  final String? artistName;
  final String? coverUrl;
  final String? albumId;
  final DateTime? releaseDate;
  final double? popularityScore;

  const PopularAlbum({
    required this.title,
    this.artistName,
    this.coverUrl,
    this.albumId,
    this.releaseDate,
    this.popularityScore,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'artistName': artistName,
        'coverUrl': coverUrl,
        'albumId': albumId,
        'releaseDate': releaseDate?.toIso8601String(),
        'popularityScore': popularityScore,
      };

  factory PopularAlbum.fromJson(Map<String, dynamic> j) => PopularAlbum(
        title: j['title'] as String? ?? '',
        artistName: j['artistName'] as String?,
        coverUrl: j['coverUrl'] as String?,
        albumId: j['albumId'] as String?,
        releaseDate: j['releaseDate'] != null
            ? DateTime.tryParse(j['releaseDate'] as String)
            : null,
        popularityScore: (j['popularityScore'] as num?)?.toDouble(),
      );
}

/// One section of the discovery feed.
class DiscoverySection<T> {
  final String title;
  final DiscoveryPeriod period;
  final List<T> items;
  final SectionAvailability availability;
  final bool isLoading;
  final String? errorMessage;

  const DiscoverySection({
    required this.title,
    required this.period,
    this.items = const [],
    this.availability = SectionAvailability.available,
    this.isLoading = false,
    this.errorMessage,
  });

  DiscoverySection<T> copyWith({
    String? title,
    DiscoveryPeriod? period,
    List<T>? items,
    SectionAvailability? availability,
    bool? isLoading,
    String? errorMessage,
  }) =>
      DiscoverySection<T>(
        title: title ?? this.title,
        period: period ?? this.period,
        items: items ?? this.items,
        availability: availability ?? this.availability,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
      );

  bool get isEmpty => items.isEmpty;
  bool get showUnavailable =>
      availability == SectionAvailability.dataUnavailable && !isLoading;
}

/// Aggregate of the four discovery sections.
class DiscoveryFeed {
  final DiscoverySection<MuzoItem> newReleases;
  final DiscoverySection<MuzoItem> newAlbums;
  final DiscoverySection<PopularArtist> popularArtists;
  final DiscoverySection<PopularAlbum> popularAlbums;

  const DiscoveryFeed({
    required this.newReleases,
    required this.newAlbums,
    required this.popularArtists,
    required this.popularAlbums,
  });

  DiscoveryFeed copyWith({
    DiscoverySection<MuzoItem>? newReleases,
    DiscoverySection<MuzoItem>? newAlbums,
    DiscoverySection<PopularArtist>? popularArtists,
    DiscoverySection<PopularAlbum>? popularAlbums,
  }) =>
      DiscoveryFeed(
        newReleases: newReleases ?? this.newReleases,
        newAlbums: newAlbums ?? this.newAlbums,
        popularArtists: popularArtists ?? this.popularArtists,
        popularAlbums: popularAlbums ?? this.popularAlbums,
      );

  bool get isLoading =>
      newReleases.isLoading ||
      newAlbums.isLoading ||
      popularArtists.isLoading ||
      popularAlbums.isLoading;

  bool get hasError =>
      newReleases.errorMessage != null ||
      newAlbums.errorMessage != null ||
      popularArtists.errorMessage != null ||
      popularAlbums.errorMessage != null;
}
