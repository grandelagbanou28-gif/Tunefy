import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:muzo/services/lyrics_service.dart';
import 'package:muzo/services/lyrics_translation_service.dart';
import 'package:muzo/widgets/karaoke_view.dart';

class LyricsView extends ConsumerStatefulWidget {
  final Lyrics lyrics;
  final VoidCallback onClose;
  final Stream<Duration> positionStream;
  final Duration totalDuration;
  final bool isEmbedded;
  final bool scrollable;
  final Color? accentColor;

  /// Media id used to fetch the green translation lines. Null = no translation.
  final String? videoId;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.onClose,
    required this.positionStream,
    required this.totalDuration,
    this.isEmbedded = true,
    this.scrollable = true,
    this.accentColor,
    this.videoId,
  });

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  late LyricController _lyricController;
  StreamSubscription<Duration>? _positionSubscription;
  final ScrollController _plainScrollController = ScrollController();
  final List<GlobalKey> _plainLineKeys = [];
  int _plainActiveLine = -1;

  /// Signature of the controller content currently loaded (lyrics +
  /// translation): reloading only happens when it changes.
  String _loadedSig = '';

  bool get _isKaraoke => widget.lyrics.karaokeLines != null;
  bool get _isSynced => widget.lyrics.syncedLyrics.trim().isNotEmpty;
  bool get _hasPlainLyrics => widget.lyrics.plainLyrics.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();

    if (!_isKaraoke && _isSynced) {
      _lyricController = LyricController();
      _lyricController.loadLyric(widget.lyrics.syncedLyrics);
      _loadedSig = '${widget.lyrics.syncedLyrics.hashCode}|-1';
      _positionSubscription = widget.positionStream.listen((duration) {
        _lyricController.setProgress(duration);
      });
    }
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Song changed: reload the synced controller and reset plain-line state so
    // the newly fetched lyrics take effect immediately.
    final karaokeChanged =
        (_isKaraoke != (oldWidget.lyrics.karaokeLines != null));
    final syncedChanged = widget.lyrics.syncedLyrics !=
        oldWidget.lyrics.syncedLyrics;
    final plainChanged =
        widget.lyrics.plainLyrics != oldWidget.lyrics.plainLyrics;
    if (karaokeChanged || syncedChanged || plainChanged) {
      if (!_isKaraoke && _isSynced) {
        _positionSubscription?.cancel();
        _lyricController.dispose();
        _lyricController = LyricController();
        _lyricController.loadLyric(widget.lyrics.syncedLyrics);
        _loadedSig = '${widget.lyrics.syncedLyrics.hashCode}|-1';
        _positionSubscription = widget.positionStream.listen((duration) {
          _lyricController.setProgress(duration);
        });
      }
      _plainLineKeys.clear();
      _plainActiveLine = -1;
      if (_plainScrollController.hasClients) {
        _plainScrollController.jumpTo(0);
      }
    }
  }

  /// Builds a translation LRC (`[mm:ss.xx] text` per line) aligned on the
  /// same timestamps as the source, for the package's native translation
  /// rendering. Null when there is nothing to show.
  String? _translationLrc(List<TranslatedLyricLine>? tr) {
    if (tr == null || tr.isEmpty) return null;
    final timed = parseTimedLyrics(widget.lyrics, widget.totalDuration);
    if (timed.isEmpty) return null;
    final byIndex = <int, String>{for (final t in tr) t.index: t.text};
    final buf = StringBuffer();
    for (var i = 0; i < timed.length; i++) {
      final text = byIndex[i];
      if (text == null || text.trim().isEmpty) continue;
      final ms = timed[i].time.inMilliseconds;
      final mm = (ms ~/ 60000).toString().padLeft(2, '0');
      final ss = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
      final hh = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
      buf.writeln('[$mm:$ss.$hh] $text');
    }
    final out = buf.toString();
    return out.isEmpty ? null : out;
  }

  /// (Re)loads the synced controller with the current translation when it
  /// changed. Called from build: it only notifies the package's own
  /// controller, never this widget's setState, so it cannot loop.
  void _syncControllerWithTranslation(List<TranslatedLyricLine>? tr) {
    if (_isKaraoke || !_isSynced) return;
    final sig =
        '${widget.lyrics.syncedLyrics.hashCode}|${tr == null ? -1 : tr.length}';
    if (sig == _loadedSig) return;
    _loadedSig = sig;
    _positionSubscription?.cancel();
    _lyricController.dispose();
    _lyricController = LyricController();
    _lyricController.loadLyric(
      widget.lyrics.syncedLyrics,
      translationLyric: _translationLrc(tr),
    );
    _positionSubscription = widget.positionStream.listen((duration) {
      _lyricController.setProgress(duration);
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _plainScrollController.dispose();
    if (!_isKaraoke && _isSynced) {
      _lyricController.dispose();
    }
    super.dispose();
  }

  Widget _buildFallbackView(BuildContext context, String? fontFamily, {required bool isInstrumental}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isInstrumental ? Icons.music_note_rounded : Icons.text_snippet_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            isInstrumental ? "Instrumental" : "No lyrics available",
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: widget.isEmbedded ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlainLyricsView(
    BuildContext context,
    String? fontFamily,
    List<TranslatedLyricLine>? tr,
  ) {
    final List<String> rawLines = widget.lyrics.plainLyrics
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) {
      return _buildFallbackView(context, fontFamily, isInstrumental: false);
    }

    final double fontSize = widget.isEmbedded ? 18.0 : 22.0;

    final trByIndex = <int, String>{
      for (final t in (tr ?? const <TranslatedLyricLine>[])) t.index: t.text,
    };

    // Estimate timestamps: evenly spread the plain lines across the song
    // duration so we can highlight and auto-scroll the current line even
    // though the source has no timestamps (Spotify-style behaviour).
    final totalMs = widget.totalDuration.inMilliseconds > 0
        ? widget.totalDuration.inMilliseconds
        : 4 * 60 * 1000;
    Duration offsetAt(int i) =>
        Duration(milliseconds: (totalMs ~/ (rawLines.length + 1)) * (i + 1));

    if (_plainLineKeys.length != rawLines.length) {
      _plainLineKeys
        ..clear()
        ..addAll(List.generate(rawLines.length, (_) => GlobalKey()));
    }

    void scrollTo(int index) {
      if (index < 0 || index >= _plainLineKeys.length) return;
      final ctx = _plainLineKeys[index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    }

    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (rect) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.08, 0.92, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _plainScrollController,
            physics: widget.scrollable
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: widget.isEmbedded ? 24 : 40,
            ),
            child: StreamBuilder<Duration>(
              stream: widget.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                int active = 0;
                for (var i = 0; i < rawLines.length; i++) {
                  if (pos >= offsetAt(i)) {
                    active = i;
                  } else {
                    break;
                  }
                }
                if (active != _plainActiveLine) {
                  _plainActiveLine = active;
                  if (widget.scrollable) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => scrollTo(active));
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: widget.isEmbedded ? 12 : 24),
                    for (var i = 0; i < rawLines.length; i++)
                      Padding(
                        key: _plainLineKeys[i],
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            fontFamily: fontFamily,
                            fontSize: i == active ? fontSize + 2 : fontSize,
                            fontWeight: FontWeight.w700,
                            color: i == active
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                            height: 1.4,
                          ),
                          child: _plainLine(
                            context,
                            rawLines[i],
                            i == active
                                ? trByIndex[i]?.trim().isNotEmpty == true
                                    ? trByIndex[i]
                                    : null
                                : null,
                          ),
                        ),
                      ),
                    SizedBox(height: widget.isEmbedded ? 24 : 48),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// A plain line, with the green translation underneath when this is the
  /// active line and a translation exists for it.
  Widget _plainLine(BuildContext context, String text, String? translation) {
    if (translation == null) {
      return Text(
        text,
        textAlign: TextAlign.center,
      );
    }
    return Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          translation,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.isEmbedded ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1DDA63),
            height: 1.2,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;

    // Green translation lines for the current song (null = none available).
    // Watching here also rebuilds this view the moment they arrive.
    final List<TranslatedLyricLine>? tr = widget.videoId == null
        ? null
        : ref.watch(translatedLyricsProvider(widget.videoId!)).valueOrNull;
    _syncControllerWithTranslation(tr);

    final customLyricStyle = LyricStyles.default1.copyWith(
      disableTouchEvent: !widget.scrollable,
      activeHighlightColor: Theme.of(context).colorScheme.onSurface,
      activeStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: widget.isEmbedded ? 22 : 26,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.3,
      ),
      textStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: widget.isEmbedded ? 17 : 20,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
        height: 1.3,
      ),
      translationStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: widget.isEmbedded ? 14 : 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );

    return Column(
      children: [
        if (widget.isEmbedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Lyrics",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

        Expanded(
          child: _isKaraoke
              ? KaraokeView(
                  lines: widget.lyrics.karaokeLines!,
                  positionStream: widget.positionStream,
                  isEmbedded: widget.isEmbedded,
                  scrollable: widget.scrollable,
                  translatedLines: tr,
                )
              : (widget.lyrics.instrumental || !_hasPlainLyrics
                  ? _buildFallbackView(context, fontFamily, isInstrumental: widget.lyrics.instrumental)
                  : (!_isSynced
                      ? _buildPlainLyricsView(context, fontFamily, tr)
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 14.0),
                          child: LyricView(
                            controller: _lyricController,
                            style: customLyricStyle,
                          ),
                        ))),
        ),
      ],
    );
  }
}
