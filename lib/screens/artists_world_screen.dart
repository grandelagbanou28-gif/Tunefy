import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/services/curated_artists_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/artist_avatar.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Title-cased, human display name for a genre key.
String _displayFor(String genre) {
  const overrides = {
    'hip-hop': 'Hip-Hop',
    'r&b': 'R&B',
    'k-pop': 'K-Pop',
    'afrobeats': 'Afrobeats',
    'electronic': 'Electronic',
  };
  if (overrides.containsKey(genre)) return overrides[genre]!;
  return genre
      .split(RegExp(r'[\s\-]+'))
      .map((w) => w.isEmpty
          ? w
          : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Full-screen catalog of artists from around the world, grouped by genre.
/// Tapping a genre opens the artists of that genre (with real images).
class ArtistsWorldScreen extends ConsumerStatefulWidget {
  const ArtistsWorldScreen({super.key});

  @override
  ConsumerState<ArtistsWorldScreen> createState() => _ArtistsWorldScreenState();
}

class _ArtistsWorldScreenState extends ConsumerState<ArtistsWorldScreen> {
  static final List<Color> _palette = [
    const Color(0xFF7C4DFF),
    const Color(0xFF26A69A),
    const Color(0xFF5C6BC0),
    const Color(0xFFEF5350),
    const Color(0xFF42A5F5),
    const Color(0xFFEC407A),
    const Color(0xFF66BB6A),
    const Color(0xFFFFA726),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = CuratedArtistsService.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.artistsWorldTitle),
        automaticallyImplyLeading: true,
        titleSpacing: 0,
      ),
      body: FutureBuilder<bool>(
        future: service.whenReady(),
        builder: (context, snapshot) {
          final ready = snapshot.hasData && snapshot.data == true;
          if (!ready) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: SpotifySpinner(),
              ),
            );
          }
          final genres = service.availableGenres;
          if (genres.isEmpty) {
            return Center(
              child: Text(l10n.artistsWorldCatalogUnavailable),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.78,
            ),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              final artists = service.artistsFor(genre);
              final color = _palette[index % _palette.length];
              return _GenreCard(
                title: _displayFor(genre),
                subtitle:
                    l10n.artistsCount({'count': '${artists.length}'}),
                coverArtists: artists.take(3).toList(),
                color: color,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    SlidePageRoute(
                      page: ArtistsByGenreScreen(genre: genre),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// A single genre card. Shows a fanned cover collage of up to 3 real artist
/// images; falls back to initials if no image is available.
class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.title,
    required this.subtitle,
    required this.coverArtists,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<CuratedArtist> coverArtists;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _CoverCollage(artists: coverArtists, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlapping circular covers (up to 3) so the card reads as "a group".
class _CoverCollage extends StatelessWidget {
  const _CoverCollage({required this.artists, required this.color});

  final List<CuratedArtist> artists;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.music_note,
            color: Colors.white.withValues(alpha: 0.9), size: 40),
      );
    }
    const size = 56.0;
    final overlays = artists.take(3).toList();
    final offset = overlays.length > 1 ? 14.0 : 0.0;
    final n = overlays.length.toDouble();
    final totalWidth = overlays.length <= 1
        ? size
        : size + (n - 1) * offset;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: totalWidth,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < overlays.length; i++)
              Transform.translate(
                offset: Offset((i - (overlays.length - 1) / 2) * offset, 0),
                child: ArtistAvatar(
                  artistName: overlays[i].name,
                  size: size,
                  imageUrl: overlays[i].imageUrl,
                  circle: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lists the curated artists of one genre with their real images.
class ArtistsByGenreScreen extends ConsumerWidget {
  final String genre;
  const ArtistsByGenreScreen({super.key, required this.genre});

  static const List<Color> _colors = [
    Color(0xFF7C4DFF),
    Color(0xFF26A69A),
    Color(0xFF5C6BC0),
    Color(0xFFEF5350),
    Color(0xFF42A5F5),
    Color(0xFFEC407A),
    Color(0xFF66BB6A),
    Color(0xFFFFA726),
    Color(0xFF26C6DA),
    Color(0xFFAB47BC),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final artists = CuratedArtistsService.instance.artistsFor(genre);
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayFor(genre)),
        automaticallyImplyLeading: true,
        titleSpacing: 0,
      ),
      body: artists.isEmpty
          ? Center(child: Text(l10n.artistsWorldNoArtistForGenre))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final a = artists[index];
                final color = _colors[index % _colors.length];
                return _ArtistCardFor(
                  artist: a,
                  color: color,
                );
              },
            ),
    );
  }
}

class _ArtistCardFor extends StatelessWidget {
  const _ArtistCardFor({required this.artist, required this.color});

  final CuratedArtist artist;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          SlidePageRoute(
            page: ArtistPageScreen(
              artistName: artist.name,
              imageUrl: artist.imageUrl,
              color: color,
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ArtistAvatar(
                  artistName: artist.name,
                  size: 120,
                  imageUrl: artist.imageUrl,
                  circle: true,
                ),
                if (artist.followers > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4, right: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatCount(artist.followers),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            artist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) {
      final m = n / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
    }
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}