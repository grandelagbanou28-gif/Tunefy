import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// Dailymotion — **no key required**. Public video catalog search.
///
/// Provides music-video METADATA (title/owner/duration/thumbnails) without an
/// API key, adding a non-YouTube discovery seed source. Items are
/// metadata-only seeds (callers resolve titles to playable audio via the main
/// search), matching the Deezer/iTunes contract. Never throws — failures
/// return [].
class DailymotionService {
  static const String _base = 'https://api.dailymotion.com/videos';
  static const Duration _timeout = Duration(seconds: 12);

  Future<List<MuzoItem>> searchTracks(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
          '$_base?search=${Uri.encodeComponent(q)}&limit=$limit'
          '&fields=id,title,owner.screenname,duration,thumbnail_240_url,url');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('Dailymotion non-200: ${resp.statusCode}');
        return const [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['list'] as List? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => _toItem(Map<String, dynamic>.from(e)))
          .where((i) => i.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Dailymotion search error: $e');
      return const [];
    }
  }

  MuzoItem _toItem(Map<String, dynamic> r) {
    final owner = (r['owner.screenname'] as String?) ?? '';
    final thumb = (r['thumbnail_240_url'] as String?) ?? '';
    final dur = (r['duration'] as num?)?.toInt();
    return MuzoItem(
      title: (r['title'] as String?) ?? '',
      resultType: 'song',
      isExplicit: false,
      durationSeconds: dur,
      artists: owner.isNotEmpty ? [MuzoArtist(name: owner)] : null,
      thumbnails: thumb.isNotEmpty
          ? [MuzoThumbnail(url: thumb, width: 240, height: 180)]
          : const [],
      source: 'dailymotion',
      sourceId: (r['id'] as String?),
      sourceUrl: (r['url'] as String?),
      fetchedAt: DateTime.now(),
    );
  }
}
