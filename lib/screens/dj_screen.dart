import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/dj_chat_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/screens/dj_mix_screen.dart';
import 'package:muzo/services/dj_chat_history_service.dart';
import 'package:muzo/services/dj_engine.dart';
import 'package:muzo/services/dj_mix_tips.dart';
import 'package:muzo/services/dj_mood_bot.dart';
import 'package:muzo/services/dj_radio_service.dart';
import 'package:muzo/services/dj_smart_playlist.dart';
import 'package:muzo/services/gemini_service.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/utils/app_colors.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Tunefy DJ — studio d'écoute « sans fin ».
///
/// Chat d'humeur persistant (Hive), détection d'humeur (mots-clés FR/EN),
/// génération d'un mix réel (jusqu'à 60 pistes) sauvegardé + page dédiée
/// pour tout lire. Rien n'est inventé.
class DjScreen extends ConsumerStatefulWidget {
  const DjScreen({super.key, this.seed});

  final MuzoItem? seed;

  @override
  ConsumerState<DjScreen> createState() => _DjScreenState();
}

class _DjScreenState extends ConsumerState<DjScreen> {
  late final DjEngine _engine = DjEngine(ref);
  late final DjMoodBot _bot = DjMoodBot(ref);
  late final DjRadioService _radio = ref.read(djRadioServiceProvider);
  late final DjChatHistoryService _history =
      ref.read(djChatHistoryServiceProvider);
  bool _busy = false;
  bool _typing = false;
  String? _typingLabel;
  bool _historyLoaded = false;
  int _durationMinutes = 60;
  DjMood? _activeMood;
  StreamSubscription<Duration>? _posSub;
  String? _prevMediaKey;
  bool _radioRefillScheduled = false;

  final List<DjChatMessage> _chat = [];
  final List<MuzoItem> _generated = [];
  String? _activeMixId;
  List<DjGeneratedMix> _recentMixes = [];

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final ScrollController _mainScroll = ScrollController();

