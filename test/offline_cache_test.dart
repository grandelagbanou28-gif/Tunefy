import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  _FakeConnectivityPlatform(this.result);

  List<ConnectivityResult> result;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => result;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream<List<ConnectivityResult>>.value(result);
}

MuzoItem _song(String title) => MuzoItem(
      title: title,
      thumbnails: const <MuzoThumbnail>[],
      resultType: 'song',
      isExplicit: false,
      videoId: 'id_$title',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('offline_cache_test');
    Hive.init(dir.path);
    await Hive.openBox('downloads');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    ContentCacheService.resetOfflineMemo();
    await Hive.box('downloads').delete('offlineMode');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  test('online: shelfCached fetches, returns fresh content and caches it',
      () async {
    ConnectivityPlatform.instance =
        _FakeConnectivityPlatform(const <ConnectivityResult>[ConnectivityResult.wifi]);
    ContentCacheService.resetOfflineMemo();
    expect(await ContentCacheService.isOffline(), isFalse);

    var fetched = 0;
    final out = await ContentCacheService.shelfCached('t|online', () async {
      fetched++;
      return <MuzoItem>[_song('Fresh')];
    });

    expect(fetched, 1);
    expect(out.single.title, 'Fresh');
    // The write is fire-and-forget: give it a beat before the next test reads.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      await ContentCacheService.instance.readStale('t|online'),
      isNotNull,
    );
  });

  test('offline: shelfCached replays the last snapshot and never fetches',
      () async {
    await ContentCacheService.instance.write('t|offline', <MuzoItem>[_song('Seed')]);

    ConnectivityPlatform.instance =
        _FakeConnectivityPlatform(const <ConnectivityResult>[ConnectivityResult.none]);
    ContentCacheService.resetOfflineMemo();
    expect(await ContentCacheService.isOffline(), isTrue);

    var fetched = 0;
    final out = await ContentCacheService.shelfCached('t|offline', () async {
      fetched++;
      return <MuzoItem>[_song('Fresh')];
    });

    expect(fetched, 0, reason: 'offline must not touch the network');
    expect(out.single.title, 'Seed');
  });

  test('offline without any snapshot returns an empty list, never throws',
      () async {
    ConnectivityPlatform.instance =
        _FakeConnectivityPlatform(const <ConnectivityResult>[ConnectivityResult.none]);
    ContentCacheService.resetOfflineMemo();

    var fetched = 0;
    final out = await ContentCacheService.shelfCached('t|missing', () async {
      fetched++;
      return <MuzoItem>[_song('Fresh')];
    });

    expect(fetched, 0);
    expect(out, isEmpty);
  });

  test('manual offline switch wins over an available network', () async {
    ConnectivityPlatform.instance =
        _FakeConnectivityPlatform(const <ConnectivityResult>[ConnectivityResult.wifi]);
    ContentCacheService.resetOfflineMemo();
    expect(await ContentCacheService.isOffline(), isFalse);

    await Hive.box('downloads').put('offlineMode', true);
    ContentCacheService.resetOfflineMemo();
    expect(await ContentCacheService.isOffline(), isTrue);

    await Hive.box('downloads').put('offlineMode', false);
    ContentCacheService.resetOfflineMemo();
    expect(await ContentCacheService.isOffline(), isFalse);
  });
}
