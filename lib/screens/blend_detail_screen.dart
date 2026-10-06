import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/blend.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/blend_provider.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/release_playback.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// One shared Blend: merged tracks with "added by" credits, add/remove,
/// play-all and invite-code sharing.
class BlendDetailScreen extends ConsumerStatefulWidget {
  const BlendDetailScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<BlendDetailScreen> createState() => _BlendDetailScreenState();
}

class _BlendDetailScreenState extends ConsumerState<BlendDetailScreen> {
  bool _adding = false;
  final _searchController = TextEditingController();
  List<MuzoItem> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ref
          .read(muzoApiServiceProvider)
          .search(q, filter: 'songs')
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _results =
          res.results.where((r) => r.videoId != null).take(20).toList());
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(blendDetailProvider(widget.code));

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: detailAsync.when(
          loading: () => const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child:
                  SpotifySpinner(strokeWidth: 2.5, color: Color(0xFF1DDA63)),
            ),
          ),
          error: (_, __) => _errorState(l10n),
          data: (blend) {
            if (blend == null) return _errorState(l10n);
            return _body(context, ref, l10n, blend);
          },
        ),
      ),
    );
  }

  Widget _errorState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpotifyBackButton(),
            const SizedBox(height: 16),
            Text(
              l10n.blendNotFound,
              textAlign: TextAlign.center,
              style: const TextStyle(color: spotifyWhite, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
      BuildContext context, WidgetRef ref, AppLocalizations l10n, Blend blend) {
    final myUid = ref.read(storageServiceProvider).supabase?.uid ?? '';
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 16, 4),
            child: Row(
              children: [
                const SpotifyBackButton(),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        blend.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: spotifyWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.blendStats('${blend.members.length}',
                            '${blend.tracks.length}'),
                        style: TextStyle(
                          color: spotifyLightGrey.withValues(alpha: 0.9),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Share.share(
                        l10n.blendShareText(blend.name, blend.code));
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.share_outlined,
                        color: spotifyWhite, size: 24),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await leaveBlend(ref, blend.code);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      l10n.blendLeave,
                      style: const TextStyle(
                        color: spotifyLightGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Members row.
        if (blend.members.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: blend.members.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final m = blend.members[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: spotifyWhite.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_rounded,
                            color: Color(0xFF1DDA63), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          m.name.isEmpty ? '?' : m.name,
                          style: const TextStyle(
                            color: spotifyWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        // Play bar.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: blend.tracks.isEmpty
                      ? null
                      : () => playReleaseTracks(
                          context, ref, blend.songs),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DDA63),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: spotifyBlack, size: 30),
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () =>
                      setState(() => _adding = !_adding),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: spotifyWhite.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      l10n.blendAddSongs,
                      style: const TextStyle(
                        color: spotifyWhite,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Add-song search.
        if (_adding)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: spotifyWhite),
                    decoration: InputDecoration(
                      hintText: l10n.blendSearchHint,
                      hintStyle:
                          const TextStyle(color: spotifyLightGrey),
                      prefixIcon: const Icon(Icons.search,
                          color: spotifyLightGrey),
                      filled: true,
                      fillColor:
                          spotifyWhite.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _search,
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: SpotifySpinner(
                            strokeWidth: 2, color: Color(0xFF1DDA63)),
                      ),
                    ),
                  for (final r in _results)
                    _SearchRow(
                      item: r,
                      onAdd: () async {
                        final ok =
                            await addSongToBlend(ref, blend.code, r);
                        if (!context.mounted) return;
                        showGlassSnackBar(
                          context,
                          ok ? l10n.blendAdded : l10n.blendNotFound,
                          error: !ok,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        // Tracks.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
          sliver: SliverList.separated(
            itemCount: blend.tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (context, i) {
              final t = blend.tracks[i];
              final mine = myUid.isNotEmpty && t.addedByUid == myUid;
              return _BlendTrackRow(
                track: t,
                l10n: l10n,
                mine: mine,
                onTap: () => playReleaseTracks(
                  context,
                  ref,
                  blend.songs,
                  startIndex: i,
                  openPlayer: false,
                ),
                onDelete: mine
                    ? () => removeMySongFromBlend(
                        ref, blend.code, t.song.videoId ?? '')
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.item, required this.onAdd});

  final MuzoItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final img = item.thumbnails.isNotEmpty
        ? item.thumbnails.last.url
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 44,
              child: BrandBadged(
                imageUrl: img,
                badgeSize: 13,
                inset: 3,
                child: img.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: img,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: spotifyDarkGrey,
                          child: const Icon(Icons.music_note,
                              color: spotifyLightGrey, size: 18),
                        ),
                      )
                    : Container(
                        color: spotifyDarkGrey,
                        child: const Icon(Icons.music_note,
                            color: spotifyLightGrey, size: 18),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  item.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: spotifyLightGrey.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: Color(0xFF1DDA63)),
            onPressed: () {
              HapticFeedback.selectionClick();
              onAdd();
            },
          ),
        ],
      ),
    );
  }
}

class _BlendTrackRow extends StatelessWidget {
  const _BlendTrackRow({
    required this.track,
    required this.l10n,
    required this.mine,
    required this.onTap,
    this.onDelete,
  });

  final BlendTrack track;
  final AppLocalizations l10n;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final song = track.song;
    final img =
        song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 47,
                height: 47,
                child: BrandBadged(
                  imageUrl: img,
                  badgeSize: 13,
                  inset: 3,
                  child: img.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: spotifyDarkGrey,
                            child: const Icon(Icons.music_note,
                                color: spotifyLightGrey, size: 20),
                          ),
                        )
                      : Container(
                          color: spotifyDarkGrey,
                          child: const Icon(Icons.music_note,
                              color: spotifyLightGrey, size: 20),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.displayArtist} · ${l10n.blendAddedBy(track.addedByName.isEmpty ? '?' : track.addedByName)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (mine && onDelete != null)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: spotifyLightGrey, size: 22),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }
}
