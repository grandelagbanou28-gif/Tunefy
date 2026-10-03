import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/services/storage_service.dart';

/// Live connectivity, seeded with the current status so the first value is
/// available immediately (the raw `onConnectivityChanged` stream only fires
/// on *changes*, which would leave a cold start offline thinking it is
/// online until the network flaps).
final connectivityStreamProvider =
    StreamProvider<List<ConnectivityResult>>((ref) async* {
  yield await Connectivity().checkConnectivity();
  yield* Connectivity().onConnectivityChanged;
});

/// Ticks on every downloads-box write (new download, removal, manual offline
/// toggle) so [isOfflineProvider] rebuilds even though [StorageService]
/// itself is a plain object that never notifies.
final _downloadsBoxTickProvider = StreamProvider<int>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final controller = StreamController<int>.broadcast();
  var tick = 0;
  void emit() {
    if (!controller.isClosed) controller.add(++tick);
  }

  storage.downloadsListenable.addListener(emit);
  ref.onDispose(() {
    storage.downloadsListenable.removeListener(emit);
    controller.close();
  });
  controller.add(tick);
  return controller.stream;
});

/// True when the app must behave offline: either the user flipped the manual
/// "offline mode" switch, or the device really lost its network. Concerts,
/// streams and every other network surface key off this single flag.
final isOfflineProvider = Provider<bool>((ref) {
  // Subscribe to box writes: manual toggle + download add/remove.
  ref.watch(_downloadsBoxTickProvider);
  if (ref.watch(storageServiceProvider).offlineMode) return true;
  final results = ref.watch(connectivityStreamProvider).valueOrNull;
  if (results == null || results.isEmpty) return false;
  return !results.contains(ConnectivityResult.mobile) &&
      !results.contains(ConnectivityResult.wifi) &&
      !results.contains(ConnectivityResult.ethernet);
});
