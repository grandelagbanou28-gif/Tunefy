import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/blend.dart';
import 'package:muzo/providers/blend_provider.dart';
import 'package:muzo/screens/blend_detail_screen.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// My shared Blend playlists: created or joined on this device, synced
/// through Supabase. Anyone holding the invite code can read and contribute.
class BlendListScreen extends ConsumerWidget {
  const BlendListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final blendsAsync = ref.watch(myBlendsProvider);

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 16, 4),
                child: Row(
                  children: [
                    const SpotifyBackButton(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.blendTitle,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: spotifyWhite,
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _showJoinDialog(context, ref),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.group_add_outlined,
                            color: spotifyWhite, size: 24),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _showCreateDialog(context, ref),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.add, color: spotifyWhite, size: 26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            blendsAsync.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: SpotifySpinner(
                        strokeWidth: 2.5, color: Color(0xFF1DDA63)),
                  ),
                ),
              ),
              error: (_, __) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    l10n.blendEmpty,
                    style: const TextStyle(color: spotifyLightGrey),
                  ),
                ),
              ),
              data: (blends) {
                if (blends.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.blendEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: spotifyLightGrey, fontSize: 15),
                        ),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
                  sliver: SliverList.separated(
                    itemCount: blends.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) =>
                        _BlendTile(blend: blends[i]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.blendCreate,
                style: const TextStyle(
                  color: spotifyWhite,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: spotifyWhite),
                decoration: InputDecoration(
                  hintText: l10n.blendNameLabel,
                  hintStyle: const TextStyle(color: spotifyLightGrey),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: spotifyLightGrey),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Color(0xFF1DDA63)),
                  ),
                ),
                onSubmitted: (_) =>
                    Navigator.of(ctx).pop(controller.text.trim()),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      final created =
                          await createBlend(ref, controller.text.trim());
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        SlidePageRoute(
                          page: BlendDetailScreen(code: created.code),
                        ),
                      );
                    },
                    child: Text(
                      l10n.createBtn,
                      style: const TextStyle(
                        color: Color(0xFF1DDA63),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (name == null) return;
  }

  Future<void> _showJoinDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          backgroundColor: const Color(0xFF282828),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.blendJoin,
                  style: const TextStyle(
                    color: spotifyWhite,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: spotifyWhite,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.blendCodeLabel,
                    hintStyle: const TextStyle(color: spotifyLightGrey),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: spotifyLightGrey),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Color(0xFF1DDA63)),
                    ),
                  ),
                  onSubmitted: (_) async {
                    if (busy) return;
                    setState(() => busy = true);
                    final joined =
                        await joinBlend(ref, controller.text).catchError(
                      (_) => null,
                    );
                    if (!ctx.mounted) return;
                    if (joined == null) {
                      setState(() => busy = false);
                      showGlassSnackBar(ctx, l10n.blendNotFound, error: true);
                      return;
                    }
                    Navigator.of(ctx).pop();
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      SlidePageRoute(
                        page: BlendDetailScreen(code: joined.code),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              final joined = await joinBlend(
                                      ref, controller.text)
                                  .catchError((_) => null);
                              if (!ctx.mounted) return;
                              if (joined == null) {
                                setState(() => busy = false);
                                showGlassSnackBar(
                                    ctx, l10n.blendNotFound,
                                    error: true);
                                return;
                              }
                              Navigator.of(ctx).pop();
                              if (!context.mounted) return;
                              Navigator.of(context).push(
                                SlidePageRoute(
                                  page: BlendDetailScreen(code: joined.code),
                                ),
                              );
                            },
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: SpotifySpinner(
                                  strokeWidth: 2,
                                  color: Color(0xFF1DDA63)),
                            )
                          : Text(
                              l10n.blendJoinBtn,
                              style: const TextStyle(
                                color: Color(0xFF1DDA63),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }
}

class _BlendTile extends StatelessWidget {
  const _BlendTile({required this.blend});

  final Blend blend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cover = blend.tracks.isNotEmpty &&
            blend.tracks.first.song.thumbnails.isNotEmpty
        ? blend.tracks.first.song.thumbnails.last.url
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          SlidePageRoute(
            page: BlendDetailScreen(code: blend.code),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1DDA63).withValues(alpha: 0.30),
              Colors.black.withValues(alpha: 0.35),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF1DDA63).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: cover != null
                    ? BrandBadged(
                        imageUrl: cover,
                        badgeSize: 14,
                        inset: 4,
                        child: Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _tileIcon(),
                        ),
                      )
                    : _tileIcon(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    blend.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: spotifyWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.blendStats(
                        '${blend.members.length}', '${blend.tracks.length}'),
                    style: TextStyle(
                      color: spotifyLightGrey.withValues(alpha: 0.9),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    blend.code,
                    style: const TextStyle(
                      color: Color(0xFF1DDA63),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: spotifyLightGrey),
          ],
        ),
      ),
    );
  }

  Widget _tileIcon() {
    return Container(
      color: const Color(0xFF1DDA63).withValues(alpha: 0.25),
      child: const Center(
        child: Icon(Icons.group_outlined, color: spotifyWhite, size: 28),
      ),
    );
  }
}
