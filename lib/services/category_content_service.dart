import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/supabase_store.dart';

/// Static curated content per (category, sub) from the Supabase
/// `category_content` table.
///
/// This is the guarantee layer for sub-sections that never (or barely) yield
/// verified live content (e.g. "Hits Bénin > Benin Gospel"). Rows are REAL
/// songs curated by hand (title + artist + real YouTube video_id); the app
/// only reads them — no live pipeline, no refresh, instant display.
///
/// Never throws: on any failure it returns an empty list and the caller falls
/// through to the live pipeline.
class CategoryContentService {
  CategoryContentService._();

  static final CategoryContentService instance = CategoryContentService._();

  /// Short in-memory memo so repeated loads within a session don't re-hit the
  /// network for the same section (Supabase is the durable store).
  final Map<String, List<MuzoItem>> _memo = {};
  DateTime _memoSince = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _memoTtl = Duration(minutes: 10);

  /// Rows for one section, ordered by [sort], or const [] when absent/failed.
  Future<List<MuzoItem>> loadFor(String category, String sub) async {
    final key = '$category|$sub';
    if (_memoContains(key)) return _memo[key]!;
    try {
      final resp = await http.get(
        Uri.parse(
          '${SupabaseStore.url}/rest/v1/category_content?'
          'select=*&order=sort.asc&limit=20&'
          'category=eq.${Uri.encodeQueryComponent(category)}&'
          'sub=eq.${Uri.encodeQueryComponent(sub)}',
        ),
        headers: {'apikey': SupabaseStore.anonKey},
      );
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final rows = (jsonDecode(resp.body) as List)
            .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
            .toList();
        _setMemo(key, rows);
        return rows;
      }
    } catch (e) {
      debugPrint('Category content REST failed: $e');
    }
    return const <MuzoItem>[];
  }

  bool _memoContains(String key) {
    if (DateTime.now().difference(_memoSince) > _memoTtl) return false;
    return _memo.containsKey(key);
  }

  void _setMemo(String key, List<MuzoItem> rows) {
    if (DateTime.now().difference(_memoSince) > _memoTtl) _memo.clear();
    _memoSince = DateTime.now();
    _memo[key] = rows;
  }

  /// Row -> real playable track. Thumbnail is derived from the video id when
  /// the row has none.
  MuzoItem _fromRow(Map<String, dynamic> row) {
    final videoId = row['video_id']?.toString() ?? '';
    final title = row['title']?.toString() ?? '';
    final artist = row['artist']?.toString() ?? '';
    final thumb = row['thumbnail']?.toString();
    return MuzoItem(
      title: title,
      artists: [MuzoArtist(name: artist)],
      videoId: videoId,
      resultType: 'video',
      isExplicit: false,
      thumbnails: [
        MuzoThumbnail(
          url: thumb?.isNotEmpty == true
              ? thumb!
              : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
          width: 480,
          height: 360,
        ),
      ],
      source: 'catalog',
      verified: true,
      relevanceScore: 100,
    );
  }
}