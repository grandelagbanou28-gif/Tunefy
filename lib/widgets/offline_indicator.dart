import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:muzo/utils/net_guard.dart';

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        final results = snapshot.data;
        final isOffline =
            results != null &&
            results.isNotEmpty &&
            !results.contains(ConnectivityResult.mobile) &&
            !results.contains(ConnectivityResult.wifi) &&
            !results.contains(ConnectivityResult.ethernet) &&
            !results.contains(ConnectivityResult.vpn);

        if (!isOffline) return const SizedBox.shrink();

        // Un clic rétablit : Android refuse qu'une app allume le Wi-Fi toute
        // seule (restriction système ≥ 10), mais le panneau Wi-Fi s'ouvre en
        // surimpression — l'utilisateur n'a qu'à le basculer, la musique
        // continue derrière.
        return GestureDetector(
          onTap: openWifiPanel,
          child: Container(
            width: double.infinity,
            color: Colors.red.withValues(alpha: 0.9),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, color: Theme.of(context).colorScheme.onSurface, size: 14),
                const SizedBox(width: 8),
                Text(
                  'Offline — tap to reconnect',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.wifi_rounded, color: Theme.of(context).colorScheme.onSurface, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}
