import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/blend_provider.dart';
import 'package:muzo/widgets/app_alert_dialog.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Picks one of my Blends to append [song] to. Mirrors
/// [PlaylistSelectionDialog] so the two flows feel identical.
class BlendSelectionDialog extends ConsumerWidget {
  final MuzoItem song;

  const BlendSelectionDialog({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final blendsAsync = ref.watch(myBlendsProvider);

    return AppAlertDialog(
      title: l10n.addToBlend,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
        ),
      ],
      content: SizedBox(
        width: double.maxFinite,
        child: blendsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: SpotifySpinner(
                    strokeWidth: 2, color: Color(0xFF1DDA63)),
              ),
            ),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              l10n.blendEmpty,
              style: const TextStyle(color: CupertinoColors.systemGrey),
            ),
          ),
          data: (blends) {
            if (blends.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.blendEmpty,
                  style: const TextStyle(color: CupertinoColors.systemGrey),
                ),
              );
            }
            return Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: blends.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final b = blends[i];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DDA63)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.group_outlined,
                              color: spotifyWhite, size: 22),
                        ),
                        title: Text(
                          b.name,
                          style: const TextStyle(
                            color: spotifyWhite,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${b.code} · ${b.tracks.length}',
                          style: const TextStyle(color: spotifyLightGrey),
                        ),
                        onTap: () async {
                          final ok = await addSongToBlend(
                              ref, b.code, song);
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          showGlassSnackBar(
                            context,
                            ok ? l10n.blendAdded : l10n.blendNotFound,
                            error: !ok,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
