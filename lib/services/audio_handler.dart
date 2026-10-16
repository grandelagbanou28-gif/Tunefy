// ignore_for_file: experimental_member_use
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/ytify_result.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/services/navigator_key.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/youtube_api_service.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:http/http.dart' as http;

class AudioHandler {
  final AudioPlayer _player = AudioPlayer(
    audioLoadConfiguration: AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: const Duration(seconds: 20),
        maxBufferDuration: const Duration(seconds: 30),
        bufferForPlaybackDuration: const Duration(milliseconds: 1000),
        bufferForPlaybackAfterRebufferDuration: const Duration(
          milliseconds: 1500,
        ),
      ),
    ),
  );
  final StorageService _storage;

  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
  );

  String? _lastHistoryId;
  bool _isInitialLoading = false;

  /// Titre refusé faute d'être téléchargé alors que l'appareil est hors
  /// ligne. Posé par `_createAudioSource`, lu par `playVideo` pour adapter le
  /// message et SURTOUT ne pas passer au suivant (hors ligne, toute la file
  /// échouerait de la même façon).
  String? _offlineBlockedTitle;

  final ValueNotifier<bool> isLoadingStream = ValueNotifier(false);

  /// True while the current playback was started from the clips feed — the
  /// main layout hides the mini player pill in that mode (background audio
  /// only, controlled from the notification).
  final ValueNotifier<bool> isClipPlayback = ValueNotifier(false);

  AudioPlayer get player => _player;
  ConcatenatingAudioSource get playlist => _playlist;

  final ValueNotifier<bool> isLofiModeNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isShuffleModeNotifier = ValueNotifier(false);
  final ValueNotifier<LoopMode> repeatModeNotifier = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> isSmartShuffleNotifier = ValueNotifier(true);
  final ValueNotifier<bool> isAutoplayNotifier = ValueNotifier(false);

  static const platform = MethodChannel('com.shashwat.muzo/audio_effects');

  double _userVolume = 1.0;
  double _crossfadeFactor = 1.0;
  int? _crossfadeTrackIndex;
  bool _crossfadeRampingOut = false;
  final Random _random = Random();
  bool _radioExtending = false;
  // Guards the ProcessingState.error auto-skip: reentrancy lock, plus the index
  // the user skipped to by hand so a late error from the previous track is
  // ignored instead of skipping twice.
  bool _handlingError = false;
  int? _errorSkipGuard;
  _FadeIn? _fadeInRemaining;

  StreamSubscription<Duration>? _positionSubscription;

  // Stream subscriptions for proper cleanup
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<int?>? _androidAudioSessionIdSubscription;
  StreamSubscription<SequenceState?>? _sequenceStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  double get userVolume => _userVolume;

  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_userVolume * _crossfadeFactor);
  }

  void _applyCrossfadeFactor(double factor) {
    final clamped = factor.clamp(0.0, 1.0);
    if ((clamped - _crossfadeFactor).abs() < 0.01) return;
    _crossfadeFactor = clamped;
    unawaited(_player.setVolume(_userVolume * clamped));
  }

  AudioHandler(this._storage) {
    _init();
  }

  Future<void> toggleLofiMode() async {
    isLofiModeNotifier.value = !isLofiModeNotifier.value;
    await updateLofiSettings();
  }

  /// Re-applies the persisted playback preferences (shuffle, repeat, audio
  /// effects) to the freshly created player. Called once from [_init].
  Future<void> _restorePlaybackPreferences() async {
    isShuffleModeNotifier.value = _storage.shuffleEnabled;
    isSmartShuffleNotifier.value = _storage.smartShuffleEnabled;
    isAutoplayNotifier.value = _storage.autoplayEnabled;
    final repeat = _repeatModeFromIndex(_storage.repeatModeIndex);
    repeatModeNotifier.value = repeat;
    try {
      await _player.setShuffleModeEnabled(_storage.shuffleEnabled);
      await _player.setLoopMode(repeat);
    } catch (e) {
      debugPrint('Error restoring playback preferences: $e');
    }
    if (_storage.loudnessNormalizationEnabled) {
      await setLoudnessNormalization(true);
    }
  }

  static LoopMode _repeatModeFromIndex(int index) {
    switch (index) {
      case 1:
        return LoopMode.all;
      case 2:
        return LoopMode.one;
      default:
        return LoopMode.off;
    }
  }

  static int _repeatModeToIndex(LoopMode mode) {
    switch (mode) {
      case LoopMode.all:
        return 1;
      case LoopMode.one:
        return 2;
      default:
        return 0;
    }
  }

  Future<void> setShuffleEnabled(bool value) async {
    isShuffleModeNotifier.value = value;
    await _storage.setShuffleEnabled(value);
    try {
      await _player.setShuffleModeEnabled(value);
    } catch (e) {
      debugPrint('Error setting shuffle mode: $e');
    }
  }

  Future<void> toggleShuffle() => setShuffleEnabled(!isShuffleModeNotifier.value);

  Future<void> setRepeatMode(LoopMode mode) async {
    repeatModeNotifier.value = mode;
    await _storage.setRepeatModeIndex(_repeatModeToIndex(mode));
    try {
      await _player.setLoopMode(mode);
    } catch (e) {
      debugPrint('Error setting loop mode: $e');
    }
  }

  /// off -> repeat all -> repeat one -> off, like every music player.
  Future<void> cycleRepeatMode() {
    final next = switch (repeatModeNotifier.value) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      _ => LoopMode.off,
    };
    return setRepeatMode(next);
  }

  /// "Smart shuffle" (Spotify's shuffle button long-press / the dedicated
  /// toggle): the track that is playing right now keeps going, and only the
  /// UPCOMING part of the queue is reordered. The player's own shuffle mode
  /// is left untouched so the user can still skip through the new order.
  Future<void> setSmartShuffleEnabled(bool value) async {
    isSmartShuffleNotifier.value = value;
    await _storage.setSmartShuffleEnabled(value);
    if (value) await shuffleUpcomingQueue();
  }

  Future<void> toggleSmartShuffle() =>
      setSmartShuffleEnabled(!isSmartShuffleNotifier.value);

  /// "Autoplay" / Radio: when the queue runs out, keep going with tracks
  /// related to the last one instead of stopping dead. Off by default so the
  /// app never starts music the user did not ask for.
  Future<void> setAutoplayEnabled(bool value) async {
    isAutoplayNotifier.value = value;
    await _storage.setAutoplayEnabled(value);
  }

  Future<void> toggleAutoplay() =>
      setAutoplayEnabled(!isAutoplayNotifier.value);

  String? _videoIdOf(AudioSource source) {
    if (source is! IndexedAudioSource) return null;
    final tag = source.tag;
    if (tag is MediaItem) return tag.id;
    if (tag is MuzoItem) return tag.videoId;
    return null;
  }

  MuzoItem _radioItemFrom(YtifyResult result) {
    return MuzoItem(
      title: result.title,
      thumbnails: [
        for (final t in result.thumbnails)
          MuzoThumbnail(url: t.url, width: 0, height: 0),
      ],
      resultType: 'song',
      isExplicit: result.isExplicit,
      videoId: result.videoId,
      browseId: result.browseId,
      duration: result.duration,
      durationSeconds: result.durationSeconds,
      videoType: result.videoType,
      artists: [
        for (final a in (result.artists ?? const <YtifyArtist>[]))
          MuzoArtist(name: a.name, id: a.id ?? ''),
      ],
      album: result.album == null
          ? null
          : MuzoAlbum(
              name: result.album!.name,
              id: result.album!.id,
            ),
    );
  }

  /// Appends ~20 tracks related to the last played one and resumes playback
  /// from the first of them. Silent no-op while already fetching, when the
  /// feature is off, or when the backend returns nothing usable.
  Future<void> _extendQueueWithRadio() async {
    if (_radioExtending) return;
    if (!isAutoplayNotifier.value) return;
    final children = _playlist.children;
    if (children.isEmpty) return;
    _radioExtending = true;
    try {
      final seed = _videoIdOf(children.last);
      if (seed == null || seed.isEmpty) return;
      final related = await YouTubeApiService().getRelatedVideos(seed);
      if (related.isEmpty) return;

      final known = <String>{
        for (final child in children)
          if (_videoIdOf(child) != null) _videoIdOf(child)!,
      };
      final sources = <AudioSource>[];
      for (final result in related) {
        final id = result.videoId;
        if (id == null || id.isEmpty || !known.add(id)) continue;
        if (result.durationSeconds != null && result.durationSeconds! < 30) {
          continue;
        }
        final source = _createLazyAudioSource(_radioItemFrom(result));
        if (source != null) sources.add(source);
        if (sources.length >= 20) break;
      }
      if (sources.isEmpty) return;

      final startIndex = _playlist.children.length;
      await _playlist.addAll(sources);
      if (_storage.shuffleEnabled && _storage.smartShuffleEnabled) {
        final upcoming = sources.toList()..shuffle(_random);
        await _playlist.removeRange(startIndex, startIndex + sources.length);
        await _playlist.addAll(upcoming);
      }
      for (int i = 0; i < sources.length && i < 2; i++) {
        final source = _playlist.children[startIndex + i];
        if (source is ResolvingAudioSource) _preResolve(source);
      }
      await _player.seek(Duration.zero, index: startIndex);
      _playWithAutoSkip();
    } catch (e) {
      debugPrint('Error extending queue with radio: $e');
    } finally {
      _radioExtending = false;
    }
  }

  /// Fisher-Yates on the queue entries that have not played yet, leaving the
  /// current track at the head of the list.
  Future<void> shuffleUpcomingQueue() async {
    try {
      final currentIndex = _player.currentIndex;
      final length = _playlist.length;
      if (length < 3) return;
      final head = currentIndex == null ? 0 : currentIndex + 1;
      if (head >= length) return;

      final upcoming = <AudioSource>[];
      for (int i = head; i < length; i++) {
        upcoming.add(_playlist.children[i]);
      }
      upcoming.shuffle(_random);
      await _playlist.removeRange(head, length);
      await _playlist.addAll(upcoming);
      for (int i = 0; i < upcoming.length && i < 3; i++) {
        final source = upcoming[i];
        if (source is ResolvingAudioSource) {
          _preResolve(source);
        }
      }
    } catch (e) {
      debugPrint('Error shuffling upcoming queue: $e');
    }
  }

  /// Crossfade and gapless are mutually exclusive: ExoPlayer can only play a
  /// seamless transition when nothing automates the volume per track.
  Future<void> setCrossfadeEnabled(bool value) async {
    await _storage.setCrossfadeEnabled(value);
    if (value) {
      await _storage.setGaplessEnabled(false);
      _crossfadeTrackIndex = _player.currentIndex;
      _crossfadeRampingOut = false;
      _fadeInRemaining = null;
      _applyCrossfadeFactor(1.0);
    } else {
      _fadeInRemaining = null;
      _applyCrossfadeFactor(1.0);
    }
  }

  Future<void> setCrossfadeSeconds(int seconds) =>
      _storage.setCrossfadeSeconds(seconds.clamp(1, 12));

  Future<void> setGaplessEnabled(bool value) async {
    await _storage.setGaplessEnabled(value);
    if (value) {
      await _storage.setCrossfadeEnabled(false);
      _fadeInRemaining = null;
      _applyCrossfadeFactor(1.0);
    }
  }

  /// Android's LoudnessEnhancer, applied on the live audio session. On other
  /// platforms the preference is still stored, it just has no effect.
  Future<void> setLoudnessNormalization(bool value) async {
    await _storage.setLoudnessNormalizationEnabled(value);
    await _applyLoudnessNormalization(value);
  }

  Future<void> _applyLoudnessNormalization(bool enable) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final sessionId = _player.androidAudioSessionId;
    if (sessionId == null) return;
    try {
      await platform.invokeMethod('setLoudnessNormalization', {
        'sessionId': sessionId,
        'enable': enable,
      });
    } catch (e) {
      debugPrint('Error toggling loudness normalization: $e');
    }
  }

  Future<void> updateLofiSettings() async {
    final enable = isLofiModeNotifier.value;

    if (enable) {
      await _player.setSpeed(_storage.lofiSpeed);
      await _player.setPitch(_storage.lofiPitch);
    } else {
      await _player.setSpeed(1.0);
      await _player.setPitch(1.0);
    }

    if (!kIsWeb && Platform.isAndroid) {
      final sessionId = _player.androidAudioSessionId;
      if (sessionId != null) {
        await _applyReverb(sessionId, enable);
      }
    }
  }

  Future<void> _init() async {
    // NOTE: JustAudioBackground.init() is configured once at app startup in
    // main.dart. Calling it again here would throw
    // "just_audio_background supports only a single player instance" and break
    // playback, so it must NOT be re-initialized.

    // Configure audio session for optimal music playback quality
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: false,
        ),
      );
    } catch (e) {
      debugPrint("Error configuring AudioSession: $e");
    }

    // just_audio reports a source that ExoPlayer could not load on
    // playbackEventStream as a stream error (not as a ProcessingState), which
    // is why a dead link used to freeze the player: nothing was listening.
    _playbackEventSubscription = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('Playback stream error: $e');
        unawaited(_handlePlaybackError());
      },
    );

    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering) {
        isLoadingStream.value = true;
      } else if (state.processingState == ProcessingState.ready ||
          state.processingState == ProcessingState.completed ||
          state.processingState == ProcessingState.idle) {
        isLoadingStream.value = false;
      }

      // Playback never starts anything on its own unless the user turned
      // Autoplay (Radio) on: when the queue ends, related tracks are appended
      // and playback continues from the first of them.
      if (state.processingState == ProcessingState.completed &&
          !state.playing &&
          isAutoplayNotifier.value) {
        unawaited(_extendQueueWithRadio());
      }

      if (state.playing && state.processingState == ProcessingState.ready) {
        final index = _player.currentIndex;
        final sequence = _player.sequenceState?.sequence;
        if (index != null && sequence != null && index < sequence.length) {
          final source = sequence[index];
          final tag = source.tag;
          if (tag is MediaItem && tag.id != _lastHistoryId) {
            _lastHistoryId = tag.id;
            final artists = _artistsFromExtras(tag.extras);
            final album = _albumFromExtras(tag.extras);
            final result = MuzoItem(
              videoId: tag.id,
              title: tag.title,
              artists: artists.isNotEmpty
                  ? artists
                  : [MuzoArtist(name: tag.artist ?? '', id: '')],
              album: album,
              thumbnails: [
                MuzoThumbnail(
                  url: tag.artUri?.toString() ?? '',
                  width: 0,
                  height: 0,
                ),
              ],
              resultType: tag.extras?['resultType'] ?? 'song',
              durationSeconds: tag.duration?.inSeconds,
              isExplicit: false,
              audioUrl: tag.extras?['audioUrl'],
            );
            _storage.addToHistory(result);
          } else if (tag is MuzoItem && tag.videoId != _lastHistoryId) {
            _lastHistoryId = tag.videoId;
            _storage.addToHistory(tag);
          }
          // Record listening stats for Sound Capsule
          if (tag is MediaItem) {
            final artists = _artistsFromExtras(tag.extras);
            final album = _albumFromExtras(tag.extras);
            final result = MuzoItem(
              videoId: tag.id,
              title: tag.title,
              artists: artists.isNotEmpty
                  ? artists
                  : [MuzoArtist(name: tag.artist ?? '', id: '')],
              album: album,
              thumbnails: [
                MuzoThumbnail(
                  url: tag.artUri?.toString() ?? '',
                  width: 0,
                  height: 0,
                ),
              ],
              resultType: tag.extras?['resultType'] ?? 'song',
              durationSeconds: tag.duration?.inSeconds,
              isExplicit: false,
              audioUrl: tag.extras?['audioUrl'],
            );
            _storage.stats.recordPlay(result);
          } else if (tag is MuzoItem) {
            _storage.stats.recordPlay(tag);
          }
        }

        if (_isInitialLoading) {
          _isInitialLoading = false;
        }

        if (sequence != null && index != null) {
          if (sequence.isNotEmpty && index < sequence.length - 1) {
            final window = _preResolveWindow;
            for (int i = 1; i <= window; i++) {
              if (index + i < sequence.length) {
                final source = sequence[index + i];
                if (source is ResolvingAudioSource) {
                  source.resolve();
                }
              }
            }
          }
        }
      }
    });

    _androidAudioSessionIdSubscription = _player.androidAudioSessionIdStream
        .listen((sessionId) {
      if (sessionId == null) return;
      if (isLofiModeNotifier.value) {
        _applyReverb(sessionId, true);
      }
      unawaited(_applyLoudnessNormalization(
        _storage.loudnessNormalizationEnabled,
      ));
    });

    unawaited(_restorePlaybackPreferences());


    _sequenceStateSubscription = _player.sequenceStateStream.listen((state) {
      if (state == null) return;
      if (_isInitialLoading) return;
      final sequence = state.sequence;
      final index = state.currentIndex;
      final window = _preResolveWindow;

      for (int i = 1; i <= window; i++) {
        if (index + i < sequence.length) {
          final source = sequence[index + i];
          if (source is ResolvingAudioSource) {
            source.resolve();
          }
        }
      }
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((
      index,
    ) async {
      if (index == null) return;
      final sequence = _player.sequenceState?.sequence;
      if (sequence == null || index >= sequence.length) return;

      // A different track gets a fresh retry budget, and the "sources to avoid"
      // list from the previous failure no longer applies: that verdict was about
      // another song.
      _retryCount = 0;
      _avoidedSources.clear();

      final window = _preResolveWindow;
      for (int i = 0; i <= window; i++) {
        if (index + i < sequence.length) {
          final source = sequence[index + i];
          if (source is ResolvingAudioSource) {
            source.resolve();
          }
        }
      }
    });

    _positionSubscription = _player.positionStream.listen(_onPositionTick);
  }

  /// A crossfaded track has to be consumed progressively: when the player has
  /// already resolved the next source ahead of time the transition is cut
  /// short. Every other mode keeps the 5-track pre-resolution window that makes
  /// skipping instant.
  int get _preResolveWindow => _storage.crossfadeEnabled ? 0 : 5;

  /// Rises from silence to full volume over the crossfade window when a new
  /// track takes over, mirroring the fade-out that ended the previous one.
  void _beginCrossfadeTrack(int? index) {
    _crossfadeTrackIndex = index;
    _crossfadeRampingOut = false;
    final position = _player.position;
    final fadeIn = _player.hasPrevious
        ? Duration(seconds: _storage.crossfadeSeconds)
        : Duration.zero;
    if (fadeIn <= Duration.zero || position >= fadeIn) {
      _fadeInRemaining = null;
      _applyCrossfadeFactor(1.0);
      return;
    }
    _applyCrossfadeFactor(0.0);
    _fadeInRemaining = _FadeIn(startedAt: position, total: fadeIn);
  }

  /// Drives the crossfade envelope. The volume is ramped down over the last
  /// [crossfadeSeconds] of a track (only when another track is queued) and
  /// ramped back up over the same duration once the next track starts, so
  /// consecutive songs melt into each other the way Spotify does it. A
  /// per-track volume envelope is incompatible with ExoPlayer's gapless
  /// concatenation, which is why enabling crossfade turns gapless off.
  void _onPositionTick(Duration position) {
    if (!_storage.crossfadeEnabled) {
      _fadeInRemaining = null;
      if (_crossfadeFactor < 1.0) _applyCrossfadeFactor(1.0);
      _crossfadeRampingOut = false;
      return;
    }
    if (!_player.playing) return;

    final fadeIn = _fadeInRemaining;
    if (fadeIn != null) {
      if (position >= fadeIn.total) {
        _fadeInRemaining = null;
        _applyCrossfadeFactor(1.0);
      } else {
        _applyCrossfadeFactor((position - fadeIn.startedAt).inMilliseconds / fadeIn.total.inMilliseconds);
      }
      return;
    }

    final index = _player.currentIndex;
    if (index != _crossfadeTrackIndex) {
      _beginCrossfadeTrack(index);
      return;
    }

    final duration = _player.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;

    final window = Duration(seconds: _storage.crossfadeSeconds);
    final remaining = duration - position;
    if (!_player.hasNext) {
      if (_crossfadeFactor < 1.0) _applyCrossfadeFactor(1.0);
      return;
    }
    if (remaining > window || remaining <= Duration.zero) {
      if (_crossfadeRampingOut) {
        _crossfadeRampingOut = false;
        _applyCrossfadeFactor(1.0);
      }
      return;
    }
    if (!_crossfadeRampingOut) {
      _crossfadeRampingOut = true;
      return;
    }
    _applyCrossfadeFactor(remaining.inMilliseconds / window.inMilliseconds);
  }

  Future<void> _applyReverb(int sessionId, bool enable) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await platform.invokeMethod('enableReverb', {
        'sessionId': sessionId,
        'enable': enable,
      });
    } catch (e) {
      debugPrint("Error toggling reverb: $e");
    }
  }

  Future<void> playVideo(dynamic video, {bool isClip = false}) async {
    try {
      _isInitialLoading = true;
      isLoadingStream.value = true;
      isClipPlayback.value = isClip;

      String? videoId = video is MuzoItem ? video.videoId : null;
      if (videoId == null) {
        debugPrint('playVideo: missing videoId');
        final context = navigatorKey.currentContext;
        if (context != null) {
          showGlassSnackBar(context, 'Cannot play this item: Missing ID');
        }
        _isInitialLoading = false;
        isLoadingStream.value = false;
        isClipPlayback.value = false;
        return;
      }
      if (StreamExtractionService.isMetadataSeedId(videoId)) {
        // dz_/it_/sp_ seeds carry no YouTube id, so the video resolvers cannot
        // help — but their title/artist are real, which is all a title-driven
        // source needs. Only refuse when there is not even a title to search.
        final seedTitle = video is MuzoItem ? video.title : '';
        if (seedTitle.isEmpty) {
          debugPrint('playVideo: unresolved metadata seed $videoId');
          final context = navigatorKey.currentContext;
          if (context != null) {
            showGlassSnackBar(context, 'This track is unavailable right now');
          }
          _isInitialLoading = false;
          isLoadingStream.value = false;
          isClipPlayback.value = false;
          return;
        }
        debugPrint('playVideo: streaming seed $videoId by title « $seedTitle »');
      }

      // Extract stream URL — UI already shows loading state
      _offlineBlockedTitle = null;
      var source = await _createAudioSource(video);
      if (source == null && _offlineBlockedTitle == null) {
        // One cold-cache retry: a stale IP-bound googlevideo URL in the
        // local stream cache is the most common first-tap failure. Useless
        // when the reason is already known (no file on a device with no net).
        try {
          await StreamExtractionService.invalidateCache(videoId);
        } catch (_) {}
        source = await _createAudioSource(video);
      }
      if (source == null) {
        isLoadingStream.value = false;
        _isInitialLoading = false;
        isClipPlayback.value = false;
        final blocked = _offlineBlockedTitle;
        _offlineBlockedTitle = null;
        _announceUnplayable(video is MuzoItem ? video.title : null,
            offlineBlocked: blocked != null);
        // "Quand un son ne marche pas, tu passes au suivant": a dead tap must
        // not end the listening session. The queue still holds what comes
        // after this track, so advance instead of stopping on the toast.
        // SAUF hors ligne : là chaque titre de la file échoue pour la même
        // raison, et défiler jusqu'au bout n'est qu'une rafale de toasts.
        if (blocked == null &&
            _player.audioSource == _playlist &&
            _player.hasNext) {
          await _skipToNextSafe(5);
        }
        return;
      }

      // Keep the existing queue alive so songs keep chaining: if the tapped
      // song is already queued, jump to it; otherwise slot it in right after
      // the current track instead of wiping everything (the old behaviour
      // replaced the queue with a single track and playback stopped at the
      // end of every song).
      final existingIndex = _player.sequenceState?.sequence.indexWhere(
        (s) => s.tag is MediaItem && (s.tag as MediaItem).id == videoId,
      );
      if (existingIndex != null && existingIndex >= 0) {
        if (_player.audioSource != _playlist) {
          await _player.setAudioSource(_playlist);
        }
        await _player.seek(Duration.zero, index: existingIndex);
        _playWithAutoSkip();
        unawaited(_waitForReadyThenClearLoading());
        return;
      }

      final currentIndex = _player.currentIndex;
      if (_player.audioSource == _playlist &&
          currentIndex != null &&
          _playlist.length > 0) {
        await _playlist.insert(currentIndex + 1, source);
        await _player.seek(Duration.zero, index: currentIndex + 1);
        _playWithAutoSkip();
      } else {
        await _playlist.clear();
        await _playlist.add(source);
        await _player.setAudioSource(
          _playlist,
          initialPosition: Duration.zero,
          initialIndex: 0,
          preload: true,
        );
        _playWithAutoSkip();
      }

      // Keep the loading spinner up until the new track is actually
      // producing sound, instead of clearing it the moment play() returns.
      unawaited(_waitForReadyThenClearLoading());
    } catch (e) {
      debugPrint('Error playing video: $e');
      isLoadingStream.value = false;
      _isInitialLoading = false;
      isClipPlayback.value = false;
      final context = navigatorKey.currentContext;
      if (context != null) {
        showGlassSnackBar(context, 'Playback failed: $e');
      }
    }
  }

  /// Waits (bounded) for the player to reach [ProcessingState.ready], then
  /// clears the global loading flag so spinners reflect real buffering.
  Future<void> _waitForReadyThenClearLoading() async {
    try {
      await _player.processingStateStream
          .firstWhere((s) => s == ProcessingState.ready)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Timeout or stream closed — clear anyway so the UI never hangs.
    } finally {
      isLoadingStream.value = false;
      _isInitialLoading = false;
    }
  }

  Future<bool> addToQueue(dynamic video) async {
    try {
      final source = await _createAudioSource(video);
      if (source != null) {
        await _playlist.add(source);
        if (_player.audioSource != _playlist) {
          await _player.setAudioSource(_playlist);
        }
        return true;
      } else {
        final context = navigatorKey.currentContext;
        if (context != null) {
          showGlassSnackBar(context, 'Failed to add to queue');
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error adding to queue: $e');
      return false;
    }
  }

  /// Appends several items to the end of the playing queue with in-memory
  /// lazy sources (no per-item network round trip), same resolution logic as
  /// [playAll]. Pre-resolves only the next 2 to keep the mix flowing. Returns
  /// the number of tracks actually queued (0 when nothing was playable).
  Future<int> enqueueSongs(List<MuzoItem> items) async {
    if (items.isEmpty) return 0;
    try {
      final sources = <AudioSource>[];
      for (final song in items) {
        final source = _createLazyAudioSource(song);
        if (source != null) sources.add(source);
      }
      if (sources.isEmpty) return 0;
      if (_player.audioSource != _playlist) {
        await _player.setAudioSource(_playlist);
      }
      await _playlist.addAll(sources);
      for (int i = 0; i < sources.length && i < 2; i++) {
        final source = sources[i];
        if (source is ResolvingAudioSource) {
          _preResolve(source);
        }
      }
      return sources.length;
    } catch (e) {
      debugPrint('Error enqueuing DJ picks: $e');
      return 0;
    }
  }

  Future<AudioSource?> _createAudioSource(dynamic video) async {
    try {
      String videoId;
      String title;
      String artist;
      String artUri;
      String resultType = 'video';
      String? artistId;
      Duration? duration;

      if (video is MuzoItem) {
        if (video.videoId == null) return null;
        videoId = video.videoId!;
        title = video.title;
        artist = video.displayArtist;
        artistId = video.artists?.firstOrNull?.id;
        artUri = video.thumbnails.isNotEmpty ? video.thumbnails.last.url : '';
        resultType = video.resultType;
        if (video.durationSeconds != null) {
          duration = Duration(seconds: video.durationSeconds!);
        }
      } else {
        return null;
      }

      final downloadPath = _storage.getDownloadPath(videoId);
      final String? directUrl = video.audioUrl;
      Uri? audioUri;

      // 1) Bytes already on the device first — the most reliable source. The
      // user's own local library travels as a file:// URL, and a local file
      // must keep playing under both "offline" and "downloaded only" rules.
      final onDevice = directUrl != null && directUrl.startsWith('file://');
      if (downloadPath != null && await File(downloadPath).exists()) {
        audioUri = Uri.file(downloadPath);
      } else if (onDevice) {
        audioUri = Uri.parse(directUrl);
      } else if (resultType == 'radio') {
        // 2) Live radio station: the URL the catalogue carries IS the stream.
        // It bypasses the downloaded-only rule (a stream is never on disk and
        // needs no relay, which is the point of having it) but not a real
        // offline state, where it could only time out.
        if (_storage.offlineMode || await ContentCacheService.isOffline()) {
          _offlineBlockedTitle = title;
          return null;
        }
        if (directUrl == null || directUrl.isEmpty) {
          debugPrint('AudioHandler: radio $videoId has no stream URL');
          return null;
        }
        audioUri = Uri.parse(directUrl);
      } else if (_storage.offlineMode ||
          _storage.playDownloadedOnly ||
          await ContentCacheService.isOffline()) {
        // 2) Nothing on disk and only downloads are allowed: AUCUNE source
        // n'est possible. Le laisser entrer dans le pipeline attend un timeout,
        // échoue, puis passe au suivant — donc la file entière défile en
        // échouant titre après titre. On s'arrête net et on nomme le titre,
        // comme Spotify qui affiche un titre grisé + une flèche de téléchargement.
        _offlineBlockedTitle = title;
        return null;
      } else if (directUrl != null &&
          directUrl.isNotEmpty &&
          video.metadata?['previewOnly'] != true &&
          StreamExtractionService.isReusableStreamUrl(directUrl)) {
        // 3) Direct stream (iTunes previews, Jamendo/Audius/ccMixter/IA,
        //    community uploads, podcast feeds) — play it as-is regardless of
        //    resultType; these ids are never YouTube videos. Stale URLs
        //    (dead Vercel worker, expired IP-bound googlevideo) are ignored
        //    so they re-resolve through the extraction pipeline instead.
        //    A `previewOnly` clip is skipped here: it is the last resort, and
        //    the full-length hunt below runs first.
        audioUri = Uri.parse(directUrl);
      } else if (video.resultType == 'user_track') {
        debugPrint('AudioHandler: user track missing audioUrl');
        return null;
      } else {
        final streamUrl = await StreamExtractionService.getStreamUrl(
          videoId,
          title: title,
          artist: artist,
          durationSeconds: duration?.inSeconds,
          // A tapped title must not wait its turn behind the background
          // enrichment of a whole shelf.
          priority: true,
        );
        if (streamUrl == null) {
          // No full-length source answered. A catalogue clip still plays, so
          // the tapped track makes sound instead of being dropped.
          if (video.metadata?['previewOnly'] == true &&
              directUrl != null &&
              directUrl.isNotEmpty) {
            debugPrint('AudioHandler: $videoId served by catalogue clip');
            audioUri = Uri.parse(directUrl);
          } else {
            debugPrint('AudioHandler: getStreamUrl returned null for $videoId');
            return null;
          }
        } else {
          audioUri = Uri.parse(streamUrl);
        }
      }

      return AudioSource.uri(
        audioUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36',
        },
        tag: MediaItem(
          id: videoId,
          album: video.album?.name ?? "Tunefy",
          title: title,
          artist: artist,
          duration: duration,
          artUri: Uri.parse(artUri),
          extras: {
            'resultType': resultType,
            'artistId': artistId,
            'isSaavn': StreamExtractionService.isSaavnCache[videoId],
            'audioUrl': video.audioUrl,
            'album': video.album?.name,
            'albumId': video.album?.id,
            'artists': video.artists
                ?.map((a) => {'name': a.name, 'id': a.id})
                .toList(),
          },
        ),
      );
    } catch (e) {
      debugPrint('Error creating audio source: $e');
      return null;
    }
  }

  Future<void> playAll(
    List<MuzoItem> results, {
    int startIndex = 0,
    int retryCount = 0,
  }) async {
    try {
      _isInitialLoading = true;
      if (results.isEmpty) {
        return;
      }

      await _playlist.clear();

      // Build a lazy source for every song. Tracks that fail to resolve are
      // auto-skipped by ResolvingAudioSource (empty stream) instead of killing
      // the whole queue, so a 100-song list never stops on one bad track.
      //
      // Songs with a direct audioUrl (Jamendo/Audius/iTunes previews) stream
      // instantly; ytify YouTube ids must be extracted (can take 10s+ and may
      // be unplayable). Reorder so every streamable-by-URL track is played
      // first — otherwise a section whose first cards are dead ytify videos
      // produces seconds of silence before anything is skipped.
      //
      // Raw googlevideo URLs are IP-bound: a copy resolved off-device
      // (Invidious/Cobalt) 403s on THIS device. Probe them all in parallel
      // (≤3s) — dead ones drop into `extracted` so ResolvingAudioSource
      // re-resolves them through the local yt-dlp proxy instead of failing
      // at the player (auto-skip = "certains sons ne se jouent pas").
      final bucketUsable = await Future.wait(
        results.map((song) async {
          final u = song.audioUrl ?? '';
          if (u.isEmpty) return false;
          if (!StreamExtractionService.isRawGooglevideo(u)) return true;
          return StreamExtractionService.probeStreamUrl(u);
        }),
      );
      final direct = <MuzoItem>[];
      final extracted = <MuzoItem>[];
      for (int i = 0; i < results.length; i++) {
        (bucketUsable[i] ? direct : extracted).add(results[i]);
      }
      // Drop items without a streamable videoId BEFORE computing safeStart:
      // _createLazyAudioSource skips them, so an index computed on the
      // unfiltered list would land on the wrong track (or out of range).
      // The same track can legitimately arrive twice ("Tous les titres" on a
      // page whose artist also appears in a feature row) — keeping it twice
      // made the queue replay the identical song back to back.
      final ordered = <MuzoItem>[];
      final queuedOnce = <String>{};
      for (final s in <MuzoItem>[...direct, ...extracted]) {
        final vid = s.videoId;
        if (vid == null || vid.isEmpty) continue;
        if (!queuedOnce.add(vid.toLowerCase())) continue;
        ordered.add(s);
      }
      final startSong = startIndex >= 0 && startIndex < results.length
          ? results[startIndex]
          : null;
var safeStart = 0;
    if (startSong != null) {
      final i = ordered.indexWhere((s) => identical(s, startSong));
      safeStart = i >= 0 ? i : 0;
    }
    // Clamp to the ordered list length so the player does not throw
    // RangeError when the start song was filtered out (no videoId) and
    // ordered.length > sources.length (items without videoId are dropped).
    safeStart = safeStart.clamp(0, ordered.length - 1);

      final sources = <AudioSource>[];
      // Kept in lockstep with `sources` because AudioSource.tag is only
      // exposed once the item is indexed into the playlist.
      final queuedIds = <String>[];
      for (final song in ordered) {
        final source = _createLazyAudioSource(song);
        if (source != null) {
          sources.add(source);
          queuedIds.add(song.videoId!);
        }
      }
      if (sources.isEmpty) {
        final context = navigatorKey.currentContext;
        if (context != null) {
          showGlassSnackBar(
            context,
            _storage.offlineMode
                ? AppLocalizations.of(context).offlineNotDownloaded
                : _storage.playDownloadedOnly
                    ? 'Aucun titre téléchargé sur cet appareil — téléchargez-'
                        'le pour l\'écouter (menu ⋮ › Télécharger).'
                    : 'No playable songs found',
          );
        }
        return;
      }

      // The lazy filter (offline / downloaded-only) drops tracks from `ordered`
      // too, so safeStart — computed before filtering — can point past the end
      // of the queue and make setAudioSource throw instead of playing the
      // downloaded subset. Land on the tapped track when it survived,
      // otherwise start at the first item that is actually on the device.
      if (startSong != null) {
        final hit = queuedIds.indexOf(startSong.videoId ?? '');
        safeStart = hit >= 0 ? hit : 0;
      }
      safeStart = safeStart.clamp(0, sources.length - 1);

      await _playlist.addAll(sources);

      // "Tous les titres" on a list that already holds the playing track must
      // CONTINUE that track where the listener left it. playAll rebuilt the
      // queue and seeked to Duration.zero, which restarted the song — heard as
      // "it plays what I already had, from the beginning".
      var resumeIndex = -1;
      Duration resumePosition = Duration.zero;
      final playingIndex = _player.currentIndex;
      final playingSeq = _player.sequenceState?.sequence;
      final previousId = (playingIndex != null &&
              playingSeq != null &&
              playingIndex < playingSeq.length)
          ? (playingIndex >= 0 ? playingSeq[playingIndex].tag : null)
          : null;
      if (previousId is MediaItem &&
          previousId.id.isNotEmpty &&
          _player.processingState != ProcessingState.idle &&
          _player.position > const Duration(seconds: 2)) {
        resumeIndex = sources.indexWhere((s) {
          final tag = s is IndexedAudioSource ? s.tag : null;
          return tag is MediaItem && tag.id == previousId.id;
        });
        if (resumeIndex >= 0) resumePosition = _player.position;
      }
      final start = resumeIndex >= 0 ? resumeIndex : safeStart;

      // Pre-resolve only the next 2 tracks — keeps the queue flowing while
      // avoiding network flooding (Saavn/yt-dlp can't handle 5+ concurrent).
      final startWindow = _storage.crossfadeEnabled ? 0 : 2;
      for (int i = start; i < sources.length && i < start + startWindow; i++) {
        final source = sources[i];
        if (source is ResolvingAudioSource) {
          _preResolve(source);
        }
      }

      await _player.setAudioSource(
        _playlist,
        initialPosition: resumePosition,
        initialIndex: start,
        preload: true,
      );

      // A restored shuffle preference must win over the natural album order,
      // and "smart shuffle" keeps the tapped track first while reordering
      // everything that comes after it.
      try {
        await _player.setShuffleModeEnabled(_storage.shuffleEnabled);
        if (_storage.shuffleEnabled && _storage.smartShuffleEnabled) {
          await shuffleUpcomingQueue();
        }
      } catch (e) {
        debugPrint('Error applying shuffle preference: $e');
      }

      // Surface play errors instead of failing silently — with a flaky backend
      // a track may refuse to buffer and the user should know why. A rapid
      // re-tap interrupts the previous play() call; that is normal, not an
      // error, so it is ignored.
      _playWithAutoSkip();
    } catch (e) {
      debugPrint('Error playing all (attempt ${retryCount + 1}): $e');
      if (retryCount < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return playAll(
          results,
          startIndex: startIndex,
          retryCount: retryCount + 1,
        );
      }
      final context = navigatorKey.currentContext;
      if (context != null) {
        showGlassSnackBar(context, 'Playback unavailable right now');
      }
    } finally {
      _isInitialLoading = false;
    }
  }

  /// Plays the current player with silent auto-skip: whenever a track fails
  /// to buffer (flaky backend), the queue advances to the next one instead of
  /// stopping with an error toast. An error snack is only shown when the whole
  /// remaining queue is unplayable — so playback errors stop being a part of
  /// normal listening. A rapid re-tap interrupts play() and is ignored.
  void _playWithAutoSkip({int? skipsLeft}) {
    // Playback is running again: any "the user just moved on" guard is stale.
    _errorSkipGuard = null;
    // One or two dead tracks in a big list must not look like a global
    // failure: budget as many consecutive skips as there are tracks left
    // (capped) instead of giving up after the second error.
    final budget = skipsLeft ?? (_player.sequence?.length ?? 0).clamp(0, 20);
    unawaited(
      _player.play().catchError((Object e) {
        if (e is PlayerInterruptedException) return;
        debugPrint('Playback error ($budget skips left): $e');
        if (budget > 0 && _player.hasNext) {
          unawaited(_skipToNextSafe(budget - 1));
          return;
        }
        final context = navigatorKey.currentContext;
        if (context != null) {
          showGlassSnackBar(context, 'Playback unavailable right now');
        }
      }),
    );
  }

  /// Auto-skips to the next track without ever letting a failure escape as an
  /// unhandled async error — a rejected seekToNext() used to bubble up through
  /// an unawaited future and take down the whole app right after a dead track.
  Future<void> _skipToNextSafe(int budget) async {
    try {
      await _player.seekToNext();
      _playWithAutoSkip(skipsLeft: budget);
    } catch (e) {
      debugPrint('Auto-skip to next track failed: $e');
      final context = navigatorKey.currentContext;
      if (context != null) {
        showGlassSnackBar(context, 'Playback unavailable right now');
      }
    }
  }

  /// How many times a single track is re-resolved before we give up on it and
  /// move on. One retry is usually enough: the first failure usually comes from
  /// one dead source, and the retry excludes it.
  static const int _maxResolvesPerTrack = 2;

  /// Sources already tried for the track currently failing, so each retry moves
  /// to a *different* resolver instead of hitting the same dead one again.
  final Set<String> _avoidedSources = <String>{};

  /// Retries spent on the current track. Reset whenever the track changes, so a
  /// track later in the queue gets its own fresh budget.
  int _retryCount = 0;

  /// Reacts to a source ExoPlayer could not load: first tries another resolver
  /// for the very same track, and only moves on when no source can produce a
  /// playable URL.
  ///
  /// The skip budget is descending (capped at 20 consecutive failures) so a
  /// queue where every source is dead terminates instead of looping forever.
  /// A manual skip records [_errorSkipGuard], which stops a late-arriving
  /// error from the track the user just left from skipping a second time.

  /// Re-resolves the failing track through another source and plays it again.
  ///
  /// Skipping was the wrong reaction: the listener asked for that song, and a
  /// dead source must not silently cost them the track. Only when no source can
  /// produce a playable URL do we move on — and then, and only then, we skip.
  Future<bool> _retrySameTrack() async {
    final index = _player.currentIndex;
    final sequence = _player.sequenceState?.sequence;
    if (index == null || sequence == null || index >= sequence.length) return false;
    final tag = sequence[index].tag;
    if (tag is! MediaItem) return false;
    final videoId = tag.id;
    if (videoId.isEmpty) return false;
    if (StreamExtractionService.isMetadataSeedId(videoId) &&
        tag.title.isEmpty) {
      // A seed with a title can still be re-resolved by title; without one
      // there is nothing any source could search for.
      return false;
    }
    if (_retryCount >= _maxResolvesPerTrack) {
      debugPrint('AudioHandler: giving up on $videoId after $_retryCount retries');
      return false;
    }
    _retryCount++;
    StreamExtractionService.invalidateCache(videoId);
    debugPrint('AudioHandler: re-resolving $videoId '
        '(attempt $_retryCount, avoiding $_avoidedSources)');

    final url = await StreamExtractionService.getStreamUrl(
      videoId,
      title: tag.title,
      artist: tag.artist,
      avoidSources: _avoidedSources,
      priority: true,
    );
    if (url == null || url.isEmpty) return false;

    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url), tag: tag),
      initialPosition: _player.position,
    );
    unawaited(_player.play());
    debugPrint('AudioHandler: recovered $videoId through a fallback source');
    return true;
  }

  Future<void> _handlePlaybackError() async {
    if (_handlingError) return;
    _handlingError = true;
    try {
      final index = _player.currentIndex;
      final sequence = _player.sequenceState?.sequence;
      if (index != null && sequence != null && index < sequence.length) {
        final tag = sequence[index].tag;
        final videoId = tag is MediaItem ? tag.id : null;
        if (videoId != null && videoId.isNotEmpty) {
          // Replaying the same dead link from cache is what made a broken track
          // fail again on every attempt during the cache TTL.
          StreamExtractionService.invalidateCache(videoId);
        }
      }

      // Give just_audio a moment to settle: an error can be reported twice for
      // the same track (once for the source, once for the play attempt).
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (_errorSkipGuard != null && _errorSkipGuard != _player.currentIndex) {
        _errorSkipGuard = null;
        return; // the user already moved on; do not skip a second time
      }

      // First: try harder on THIS track. Only skip when it is genuinely
      // unplayable everywhere.
      if (await _retrySameTrack()) {
        _avoidedSources.add('saavn');
        return;
      }

      // The track is unplayable everywhere: tell the user instead of skipping
      // in silence (a song that just vanishes looks like a bug).
      String? failedTitle;
      if (index != null && sequence != null && index < sequence.length) {
        final t = sequence[index].tag;
        if (t is MediaItem) failedTitle = t.title;
      }
      _announceUnplayable(failedTitle);

      if (!_player.hasNext) {
        debugPrint('Playback error on the last track: nothing left to skip to');
        return;
      }
      await _player.seekToNext();
      _playWithAutoSkip(
        skipsLeft: (_player.sequence?.length ?? 0).clamp(0, 20) - 1,
      );
    } catch (e) {
      debugPrint('Auto-skip after playback error failed: $e');
    } finally {
      _handlingError = false;
    }
  }

  /// Toast announcing the track the player had to stop on. A 30 s extract that
  /// ends without explanation reads as a playback bug, and on an IP where the
  /// label's uploads are geo-refused it happens for a whole queue — so it is
  /// said once per minute, not on every track.
  void _announceClip(String? title) {
    try {
      final now = DateTime.now();
      if (_lastClipNotice != null &&
          now.difference(_lastClipNotice!) < const Duration(minutes: 1)) {
        return;
      }
      _lastClipNotice = now;
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final name =
          (title != null && title.isNotEmpty) ? '« $title » ' : 'Ce titre ';
      showGlassSnackBar(
        context,
        '$name se lit en extrait de 30 s : la version complète est bloquée dans '
            'ce pays. Les titres libres et vos téléchargements restent entiers.',
      );
    } catch (_) {}
  }

  DateTime? _lastClipNotice;

  /// Surfaces a toast naming the track that could not be resolved, so a
  /// failure is never a silent skip. Best-effort: never throws.
  void _announceUnplayable(String? title, {bool offlineBlocked = false}) {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final name =
          (title != null && title.isNotEmpty) ? '« $title » ' : 'Ce titre ';
      final msg = offlineBlocked
          ? _storage.offlineMode
              ? '$name n\'est pas téléchargé. Hors ligne, seuls vos titres '
                  'téléchargés se lisent.'
              : '$name n\'est pas téléchargé. Seuls vos titres téléchargés se '
                  'lisent — téléchargez-le (menu ⋮), ou désactivez la règle '
                  'dans Réglages › Lecture.'
          : _storage.offlineMode
              ? '$name est indisponible hors ligne — téléchargez-le pour '
                  'l\'écouter.'
              : '$name est indisponible pour le moment.';
      showGlassSnackBar(context, msg, error: true);
    } catch (_) {}
  }

  /// Pre-resolves a lazy source in the background, swallowing failures so they
  /// can never become unhandled async errors (app-wide crash risk).
  void _preResolve(ResolvingAudioSource source) {
    unawaited(
      source.resolve().catchError((Object e) {
        debugPrint('Error pre-resolving track ${source.videoId}: $e');
      }),
    );
  }

  AudioSource? _createLazyAudioSource(MuzoItem result) {
    if (result.videoId == null) return null;
    final videoId = result.videoId!;

    // Strict offline mode / "downloaded only" rule: only tracks present on
    // disk are queued. Non-downloaded items are dropped here so every queue
    // path (playAll / enqueueSongs / DJ radio) becomes local-only without
    // extra plumbing. Local-device library files live on disk by definition,
    // so they always pass.
    //
    // A radio station is the one item that is never bytes on disk AND never a
    // YouTube track: its URL is a live stream that plays with no relay and no
    // server, which is exactly why the downloaded-only rule must not drop it.
    // A forced offline mode still refuses it (there is no network at all).
    final isRadio = result.resultType == 'radio';
    final downloadsOnly = _storage.playDownloadedOnly && !isRadio;
    if ((_storage.offlineMode || downloadsOnly) &&
        result.resultType != 'local_file' &&
        !_storage.isDownloaded(videoId)) {
      debugPrint('Downloaded-only: skipping non-downloaded $videoId');
      return null;
    }
    final title = result.title;
    final artist = result.displayArtist;
    final artUri = result.thumbnails.isNotEmpty
        ? result.thumbnails.last.url
        : '';
    final duration = result.durationSeconds != null
        ? Duration(seconds: result.durationSeconds!)
        : null;

    // A seed whose only stream is a short clip from the catalogue API (Deezer
    // answers with 30s previews). The clip keeps the title playable, but it is
    // a fallback, not the goal: the resolver still hunts a full-length source
    // by title and the clip is used only when every one of them fails.
    final previewOnly = result.metadata?['previewOnly'] == true;

    final mediaItem = MediaItem(
      id: videoId,
      album: result.album?.name ?? 'Tunefy',
      title: title,
      artist: artist,
      duration: duration,
      artUri: Uri.parse(artUri),
      extras: {
        'resultType': result.resultType,
        'lazy': true,
        'audioUrl': result.audioUrl,
        'previewOnly': previewOnly,
        'album': result.album?.name,
        'albumId': result.album?.id,
        'artists': result.artists
            ?.map((a) => {'name': a.name, 'id': a.id})
            .toList(),
      },
    );

    // Downloaded file first: play it directly as a file URI (ExoPlayer picks
    // the right extractor from the .m4a extension) instead of routing through
    // ResolvingAudioSource, which served local bytes with a wrong MIME type
    // and made every downloaded track skip silently.
    try {
      final downloadPath = _storage.getDownloadPath(videoId);
      if (downloadPath != null && File(downloadPath).existsSync()) {
        return AudioSource.uri(
          Uri.file(downloadPath),
          tag: mediaItem,
        );
      }
    } catch (_) {}

      // A pre-resolved stream URL (e.g. artist-page enrichment) is played
      // DIRECTLY instead of being thrown away: the old path rebuilt a
      // ResolvingAudioSource that ignored audioUrl and re-downloaded the whole
      // file into memory — which made artist-page taps resolve silently and
      // fail on any dead copy. googlevideo URLs are IP-bound, so an enrichment
      // that just ran on THIS device (tracked via `streamFreshTs`) is trusted
      // exactly like the local stream cache's 30-minute window — EXCEPT
      // trycloudflare tunnels (dead DNS) which always Source-error.
      final url = result.audioUrl;
      if (url != null && url.isNotEmpty) {
        final lower = url.toLowerCase();
        final metaTs = result.metadata?['streamFreshTs'];
        final now = DateTime.now().millisecondsSinceEpoch;
        final isFresh = metaTs is int && (now - metaTs) <=
            StreamExtractionService.streamCacheTtlMs;
        final freshGooglevideo =
            isFresh && lower.contains('googlevideo.com');
        // Any URL freshly resolved on THIS device (streamFreshTs ≤ 30 min) is
        // streamed directly — googlevideo, cobalt, saavn, piped… The only URLs
        // excluded are known-dead hosts (serverless workers / shared caches /
        // expired cloudflare tunnels) whose copies 403 no matter how fresh.
        final freshOnDevice = isFresh &&
            !lower.contains('vercel.app') &&
            !lower.contains('netlify.app') &&
            !lower.contains('supabase.co') &&
            !lower.contains('trycloudflare.com');
      if (isRadio ||
          (!previewOnly &&
              (StreamExtractionService.isReusableStreamUrl(url) ||
                  freshGooglevideo ||
                  freshOnDevice))) {
        return AudioSource.uri(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36',
          },
          tag: mediaItem,
        );
      }
    }

    // A station without its stream URL has nothing to resolve: there is no
    // YouTube video behind it, so the resolver would only search and fail.
    if (isRadio) {
      debugPrint('Radio: no stream URL for $videoId');
      return null;
    }

    return ResolvingAudioSource(
      videoId: videoId,
      storage: _storage,
      // A track that ends up unresolvable must not vanish in silence: the queue
      // advances on the empty response, so say which one it skipped.
      onUnresolvable: (id, t) => _announceUnplayable(t),
      onClipServed: (id, t) => _announceClip(t),
      // The clip travels here so the resolver can fall back to it after the
      // full-length hunt fails, instead of returning nothing.
      fallbackUrl: previewOnly ? result.audioUrl : null,
      tag: mediaItem,
    );
  }

  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position, {int? index}) =>
      _player.seek(position, index: index);
  Future<void> resume() async => _safePlay();

  /// Starts playback, swallowing harmless errors: a rapid re-tap interrupts
  /// play() (PlayerInterruptedException) and a stream that refuses to buffer
  /// is logged, never thrown as an unhandled async error.
  void _safePlay() {
    unawaited(
      _player.play().catchError((Object e) {
        if (e is PlayerInterruptedException) return;
        debugPrint('Playback error: $e');
      }),
    );
  }

  Future<void> skipToNext() async {
    // Mark the manual move so a playback error still in flight for the track
    // being left does not skip a second time behind the user's back.
    _errorSkipGuard = _player.currentIndex;
    await _player.seekToNext();
    _safePlay();
  }

  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    _safePlay();
  }

  void dispose() {
    // Cancel all stream subscriptions to prevent memory leaks
    _playerStateSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _androidAudioSessionIdSubscription?.cancel();
    _sequenceStateSubscription?.cancel();
    _currentIndexSubscription?.cancel();
    _positionSubscription?.cancel();

    // Dispose notifiers
    isLoadingStream.dispose();
    isLofiModeNotifier.dispose();
    isShuffleModeNotifier.dispose();
    repeatModeNotifier.dispose();
    isSmartShuffleNotifier.dispose();
    isAutoplayNotifier.dispose();

    // Dispose player last
    _player.dispose();
  }

  Future<void> removeQueueItem(int index) async {
    try {
      await _playlist.removeAt(index);
    } catch (e) {
      debugPrint('Error removing queue item: $e');
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    try {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      await _playlist.move(oldIndex, newIndex);
    } catch (e) {
      debugPrint('Error reordering queue: $e');
    }
  }

  Future<void> clearQueue() async {
    try {
      final currentIndex = _player.currentIndex;
      if (currentIndex != null && _playlist.length > 1) {
        if (currentIndex < _playlist.length - 1) {
          await _playlist.removeRange(currentIndex + 1, _playlist.length);
        }
        if (currentIndex > 0) {
          await _playlist.removeRange(0, currentIndex);
        }
      } else {
        await _playlist.clear();
      }
    } catch (e) {
      debugPrint('Error clearing queue: $e');
    }
  }

  Future<void> playNext(MuzoItem result) async {
    try {
      final index = _player.currentIndex;
      if (index == null) {
        await addToQueue(result);
        return;
      }
      if (result.videoId == null) return;
      final videoId = result.videoId!;
      if ((_storage.offlineMode ||
              (_storage.playDownloadedOnly && result.resultType != 'radio')) &&
          result.resultType != 'local_file' &&
          !_storage.isDownloaded(videoId)) {
        debugPrint('Downloaded-only: playNext blocked (not downloaded) $videoId');
        return;
      }
      final title = result.title;
      final artist = result.displayArtist;
      final artistId = result.artists?.firstOrNull?.id;
      final artUri = result.thumbnails.isNotEmpty
          ? result.thumbnails.last.url
          : '';
      final resultType = result.resultType;
      Duration? duration;
      if (result.durationSeconds != null) {
        duration = Duration(seconds: result.durationSeconds!);
      }

      final downloadPath = _storage.getDownloadPath(videoId);
      Uri audioUri;

      if (downloadPath != null && await File(downloadPath).exists()) {
        audioUri = Uri.file(downloadPath);
      } else if (resultType == 'radio') {
        // A live station is not a YouTube video: its own URL is the stream,
        // so the extraction pipeline (which would fail on an "ra_" id) never
        // runs for it. A device with no network still refuses it.
        if (_storage.offlineMode || await ContentCacheService.isOffline()) {
          _offlineBlockedTitle = title;
          return;
        }
        final url = result.audioUrl;
        if (url == null || url.isEmpty) return;
        audioUri = Uri.parse(url);
      } else {
        final streamUrl = await StreamExtractionService.getStreamUrl(
          videoId,
          title: title,
          artist: artist,
          durationSeconds: duration?.inSeconds,
          priority: true,
        );
        if (streamUrl == null) return;
        audioUri = Uri.parse(streamUrl);
      }

      final audioSource = AudioSource.uri(
        audioUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36',
        },
        tag: MediaItem(
          id: videoId,
          album: result.album?.name ?? "Tunefy",
          title: title,
          artist: artist,
          duration: duration,
          artUri: Uri.parse(artUri),
          extras: {
            'resultType': resultType,
            'artistId': artistId,
            'isSaavn': StreamExtractionService.isSaavnCache[videoId],
            'album': result.album?.name,
            'albumId': result.album?.id,
            'artists': result.artists
                ?.map((a) => {'name': a.name, 'id': a.id})
                .toList(),
          },
        ),
      );

      await _playlist.insert(index + 1, audioSource);

      final context = navigatorKey.currentContext;
      if (context != null) {
        showGlassSnackBar(context, 'Song added to play next');
      }
    } catch (e) {
      debugPrint('Error playing next: $e');
    }
  }

  /// Rebuilds the original artist list from a MediaItem's extras. The tag is
  /// the only place the full metadata survives: audio_service wraps everything
  /// in a MediaItem and drops the original MuzoItem's `artists`/`album`.
  static List<MuzoArtist> _artistsFromExtras(Map<String, dynamic>? extras) {
    final raw = extras?['artists'];
    if (raw is! List || raw.isEmpty) return [];
    return raw.map((a) {
      if (a is Map && a['name'] != null) {
        return MuzoArtist(
          name: a['name'].toString(),
          id: a['id']?.toString(),
        );
      }
      return MuzoArtist(name: a.toString(), id: null);
    }).toList();
  }

  /// Rebuilds the original album from a MediaItem's extras. Falls back to the
  /// tag's hardcoded album only when the item truly has no album metadata.
  static MuzoAlbum? _albumFromExtras(Map<String, dynamic>? extras) {
    final name = extras?['album'];
    if (name is String && name.isNotEmpty) {
      return MuzoAlbum(
        name: name,
        id: extras?['albumId']?.toString() ?? '',
      );
    }
    return null;
  }
}