  static String _keyFromMedia(MediaItem m) => m.id.toLowerCase();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadHistory());
      _attachPlayerHooks();
      final media = ref.read(currentMediaItemProvider).valueOrNull;
      if (media == null && widget.seed != null) _startFromSeed();
    });
  }

  Future<void> _loadHistory() async {
    final messages = await _history.loadMessages();
    final mixes = await _history.listMixes();
    final session = await _history.loadSession();
    // Drop transient status lines from older sessions (building…, etc.).
    final cleaned = messages
        .where((m) => m.text != AppLocalizations.of(context).djSmartPlaylistBuilding)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    String? mixId;
    if (cleaned.isNotEmpty) {
      final lastWithMix = cleaned.lastWhere(
        (m) => m.mixId != null,
        orElse: () => cleaned.last,
      );
      mixId = lastWithMix.mixId;
    }
    // Restore the suggested-songs list from the active mix so quitting the
    // page and coming back shows the same picks, not just the bubbles.
    DjGeneratedMix? activeMix;
    if (mixId != null) activeMix = await _history.loadMix(mixId);
    if (!mounted) return;
    setState(() {
      _chat
        ..clear()
        ..addAll(cleaned);
      _recentMixes = mixes;
      _historyLoaded = true;
      _activeMixId = activeMix?.id ?? mixId;
      if (activeMix != null) {
        _generated
          ..clear()
          ..addAll(activeMix.tracks);
      }
      final dur = (session['durationMinutes'] as num?)?.toInt();
      if (dur != null && dur > 0) _durationMinutes = dur;
      _activeMood = _moodFromName(session['activeMood'] as String?);
      _radio.setEnabled(session['radioEnabled'] == true);
      if (_activeMood != null) {
        _radio.setMood(_activeMood);
        _bot.tracker.setActiveMood(_activeMood!.name);
      }
    });
    if (_chat.isNotEmpty) _chatScrollToBottom();
  }

  Future<void> _persistChat() async {
    await _history.saveMessages(List.of(_chat));
  }

  /// Persists duration / radio / active mood so the whole panel comes back.
  Future<void> _persistSession() async {
    await _history.saveSession({
      'durationMinutes': _durationMinutes,
      'radioEnabled': _radio.enabled,
      'activeMood': _activeMood?.name,
    });
  }

  DjMood? _moodFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final m in DjMood.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _chatController.dispose();
    _chatScroll.dispose();
    _mainScroll.dispose();
    super.dispose();
  }

  /// Branche mood tracking (>75% like / early skip) sur la position réelle.
  void _attachPlayerHooks() {
    final handler = ref.read(audioHandlerProvider);

    _posSub = handler.player.positionStream.listen((pos) {
      final media = handler.player.sequenceState?.currentSource?.tag;
      if (media is! MediaItem) return;
      _radio.noteProgress(
        MediaItemLike(
          id: media.id,
          title: media.title,
          artist: media.artist ?? '',
          durationMs: media.duration?.inMilliseconds,
        ),
        pos.inMilliseconds,
      );
    });
  }

  void _onMediaChanged(MediaItem? media) {
    final key = media == null ? null : _keyFromMedia(media);
    if (key == null || key == _prevMediaKey) return;
    final prev = _prevMediaKey;
    _prevMediaKey = key;
    if (prev != null) {
      unawaited(_scoreAndMaybeRefill(prev, media));
    }
  }

  Future<void> _scoreAndMaybeRefill(String prevKey, MediaItem? current) async {
    final prevMedia = _findMediaByKey(prevKey);
    await _radio.scoreCurrentAsPrevious(prevMedia);
    if (!_radio.enabled) return;

    final remaining = _remainingQueue();
    if (remaining <= _radio.refillThreshold && !_radioRefillScheduled) {
      _radioRefillScheduled = true;
      try {
        final anchor = _lastGeneratedOrCurrent(current);
        await _radio.maybeRefill(anchor: anchor, remaining: remaining);
      } finally {
        _radioRefillScheduled = false;
      }
    }
  }

  MediaItemLike? _findMediaByKey(String key) {
    final handler = ref.read(audioHandlerProvider);
    final sequence = handler.player.sequenceState?.sequence ?? const [];
    for (final s in sequence) {
      final tag = s.tag;
      if (tag is MediaItem && tag.id.toLowerCase() == key) {
        return MediaItemLike(
          id: tag.id,
          title: tag.title,
          artist: tag.artist ?? '',
          durationMs: tag.duration?.inMilliseconds,
        );
      }
    }
    return null;
  }

  int _remainingQueue() {
    final handler = ref.read(audioHandlerProvider);
    final seq = handler.player.sequenceState;
    if (seq == null) return 0;
    final total = seq.sequence.length;
    final idx = seq.currentIndex;
    return total - idx - 1;
  }

  MuzoItem? _lastGeneratedOrCurrent(MediaItem? current) {
    if (_generated.isNotEmpty) {
      final key = current == null ? null : _keyFromMedia(current);
      for (final s in _generated.reversed) {
        final sk = (s.videoId ?? '${s.title}|${s.displayArtist}').toLowerCase();
        if (key == null || sk != key) return s;
      }
      return _generated.last;
    }
    if (current != null) {
      return MuzoItem(
        title: current.title,
        thumbnails: [
          if (current.artUri != null)
            MuzoThumbnail(url: current.artUri.toString(), width: 0, height: 0),
        ],
        resultType: 'song',
        isExplicit: false,
        videoId: current.id,
        artists: [MuzoArtist(name: current.artist ?? '', id: '')],
        durationSeconds: current.duration?.inSeconds,
      );
    }
    return null;
  }

  void _chatScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _mainScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_mainScroll.hasClients) return;
      _mainScroll.animateTo(
        _mainScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _sendMood() {
    final text = _chatController.text.trim();
    if (text.isEmpty || _typing || _busy) return;
    _chatController.clear();
    setState(() => _chat.add(DjChatMessage.user(text)));
    _chatScrollToBottom();
    unawaited(_persistChat());
    unawaited(_runMoodChat(text));
  }

  Future<void> _runMoodChat(String raw, {DjMood? preDetected}) async {
    if (_typing || _busy) return;
    final l10n = AppLocalizations.of(context);

    // Freedify Smart Playlist: free-text vibe → Gemini catalog seeds.
    if (preDetected == null &&
        raw.isNotEmpty &&
        DjSmartPlaylistService.looksLikeSmartPlaylist(raw)) {
      await _runSmartPlaylist(raw);
      return;
    }

    final mood = preDetected ?? _bot.detect(raw);
    if (mood == null) {
      await _runChatReply(raw);
      return;
    }

    setState(() {
      _typing = true;
      _busy = true;
      _typingLabel = null;
    });
    _chatScrollToBottom();
    try {
      final handler = ref.read(audioHandlerProvider);
      final seen = <String>{};
      for (final s in handler.player.sequenceState?.sequence ?? const []) {
        if (s.tag is MediaItem) seen.add(_keyFromMedia(s.tag as MediaItem));
      }

      final want = DjMoodBot.trackCountForMinutes(_durationMinutes);
      final picks = await _bot.buildSet(mood, seenKeys: seen, count: want);
      if (!mounted) return;
      if (picks.isEmpty) {
        setState(() {
          _typing = false;
          _busy = false;
          _typingLabel = null;
          _chat.add(DjChatMessage.bot(l10n.djMoodEmpty));
        });
        _chatScrollToBottom();
        unawaited(_persistChat());
        return;
      }

      await _publishMix(
        picks: picks,
        mood: mood,
        mixTitle: '${_moodName(l10n, mood)} · ${l10n.tunefyDj}',
        reply: '${_moodReply(l10n, mood)}\n\n'
            '${l10n.djMoodReady.replaceAll('{count}', '${picks.length}')}',
      );
    } catch (e, st) {
      debugPrint('[TunefyDJ] generate error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _typing = false;
        _busy = false;
        _typingLabel = null;
        _chat.add(DjChatMessage.bot(l10n.djMoodError));
      });
      _chatScrollToBottom();
      unawaited(_persistChat());
    } finally {
      if (mounted && (_typing || _busy)) {
        setState(() {
          _typing = false;
          _busy = false;
          _typingLabel = null;
        });
      }
    }
  }

  /// Discussion libre : si aucun mood n'est détecté, le DJ répond comme un
  /// vrai interlocuteur (Gemini) avec un repli local hors-ligne. Il ne
  /// fabrique jamais de titres : il répond, puis invite à décrire une humeur.
  Future<void> _runChatReply(String raw) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _typing = true;
      _busy = true;
      _typingLabel = l10n.djTyping;
    });
    _chatScrollToBottom();
    try {
      final gemini = ref.read(geminiServiceProvider);
      final recentSlices = _chat
          .skip(_chat.length > 8 ? _chat.length - 8 : 0)
          .map((m) => '${m.fromUser ? 'User' : 'DJ'}: ${m.text}');
      final prompt = 'You are Tunefy DJ, the DJ assistant of a music app. '
          'Reply in the ${l10n.locale.languageCode} language, like a warm, '
          'professional DJ. Keep it under 3 short sentences. If the user '
          'shares a mood or feeling, acknowledge it and invite them to let '
          'you spin a real mix. If the message is off-topic, steer gently '
          'back to music. Never invent specific song titles, artists or '
          'links.\n\n'
          'Recent conversation:\n${recentSlices.join('\n')}\n\n'
          'User: $raw\nDJ:';
      final reply = await gemini.completeProse(prompt);
      if (!mounted) return;
      setState(() {
        _typing = false;
        _busy = false;
        _typingLabel = null;
        _chat.add(DjChatMessage.bot(reply ?? l10n.djChatFallback));
      });
      _chatScrollToBottom();
      unawaited(_persistChat());
    } catch (e, st) {
      debugPrint('[TunefyDJ] chat reply error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _typing = false;
        _busy = false;
        _typingLabel = null;
        _chat.add(DjChatMessage.bot(l10n.djChatFallback));
      });
      _chatScrollToBottom();
      unawaited(_persistChat());
    } finally {
      if (mounted && (_typing || _busy)) {
        setState(() {
          _typing = false;
          _busy = false;
          _typingLabel = null;
        });
      }
    }
  }

  /// Freedify Smart Playlist via Gemini + real catalog search.
  Future<void> _runSmartPlaylist(String prompt) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _typing = true;
      _busy = true;
      _typingLabel = l10n.djSmartPlaylistBuilding;
    });
    // Typing label only — do not persist a "building…" bubble.
    _chatScrollToBottom();
    try {
      final handler = ref.read(audioHandlerProvider);
      final seen = <String>{};
      for (final s in handler.player.sequenceState?.sequence ?? const []) {
        if (s.tag is MediaItem) seen.add(_keyFromMedia(s.tag as MediaItem));
      }

      final want = DjMoodBot.trackCountForMinutes(_durationMinutes);
      final picks = await ref.read(djSmartPlaylistProvider).build(
            prompt: prompt,
            durationMinutes: _durationMinutes,
            seenKeys: seen,
            targetCount: want,
          );
      if (!mounted) return;
      if (picks.isEmpty) {
        setState(() {
          _typing = false;
          _busy = false;
          _typingLabel = null;
          _chat.add(DjChatMessage.bot(l10n.djSmartPlaylistEmpty));
        });
        _chatScrollToBottom();
        unawaited(_persistChat());
        return;
      }

      await _publishMix(
        picks: picks,
        mood: null,
        mixTitle: prompt.length > 48 ? '${prompt.substring(0, 48)}…' : prompt,
        reply:
            l10n.djSmartPlaylistReady.replaceAll('{count}', '${picks.length}'),
      );
    } catch (e, st) {
      debugPrint('[TunefyDJ] smart playlist error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _typing = false;
        _busy = false;
        _typingLabel = null;
        _chat.add(DjChatMessage.bot(l10n.djSmartPlaylistEmpty));
      });
      _chatScrollToBottom();
      unawaited(_persistChat());
    } finally {
      if (mounted && (_typing || _busy)) {
        setState(() {
          _typing = false;
          _busy = false;
          _typingLabel = null;
        });
      }
    }
  }

  /// Enrich head, save mix, reply, optional AI tip, start playback.
  Future<void> _publishMix({
    required List<MuzoItem> picks,
    required DjMood? mood,
    required String mixTitle,
    required String reply,
  }) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    // Enrich only the head for instant playback; keep the full list
    // (50–60 tracks) for the mix page — audio_handler resolves the rest
    // lazily via ResolvingAudioSource.
    final enrichedHead = await _enrichForPlay(picks);
    if (!mounted) return;
    final playable = <MuzoItem>[
      ...enrichedHead,
      ...picks.skip(enrichedHead.length),
    ];

    if (mood != null) {
      _activeMood = mood;
      _radio.setMood(mood);
      _bot.tracker.setActiveMood(mood.name);
    }
    unawaited(_persistSession());

    final mixId = DateTime.now().microsecondsSinceEpoch.toString();
    final mix = DjGeneratedMix(
      id: mixId,
      mood: mood?.name ?? 'custom',
      title: mixTitle,
      createdAt: DateTime.now(),
      durationMinutes: _durationMinutes,
      tracks: List.of(picks),
    );
    await _history.saveMix(mix);

    // Attach the AI tip to the mix reply (single bubble, less clutter).
    var fullReply = reply;
    if (playable.length >= 2) {
      final tips = DjMixTips(gemini: ref.read(geminiServiceProvider));
      final tip = await tips.analyze(playable.first, playable[1]);
      if (tip != null && mounted) {
        final typeLabel = tips.labelOf(tip.transitionType);
        var tipLine = l10n.djMixTip
            .replaceAll('{type}', typeLabel)
            .replaceAll('{sec}', '${tip.crossfadeSeconds}');
        if (tip.aiAdvice != null && tip.aiAdvice!.isNotEmpty) {
          tipLine = '$tipLine — ${tip.aiAdvice}';
        }
        fullReply = '$fullReply\n\n$tipLine';
      }
    }

    if (!mounted) return;
    setState(() {
      _typing = false;
      _busy = false;
      _typingLabel = null;
      _generated
        ..clear()
        ..addAll(playable);
      _activeMixId = mixId;
      _chat.add(DjChatMessage.bot(fullReply, mixId: mixId));
    });
    _chatScrollToBottom();
    _mainScrollToBottom();
    unawaited(_persistChat());
    unawaited(_refreshMixes());

    final isPlaying = ref.read(currentMediaItemProvider).valueOrNull != null;
    debugPrint('[TunefyDJ] mood=${mood?.name ?? 'custom'} '
        'picks=${playable.length} duration=${_durationMinutes}m mix=$mixId');
    final handler = ref.read(audioHandlerProvider);
    if (isPlaying) {
      await handler.enqueueSongs(playable);
    } else {
      await handler.playAll(playable, startIndex: 0);
    }
  }

  Future<void> _refreshMixes() async {
    final mixes = await _history.listMixes();
    if (!mounted) return;
    setState(() => _recentMixes = mixes);
  }

  /// « Tout effacer » : chat, session (durée/radio/humeur), mixs générés,
  /// feedbacks d'humeur appris et radio — tout repart de zéro.
  Future<void> _clearHistory() async {
    await Future.wait([
      _history.clearAll(),
      _bot.tracker.clearAll(),
      _radio.tracker.clearAll(),
    ]);
    _radio.reset();
    if (!mounted) return;
    setState(() {
      _chat.clear();
      _activeMixId = null;
      _generated.clear();
      _recentMixes = [];
      _activeMood = null;
      _durationMinutes = 60;
    });
    final l10n = AppLocalizations.of(context);
    showGlassSnackBar(context, l10n.djAllCleared);
  }

  Future<void> _openMix(String mixId) async {
    final mix = await _history.loadMix(mixId);
    if (!mounted) return;
    if (mix == null) {
      showGlassSnackBar(context, AppLocalizations.of(context).djMoodEmpty);
      return;
    }
    await Navigator.of(context).push(
      SlidePageRoute(page: DjMixScreen(mix: mix)),
    );
  }

  /// Résout un vrai flux pour la tête de la playlist (2 à 2) — le reste est
  /// résolu à la volée par [audio_handler] (lazy ResolvingAudioSource).
  Future<List<MuzoItem>> _enrichForPlay(List<MuzoItem> songs) async {
    const headSize = 12;
    final target = songs.take(headSize).toList();
    final enriched = <MuzoItem>[];
    for (int i = 0; i < target.length; i += 2) {
      final end = i + 2 < target.length ? i + 2 : target.length;
      final chunk = target.sublist(i, end);
      final results = await Future.wait(chunk.map((s) async {
        if (s.videoId == null) return s;
        try {
          final url = await StreamExtractionService.getStreamUrl(
            s.videoId!,
            title: s.title,
            artist: s.displayArtist,
            durationSeconds: s.durationSeconds,
          );
          if (url != null && url.isNotEmpty) {
            return s.copyWith(
              audioUrl: url,
              metadata: {
                ...?s.metadata,
                'streamFreshTs': DateTime.now().millisecondsSinceEpoch,
              },
            );
          }
        } catch (_) {}
        return s;
      }));
      enriched.addAll(results);
    }
    return enriched;
  }

  String _moodName(AppLocalizations l10n, DjMood mood) {
    switch (mood) {
      case DjMood.energetic:
        return l10n.djMoodEnergy;
      case DjMood.calm:
        return l10n.djMoodCalm;
      case DjMood.sad:
        return l10n.djMoodSad;
      case DjMood.happy:
        return l10n.djMoodHappy;
      case DjMood.focus:
        return l10n.djMoodFocus;
      case DjMood.love:
        return l10n.djMoodLove;
      case DjMood.nostalgia:
        return l10n.djMoodNostalgia;
      case DjMood.sleep:
        return l10n.djMoodSleep;
    }
  }

  String _moodReply(AppLocalizations l10n, DjMood mood) {
    switch (mood) {
      case DjMood.energetic:
        return l10n.djReplyEnergy;
      case DjMood.calm:
        return l10n.djReplyCalm;
      case DjMood.sad:
        return l10n.djReplySad;
      case DjMood.happy:
        return l10n.djReplyHappy;
      case DjMood.focus:
        return l10n.djReplyFocus;
      case DjMood.love:
        return l10n.djReplyLove;
      case DjMood.nostalgia:
        return l10n.djReplyNostalgia;
      case DjMood.sleep:
        return l10n.djReplySleep;
    }
  }

  Future<void> _startFromSeed() async {
    final seed = widget.seed;
    if (seed == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final picks = await _engine.suggest(
        anchor: seed,
        seenKeys: <String>{},
        count: 10,
      );
      if (!mounted) return;
      final handler = ref.read(audioHandlerProvider);
      await handler.playAll(
        picks.isEmpty ? [seed] : [seed, ...picks.take(9)],
        startIndex: 0,
      );
    } catch (_) {
      if (mounted) showGlassSnackBar(context, l10n.djNoneLeft);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    ref.listen(currentMediaItemProvider, (prev, next) {
      _onMediaChanged(next.valueOrNull);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.graphic_eq,
                            color: Color(0xFF1DB954), size: 22),
                        const SizedBox(width: 8),
                        Text(l10n.tunefyDj,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (_historyLoaded &&
                      (_chat.isNotEmpty ||
                          _generated.isNotEmpty ||
                          _recentMixes.isNotEmpty ||
                          _radio.enabled))
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.white.withValues(alpha: 0.45),
                          size: 20),
                      tooltip: l10n.djClearAll,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _confirmClearHistory(l10n);
                      },
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _mainScroll,
                child: Column(
                  children: [
                    _buildChat(l10n),
                    const SizedBox(height: 4),
                    if (_generated.isNotEmpty) _buildMoodSongs(l10n),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat d'humeur avec le DJ ──────────────────────────────────────────────

  Widget _buildChat(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardTranslucent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1DB954),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.graphic_eq,
                      color: Colors.black, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.tunefyDj,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF1DB954)
                            .withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1DB954),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(l10n.djOnline,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              controller: _chatScroll,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _chat.length + (_typing ? 1 : 0),
              itemBuilder: (context, index) {
                if (_typing && index == _chat.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bubbleAvatar(bot: true),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF232323),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomRight: Radius.circular(18),
                                bottomLeft: Radius.circular(5),
                              ),
                              border:
                                  Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: SpotifySpinner(
                                      strokeWidth: 2,
                                      color: Color(0xFF1DB954)),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _typingLabel ?? '…',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return _bubble(_chat[index], l10n);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    cursorColor: const Color(0xFF1DB954),
                    decoration: InputDecoration(
                      hintText: l10n.djMoodPlaceholder,
                      hintStyle: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:
                            const BorderSide(color: Color(0xFF1DB954)),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMood(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: (_typing || _busy) ? null : _sendMood,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DB954),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(l10n.djClearAll,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(l10n.djClearAllConfirm,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.retry,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_clearHistory());
            },
            child: Text(l10n.djClearAll,
                style: const TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }

  Widget _bubble(DjChatMessage m, AppLocalizations l10n) {
    final fromUser = m.fromUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!fromUser) ...[
            _bubbleAvatar(bot: true),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.68),
                  decoration: BoxDecoration(
                    gradient: fromUser
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1DB954), Color(0xFF158d43)],
                          )
                        : null,
                    color: fromUser ? null : const Color(0xFF232323),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(fromUser ? 18 : 5),
                      bottomRight: Radius.circular(fromUser ? 5 : 18),
                    ),
                    border: Border.all(
                        color: fromUser
                            ? Colors.transparent
                            : Colors.white12),
                    boxShadow: [
                      if (fromUser)
                        BoxShadow(
                          color: const Color(0xFF1DB954)
                              .withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.text,
                          style: TextStyle(
                              color: fromUser
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 13.5,
                              height: 1.35)),
                      if (m.mixId != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            unawaited(_openMix(m.mixId!));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: fromUser
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : const Color(0xFF1DB954),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.queue_music,
                                    color: fromUser
                                        ? Colors.white
                                        : Colors.black,
                                    size: 15),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.djOpenMixPage,
                                  style: TextStyle(
                                      color: fromUser
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(_timeLabel(m.createdAt),
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          if (fromUser) ...[
            const SizedBox(width: 8),
            _bubbleAvatar(bot: false),
          ],
        ],
      ),
    );
  }

  Widget _bubbleAvatar({required bool bot}) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: bot
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1DB954), Color(0xFF158d43)],
              )
            : null,
        color: bot ? null : Colors.white.withValues(alpha: 0.08),
        border: Border.all(
            color: bot
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.25)),
      ),
      child: Icon(
        bot ? Icons.graphic_eq : Icons.person,
        size: 16,
        color: bot ? Colors.black : Colors.white70,
      ),
    );
  }

  static String _timeLabel(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  // ── Sélection générée pour l'humeur ───────────────────────────────────────

  Widget _buildMoodSongs(AppLocalizations l10n) {
    final preview = _generated.take(8).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: Color(0xFF1DB954), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l10n.djMoodSongs} · '
                    '${l10n.djMixTracks.replaceAll('{count}', '${_generated.length}')}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                if (_activeMixId != null)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      unawaited(_openMix(_activeMixId!));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l10n.djOpenMixPage,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < preview.length; i++)
            _songCard(i, preview[i]),
          if (_generated.length > preview.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: () {
                  if (_activeMixId == null) return;
                  HapticFeedback.selectionClick();
                  unawaited(_openMix(_activeMixId!));
                },
                child: Text(
                  l10n.djShowAllTracks.replaceAll(
                      '{count}', '${_generated.length}'),
                  style: const TextStyle(
                      color: Color(0xFF1DB954),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_recentMixes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                l10n.djRecentMixes,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recentMixes.length.clamp(0, 12),
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final mix = _recentMixes[i];
                  final cover = mix.tracks.isNotEmpty &&
                          mix.tracks.first.thumbnails.isNotEmpty
                      ? mix.tracks.first.thumbnails.last.url
                      : '';
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      unawaited(_openMix(mix.id));
                    },
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: cover.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: cover,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        _miniCoverIcon(),
                                  )
                                : _miniCoverIcon(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mix.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  l10n.djMixTracks.replaceAll(
                                      '{count}', '${mix.trackCount}'),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniCoverIcon() => Container(
        width: 40,
        height: 40,
        color: Colors.grey[850],
        child: const Icon(Icons.graphic_eq,
            color: Color(0xFF1DB954), size: 16),
      );

  Widget _songCard(int index, MuzoItem song) {
    final handler = ref.read(audioHandlerProvider);
    final img = song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: img,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(
            width: 44,
            height: 44,
            color: Colors.grey[850],
            child: const Icon(Icons.music_note,
                color: Colors.white38, size: 18),
          ),
        ),
      ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
      subtitle: Text(song.displayArtist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
      onTap: () {
        if (_typing || _busy) return;
        unawaited(handler.playAll(List.of(_generated), startIndex: index));
      },
    );
  }
}