import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:muzo/services/audio_handler.dart';
import 'package:muzo/services/lyrics_service.dart';

import 'package:muzo/services/storage_service.dart';

final audioHandlerProvider = Provider<AudioHandler>((ref) {
  final storage = ref.read(storageServiceProvider);
  return AudioHandler(storage);
});

/// A single, atomic snapshot of everything the UI needs to render the current
/// playback state. Emitted from one stream so that the song title highlight,
/// the play/pause button and the equalizer icon all update in the same frame.
class PlayerUiSnapshot {
  final MediaItem? currentMediaItem;
  final bool isPlaying;
  final bool isLoading;

  const PlayerUiSnapshot({
    this.currentMediaItem,
    this.isPlaying = false,
    this.isLoading = false,
  });
}

final playerUiStateProvider = StreamProvider<PlayerUiSnapshot>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return audioHandler.player.playerStateStream.map(
    (state) => PlayerUiSnapshot(
      currentMediaItem:
          audioHandler.player.sequenceState?.currentSource?.tag as MediaItem?,
      isPlaying: state.playing,
      isLoading: state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering,
    ),
  );
});

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return audioHandler.player.sequenceStateStream.map(
    (state) => state?.currentSource?.tag as MediaItem?,
  );
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return audioHandler.player.playingStream;
});

final shuffleModeNotifierProvider = Provider<ValueNotifier<bool>>((ref) {
  return ref.watch(audioHandlerProvider).isShuffleModeNotifier;
});

final processingStateProvider = StreamProvider<ProcessingState>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return audioHandler.player.processingStateStream;
});

final positionProvider = StreamProvider<Duration>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return audioHandler.player.positionStream;
});

final durationProvider = StreamProvider<Duration?>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return audioHandler.player.durationStream;
});

/// Lyrics for the CURRENT track, fetched ONCE per song and shared by every
/// lyrics view (now-playing preview, standard player, fullscreen lyrics page).
/// Keyed by the media id so a track change auto-invalidates the fetch; all
/// screens reading this provider always display the exact same lyrics.
final currentLyricsProvider =
    FutureProvider.autoDispose.family<Lyrics?, String>((ref, videoId) async {
  final media = ref.watch(currentMediaItemProvider).valueOrNull;
  if (media == null || media.id != videoId) return null;
  final service = ref.watch(lyricsServiceProvider);
  return service.fetchLyrics(
    media.title,
    media.artist ?? '',
    media.duration?.inSeconds ?? 0,
  );
});

final isPlayerExpandedProvider = StateProvider<bool>((ref) => false);

/// Set when the mini player is swiped away. It comes back on its own as soon
/// as another track starts, so it never has to be restored by hand.
final isMiniPlayerCollapsedProvider = StateProvider<bool>((ref) => false);

final lofiModeNotifierProvider = Provider<ValueNotifier<bool>>((ref) {
  return ref.watch(audioHandlerProvider).isLofiModeNotifier;
});
