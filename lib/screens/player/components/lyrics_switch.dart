import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/screens/lyrics_screen.dart';
import 'package:muzo/l10n/app_localizations.dart';

class LyricsSwitch extends ConsumerWidget {
  const LyricsSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextButton.icon(
              onPressed: () {
                final mediaItem = ref.read(currentMediaItemProvider).value;
                if (mediaItem != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LyricsScreen(
                        title: mediaItem.title,
                        artist: mediaItem.artist ?? '',
                        thumbnailUrl: mediaItem.artUri?.toString(),
                        durationSeconds: mediaItem.duration?.inSeconds ?? 0,
                        videoId: mediaItem.id,
                      ),
                    ),
                  );
                }
              },
              icon: Icon(
                FluentIcons.text_quote_20_regular,
                color: Theme.of(context).colorScheme.onSurface,
                size: 16,
              ),
              label: Text(
                AppLocalizations.of(context).lyrics,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
