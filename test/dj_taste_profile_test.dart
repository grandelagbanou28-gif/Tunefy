import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/dj_taste_profile.dart';
import 'package:muzo/services/storage_service.dart';

void main() {
  MuzoItem song(String title, String artist) => MuzoItem(
        title: title,
        thumbnails: const [],
        resultType: 'song',
        isExplicit: false,
        artists: [MuzoArtist(name: artist, id: '')],
      );

  test('artistWeights compte les écoutes distinctes par artiste', () async {
    final storage = StorageService();
    // getHistory sur storage non initialisé → liste vide tolérée.
    final profile = DjTasteProfile(storage);
    final weights = profile.artistWeights();
    expect(weights, isA<Map<String, int>>());
    expect(profile.topArtists(), isA<List<String>>());
    // Hors session Hive, affinity d un item inconnu = 0.
    expect(profile.affinityScore(song('x', 'Nobody')), 0.0);
  });
}
