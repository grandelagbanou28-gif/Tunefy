import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/category_providers.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/page_routes.dart';

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return <ConnectivityResult>[ConnectivityResult.none];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return Stream<List<ConnectivityResult>>.value(
      <ConnectivityResult>[ConnectivityResult.none],
    );
  }
}

class _FakeMuzoApiService extends MuzoApiService {
  _FakeMuzoApiService() : super(StorageService());

  @override
  Future<MuzoSearchResponse> search(
    String query, {
    String filter = 'songs',
    String? continuationToken,
    bool shortOnly = false,
  }) async {
    return MuzoSearchResponse(results: <MuzoItem>[]);
  }
}

MuzoItem _fakeSong(String title, String videoId) {
  return MuzoItem(
    title: title,
    thumbnails: <MuzoThumbnail>[],
    resultType: 'song',
    isExplicit: false,
    videoId: videoId,
    artists: <MuzoArtist>[MuzoArtist(name: 'Jul', id: 'jul')],
    duration: '3:00',
    durationSeconds: 180,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('artist_page_jul_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    await Hive.openBox('downloads');
    await Hive.openBox('stream_url_cache_v3');
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
  });

  tearDownAll(() async {
    // The page writes `lastVisitedArtist` into the settings box from a
    // post-frame callback; testWidgets runs in FakeAsync, so that write's
    // completion is trapped in the fake zone and close() would never
    // resolve. Guard it — the process exits right after anyway.
    try {
      await Hive.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // TimeoutException: pending fake-async IO, nothing to salvage in a test.
    }
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        switch (call.method) {
          case 'init':
            return null;
          case 'disposePlayer':
          case 'disposeAllPlayers':
            return <dynamic, dynamic>{};
          default:
            return null;
        }
      },
    );

    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('artist page for Jul opens from Home and renders',
      (WidgetTester tester) async {
    final fakeSongs = <MuzoItem>[
      _fakeSong('Jul Music Test One', 'jul_v1'),
      _fakeSong('Jul Music Test Two', 'jul_v2'),
      _fakeSong('Jul Music Test Three', 'jul_v3'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artistSongsProvider('Jul').overrideWith((ref) async => fakeSongs),
          categoryAlbumsProvider('Jul')
              .overrideWith((ref) async => <CategoryAlbum>[]),
          playerUiStateProvider.overrideWith(
            (ref) => Stream<PlayerUiSnapshot>.value(const PlayerUiSnapshot()),
          ),
          shuffleModeNotifierProvider
              .overrideWithValue(ValueNotifier<bool>(false)),
          muzoApiServiceProvider.overrideWithValue(_FakeMuzoApiService()),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: const <Locale>[Locale('fr'), Locale('en')],
          locale: const Locale('fr'),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        SlidePageRoute(
                          page: const ArtistPageScreen(artistName: 'Jul'),
                        ),
                      );
                    },
                    child: const Text('Open Jul'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Open Jul'), findsOneWidget);

    await tester.tap(find.text('Open Jul'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ArtistPageScreen), findsOneWidget);
    expect(find.text('Jul'), findsWidgets);
    expect(find.text('Populaires'), findsOneWidget);
    expect(find.textContaining('3 chansons'), findsWidgets);
    expect(find.text('Morceaux populaires'), findsOneWidget);
    expect(find.text('Suivre'), findsNothing);
    expect(find.text('Jul Music Test One'), findsOneWidget);

    // Rows below the fold need a scroll now that the list carries a title.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pump();
    await tester.pump();
    expect(find.text('Jul Music Test Two'), findsOneWidget);

    // Third chip is below the fold — scroll the artist list to reveal it.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pump();
    await tester.pump();
    expect(find.text('Jul Music Test Three'), findsOneWidget);

    // Artist name on a song row is a no-op when it matches the page artist.
    await tester.tap(find.text('Morceau . Jul').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ArtistPageScreen), findsOneWidget);

    // Back returns to Home.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(ArtistPageScreen), findsNothing);
    expect(find.text('Open Jul'), findsOneWidget);

    // Flush enrichment microtasks (offline connectivity short-circuits cascade).
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
  });
}
