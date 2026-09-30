import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';

/// Spotify Web API client using OAuth Client Credentials.
///
/// Les identifiants sont injectés au build via
/// `--dart-define=SPOTIFY_CLIENT_ID=... --dart-define=SPOTIFY_CLIENT_SECRET=...`
/// avec un fallback vers les identifiants de développement fournis.
///
/// NOTE Spotify : le flux `client_credentials` est bloqué (403) tant que
/// l'application est en mode *Développement*. Une fois passée en production
/// sur dashboard.spotify.com, [search] renvoie le vrai catalogue.
///
/// Le Web API ne fournit pas d'audio complet : on l'utilise pour DÉCOUVRIR
/// des titres/artistes réels, que les appelants résolvent ensuite en pistes
/// YouTube jouables (voir MultiApiService.resolveToPlayable).
class SpotifyUnofficialService {
  static const _base = 'https://api.spotify.com/v1';
  static const _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const _timeout = Duration(seconds: 12);

  static const _clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment('SPOTIFY_CLIENT_SECRET');
  static const _fallbackClientId = '454f2a3d05e44052b2f6cbf0dee15765';
  static const _fallbackClientSecret = 'b2a2ae2a96f94e928171dc525aa07a4c';

  String? _token;
  DateTime? _tokenExpiry;

  String get clientId => _clientId.isNotEmpty ? _clientId : _fallbackClientId;
  String get clientSecret =>
      _clientSecret.isNotEmpty ? _clientSecret : _fallbackClientSecret;

  bool get hasCredentials => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Obtient (et met en cache / rafraîchit) un jeton client_credentials.
  Future<String?> _getToken() async {
    final now = DateTime.now();
    if (_token != null &&
        _tokenExpiry != null &&
        now.isBefore(_tokenExpiry!)) {
      return _token;
    }
    try {
      final creds = '$clientId:$clientSecret';
      final basic = base64Encode(utf8.encode(creds));
      final resp = await http
          .post(
            Uri.parse(_tokenUrl),
            headers: {
              'Authorization': 'Basic $basic',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'grant_type': 'client_credentials'},
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint(
            'Spotify token error ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final token = data['access_token'];
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      if (token == null) return null;
      _token = token;
      _tokenExpiry = now.add(Duration(seconds: expiresIn - 60));
      return _token;
    } catch (e) {
      debugPrint('Spotify token catch: $e');
      return null;
    }
  }

  /// Exécute un GET authentifié; renvoie null si jeton absent ou erreur HTTP.
  Future<Map<String, dynamic>?> _get(String path) async {
    final token = await _getToken();
    if (token == null) return null;
    try {
      final resp = await http
          .get(
            Uri.parse('$_base$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('Spotify GET $path -> ${resp.statusCode}');
        return null;
      }
      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Spotify GET catch: $e');
      return null;
    }
  }

  /// Recherche générale (conservé pour compatibilité) : pistes.
  Future<List<MuzoItem>> search(String query) =>
      searchTracks(query, limit: 20);

  /// Recherche de pistes. Métadonnées uniquement (pas d'audio complet Web API).
  Future<List<MuzoItem>> searchTracks(String query, {int limit = 20}) async {
    final data = await _get(
        '/search?q=${Uri.encodeQueryComponent(query)}&type=track&limit=$limit');
    if (data == null) return [];
    final tracks = data['tracks']?['items'] as List? ?? [];
    return tracks.whereType<Map<String, dynamic>>().map(_trackToItem).toList();
  }

  MuzoItem _trackToItem(Map<String, dynamic> t) {
    final name = t['name'] ?? '';
    final artists = (t['artists'] as List?) ?? const [];
    final artist = artists.isNotEmpty && artists[0] is Map
        ? (artists[0] as Map)['name']?.toString() ?? ''
        : '';
    final images = (t['album'] is Map)
        ? (t['album']?['images'] as List?) ?? const []
        : const [];
    final thumb = images.isNotEmpty && images[0] is Map
        ? (images[0]['url']?.toString() ?? '')
        : '';
    final durationMs = (t['duration_ms'] as num?)?.toInt() ?? 0;
    return MuzoItem(
      videoId: null,
      title: '$name - $artist',
      artists: [MuzoArtist(name: artist, id: null)],
      thumbnails: thumb.isNotEmpty
          ? [MuzoThumbnail(url: thumb, width: 0, height: 0)]
          : [],
      resultType: 'video',
      isExplicit: t['explicit'] ?? false,
      durationSeconds: durationMs > 0 ? (durationMs / 1000).round() : null,
    );
  }

  /// Recherche de playlists (utile pour le système de catégories/browse).
  Future<List<Map<String, dynamic>>> searchPlaylistsRaw(
    String query, {
    int limit = 20,
  }) async {
    final data = await _get(
        '/search?q=${Uri.encodeQueryComponent(query)}&type=playlist&limit=$limit');
    if (data == null) return [];
    return (data['playlists']?['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}
