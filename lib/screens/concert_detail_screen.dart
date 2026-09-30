import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/concert_event.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/screens/concert_video_screen.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full concert details: date, venue, price, official ticket link and —
/// for past dates — real concert videos found on YouTube, playable in-app.
class ConcertDetailScreen extends ConsumerWidget {
  const ConcertDetailScreen({super.key, required this.event});

  final ConcertEvent event;

  String _dateLabel(AppLocalizations l10n) {
    final d = event.date;
    if (d == null) return l10n.concertDateTbc;
    final base = '${d.day} ${l10n.monthName(d.month)} ${d.year}';
    return event.time.isNotEmpty ? '$base · ${event.time}' : base;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasTickets = event.ticketUrl.startsWith('http');
    final hasImage = event.image.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            backgroundColor: Colors.black,
            leading: const Padding(
              padding: EdgeInsets.all(8),
              child: SpotifyBackButton(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: hasImage
                  ? CachedNetworkImage(
                      imageUrl: event.image,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const _HeaderFallback(),
                    )
                  : const _HeaderFallback(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: event.isUpcoming
                          ? const Color(0xFF1DDA63).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      event.isUpcoming
                          ? l10n.concertUpcoming
                          : l10n.concertPast,
                      style: TextStyle(
                        color: event.isUpcoming
                            ? const Color(0xFF1DDA63)
                            : spotifyLightGrey,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    event.name.isNotEmpty ? event.name : event.artist,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: l10n.concertDate,
                    value: _dateLabel(l10n),
                  ),
                  if (event.locationLabel.isNotEmpty)
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: l10n.concertVenue,
                      value: event.locationLabel,
                    ),
                  if (event.country.isNotEmpty &&
                      !event.locationLabel.contains(event.country))
                    _InfoRow(
                      icon: Icons.public,
                      label: l10n.concertCountry,
                      value: event.country,
                    ),
                  if (event.priceLabel.isNotEmpty)
                    _InfoRow(
                      icon: Icons.confirmation_number_outlined,
                      label: l10n.concertPrice,
                      value: event.priceLabel,
                    ),
                  if (event.source.isNotEmpty)
                    _InfoRow(
                      icon: Icons.verified_outlined,
                      label: l10n.concertSource,
                      value: event.source,
                    ),
                  const SizedBox(height: 20),
                  if (hasTickets)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final ok = await launchUrl(
                            Uri.parse(event.ticketUrl),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!ok && context.mounted) {
                            showGlassSnackBar(
                              context,
                              l10n.concertTicketsOpenFailed,
                              error: true,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DDA63),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Text(
                          l10n.concertViewTickets,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _ConcertVideosSection(event: event),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1DDA63).withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.local_fire_department_outlined,
          size: 64,
          color: Colors.white54,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: spotifyLightGrey),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: spotifyLightGrey.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: spotifyWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared YouTube query for a concert's videos — used by the detail screen
/// AND by the artist page (stats / prefetch) so both hit the same cache key.
String concertVideoQuery(ConcertEvent event) {
  final year = event.date?.year.toString() ?? '';
  final parts = [
    event.artist,
    'concert',
    if (event.city.isNotEmpty) event.city,
    if (year.isNotEmpty) year,
  ];
  return parts.join(' ');
}

/// Fallback query when the artist has no archived date to scope the search
/// to: still finds live performances instead of showing nothing.
String concertArtistVideoQuery(String artist) => '$artist live concert';

/// Concert videos. A past date scopes the search to that exact show, anything
/// else falls back to the artist's live videos so the section is never empty
/// just because no concert happened yet.
class _ConcertVideosSection extends ConsumerWidget {
  const _ConcertVideosSection({required this.event});

  final ConcertEvent event;

  String get _query => event.date != null && !event.isUpcoming
      ? concertVideoQuery(event)
      : concertArtistVideoQuery(event.artist);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (event.artist.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final videosAsync = ref.watch(concertVideosProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.concertEventVideos,
          style: const TextStyle(
            color: spotifyWhite,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _query,
          style: TextStyle(
            color: spotifyLightGrey.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        videosAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: SpotifySpinner(
                  strokeWidth: 2.5,
                  color: Color(0xFF1DDA63),
                ),
              ),
            ),
          ),
          error: (_, __) => Text(
            l10n.concertVideosUnavailableNow,
            style: const TextStyle(color: spotifyLightGrey, fontSize: 13),
          ),
          data: (videos) {
            if (videos.isEmpty) {
              return Text(
                l10n.concertNoVideosFound,
                style: const TextStyle(color: spotifyLightGrey, fontSize: 13),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < videos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Builder(builder: (context) {
                      final v = videos[i];
                      return SpotifySongChip(
                        imageUrl: v.thumbnails.isNotEmpty
                            ? v.thumbnails.last.url
                            : '',
                        songTitle: v.title,
                        singerName: v.displayArtist,
                        size: 47,
                        videoId: v.videoId,
                        isExplicit: v.isExplicit,
                        result: v,
                        onTap: () => openConcertVideo(context, videos, i),
                      );
                    }),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// YouTube videos matching a concert query. Family-keyed per query so the
/// artist page can prefetch while this screen only pays for its own.
final concertVideosProvider =
    FutureProvider.family<List<MuzoItem>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  try {
    final api = ref.read(muzoApiServiceProvider);
    final res = await api.search(query, filter: 'videos');
    return res.results
        .where((r) => r.videoId != null)
        .take(8)
        .toList();
  } catch (_) {
    return const [];
  }
});
