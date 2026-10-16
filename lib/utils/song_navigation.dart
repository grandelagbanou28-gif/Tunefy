import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/screens/player_screen.dart';
import 'package:muzo/services/multi_api_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/glass_snackbar.dart';

void openArtistForSong(BuildContext context, MuzoItem item) {
  final name = primaryArtistName(
    item.displayArtist.isNotEmpty ? item.displayArtist : item.title,
  );
  if (name.isEmpty) return;
  final imageUrl = item.thumbnails.lastOrNull?.url;
  HapticFeedback.selectionClick();
  Navigator.of(context).push(
    SlidePageRoute(
      page: ArtistPageScreen(
        artistName: name,
        imageUrl: imageUrl,
      ),
    ),
  );
}

void openArtistForAlbum(BuildContext context, MuzoItem album) {
  final direct = album.artists?.isNotEmpty == true
      ? album.artists!.first.name
      : null;
  final name = primaryArtistName(
    direct ?? album.displayArtist,
  );
  if (name.isEmpty) return;
  final imageUrl = album.thumbnails.lastOrNull?.url;
  HapticFeedback.selectionClick();
  Navigator.of(context).push(
    SlidePageRoute(
      page: ArtistPageScreen(
        artistName: name,
        imageUrl: imageUrl,
      ),
    ),
  );
}

Future<void> playSongAndOpenNowPlaying(
  BuildContext context,
  MuzoItem item, {
  bool openPlayer = true,
}) async {
  final container = ProviderScope.containerOf(context);
  // Le feedback du tap part avant toute attente réseau : un tap qui ne vibre
  // qu'après la résolution du titre donne l'impression que l'app ne répond pas.
  HapticFeedback.selectionClick();
  final videoId = item.videoId;
  if (videoId == null ||
      videoId.isEmpty ||
      StreamExtractionService.isMetadataSeedId(videoId)) {
    final resolved = await container
        .read(multiApiServiceProvider)
        .resolveSingle(item);
    if (!context.mounted) return;
    if (resolved != null) {
      item = resolved;
    } else if (item.title.trim().isEmpty) {
      // Nothing to play and nothing to search for.
      showGlassSnackBar(
        context,
        '« ${item.title} » est indisponible pour le moment.',
        error: true,
      );
      return;
    }
    // When the catalogue search finds no YouTube match we do NOT give up: a
    // seed still carries a real title/artist, which is all the title-driven
    // sources (Saavn/Jamendo/Audius) need. playVideo runs that cascade and
    // reports the track itself if every source misses.
  }
  container.read(audioHandlerProvider).playVideo(item);
  if (!openPlayer) return;
  if (!context.mounted) return;
  final expanded = container.read(isPlayerExpandedProvider.notifier);
  expanded.state = true;
  try {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ExpandedPlayer(),
        fullscreenDialog: true,
      ),
    );
  } finally {
    expanded.state = false;
  }
}
