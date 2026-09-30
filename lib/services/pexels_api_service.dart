import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// One stock clip, reduced to what the feed needs to play it.
class PexelsClip {
  const PexelsClip({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.width,
    required this.height,
    this.durationSeconds,
    this.query = '',
  });

  final String id;
  final String videoUrl;
  final String thumbnailUrl;
  final int width;
  final int height;
  final int? durationSeconds;
  final String query;

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'width': width,
        'height': height,
        'durationSeconds': durationSeconds,
        'query': query,
      };

  factory PexelsClip.fromJson(Map<String, dynamic> json) => PexelsClip(
        id: json['id']?.toString() ?? '',
        videoUrl: json['videoUrl']?.toString() ?? '',
        thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
        query: json['query']?.toString() ?? '',
      );
}

/// Pexels stock footage, used as the visual layer of the clips feed: when a
/// music video cannot be resolved we play a real vertical video instead of a
/// static cover. Audio always stays on the audio handler, these are muted.
///
/// Pexels is free, but the quota is 20 000 calls/month, so every lookup is
/// cached for a week in Hive — the returned file URLs stay valid.
class PexelsApiService {
  PexelsApiService({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? _keyFromEnvironment;

  static const _keyFromEnvironment = String.fromEnvironment('PEXELS_API_KEY');

  static const String _boxName = 'pexels_cache';
  static const Duration _cacheTtl = Duration(days: 7);
  static const Duration _timeout = Duration(seconds: 12);

  final http.Client _client;
  final String _apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<PexelsClip?> findClip(String query, {String? cacheKey}) async {
    if (!isConfigured) return null;
    final key = cacheKey ?? 'q:$query';
    final cached = await _readCache(key);
    if (cached != null) return cached;
    try {
      final uri = Uri.parse('https://api.pexels.com/v1/videos/search')
          .replace(queryParameters: {
        'query': query,
        'orientation': 'portrait',
        'size': 'medium',
        'per_page': '1',
      });
      final response = await _client
          .get(uri, headers: {'Authorization': _apiKey})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final videos = (jsonDecode(response.body) as Map)['videos'] as List?;
      if (videos == null || videos.isEmpty) return null;
      final clip = _parse(videos.first as Map<String, dynamic>, query);
      if (clip == null) return null;
      await _writeCache(key, clip);
      return clip;
    } catch (e) {
      debugPrint('Pexels lookup failed for "$query": $e');
      return null;
    }
  }

  /// A small pool of clips, so a whole feed page can be decorated without
  /// hammering the 20k/month quota.
  Future<List<PexelsClip>> findMany(
    List<String> queries, {
    Duration? ttl,
  }) async {
    final out = <PexelsClip>[];
    for (final q in queries) {
      final clip = await findClip(q, cacheKey: 'multi:${ttl?.inMinutes ?? 0}:$q');
      if (clip != null) out.add(clip);
    }
    return out;
  }

  PexelsClip? _parse(Map<String, dynamic> json, String query) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final files = (json['video_files'] as List?) ?? const [];
    String? best;
    var bestArea = 0;
    for (final f in files) {
      if (f is! Map) continue;
      final w = (f['width'] as num?)?.toInt() ?? 0;
      final h = (f['height'] as num?)?.toInt() ?? 0;
      final link = f['link']?.toString() ?? '';
      if (link.isEmpty) continue;
      // Prefer the smallest file that is still tall enough for a phone.
      if (h >= 720) {
        final area = w * h;
        if (best == null || area < bestArea) {
          best = link;
          bestArea = area;
        }
      }
    }
    if (best == null) return null;
    return PexelsClip(
      id: id,
      videoUrl: best,
      thumbnailUrl: (json['image'] as String?) ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration'] as num?)?.toInt(),
      query: query,
    );
  }

  Future<Box> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<PexelsClip?> _readCache(String key) async {
    try {
      final box = await _box();
      final raw = box.get(key) as Map?;
      if (raw == null) return null;
      final ts = raw['ts'] as int? ?? 0;
      if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) >
          _cacheTtl) {
        return null;
      }
      return PexelsClip.fromJson(Map<String, dynamic>.from(raw['clip'] as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, PexelsClip clip) async {
    try {
      final box = await _box();
      await box.put(key, {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'clip': clip.toJson(),
      });
    } catch (_) {}
  }
}
