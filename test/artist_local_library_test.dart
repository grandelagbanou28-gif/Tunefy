import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('artist_local_lib_test');
    Hive.init(dir.path);
    await Hive.openBox('downloads');
  });

  tearDown(() async {
    await Hive.box('downloads').clear();
  });

  test('localLibraryForArtist pulls the artist out of the downloads box',
      () async {
    await Hive.box('downloads').put('list', <Map<String, dynamic>>[
      {
        'videoId': 'jul_dl_1',
        'path': '/tmp/jul_dl_1.m4a',
        'result': <String, dynamic>{
          'videoId': 'jul_dl_1',
          'title': 'Tout va bien',
          'resultType': 'song',
          'artists': <Map<String, dynamic>>[{'name': 'Jul', 'id': 'j1'}],
        },
      },
      {
        'videoId': 'other_dl',
        'path': '/tmp/other_dl.m4a',
        'result': <String, dynamic>{
          'videoId': 'other_dl',
          'title': 'Unrelated Song',
          'resultType': 'song',
          'artists': <Map<String, dynamic>>[{'name': 'Someone Else'}],
        },
      },
    ]);

    final found = localLibraryForArtist(StorageService(), 'Jul');

    expect(found, hasLength(1));
    expect(found.single.title, 'Tout va bien');
    expect(found.single.videoId, 'jul_dl_1');
  });

  test('localLibraryForArtist stays empty for an artist nothing is stored for',
      () {
    expect(localLibraryForArtist(StorageService(), 'Nobody Here'), isEmpty);
  });

  test('localLibraryForArtist tolerates a blank artist name', () {
    expect(localLibraryForArtist(StorageService(), '   '), isEmpty);
  });
}
