import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/dj_chat_models.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/download_provider.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/song_options_menu.dart';

/// Full play page for a generated DJ mix (can hold 50–60 tracks).
/// Play All / Shuffle / tap a row → `playAll` from that index.
class DjMixScreen extends ConsumerStatefulWidget {
  const DjMixScreen({super.key, required this.mix});

  final DjGeneratedMix mix;

  @override
  ConsumerState<DjMixScreen> createState() => _DjMixScreenState();
}

class _DjMixScreenState extends ConsumerState<DjMixScreen> {
  bool _playing = false;
  bool _downloadingMix = false;

  List<MuzoItem> get _tracks => widget.mix.tracks;

  Future<void> _playAll({int startIndex = 0, bool shuffle = false}) async {
    if (_tracks.isEmpty || _playing) return;
    setState(() => _playing = true);
    try {
      final handler = ref.read(audioHandlerProvider);
      var list = List<MuzoItem>.of(_tracks);
      if (shuffle) list = List<MuzoItem>.of(list)..shuffle();
      await handler.playAll(list, startIndex: shuffle ? 0 : startIndex);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _downloadTrack(MuzoItem song) async {
    final l10n = AppLocalizations.of(context);
    HapticFeedback.selectionClick();
    final ok = await ref.read(downloadProvider.notifier).startDownload(song);
    if (!mounted) return;
    showGlassSnackBar(
      context,
      ok ? l10n.djDownloaded : l10n.djDownloadFailed,
      error: !ok,
    );
  }

  /// Downloads every track of the mix that isn't already on disk,
  /// sequentially (bounded concurrency keeps backends happy).
  Future<void> _downloadAll() async {
    if (_downloadingMix) return;
    final l10n = AppLocalizations.of(context);
    final storage = ref.read(storageServiceProvider);
    final pending = _tracks
        .where((t) => t.videoId != null && !storage.isDownloaded(t.videoId!))
        .toList();
    if (pending.isEmpty) {
      showGlassSnackBar(context, l10n.djAlreadyDownloaded);
      return;
    }
    setState(() => _downloadingMix = true);
    try {
      var done = 0;
      for (final t in pending) {
        final ok = await ref.read(downloadProvider.notifier).startDownload(t);
        if (ok) done++;
        if (!mounted) return;
      }
      if (!mounted) return;
      showGlassSnackBar(
        context,
        l10n.djDownloadAllDone
            .replaceAll('{done}', '$done')
            .replaceAll('{total}', '${pending.length}'),
        error: done < pending.length,
      );
    } finally {
      if (mounted) setState(() => _downloadingMix = false);
    }
  }

  String _formatDate(BuildContext context, DateTime dt) {
    final l10n = AppLocalizations.of(context);
    return '${dt.day}/${dt.month}/${dt.year} · '
        '${l10n.djMixTracks.replaceAll('{count}', '${_tracks.length}')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mix = widget.mix;
    final cover = _tracks.isNotEmpty && _tracks.first.thumbnails.isNotEmpty
        ? _tracks.first.thumbnails.last.url
        : '';

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
                    child: Text(
                      mix.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: cover.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: cover,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        _coverPlaceholder(),
                                  )
                                : _coverPlaceholder(),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mix.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(context, mix.createdAt),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12),
                                ),
                                if (mix.durationMinutes > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.djMixDuration.replaceAll(
                                        '{minutes}', '${mix.durationMinutes}'),
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ActionPill(
                              icon: Icons.play_arrow_rounded,
                              label: l10n.playAll,
                              filled: true,
                              onTap: _playing
                                  ? null
                                  : () => unawaitedPlay(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ActionPill(
                              icon: Icons.shuffle_rounded,
                              label: l10n.djShuffle,
                              filled: false,
                              onTap: _playing
                                  ? null
                                  : () => _playAll(shuffle: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ActionPill(
                              icon: Icons.download_rounded,
                              label: l10n.djDownloadAll,
                              filled: false,
                              onTap: _downloadingMix
                                  ? null
                                  : () => unawaited(_downloadAll()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_tracks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(l10n.djMoodEmpty,
                            style: const TextStyle(color: Colors.white54)),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _TrackRow(
                          index: i,
                          song: _tracks[i],
                          onTap: () => _playAll(startIndex: i),
                          onDownload: () =>
                              unawaited(_downloadTrack(_tracks[i])),
                          onOptions: () =>
                              SongOptionsMenu.show(ref, _tracks[i]),
                        ),
                        childCount: _tracks.length,
                      ),
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> unawaitedPlay() => _playAll();

  Widget _coverPlaceholder() => Container(
        width: 96,
        height: 96,
        color: Colors.grey[850],
        child: const Icon(Icons.graphic_eq, color: Color(0xFF1DB954), size: 36),
      );
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF1DB954) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: filled
                ? const Color(0xFF1DB954)
                : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: filled ? Colors.black : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: filled ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.song,
    required this.onTap,
    required this.onDownload,
    required this.onOptions,
  });

  final int index;
  final MuzoItem song;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final img = song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: img.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: img,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _ph(),
                    )
                  : _ph(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  Text(song.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded,
                  color: Colors.white38, size: 18),
              onPressed: onDownload,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
              onPressed: onOptions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ph() => Container(
        width: 44,
        height: 44,
        color: Colors.grey[850],
        child: const Icon(Icons.music_note, color: Colors.white38, size: 18),
      );
}