class _FadeIn {
  final Duration startedAt;
  final Duration total;

  const _FadeIn({required this.startedAt, required this.total});
}

class ResolvingAudioSource extends StreamAudioSource {
  final String videoId;
  final StorageService storage;
  String? _resolvedUrl;
  Future<void>? _resolveFuture;
  Uint8List? _downloadedBytes;
  String? _title;
  String? _artist;
  int? _durationSeconds;
  bool _retriedWithoutSaavn = false;
  bool _retriedDeadUrl = false;
  bool _retriedFullCascade = false;
  bool _unresolvableAnnounced = false;

  /// Called when the player itself asks for this track's bytes and nothing can
  /// be resolved. That is the moment a silent skip looks like a bug to the user,
  /// so the handler gets one chance to say so. Pre-resolution of the next track
  /// never reaches it: `request` only runs for the track being played.
  final void Function(String videoId, String? title)? onUnresolvable;

  /// Short catalogue clip (Deezer's 30s preview) kept as a last resort: the
  /// full-length sources are tried first, and if none answers the clip is
  /// streamed so the track the user tapped always makes sound.
  final String? fallbackUrl;

  /// Set when the track is finally served by a short catalogue clip rather than
  /// a full stream. Without a word about it, a song stopping at 30 seconds reads
  /// as a new playback bug — and on an IP where YouTube geo-refuses the label's
  /// uploads, that is now the normal outcome.
  final void Function(String videoId, String? title)? onClipServed;

