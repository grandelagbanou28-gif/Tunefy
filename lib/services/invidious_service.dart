import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// Invidious — **no key required**. Keyless YouTube front-end instances.
///
/// Provides YouTube METADATA (title/channel/views/duration/thumbnails) without
/// an API key, so it adds a resilient discovery seed source when the keyed
/// YouTube backend is unavailable. Each instance is probed cheaply and the
/// first healthy one answers; failures fall through to []. Never throws.
class InvidiousService {
  /// Public instances known to expose /api/v1 (rotated as they move).
  static const List<String> _instances = [
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://yewtu.be',
    'https://vid.puffyan.us',
  ];
  static const Duration _timeout = Duration(seconds: 10);

  Future<List<MuzoItem>> searchTracks(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    for (final host in _instances) {
      final items = await _searchOn(host, q, limit);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  Future<List<MuzoItem>> _searchOn(
      String host, String query, int limit) async {
    try {
      final uri = Uri.parse(
          '$host/api/v1/search?q=${Uri.encodeComponent(query)}'
          '&type=video&sort_by=relevance');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as List? ?? [];
      final items = <MuzoItem>[];
      for (final r in data.take(limit)) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        final videoId = (m['videoId'] as String?) ?? '';
        if (videoId.isEmpty) continue;
        final author = (m['author'] as String?) ?? '';
        final length = (m['lengthSeconds'] as num?)?.toInt();
        final thumbs = (m['videoThumbnails'] as List?) ?? const [];
        final thumbUrl = thumbs.isNotEmpty
            ? ((thumbs.first as Map)['url'] as String? ?? '')
            : '';
        items.add(MuzoItem(
          title: (m['title'] as String?) ?? '',
          videoId: videoId,
          resultType: 'song',
          isExplicit: false,
          durationSeconds: length,
          channelName: author.isNotEmpty ? author : null,
          artists: author.isNotEmpty ? [MuzoArtist(name: author)] : null,
          thumbnails: thumbUrl.isNotEmpty
              ? [MuzoThumbnail(url: thumbUrl, width: 320, height: 180)]
              : const [],
          source: 'invidious',
          sourceId: videoId,
          sourceUrl: '$host/watch?v=$videoId',
          fetchedAt: DateTime.now(),
        ));
      }
      return items;
    } catch (e) {
      debugPrint('Invidious ($host) error: $e');
      return const [];
    }
  }
}
