import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// Wikimedia Commons — **no key required**, public-domain audio catalogue.
///
/// Queries the MediaWiki API for audio files (namespace 6) matching a term,
/// then resolves each file's direct upload URL. Commons audio is PD/CC, so it
/// is directly playable; used as a free fallback source when commercial
/// catalogues miss a track. Never throws — failures return [].
class WikimediaCommonsService {
  static const String _base = 'https://commons.wikimedia.org/w/api.php';
  static const Duration _timeout = Duration(seconds: 12);

  Future<List<MuzoItem>> searchTracks(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final searchUri = Uri.parse(
          '$_base?action=query&format=json&generator=search'
          '&gsrsearch=${Uri.encodeComponent('filetype:audio $q')}'
          '&gsrnamespace=6&gsrlimit=$limit'
          '&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=300');
      final resp = await http.get(searchUri).timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('Wikimedia non-200: ${resp.statusCode}');
        return const [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final pages =
          (data['query'] as Map<String, dynamic>?)?['pages'] as Map?;
      if (pages == null) return const [];
      final items = <MuzoItem>[];
      for (final page in pages.values) {
        final p = page as Map<String, dynamic>;
        final info = (p['imageinfo'] as List?)?.firstOrNull;
        if (info is! Map) continue;
        final url = (info['url'] as String?) ?? '';
        if (url.isEmpty) continue;
        final title = ((p['title'] as String?) ?? '')
            .replaceFirst(RegExp(r'^File:'), '')
            .replaceAll(RegExp(r'\.\w+$'), '');
        final thumb = (info['thumburl'] as String?) ?? '';
        items.add(MuzoItem(
          title: title,
          resultType: 'song',
          isExplicit: false,
          audioUrl: url,
          thumbnails: thumb.isNotEmpty
              ? [MuzoThumbnail(url: thumb, width: 300, height: 300)]
              : const [],
          source: 'wikimedia',
          sourceId: (p['pageid'] as num?)?.toString(),
          sourceUrl: url,
          fetchedAt: DateTime.now(),
        ));
      }
      return items;
    } catch (e) {
      debugPrint('Wikimedia search error: $e');
      return const [];
    }
  }
}