  ResolvingAudioSource({
    required this.videoId,
    required this.storage,
    this.onUnresolvable,
    this.onClipServed,
    this.fallbackUrl,
    super.tag,
  });

  /// The clip to fall back on, from the constructor or from the MediaItem
  /// extras (whichever path built this source passed it).
  String? get _clipUrl {
    if (fallbackUrl != null && fallbackUrl!.isNotEmpty) return fallbackUrl;
    final mediaItem = tag as MediaItem?;
    if (mediaItem?.extras?['previewOnly'] == true) {
      final url = mediaItem?.extras?['audioUrl'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  /// Finds a stream URL for this track. It deliberately does NOT fetch the
  /// audio body: pre-resolving the next tracks used to download every one of
  /// them, which is exactly what the user read as "it downloads while I listen"
  /// (and it stalled the track actually asked for). The body is fetched by
  /// `request()`, i.e. only for the song the player is about to play.
  Future<void> resolve() async {
    if (_resolvedUrl != null && _resolvedUrl != 'EMPTY') return;
    if (_resolvedUrl == 'EMPTY') return;
    if (_resolveFuture != null) {
      await _resolveFuture;
      return;
    }

    final mediaItem = tag as MediaItem?;
    final audioUrl = mediaItem?.extras?['audioUrl'];
    if (mediaItem?.extras?['previewOnly'] != true &&
        audioUrl is String &&
        audioUrl.isNotEmpty &&
        StreamExtractionService.isReusableStreamUrl(audioUrl)) {
      _resolvedUrl = audioUrl;
      return;
    }
    if (mediaItem?.extras?['resultType'] == 'user_track') {
      _resolvedUrl = 'EMPTY';
      return;
    }

    final title = mediaItem?.title;
    final artist = mediaItem?.artist;
    final durationSeconds = mediaItem?.duration?.inSeconds;
    _title = title;
    _artist = artist;
    _durationSeconds = durationSeconds;

    final future =
        StreamExtractionService.getStreamUrl(
              videoId,
              title: title,
              artist: artist,
              durationSeconds: durationSeconds,
            )
            .then((url) async {
              _resolvedUrl = url;
              if (url != null) return;
              // Nothing resolved. Before giving up, force a second pass with the
              // stream cache dropped and Saavn out of the mix: the first pass can
              // miss because a source parked itself for the whole artist page,
              // and a cached dead URL is replayed instead of re-resolved.
              // Skipped when a catalogue clip is already in hand — a second
              // 18s hunt would only delay the audio the user is waiting for.
              if (!_retriedFullCascade && _clipUrl == null) {
                _retriedFullCascade = true;
                try {
                  await StreamExtractionService.invalidateCache(videoId);
                } catch (_) {}
                final again = await StreamExtractionService.getStreamUrl(
                  videoId,
                  title: title,
                  artist: artist,
                  durationSeconds: durationSeconds,
                  skipSaavn: true,
                );
                if (again != null) {
                  _resolvedUrl = again;
                  debugPrint('ResolvingAudioSource: cascade retry resolved '
                      '$videoId via $again');
                }
              }
              // Full race failed. A short catalogue clip beats silence: play it
              // so the track the user tapped always makes sound. Without one,
              // mark EMPTY so request() stops retrying a hopeless extraction —
              // the empty response reads as an instant end-of-track, so the
              // queue moves on by itself.
              // When the item carries no clip of its own, ask Deezer: French
              // "- Topic" uploads are licensed to a country list that excludes
              // Benin, so on this network a whole shelf can come back
              // UNPLAYABLE while Deezer's preview CDN answers in two seconds.
              final clip = _clipUrl ??
                  await StreamExtractionService.catalogClipUrl(
                      title ?? '', artist ?? '');
              if (clip != null) {
                debugPrint('ResolvingAudioSource: $videoId served by '
                    'catalogue clip after full hunt failed');
                // Recorded so nothing downstream treats this source as a full
                // track (no clip-of-a-clip retry, no "download" of an extract).
                final item = tag;
                if (item is MediaItem) {
                  item.extras?['previewOnly'] = true;
                }
                _resolvedUrl = clip;
                onClipServed?.call(videoId, title);
                return;
              }
              debugPrint(
                  'ResolvingAudioSource: no stream resolved for $videoId');
              _resolvedUrl = 'EMPTY';
            })
            .catchError((e) {
              debugPrint('Error pre-resolving track $videoId: $e');
              final clip = _clipUrl;
              _resolvedUrl = clip ?? 'EMPTY';
            })
            .whenComplete(() {
              _resolveFuture = null;
            });

    _resolveFuture = future;
    await future;
  }

  Future<void> _downloadFullAudio() async {
    if (_resolvedUrl == null || _resolvedUrl == 'EMPTY') return;
    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(_resolvedUrl!));
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36';
        request.headers['Range'] = 'bytes=0-';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200 || response.statusCode == 206) {
          // The response HEAD can be fast while the body stalls forever on a
          // dying proxy — bound the full read too, then re-resolve once.
          final bytes = await response.stream
              .toBytes()
              .timeout(const Duration(seconds: 45));
          final data = bytes.buffer.asUint8List();
          if (!_looksLikeAudio(data)) {
            // Dead proxies often return an HTML/JSON error page with HTTP 200 —
            // feeding it to ExoPlayer fails with "UnrecognizedInputFormatException".
            debugPrint(
              'ResolvingAudioSource: non-audio bytes (${data.length}) for $videoId — discarding',
            );
            _downloadedBytes = null;
            _resolvedUrl = null;
            try {
              await StreamExtractionService.invalidateCache(videoId);
            } catch (_) {}
            if (!_retriedWithoutSaavn) {
              _retriedWithoutSaavn = true;
              final alt = await StreamExtractionService.getStreamUrl(
                videoId,
                title: _title,
                artist: _artist,
                durationSeconds: _durationSeconds,
                skipSaavn: true,
              );
              if (alt != null) {
                _resolvedUrl = alt;
                debugPrint(
                  'ResolvingAudioSource: retrying $videoId without Saavn via $alt',
                );
                await _downloadFullAudio();
                return;
              }
            }
            return;
          }
          _downloadedBytes = data;
          debugPrint(
            'ResolvingAudioSource: downloaded ${_downloadedBytes!.length} bytes for $videoId',
          );
        } else {
          debugPrint(
            'ResolvingAudioSource: download failed ${response.statusCode} for $videoId',
          );
          // The URL is dead (IP-bound, expired, blocked). Drop it everywhere
          // so the next attempt re-resolves from scratch, then retry once —
          // a cached googlevideo URL bound to another IP 403s here even
          // though a fresh URL (same device IP) plays fine.
          _downloadedBytes = null;
          _resolvedUrl = null;
          try {
            await StreamExtractionService.invalidateCache(videoId);
          } catch (_) {}
          if (!_retriedDeadUrl) {
            _retriedDeadUrl = true;
            debugPrint(
              'ResolvingAudioSource: re-resolving $videoId after ${response.statusCode}',
            );
            final alt = await StreamExtractionService.getStreamUrl(
              videoId,
              title: _title,
              artist: _artist,
              durationSeconds: _durationSeconds,
            );
            if (alt != null) {
              _resolvedUrl = alt;
              await _downloadFullAudio();
              return;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('ResolvingAudioSource: download error for $videoId: $e');
      _downloadedBytes = null;
      if (e is TimeoutException) {
        // Body read stalled — the URL is likely a dying proxy. Drop it from
        // the cache and re-resolve once, same as a dead-URL 403.
        _resolvedUrl = null;
        try {
          await StreamExtractionService.invalidateCache(videoId);
        } catch (_) {}
        if (!_retriedDeadUrl) {
          _retriedDeadUrl = true;
          final alt = await StreamExtractionService.getStreamUrl(
            videoId,
            title: _title,
            artist: _artist,
            durationSeconds: _durationSeconds,
          );
          if (alt != null) {
            _resolvedUrl = alt;
            debugPrint(
              'ResolvingAudioSource: retrying $videoId after download timeout',
            );
            await _downloadFullAudio();
          }
        }
      }
    }
  }

  /// Cheap magic-byte sniff to avoid handing non-media payloads (HTML/JSON
  /// error pages) to the media player, which would fail the format scan.
  static bool _looksLikeAudio(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final b = bytes;
    // MP4/M4A/MOV: box size followed by 'ftyp'
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return true;
    }
    // MP3: ID3 tag or MPEG audio frame sync
    if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
      return true;
    }
    if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
      return true;
    }
    // WebM/Matroska EBML header
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
      return true;
    }
    // Ogg/Opus
    if (b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return true;
    }
    // FLAC, WAV, AAC (ADTS)
    if (b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43) {
      return true;
    }
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
      return true;
    }
    if (b.length > 3 && b[0] == 0xFF && (b[1] & 0xF6) == 0xF0) {
      return true;
    }
    return false;
  }

  static String _contentTypeFor(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.m4b')) {
      return 'audio/mp4';
    }
    if (lower.endsWith('.webm')) return 'audio/webm';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'audio/ogg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    return 'audio/mpeg';
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (!kIsWeb) {
      final downloadPath = storage.getDownloadPath(videoId);
      if (downloadPath != null && await File(downloadPath).exists()) {
        final file = File(downloadPath);
        final length = await file.length();
        final s = start ?? 0;
        final e = end ?? length;
        return StreamAudioResponse(
          sourceLength: length,
          contentLength: e - s,
          offset: s,
          contentType: _contentTypeFor(downloadPath),
          stream: file.openRead(s, e),
        );
      }
    }

    if (_downloadedBytes == null && _resolvedUrl != 'EMPTY') {
      await resolve();
      // The player is asking for THIS track's bytes now, so this is the only
      // moment a body may be fetched.
      if (_resolvedUrl != null && _resolvedUrl != 'EMPTY') {
        await _downloadFullAudio();
      }
    }

    if (_downloadedBytes == null || _downloadedBytes!.isEmpty) {
      if (_resolvedUrl == 'EMPTY' && !_unresolvableAnnounced) {
        _unresolvableAnnounced = true;
        try {
          onUnresolvable?.call(videoId, _title);
        } catch (_) {}
      }
      return _emptyResponse(start);
    }

    final s = start ?? 0;
    final totalLen = _downloadedBytes!.length;
    final e = (end != null && end > s) ? end : totalLen;
    final len = (e - s).clamp(0, totalLen - s);
    final chunk = _downloadedBytes!.buffer.asUint8List(s, len);
    return StreamAudioResponse(
      sourceLength: totalLen,
      contentLength: chunk.length,
      offset: s,
      contentType: _contentTypeFor(_resolvedUrl ?? ''),
      stream: Stream.value(chunk),
    );
  }

  /// A zero-length audio response. The player treats it as an instant end-of-
  /// track and advances to the next song, so unplayable tracks are skipped.
  StreamAudioResponse _emptyResponse(int? start) {
    return StreamAudioResponse(
      sourceLength: 0,
      contentLength: 0,
      offset: start ?? 0,
      contentType: 'audio/mpeg',
      stream: const Stream.empty(),
    );
  }
}
