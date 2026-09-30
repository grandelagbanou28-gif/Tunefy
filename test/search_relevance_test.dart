import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/search_relevance.dart';

MuzoItem item({
  required String title,
  String resultType = 'video',
  String? artist,
  String? album,
  String? videoId,
  String? browseId,
  String? uploaded,
}) {
  return MuzoItem(
    title: title,
    thumbnails: const [],
    resultType: resultType,
    isExplicit: false,
    videoId: videoId ?? (resultType == 'video' || resultType == 'song' ? 'vid-$title' : null),
    browseId: browseId ?? (resultType != 'video' && resultType != 'song' ? 'bid-$title' : null),
    artists: artist != null ? [MuzoArtist(name: artist, id: null)] : null,
    album: album != null ? MuzoAlbum(name: album, id: '') : null,
    uploaded: uploaded,
  );
}

void main() {
  group('SearchRelevance.normalize', () {
    test('lowercases, strips accents and punctuation', () {
      expect(SearchRelevance.normalize("Café Déjà-Vu!"), 'cafe deja vu');
      expect(SearchRelevance.normalize('  Ünïcode  '), 'unicode');
    });
  });

  group('SearchRelevance.matchesFilter', () {
    test('all accepts everything', () {
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'album'), 'all'),
        isTrue,
      );
    });

    test('songs accepts song/video/user_track/track', () {
      for (final t in ['song', 'video', 'user_track', 'track']) {
        expect(
          SearchRelevance.matchesFilter(item(title: 'x', resultType: t), 'songs'),
          isTrue,
          reason: t,
        );
      }
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'album'), 'songs'),
        isFalse,
      );
    });

    test('albums only accepts album (or bare browseId entity)', () {
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'album'), 'albums'),
        isTrue,
      );
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'song'), 'albums'),
        isFalse,
      );
      expect(
        SearchRelevance.matchesFilter(
          item(title: 'x', resultType: '', browseId: 'b', videoId: null),
          'albums',
        ),
        isTrue,
      );
    });

    test('artists accepts artist/channel', () {
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'artist'), 'artists'),
        isTrue,
      );
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'channel'), 'artists'),
        isTrue,
      );
      expect(
        SearchRelevance.matchesFilter(item(title: 'x', resultType: 'album'), 'artists'),
        isFalse,
      );
    });
  });

  group('SearchRelevance.score / rank', () {
    test('exact title match outranks unrelated title', () {
      final exact = item(title: 'Blinding Lights', artist: 'The Weeknd');
      final other = item(title: 'Random Song', artist: 'Someone');
      final sExact = SearchRelevance.score(exact, 'Blinding Lights', 'songs');
      final sOther = SearchRelevance.score(other, 'Blinding Lights', 'songs');
      expect(sExact, greaterThan(sOther));
      expect(sOther, 0);
    });

    test('artist-name query ranks that artist above others', () {
      final weeknd = item(title: 'Save Your Tears', artist: 'The Weeknd');
      final drake = item(title: 'God\'s Plan', artist: 'Drake');
      final ranked = SearchRelevance.rank(
        [drake, weeknd],
        'the weeknd',
        'songs',
      );
      expect(ranked.first.title, 'Save Your Tears');
    });

    test('album filter drops songs and keeps matching album first', () {
      final album = item(
        title: 'After Hours',
        resultType: 'album',
        artist: 'The Weeknd',
      );
      final song = item(title: 'After Hours', resultType: 'song', artist: 'The Weeknd');
      final ranked = SearchRelevance.rank(
        [song, album],
        'After Hours',
        'albums',
      );
      expect(ranked, hasLength(1));
      expect(ranked.single.resultType, 'album');
    });

    test('artists filter drops non-artists', () {
      final artist = item(title: 'Adele', resultType: 'artist');
      final song = item(title: 'Adele', resultType: 'song');
      final ranked = SearchRelevance.rank(
        [song, artist],
        'adele',
        'artists',
      );
      expect(ranked, hasLength(1));
      expect(ranked.single.resultType, 'artist');
    });

    test('accented query matches unaccented title', () {
      final t = item(title: 'Ca Révolutionne', artist: 'Booba');
      expect(SearchRelevance.score(t, 'ca revolutionne', 'songs'), greaterThan(0));
    });

    test('zero-score noise is pruned when enough strong matches exist', () {
      final good = [
        item(title: 'Hello', artist: 'Adele'),
        item(title: 'Someone Like You', artist: 'Adele'),
        item(title: 'Rolling in the Deep', artist: 'Adele'),
      ];
      final noise = item(title: 'Totally Unrelated Track', artist: 'Other Band');
      final ranked = SearchRelevance.rank(
        [...good, noise],
        'adele',
        'songs',
      );
      expect(ranked.length, 3);
      expect(ranked.any((i) => i.title == 'Totally Unrelated Track'), isFalse);
    });

    test('all-zero scores keep original order (nothing to prune against)', () {
      final a = item(title: 'Alpha', artist: 'X');
      final b = item(title: 'Beta', artist: 'Y');
      final ranked = SearchRelevance.rank([a, b], 'zzzz', 'songs');
      expect(ranked.map((i) => i.title), ['Alpha', 'Beta']);
    });

    test('empty query returns gated items without scoring', () {
      final song = item(title: 'Anything', resultType: 'song');
      final album = item(title: 'Anything', resultType: 'album');
      final ranked = SearchRelevance.rank([song, album], '', 'songs');
      expect(ranked, hasLength(1));
      expect(ranked.single.resultType, 'song');
    });
  });
}
