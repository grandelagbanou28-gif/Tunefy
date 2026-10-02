import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/providers/overlay_scenes.dart';

void main() {
  late ProviderContainer container;
  late PlayerSceneObserver observer;

  setUp(() {
    container = ProviderContainer();
    observer = PlayerSceneObserver()..container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('root')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Route<void> _sceneRoute(PlayerScene scene) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(arguments: SceneArg(scene)),
        builder: (_) => const Scaffold(body: Text('scene')),
      );

  testWidgets('a plain page is not a player scene', (tester) async {
    await pumpApp(tester);
    expect(container.read(overlayScenesProvider), isEmpty);
  });

  testWidgets('pushing a tagged route publishes the scene', (tester) async {
    await pumpApp(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(_sceneRoute(PlayerScene.clips));
    await tester.pumpAndSettle();

    expect(container.read(overlayScenesProvider), contains(PlayerScene.clips));
    expect(container.read(overlayScenesProvider.notifier).hasClips, isTrue);
  });

  testWidgets('popping it clears the scene without any screen help',
      (tester) async {
    await pumpApp(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(_sceneRoute(PlayerScene.clips));
    await tester.pumpAndSettle();
    expect(container.read(overlayScenesProvider), isNotEmpty);

    // The point of the whole refactor: the state follows the navigator, so the
    // scene disappears without the screen remembering to reset anything.
    nav.pop();
    await tester.pumpAndSettle();
    expect(container.read(overlayScenesProvider), isEmpty);
    expect(container.read(overlayScenesProvider.notifier).hasClips, isFalse);
  });

  testWidgets('two stacked scenes both disappear, inner first',
      (tester) async {
    await pumpApp(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(_sceneRoute(PlayerScene.clips));
    await tester.pumpAndSettle();
    nav.push(_sceneRoute(PlayerScene.nowPlaying));
    await tester.pumpAndSettle();

    final scenes = container.read(overlayScenesProvider);
    expect(scenes, containsAll(<PlayerScene>[
      PlayerScene.clips,
      PlayerScene.nowPlaying,
    ]));

    nav.pop();
    await tester.pumpAndSettle();
    expect(container.read(overlayScenesProvider), [PlayerScene.clips]);

    nav.pop();
    await tester.pumpAndSettle();
    expect(container.read(overlayScenesProvider), isEmpty);
  });

  test('the notifier collapses a redundant publish', () {
    final notifier = container.read(overlayScenesProvider.notifier);
    notifier.sync(const <PlayerScene>[PlayerScene.clips]);
    final first = container.read(overlayScenesProvider);
    notifier.sync(const <PlayerScene>[PlayerScene.clips]);
    final second = container.read(overlayScenesProvider);
    // Same list instance: no rebuild is triggered for a no-op update.
    expect(identical(first, second), isTrue);
  });
}