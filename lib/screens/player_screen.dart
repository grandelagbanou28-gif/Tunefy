import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player/hivefy_full_player.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, this.onClose});

  /// Closes the player. `Navigator.pop` only works when the player was pushed
  /// as a route; inside a bottom sheet the sheet has to be dismissed
  /// explicitly, otherwise the swipe-down does nothing and the app is stuck.
  final VoidCallback? onClose;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: const Key('player_dismiss'),
      direction: DismissDirection.down,
      onDismissed: (_) => _close(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: HivefyFullPlayer(onClose: _close),
      ),
    );
  }
}

class ExpandedPlayer extends PlayerScreen {
  const ExpandedPlayer({super.key, super.onClose});
}
