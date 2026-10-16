import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/screens/player_screen.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Resolves [title] + [artist] to a playable track. Release feeds (new albums,
/// popular albums, charts) only carry a title and an artist name, so the
/// streamable track has to be looked up first.
Future<List<MuzoItem>> resolveTracks({
  required WidgetRef ref,
  required String title,
  required String artist,
  int limit = 5,
  bool wide = false,
}) async {
  final query = [title, artist].where((s) => s.trim().isNotEmpty).join(' ');
  if (query.trim().isEmpty) return const [];
  // Service read once, before the first await: the widget can be disposed
  // while the lookup runs, and `ref` must not be touched after that.
  final api = ref.read(muzoApiServiceProvider);
  final response = await api
      .search(query, filter: 'songs')
      .timeout(const Duration(seconds: 12));
  var playable =
      response.results.where((r) => (r.videoId ?? '').isNotEmpty).toList();
  if (playable.isEmpty && wide && artist.trim().isNotEmpty) {
    // An album or an artist row rarely matches a single track by its own
    // name: fall back to the artist so the tap still plays something real
    // instead of doing nothing.
    final fallback = await api
        .search(artist, filter: 'songs')
        .timeout(const Duration(seconds: 12));
    playable = fallback.results
        .where((r) => (r.videoId ?? '').isNotEmpty)
        .toList();
  }
  if (playable.isEmpty) {
    // The YouTube worker is the only part of this that can be offline. A
    // title+artist pair is enough for the title-driven sources (Saavn,
    // Jamendo, Audius), so hand back a title seed instead of nothing: the
    // tap then still plays instead of reporting "indisponible".
    return [
      MuzoItem(
        videoId: 'tt_${'$title|$artist'.hashCode.abs()}',
        title: title,
        thumbnails: const [],
        resultType: 'video',
        isExplicit: false,
        artists: artist.trim().isEmpty
            ? const []
            : [MuzoArtist(name: artist, id: null)],
      ),
    ];
  }
  // The artist outranks the title: a title hit on the wrong artist plays the
  // wrong song, so results naming the requested artist lead, then title hits.
  if (artist.trim().isNotEmpty) {
    final needle = artist.trim().toLowerCase();
    playable.sort((a, b) {
      final am = _namesArtist(a.displayArtist, needle) ? 0 : 1;
      final bm = _namesArtist(b.displayArtist, needle) ? 0 : 1;
      if (am != bm) return am.compareTo(bm);
      final needleTitle = title.trim().toLowerCase();
      final at = needleTitle.isNotEmpty && a.title.toLowerCase().contains(needleTitle) ? 0 : 1;
      final bt = needleTitle.isNotEmpty && b.title.toLowerCase().contains(needleTitle) ? 0 : 1;
      return at.compareTo(bt);
    });
  }
  return playable.take(limit).toList();
}

bool _namesArtist(String? resultArtist, String needle) {
  final a = (resultArtist ?? '').toLowerCase();
  if (a.isEmpty || needle.isEmpty) return false;
  return a.contains(needle) || needle.contains(a);
}

/// Plays a list of tracks and, unless [openPlayer] is false, opens Now
/// Playing.
///
/// [openPlayer] is the difference between the two gestures of a release feed:
/// the header Play/Shuffle button is an explicit "show me the player" action,
/// so it opens the full player. Tapping a single row just starts the track —
/// the mini player is already on screen, and pushing a full page there is
/// exactly the "a New Release opened another page" behaviour we do not want.
Future<void> playReleaseTracks(
  BuildContext context,
  WidgetRef ref,
  List<MuzoItem> tracks, {
  int startIndex = 0,
  bool shuffle = false,
  bool openPlayer = true,
}) async {
  if (tracks.isEmpty) return;
  final handler = ref.read(audioHandlerProvider);
  // Read before every await: `ref` dies with the calling widget, and a throw
  // here would leave the flag stuck (mini player hidden everywhere).
  final expanded = ref.read(isPlayerExpandedProvider.notifier);
  final list = shuffle ? (List<MuzoItem>.from(tracks)..shuffle()) : tracks;
  handler.isShuffleModeNotifier.value = shuffle;
  await handler.playAll(list, startIndex: shuffle ? 0 : startIndex);
  if (!openPlayer) return;
  expanded.state = true;
  if (!context.mounted) return;
  try {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ExpandedPlayer(),
        fullscreenDialog: true,
      ),
    );
  } finally {
    // Always release the flag, or the nav bar and mini player stay hidden.
    expanded.state = false;
  }
}

/// Tapping a title on a release feed plays it in place: no page change at
/// all, neither an album page nor the full player. The mini player is already
/// there, so the tap is fully acknowledged by the audio starting.
Future<void> playReleaseTitle(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String artist,
}) async {
  HapticFeedback.selectionClick();
  final overlay = ReleaseBusyOverlay.show(context);
  final tracks = await resolveTracks(
    ref: ref,
    title: title,
    artist: artist,
    wide: true,
  );
  overlay();
  if (!context.mounted) return;
  if (tracks.isEmpty) {
    showGlassSnackBar(context, AppLocalizations.of(context).releaseTrackUnavailable,
        error: true);
    return;
  }
  await playReleaseTracks(context, ref, tracks, openPlayer: false);
}

/// Small spinner shown over the page while titles are being resolved, so the
/// tap is acknowledged without a blocking dialog or a message.
class ReleaseBusyOverlay {
  static void Function() show(BuildContext context) {
    final entry = OverlayEntry(
      builder: (ctx) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .35),
          child: const Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: SpotifySpinner(color: Color(0xFF1DDA63), strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    return () {
      if (entry.mounted) entry.remove();
    };
  }
}

/// Green / plain round action button shared by the release feeds.
class ReleaseRoundButton extends StatelessWidget {
  const ReleaseRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.background,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Container(
        width: size + 20,
        height: size + 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ??
              Colors.white.withValues(alpha: enabled ? 0.10 : 0.04),
        ),
        child: Icon(
          icon,
          size: size,
          color: enabled ? color : color.withValues(alpha: .35),
        ),
      ),
    );
  }
}
