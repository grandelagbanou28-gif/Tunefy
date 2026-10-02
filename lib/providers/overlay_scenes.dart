import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen surfaces that take over the phone while they are on top.
///
/// This replaces the "flag the screen sets on open and clears on dispose" style.
/// The reason is simple and was learned the hard way: a flag a screen must
/// remember to reset will, at least once, not get reset — a route popped out of
/// order, a rebuild during teardown, a `ref` read that throws once the widget is
/// gone. The result is an app that keeps playing audio with no way to bring the
/// controls back.
///
/// Deriving the state from the live route stack cannot drift: when a route is
/// popped, the observer drops it, whatever the screen did or forgot to do.
enum PlayerScene {
  /// Vertical clips feed — video only.
  clips,

  /// Full Now Playing screen.
  nowPlaying,
}

/// Marks a route as a player scene.
///
/// Explicit on purpose: matching on widget types breaks the moment a screen is
/// wrapped, subclassed or rebuilt with a different type.
@immutable
class SceneArg {
  final PlayerScene scene;
  const SceneArg(this.scene);

  @override
  bool operator ==(Object other) =>
      other is SceneArg && other.scene == scene;

  @override
  int get hashCode => scene.hashCode;
}

/// The player surfaces currently stacked, innermost last.
final overlayScenesProvider =
    NotifierProvider<OverlayScenesNotifier, List<PlayerScene>>(
  OverlayScenesNotifier.new,
);

class OverlayScenesNotifier extends Notifier<List<PlayerScene>> {
  @override
  List<PlayerScene> build() => const [];

  /// Re-entrant updates are collapsed: a push and a pop inside the same frame
  /// must leave a consistent list, not a stack of both.
  void sync(List<PlayerScene> next) {
    if (listEquals(state, next)) return;
    state = List<PlayerScene>.unmodifiable(next);
  }

  bool get hasClips => state.contains(PlayerScene.clips);
  bool get hasNowPlaying => state.contains(PlayerScene.nowPlaying);
}

/// Keeps [overlayScenesProvider] in step with the navigator. The only writer of
/// that state, so no screen has to be trusted to clean up after itself.
class PlayerSceneObserver extends NavigatorObserver {
  /// Provided once by the app shell: an observer cannot read providers itself
  /// and a `ref` captured from a disposed element is exactly the bug this class
  /// exists to remove.
  ProviderContainer? container;

  final List<PlayerScene> _scenes = <PlayerScene>[];

  List<PlayerScene> get scenes => List<PlayerScene>.unmodifiable(_scenes);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final scene = _sceneOf(route);
    if (scene != null) _scenes.add(scene);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final scene = _sceneOf(route);
    if (scene != null) _scenes.remove(scene);
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final scene = _sceneOf(oldRoute);
      if (scene != null) _scenes.remove(scene);
    }
    if (newRoute != null) {
      final scene = _sceneOf(newRoute);
      if (scene != null) _scenes.add(scene);
    }
    _publish();
  }

  PlayerScene? _sceneOf(Route<dynamic> route) {
    final arg = route.settings.arguments;
    return arg is SceneArg ? arg.scene : null;
  }

  void _publish() {
    container?.read(overlayScenesProvider.notifier).sync(_scenes);
  }
}

/// One instance for the app: there is exactly one navigator (`navigatorKey`), so
/// an observer per rebuild would just drop state on the floor.
final PlayerSceneObserver playerSceneObserver = PlayerSceneObserver();