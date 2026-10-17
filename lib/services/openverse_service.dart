import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// Openverse (Creative Commons) — **no key required**, audio catalogue CC0/PD.
///
/// Each result carries a direct, streamable `audio` URL (a real file, not a
/// 30-second preview), so Openverse items are BOTH metadata seeds AND usable
/// audio sources. Callers still prefer full catalogues (YouTube/Deezer) and
/// fall back to Openverse for genuinely free-to-play tracks. Anonymous access
/// is rate-limited (~100 req/h) so this stays a low-priority source.
class OpenverseService {
  static const String _base = 'https://api.openverse.org/v1/audio';
  static const Duration _timeout = Duration(seconds: 12);

  /// Search Creative-Commons audio. Never throws — failures return [].
  Future<List<MuzoItem>> searchTracks(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
          '$_base/?q=${Uri.encodeComponent(q)}&page_size=$limit');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('Openverse non-200: ${resp.statusCode}');
        return const [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      return results
          .whereType<Map>()
          .map((e) => _toItem(Map<String, dynamic>.from(e)))
          .where((i) => i.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Openverse search error: $e');
      return const [];
    }
  }

  MuzoItem _toItem(Map<String, dynamic> r) {
    final title = (r['title'] as String?) ?? '';
    final creator = (r['creator'] as String?) ?? '';
    final audio = (r['url'] as String?) ?? '';
    final thumb = (r['thumbnail'] as String?) ?? '';
    final duration = (r['duration'] as num?)?.toInt();
    return MuzoItem(
      title: title,
      resultType: 'song',
      isExplicit: false,
      durationSeconds: duration,
      artists: creator.isNotEmpty ? [MuzoArtist(name: creator)] : null,
      audioUrl: audio.isNotEmpty ? audio : null,
      thumbnails: thumb.isNotEmpty
          ? [MuzoThumbnail(url: thumb, width: 300, height: 300)]
          : const [],
      source: 'openverse',
      sourceId: (r['id'] as num?)?.toString(),
      sourceUrl: (r['foreign_landing_url'] as String?),
      fetchedAt: DateTime.now(),
    );
  }
}
