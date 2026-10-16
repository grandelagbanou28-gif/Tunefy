import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/discovery_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/discovery_provider.dart';
import 'package:muzo/screens/album_screen.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/utils/period_utils.dart';
import 'package:muzo/utils/release_playback.dart';
import 'package:muzo/utils/shelf_claim.dart';
import 'package:muzo/utils/song_navigation.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/skeleton_loader.dart';

/// Localized caption for a discovery shelf period (rolling windows + months).
String localizedPeriodLabel(BuildContext context, DiscoveryPeriod p) {
  final l10n = AppLocalizations.of(context);
  return l10n.periodLabelFor(p.id, month: p.month, year: p.year);
}

// ─── Generic section shell ───────────────────────────────────────────────

class _MuzoSection extends StatelessWidget {
  final String title;
  final String periodLabel;
  final DiscoverySection<MuzoItem> section;
  final String emptyMessage;
  final Widget Function(MuzoItem) itemBuilder;

  const _MuzoSection({
    required this.title,
    required this.periodLabel,
    required this.section,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          periodLabel: periodLabel,
        ),
        if (section.isLoading)
          const HomeSkeletonSection(forceDark: true, 
            showTitle: false,
            rowHeight: 200,
            itemSpacing: 14,
          )
        else if (section.showUnavailable)
          const _UnavailableState()
        else if (section.errorMessage != null)
          _SectionError(message: section.errorMessage!)
        else if (section.isEmpty)
          _EmptyState(message: emptyMessage)
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => itemBuilder(section.items[i]),
            ),
          ),
      ],
    );
  }
}

class _ArtistSection extends StatelessWidget {
  final String title;
  final String periodLabel;
  final DiscoverySection<PopularArtist> section;
  final String emptyMessage;

  const _ArtistSection({
    required this.title,
    required this.periodLabel,
    required this.section,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          periodLabel: periodLabel,
        ),
        if (section.isLoading)
          const HomeSkeletonSection(forceDark: true, 
            showTitle: false,
            rowHeight: 200,
            itemSpacing: 14,
          )
        else if (section.showUnavailable)
          const _UnavailableState()
        else if (section.errorMessage != null)
          _SectionError(message: section.errorMessage!)
        else if (section.isEmpty)
          _EmptyState(message: emptyMessage)
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, i) =>
                  _ArtistCard(artist: section.items[i]),
            ),
          ),
      ],
    );
  }
}

class _AlbumSection extends StatelessWidget {
  final String title;
  final String periodLabel;
  final DiscoverySection<PopularAlbum> section;
  final String emptyMessage;

