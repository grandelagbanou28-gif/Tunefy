import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// Beatport — **no key required**. Electronic / dance catalog metadata.
///
/// Beatport's public catalog endpoint answers without authentication and
/// carries rich EDM metadata (label, genre, BPM, release). Tracks are
/// metadata-only seeds (no streamable audio), exactly like the Deezer/iTunes
/// contract: callers resolve titles to playable tracks via the main search.
/// Never throws — failures return [].
class BeatportService {
  static const String _base = 'https://api.beatport.com/v4/catalog/search';
  static const Duration _timeout = Duration(seconds: 12);

  Future<List<MuzoItem>> searchTracks(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
          '$_base?q=${Uri.encodeComponent(q)}&type=tracks&limit=$limit');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('Beatport non-200: ${resp.statusCode}');
        return const [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as Map<String, dynamic>?;
      final tracks = (results?['tracks'] as List?) ?? const [];
      return tracks
          .whereType<Map>()
          .map((e) => _toItem(Map<String, dynamic>.from(e)))
          .where((i) => i.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Beatport search error: $e');
      return const [];
    }
  }

  MuzoItem _toItem(Map<String, dynamic> r) {
    final artists = (r['artists'] as List?) ?? const [];
    final artistNames = artists
        .whereType<Map>()
        .map((a) => (a['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final release = r['release'] as Map?;
    final genre = r['genres'] as List?;
    final genreName = genre != null && genre.isNotEmpty
        ? ((genre.first as Map)['name'] as String?)
        : null;
    final mix = (r['mix'] as String?) ?? '';
    final name = (r['name'] as String?) ?? '';
    final title = mix.isNotEmpty && mix != 'Original Mix'
        ? '$name ($mix)'
        : name;
    final art = (r['image'] as Map?)?['https_url'] as String?;
    final bpm = (r['bpm'] as num?)?.toInt();
    return MuzoItem(
      title: title,
      resultType: 'song',
      isExplicit: false,
      artists: artistNames.isNotEmpty
          ? artistNames.map((n) => MuzoArtist(name: n)).toList()
          : null,
      album: release != null
          ? MuzoAlbum(
              name: (release['name'] as String?) ?? '',
              id: (release['id'] as num?)?.toString() ?? '',
            )
          : null,
      category: genreName,
      thumbnails: art != null && art.isNotEmpty
          ? [MuzoThumbnail(url: art, width: 300, height: 300)]
          : const [],
      source: 'beatport',
      sourceId: (r['id'] as num?)?.toString(),
      sourceUrl: (r['url'] as String?),
      metadata: bpm != null ? {'bpm': bpm} : null,
      fetchedAt: DateTime.now(),
    );
  }
}
