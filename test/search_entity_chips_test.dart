import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';

/// Reproduit le contrat reel du worker de recherche : les entites navigables
/// (album MPREb_..., playlist VLPL...) ne sont renvoyees QUE si le filtre de
/// type est explicite. Sans filtre il ne repond qu'avec des morceaux, sans
/// browseId, et le garde-fou du chip rejetait alors toute la page.
class _FakeSearchApi extends MuzoApiService {
  _FakeSearchApi() : super(StorageService());

  final List<String> calls = [];

  static final albums = <MuzoItem>[
    MuzoItem(
      title: 'Jefe',
      thumbnails: const [],
      resultType: 'album',
      isExplicit: false,
      browseId: 'MPREb_09DO8gDztAC',
      artists: [MuzoArtist(name: 'Ninho', id: null)],
    ),
  ];

  static final playlists = <MuzoItem>[
    MuzoItem(
      title: 'Ninho - Exclu 2026',
      thumbnails: const [],
      resultType: 'playlist',
      isExplicit: false,
      browseId: 'VLPLWpyk9zU9trM',
      artists: [MuzoArtist(name: 'Ninho', id: null)],
    ),
  ];

  @override
  Future<MuzoSearchResponse> search(
    String query, {
    String filter = 'songs',
    String? continuationToken,
    bool shortOnly = false,
  }) async {
    calls.add('$query|$filter');
    final songs = <MuzoItem>[
      MuzoItem(
        title: 'J Introduction',
        thumbnails: const [],
        resultType: 'song',
        isExplicit: false,
        videoId: 'aaaaaaaaaaa',
        artists: [MuzoArtist(name: 'Ninho', id: null)],
      ),
    ];
    if (filter == 'albums') return MuzoSearchResponse(results: albums);
    if (filter == 'playlists') return MuzoSearchResponse(results: playlists);
    return MuzoSearchResponse(results: songs);
  }
}

void main() {
  group('artistAlbumsProvider', () {
    test('demande le filtre albums, pas la page non filtree', () async {
      final api = _FakeSearchApi();
      final container = ProviderContainer(
        overrides: [muzoApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final albums = await container.read(artistAlbumsProvider('ninho').future);

      expect(albums, isNotEmpty, reason: 'le chip Albums ne doit pas etre vide');
      expect(albums.first.browseId, 'MPREb_09DO8gDztAC');
      expect(albums.every((a) => a.resultType == 'album'), isTrue);
      expect(
        api.calls,
        contains('ninho|albums'),
        reason: 'le worker ne donne de browseId que sur un filtre explicite',
      );
      expect(api.calls.where((c) => c.endsWith('|all')), isEmpty);
    });
  });

  group('artistPlaylistsProvider', () {
    test('demande le filtre playlists', () async {
      final api = _FakeSearchApi();
      final container = ProviderContainer(
        overrides: [muzoApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final playlists =
          await container.read(artistPlaylistsProvider('ninho').future);

      expect(playlists, isNotEmpty,
          reason: 'le chip Playlists ne doit pas etre vide');
      expect(playlists.first.browseId, 'VLPLWpyk9zU9trM');
      expect(playlists.every((p) => p.resultType == 'playlist'), isTrue);
      expect(api.calls, contains('ninho|playlists'));
    });
  });
}