  const _AlbumSection({
    required this.title,
    required this.periodLabel,
    required this.section,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          periodLabel: periodLabel,
        ),
        if (section.isLoading)
          const HomeSkeletonSection(forceDark: true, 
            showTitle: false,
            rowHeight: 200,
            itemSpacing: 14,
          )
        else if (section.showUnavailable)
          const _UnavailableState()
        else if (section.errorMessage != null)
          _SectionError(message: section.errorMessage!)
        else if (section.isEmpty)
          _EmptyState(message: emptyMessage)
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) =>
                  _PopularAlbumCard(album: section.items[i]),
            ),
          ),
      ],
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String periodLabel;

  const _SectionHeader({
    required this.title,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: spotifyWhite,
            ),
          ),
          if (periodLabel.isNotEmpty)
            Text(
              periodLabel,
              style: TextStyle(
                fontSize: 12,
                color: spotifyLightGrey.withValues(alpha: 0.9),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        AppLocalizations.of(context).dataUnavailable,
        style: TextStyle(
          color: spotifyLightGrey.withValues(alpha: 0.9),
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(
          color: spotifyLightGrey.withValues(alpha: 0.9),
          fontSize: 14,
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  final String message;
  const _SectionError({required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${l10n.loadError}: $message',
        style: TextStyle(
          color: Colors.redAccent.withValues(alpha: 0.9),
          fontSize: 13,
        ),
      ),
    );
  }
}


// ─── Cards ───────────────────────────────────────────────────────────────

class _MuzoCard extends ConsumerWidget {
  final MuzoItem item;
  const _MuzoCard({required this.item});

  /// Cover tap. On the release shelves nothing navigates: an unresolved or
  /// non-Deezer album used to land on the artist page, which broke the
  /// "these shelves are a listening surface" rule. It now plays, like the
  /// title does.
  void _open(BuildContext context, WidgetRef ref) {
    HapticFeedback.selectionClick();
    final browse = item.browseId;
    final isDeezerAlbum = browse != null &&
        browse.isNotEmpty &&
        (browse.startsWith('dz:') || browse.startsWith('dz_')) &&
        item.resultType == 'album';
    if (isDeezerAlbum) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AlbumScreen(
            albumId: browse,
            albumName: item.title,
            thumbnailUrl: item.thumbnails.isNotEmpty
                ? item.thumbnails.last.url
                : null,
          ),
        ),
      );
      return;
    }
    playReleaseTitle(
      context,
      ref,
      title: item.title,
      artist: item.displayArtist,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = item.thumbnails.isNotEmpty ? item.thumbnails.last.url : '';
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover opens the album / artist page.
          GestureDetector(
            onTap: () => _open(context, ref),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                height: 140,
                child: BrandBadged(
                  imageUrl: thumb,
                  badgeSize: 20,
                  inset: 6,
                  child: thumb.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Tapping the title plays it here: the cover is the only way to open
          // a page, so browsing and listening never fight over the same tap.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => playReleaseTitle(
              context,
              ref,
              title: item.title,
              artist: item.displayArtist,
            ),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.displayArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: spotifyLightGrey.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: spotifyDarkGrey,
        child: const Center(
          child: Icon(Icons.music_note, color: spotifyLightGrey, size: 32),
        ),
      );
}

class _ArtistCard extends StatelessWidget {
  final PopularArtist artist;
  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    final img = artist.imageUrl ?? '';
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          SlidePageRoute(
            page: ArtistPageScreen(
              artistName: artist.name,
              imageUrl: img.isNotEmpty ? img : null,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 100,
        child: Column(
          children: [
            ClipOval(
              child: SizedBox(
                width: 90,
                height: 90,
                child: BrandBadged(
                  imageUrl: img,
                  badgeSize: 18,
                  opacity: 0.9,
                  inset: 15,
                  child: img.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: spotifyDarkGrey,
        child: const Icon(Icons.person, color: spotifyLightGrey, size: 36),
      );
}

class _PopularAlbumCard extends ConsumerWidget {
  final PopularAlbum album;
  const _PopularAlbumCard({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = album.coverUrl ?? '';
    final artist = album.artistName ?? '';
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover opens the album page.
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              final id = album.albumId;
              if (id == null || id.isEmpty) {
                openArtistForAlbum(
                  context,
                  MuzoItem(
                    title: album.title,
                    thumbnails: cover.isNotEmpty
                        ? [MuzoThumbnail(url: cover, width: 250, height: 250)]
                        : const [],
                    resultType: 'album',
                    isExplicit: false,
                    artists: artist.isNotEmpty
                        ? [MuzoArtist(name: artist, id: null)]
                        : null,
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlbumScreen(
                    albumId: id.startsWith('dz:') ? id : 'dz:$id',
                    albumName: album.title,
                    thumbnailUrl: cover.isNotEmpty ? cover : null,
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                height: 140,
                child: BrandBadged(
                  imageUrl: cover,
                  badgeSize: 20,
                  inset: 6,
                  child: cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Tapping the title plays it without leaving the page.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => playReleaseTitle(
              context,
              ref,
              title: album.title,
              artist: artist,
            ),
            child: Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
            const SizedBox(height: 2),
            Text(
              album.artistName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: spotifyDarkGrey,
        child: const Center(
          child: Icon(Icons.album, color: spotifyLightGrey, size: 32),
        ),
      );
}

// ─── Home-embedded feed ──────────────────────────────────────────────────

/// One Discovery shelf embedded on Home. Sections with no content are fully
/// hidden (not empty-state placeholders). No parent title — each shelf has
/// its own header so Home can place them in any order.
enum DiscoveryHomePart { releases, newAlbums, artists, popularAlbums }

class DiscoveryHomeSection extends ConsumerWidget {
  final DiscoveryHomePart part;
  const DiscoveryHomeSection(this.part, {super.key});

  static bool _hasContent<T>(DiscoverySection<T> s) =>
      !s.isLoading && !s.showUnavailable && s.errorMessage == null && !s.isEmpty;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(discoveryFeedProvider);
    final l10n = AppLocalizations.of(context);
    return feedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (feed) {
        switch (part) {
          case DiscoveryHomePart.releases:
            if (!_hasContent(feed.newReleases)) {
              return const SizedBox.shrink();
            }
            return _MuzoSection(
              title: l10n.discoveryNewReleases,
              periodLabel: localizedPeriodLabel(context, feed.newReleases.period),
              section: feed.newReleases,
              emptyMessage: '',
              itemBuilder: (item) => _MuzoCard(item: item),
            );
          case DiscoveryHomePart.newAlbums:
            if (!_hasContent(feed.newAlbums)) {
              return const SizedBox.shrink();
            }
            return _MuzoSection(
              title: l10n.discoveryNewAlbums,
              periodLabel: localizedPeriodLabel(context, feed.newAlbums.period),
              section: feed.newAlbums,
              emptyMessage: '',
              itemBuilder: (item) => _MuzoCard(item: item),
            );
          case DiscoveryHomePart.artists:
            if (!_hasContent(feed.popularArtists)) {
              return const SizedBox.shrink();
            }
            // Home's artist rule, applied to the avatar row too: an artist
            // already leading a tile in a ray above is a second face of the
            // same person on the same page.
            return ShelfClaimBuilder<PopularArtist>(
              items: feed.popularArtists.items,
              artistOf: (artist) => artist.name,
              keyOf: (artist) =>
                  (artist.artistId ?? artist.name).toLowerCase(),
              builder: (context, claimed) => _ArtistSection(
                title: l10n.discoveryPopularArtists,
                periodLabel:
                    localizedPeriodLabel(context, feed.popularArtists.period),
                section: feed.popularArtists.copyWith(items: claimed),
                emptyMessage: l10n.discoveryEmptyArtists,
              ),
            );
          case DiscoveryHomePart.popularAlbums:
            if (!_hasContent(feed.popularAlbums)) {
              return const SizedBox.shrink();
            }
            // Home's artist rule applies here too: an album by an artist a ray
            // above already showed is a duplicate tile, and this row carried no
            // claim at all before.
            return ShelfClaimBuilder<PopularAlbum>(
              items: feed.popularAlbums.items,
              artistOf: (album) => album.artistName ?? '',
              keyOf: (album) =>
                  (album.albumId ?? album.title).toLowerCase(),
              builder: (context, claimed) => _AlbumSection(
                title: l10n.discoveryPopularAlbums,
                periodLabel:
                    localizedPeriodLabel(context, feed.popularAlbums.period),
                section: feed.popularAlbums.copyWith(items: claimed),
                emptyMessage: l10n.discoveryEmptyPopularAlbums,
              ),
            );
        }
      },
    );
  }
}
