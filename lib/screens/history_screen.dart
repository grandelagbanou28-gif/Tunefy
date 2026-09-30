import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/result_tile.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/app_alert_dialog.dart';
import 'package:muzo/widgets/global_background.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final l10n = AppLocalizations.of(context);

    return GlobalBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              floating: true,
              pinned: false,
              title: Text(
                'History',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
            ),

            // Header / Clear Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      'Recently Played',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        showAppAlertDialog(
                          context: context,
                          title: l10n.clearHistory,
                          content: Text(
                            'Are you sure you want to clear your listening history?',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                storage.clearHistory();
                                showGlassSnackBar(context, 'History cleared');
                              },
                              child: const Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                      icon: const Icon(
                        FluentIcons.delete_24_regular,
                        size: 16,
                        color: Colors.grey,
                      ),
                      label: const Text(
                        'Clear',
                        style: TextStyle(color: Colors.grey),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            ValueListenableBuilder<List<MuzoItem>>(
              valueListenable: storage.historyListenable,
              builder: (context, history, _) {
                if (history.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No history yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = history[index];
                    return ResultTile(
                      result: item,
                      fromHistory: true,
                      trailing: item.addedAt != null
                          ? _HistoryTimestamp(timestamp: item.addedAt!)
                          : null,
                    );
                  }, childCount: history.length),
                );
              },
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 160)),
          ],
        ),
      ),
    ),);
  }
}

class _HistoryTimestamp extends StatelessWidget {
  final String timestamp;
  const _HistoryTimestamp({required this.timestamp});

  String _format() {
    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final text = _format();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
