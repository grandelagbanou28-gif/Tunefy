library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service YouTube pour les catégories (Gospel, Benin, etc.).
class YoutubeApiService {
  // La clé est injectée au build via --dart-define-from-file=secrets.json ;
  // sans clé la recherche YouTube est simplement désactivée (fallback iTunes).
  static const String _key = String.fromEnvironment('YOUTUBE_API_KEY');

  String get key => _key;

  /// Recherche YouTube par terme.
  Future<List<dynamic>> search({
    required String query,
    int maxResults = 10,
  }) async {
    if (key.isEmpty) return [];
    final uri = Uri.parse(
      'https://www.googleapis.com/youtube/v3/search?'
      'part=snippet'
      '&type=video'
      '&q=$query'
      '&maxResults=$maxResults'
      '&key=$key',
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    return (data['items'] as List<dynamic>?)
        ?.map((item) {
          final snippet = item['snippet'] as Map<String, dynamic>? ?? const {};
          final th = snippet['thumbnails'] as Map<String, dynamic>? ?? const {};
          final thBest =
              (th['high'] ?? th['medium'] ?? th['default']) as Map<String, dynamic>?;
          return {
            'id': item['id']['videoId'] as String?,
            'title': snippet['title'] as String?,
            'channel': snippet['channelTitle'] as String?,
            'thumbnail': thBest?['url'] as String?,
            'url': 'https://www.youtube.com/watch?v=${item['id']['videoId']}',
          };
        })
        .toList() ?? [];
  }

  /// Recherche par sous-catégorie Gospel.
  Future<List<dynamic>> searchBySub(String sub) async {
    return search(query: sub, maxResults: 10);
  }
}
