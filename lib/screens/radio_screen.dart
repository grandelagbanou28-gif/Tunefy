import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/radio_browser_service.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// One row of the radio page: a label plus the Radio Browser query behind it.
class _RadioRow {
  const _RadioRow(this.label, {this.tag = '', this.cc = ''});

  final String label;
  final String tag;
  final String cc;
}

/// Every row here was measured against the live registry on 2026-10-11 and
/// returns at least four usable HTTPS streams; a query that came back empty
/// ("rap + BJ", "zouk + CI") was dropped rather than shipped as a dead row.
const List<_RadioRow> _kRadioRows = [
  _RadioRow('Rap & Urbain — France', tag: 'rap', cc: 'FR'),
  _RadioRow('Hip-hop — USA', tag: 'hip hop', cc: 'US'),
  _RadioRow('R&B / Funk — USA', tag: 'r&b', cc: 'US'),
  _RadioRow('Afrobeats', tag: 'afrobeats'),
  _RadioRow('Amapiano', tag: 'amapiano'),
  _RadioRow('Gospel', tag: 'gospel'),
  _RadioRow('Dancehall', tag: 'dancehall'),
  _RadioRow('Reggae — France', tag: 'reggae', cc: 'FR'),
  _RadioRow('Hits & Pop — France', tag: 'hits', cc: 'FR'),
  _RadioRow('Bénin — en direct', cc: 'BJ'),
  _RadioRow('Côte d\'Ivoire', cc: 'CI'),
  _RadioRow('Sénégal', cc: 'SN'),
  _RadioRow('Ghana', cc: 'GH'),
];

/// Stations are cached raw (shared across installs) and rotated at read time,
/// so two phones show the same pool in a different order — the rule every other
/// browse surface follows.
final radioRowProvider =
    FutureProvider.family<List<MuzoItem>, ({String tag, String cc})>(
  (ref, key) async {
    final stations = await RadioBrowserService.instance.stations(
      tag: key.tag,
      countryCode: key.cc,
      limit: 18,
    );
    if (stations.isEmpty) return const [];
    return ContentCacheService.rotate(
      stations,
      ContentCacheService.refreshBucket,
    );
  },
);

class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key, this.initialTag = '', this.initialCountry = ''});

  /// When opened from a category, that row is placed first and loaded eagerly.
  final String initialTag;
  final String initialCountry;

  static const Color _green = Color(0xFF1DB954);

  List<_RadioRow> get _rows {
    if (initialTag.isEmpty && initialCountry.isEmpty) return _kRadioRows;
    final pinned = _RadioRow(
      initialCountry.isEmpty ? initialTag : '$initialTag — $initialCountry',
      tag: initialTag,
      cc: initialCountry,
    );
    return [pinned, ..._kRadioRows];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
                child: Row(
                  children: [
                    const SpotifyBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Radio',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: spotifyWhite,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'En direct — aucun téléchargement, aucune redirection',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: spotifyLightGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final row in _rows)
              SliverToBoxAdapter(child: _RadioSection(row: row, green: _green)),
            const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
          ],
        ),
      ),
    );
  }
}

class _RadioSection extends ConsumerWidget {
  const _RadioSection({required this.row, required this.green});

  final _RadioRow row;
  final Color green;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same key shape as the provider family: tag + country code.
    final stationsAsync =
        ref.watch(radioRowProvider((tag: row.tag, cc: row.cc)));
    final stations = stationsAsync.value ?? const <MuzoItem>[];
    if (stationsAsync.isLoading && stations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(row.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: spotifyWhite)),
            ),
            const SizedBox(width: 14),
            SpotifySpinner(color: green),
          ],
        ),
      );
    }
    // A row the registry cannot fill stays hidden rather than becoming an
    // empty band — the same rule the category page uses.
    if (stations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
          child: Row(
            children: [
              Icon(Icons.radio_rounded, size: 16, color: green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.label,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: spotifyWhite,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: stations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _StationCard(
              station: stations[index],
              green: green,
              onPlay: () {
                HapticFeedback.mediumImpact();
                ref.read(audioHandlerProvider).playVideo(stations[index]);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.green,
    required this.onPlay,
  });

  final MuzoItem station;
  final Color green;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final art = station.thumbnails.isNotEmpty
        ? station.thumbnails.last.url
        : '';
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: const Color(0xFF282828),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: art.isEmpty
                  ? Center(
                      child: Icon(Icons.graphic_eq_rounded,
                          size: 44, color: green.withValues(alpha: .8)))
                  : Image.network(
                      art,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.graphic_eq_rounded,
                            size: 44, color: green.withValues(alpha: .8)),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              station.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: spotifyWhite,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              station.displayArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: spotifyLightGrey.withValues(alpha: .85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
