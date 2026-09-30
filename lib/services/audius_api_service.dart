import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// A single track from the Audius API (decentralized, keyless).
class AudiusTrack {
  final String id;
  final String title;
  final String genre;
  final String artistName;
  final String? artworkUrl;
  final String streamUrl;
  final int? durationSeconds;

  const AudiusTrack({
    required this.id,
    required this.title,
    required this.genre,
    required this.artistName,
    required this.streamUrl,
    this.artworkUrl,
    this.durationSeconds,
  });

  /// Audius artwork maps { "150x150": url, "480x480": url, "1000x1000": url }.
  /// Picks the largest resolution and bumps it to 1000x1000 so tiles/player
  /// never upscale a blurred thumbnail.
  static String _largestArtwork(Map<dynamic, dynamic> artworkMap) {
    String best = '';
    int bestPx = 0;
    for (final v in artworkMap.values) {
      if (v is! String || v.isEmpty) continue;
      var px = 0;
      final m = RegExp(r'/(\d+)x\d+\.').firstMatch(v);
      if (m != null) px = int.tryParse(m.group(1)!) ?? 0;
      if (px > bestPx || (px == bestPx && best.isEmpty)) {
        best = v;
        bestPx = px;
      }
    }
    if (best.isEmpty) return '';
    final m = RegExp(r'/(\d+)x(\d+)(\.\w+)$').firstMatch(best);
    if (m != null) {
      return best.replaceRange(m.start, m.end, '/1000x1000${m.group(3)}');
    }
    return best;
  }

  factory AudiusTrack.fromJson(Map<String, dynamic> json) {
    final artworkUrl = _largestArtwork(
      (json['artwork'] is Map ? json['artwork'] : const {}) as Map<dynamic, dynamic>,
    );
    final user = json['user'];
    return AudiusTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      genre: json['genre']?.toString() ?? '',
      artistName: user is Map
          ? (user['name']?.toString() ?? '')
          : (json['handle']?.toString() ?? ''),
      artworkUrl: artworkUrl.isEmpty ? null : artworkUrl,
      streamUrl: (json['stream'] as Map?)?['url']?.toString() ?? '',
      durationSeconds: (json['duration'] as num?)?.toInt(),
    );
  }

  /// Audius tracks are directly playable through their signed stream URL:
  /// same 'user_track' contract as Jamendo so the audio handler streams it
  /// straight away instead of resolving a YouTube id.
  MuzoItem toMuzoItem() {
    return MuzoItem(
      title: title,
      thumbnails: artworkUrl != null && artworkUrl!.isNotEmpty
          ? [MuzoThumbnail(url: artworkUrl!, width: 300, height: 300)]
          : const [],
      resultType: 'user_track',
      isExplicit: false,
      videoId: id,
      durationSeconds: durationSeconds,
      artists:
          artistName.isNotEmpty ? [MuzoArtist(name: artistName, id: null)] : null,
      channelName: artistName.isEmpty ? null : artistName,
      audioUrl: streamUrl,
      source: 'audius',
      sourceId: id,
      sourceUrl: streamUrl,
      fetchedAt: DateTime.now(),
    );
  }
}

/// Keyless-minimal Audius client. Every method returns an empty list on any
/// failure so callers can fall through to the next source without try/catch.
class AudiusApiService {
  static const String _base = 'https://api.audius.co';
  static const Duration _timeout = Duration(seconds: 8);
  final http.Client _client = http.Client();

  Future<List<AudiusTrack>> _fetch(
    String path,
    Map<String, String> params,
  ) async {
    try {
      final uri = Uri.parse('$_base$path').replace(queryParameters: params);
      final res = await _client
          .get(uri, headers: const {'User-Agent': 'Tunefy/3.9.0 (Android)'})
          .timeout(_timeout);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['data'] as List?) ?? const [];
      return list
          .map((e) => AudiusTrack.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('AUDIUS fetch fail $path :: $e');
      return [];
    }
  }

  /// Trending tracks filtered by genre (Audius' free-text search endpoint 404s,
  /// so trending-by-genre is the reliable genre lookup: the API returns tracks
  /// whose declared genre matches exactly).
  Future<List<AudiusTrack>> tracksByGenre(
    String genre, {
    int limit = 10,
  }) {
    final q = genre.trim();
    if (q.isEmpty) return Future.value(const []);
    return _fetch('/v1/tracks/trending', {
      'genre': q,
      'limit': '$limit',
      'app_name': 'Tunefy',
    });
  }
}

final audiusApiServiceProvider = Provider<AudiusApiService>((ref) {
  return AudiusApiService();
});