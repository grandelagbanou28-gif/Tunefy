import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/models/user_data.dart';
import 'package:muzo/models/artist_details.dart';
import 'package:muzo/models/album_details.dart';
import 'package:muzo/services/auth_service.dart';
import 'package:muzo/services/indian_content_filter.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/api_constants.dart';
import 'package:muzo/models/user_track.dart';
import 'package:muzo/services/piped_api_service.dart';

final muzoApiServiceProvider = Provider<MuzoApiService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return MuzoApiService(storage);
});

class MuzoSearchResponse {
  final List<MuzoItem> results;
  final String? continuationToken;

  MuzoSearchResponse({required this.results, this.continuationToken});
}

class MuzoApiService {
  final StorageService _storage;
  late final AuthService _auth;
  final http.Client _client = http.Client();

  MuzoApiService(this._storage) {
    _auth = AuthService(_storage);
  }

  /// Copies a raw backend map and stamps provenance so every item remembers
  /// where it came from and when it was fetched (never fabricated — just the
  /// actual retrieval metadata).
  static Map<String, dynamic> _taggedJson(dynamic raw, String source) {
    return Map<String, dynamic>.from(raw as Map)
      ..['source'] = source
      ..['fetched_at'] = DateTime.now().toIso8601String();
  }

  /// Le worker Vercel répond HTTP 500 (« upstream 400/405 ») dès qu'un seul
  /// caractère non-ASCII est présent dans `q` — mesuré le 2026-10-11 : `q=é`
  /// suffit, et la casse n'y change rien. Les titres viennent parfois déjà
  /// **décomposés** de l'amont (`a` + U+0300 dans « Fille à Papa »), que la
  /// table ci-dessous ne voit pas → les diacritiques combinants sont retirés
  /// d'abord. Une requête réduite à rien par la pliage (arabe, hangul…) est
  /// envoyée telle quelle : un 500 honnête vaut mieux qu'un `q` vide.
  static String _stripAccents(String s) {
    var result =
        s.replaceAllMapped(RegExp(r'\p{M}', unicode: true), (_) => '');
    const map = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'æ': 'ae',
      'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ð': 'd', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'þ': 'th', 'ÿ': 'y', 'œ': 'oe',
      'À': 'A', 'Á': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A', 'Æ': 'AE',
      'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
      'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
      'Ð': 'D', 'Ñ': 'N', 'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
      'Ø': 'O', 'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
      'Ý': 'Y', 'Þ': 'TH', 'Ÿ': 'Y', 'Œ': 'OE',
    };
    for (final e in map.entries) {
      result = result.replaceAll(e.key, e.value);
    }
    return result.trim().isEmpty ? s.trim() : result;
  }

  @visibleForTesting
  static String workerQueryFor(String s) => _stripAccents(s);

  static const String _baseUrl = ApiConstants.mainApiBaseUrl;

  Map<String, String> get _headers {
    final token = _storage.authToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static const Map<String, String> _ytHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  void dispose() {
    _client.close();
  }

  Future<http.Response> _retryWithRefresh(
    Future<http.Response> Function() request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    var response = await request().timeout(timeout);

    if (response.statusCode == 403) {
      debugPrint('Received 403, attempting token refresh...');
      final newToken = await _auth.refreshToken();
      if (newToken != null) {
        debugPrint('Token refreshed, retrying request...');
        response = await request().timeout(timeout);
      }
    }

    return response;
  }

  // --- User Data ---

  Future<UserData> getUserData() async {
    final response = await _retryWithRefresh(
      () => _client.get(
        Uri.parse('$_baseUrl/user/data'),
        headers: _headers,
      ),
      timeout: const Duration(seconds: 200),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UserData.fromJson(data);
    } else {
      throw Exception('Failed to load user data');
    }
  }

  Future<User> getProfile() async {
    final response = await _retryWithRefresh(
      () => _client.get(
        Uri.parse('$_baseUrl/user/profile'),
        headers: _headers,
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return User.fromJson(data['user'] ?? data);
    } else {
      throw Exception('Failed to load profile');
    }
  }

  Future<User> updateProfile({
    String? username,
    String? email,
    String? currentPassword,
    String? newPassword,
  }) async {
    final response = await _retryWithRefresh(
      () => _client.put(
        Uri.parse('$_baseUrl/user/profile'),
        headers: _headers,
        body: jsonEncode({
          if (username != null) 'username': username,
          if (email != null) 'email': email,
          if (currentPassword != null) 'currentPassword': currentPassword,
          if (newPassword != null) 'newPassword': newPassword,
        }),
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return User.fromJson(data['user'] ?? data);
    } else {
      dynamic errorMsg = 'Update failed';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Update failed';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  Future<String> updateAvatar(String filePath) async {
    final uri = Uri.parse('$_baseUrl/user/avatar');
    final request = http.MultipartRequest('PUT', uri);
    request.headers.addAll(_headers);
    request.files.add(await http.MultipartFile.fromPath('image', filePath));

    final response = await _retryWithRefresh(() async {
      final streamedResponse = await request.send();
      return http.Response.fromStream(streamedResponse);
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['avatar'];
    } else {
      dynamic errorMsg = 'Avatar upload failed';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Avatar upload failed';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  // --- History ---

  Future<void> addToHistory(MuzoItem song) async {
    final response = await _retryWithRefresh(
      () => _client.post(
        Uri.parse('$_baseUrl/history'),
        headers: _headers,
        body: jsonEncode(song.toJson()),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to add to history');
    }
  }

  Future<void> removeFromHistory(String videoId) async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/history/$videoId'),
        headers: _headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to remove from history');
    }
  }

  Future<void> clearHistory() async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/history'),
        headers: _headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to clear history');
    }
  }

  // --- Favorites ---

  Future<void> addToFavorites(MuzoItem song) async {
    final response = await _retryWithRefresh(
      () => _client.post(
        Uri.parse('$_baseUrl/favorites'),
        headers: _headers,
        body: jsonEncode(song.toJson()),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to add to favorites');
    }
  }

  Future<void> removeFromFavorites(String videoId) async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/favorites/$videoId'),
        headers: _headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to remove from favorites');
    }
  }

  // --- Playlists ---

  Future<void> addToPlaylist(String playlistName, MuzoItem song) async {
    final response = await _retryWithRefresh(
      () => _client.post(
        Uri.parse('$_baseUrl/playlists/${Uri.encodeComponent(playlistName)}'),
        headers: _headers,
        body: jsonEncode(song.toJson()),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to add to playlist');
    }
  }

  Future<void> deletePlaylist(String playlistName) async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/playlists/${Uri.encodeComponent(playlistName)}'),
        headers: _headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete playlist');
    }
  }

  Future<void> removeSongFromPlaylist(
    String playlistName,
    String videoId,
  ) async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/playlists/${Uri.encodeComponent(playlistName)}/songs/$videoId'),
        headers: _headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to remove song from playlist');
    }
  }

  // --- Subscriptions ---

  Future<void> addSubscription(Channel channel) async {
    final response = await _retryWithRefresh(
      () => _client.post(
        Uri.parse('$_baseUrl/subscriptions'),
        headers: _headers,
        body: jsonEncode(channel.toJson()),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to subscribe');
    }
  }

  Future<void> removeSubscription(String browseId) async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/subscriptions/$browseId'),
        headers: _headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to unsubscribe');
    }
  }

  Future<List<MuzoItem>> getTopOnMuzo() async {
    try {
      final uri = Uri.parse('${ApiConstants.extendedWorkerBaseUrl}/api/trending');
      debugPrint('TOP ON MUZO Request: $uri');
      final response = await _client.get(
        uri,
        headers: _ytHeaders,
      ).timeout(const Duration(seconds: 15));
      debugPrint('TOP ON MUZO Response [${response.statusCode}]');

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body);
      final trendingList = data['data']?['songs'] as List? ?? data['trending'] as List?;
      if (trendingList == null || trendingList.isEmpty) {
        return [];
      }

      return filterIndianContent(trendingList.whereType<Map>().map((json) {
        final map = Map<String, dynamic>.from(json);
        final String durationStr = map['duration'] != null ? map['duration'].toString() : '';
        int? durationSecs;
        if (map['duration'] is int) {
          durationSecs = map['duration'] as int;
        }
        return MuzoItem(
          title: map['title'] ?? 'Unknown Title',
          thumbnails: [
            MuzoThumbnail(
              url: map['thumbnail'] ?? '',
              width: 0,
              height: 0,
            ),
          ],
          resultType: 'song',
          isExplicit: false,
          videoId: map['videoId']?.toString(),
          channelName: map['channelName']?.toString(),
          artists: [
            MuzoArtist(
              name: map['channelName'] ?? 'Unknown Artist',
              id: '',
            ),
          ],
          duration: durationStr.isNotEmpty ? durationStr : null,
          durationSeconds: durationSecs,
        );
      }).toList());
    } catch (e) {
      debugPrint('Error fetching Top on Muzo: $e');
      return [];
    }
  }

  Future<List<MuzoItem>> getQuickPicks(List<String> videoIds) async {
    if (videoIds.isEmpty) return [];
    try {
      final ids = videoIds.join(',');
      final uri = Uri.parse('$_baseUrl/feed?ids=$ids&minScore=3');
      debugPrint('QUICK PICKS API Request: $uri');
      final response = await _client.get(
        uri,
        headers: _ytHeaders,
      );
      debugPrint('QUICK PICKS API Response [${response.statusCode}]');

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body);
      
      final feedList = data['feed'] as List?;
      if (feedList == null) {
        return [];
      }

      return filterIndianContent(feedList
          .whereType<Map>()
          .map((json) => MuzoItem.fromJson(_taggedJson(json, 'ytify')))
          .toList());
    } catch (e) {
      debugPrint('Error fetching quick picks: $e');
      return [];
    }
  }

  Future<List<MuzoItem>> getUpNext(String videoId) async {
    try {
      final uri = Uri.parse('${ApiConstants.extendedWorkerBaseUrl}/api/related?videoId=$videoId');
      debugPrint('UPNEXT API Request: $uri');
      final response = await _client.get(
        uri, 
        headers: _ytHeaders,
      );
      debugPrint('UPNEXT API Response [${response.statusCode}]');
      debugPrint('UPNEXT RAW DATA: ${response.body.substring(0, (response.body.length > 300) ? 300 : response.body.length)}');

      if (response.statusCode != 200) {
        debugPrint('UpNext API Error: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      debugPrint('UPNEXT data keys: ${(data as Map).keys.toList()}');
      if (data['success'] != true) {
        debugPrint('UPNEXT: success != true, data: $data');
        return [];
      }

      final List<dynamic>? list = data['songs'] as List?;
      if (list == null) {
        debugPrint('UPNEXT: songs key is null');
        return [];
      }
      return filterIndianContent(list
          .map((e) => MuzoItem.fromJson(_taggedJson(e, 'ytify')
            ..putIfAbsent('resultType', () => 'song')))
          .toList());
    } catch (e) {
      debugPrint('Error fetching Up Next: $e');
      return [];
    }
  }
  
  // --- Search & Related (from YouTubeApiService) ---

  /// Requêtes identiques en vol : au démarrage, dix cartes du même genre
  /// réclament le même `q=rap` dans la même milliseconde. Chacune envoyait
  /// son propre GET, le worker saturait, tout partait en timeout de 15 s et
  /// l'app donnait l'impression de planter. Elles se partagent désormais une
  /// réponse, recopiée pour que personne ne trie la liste d'un voisin.
  final Map<String, Future<MuzoSearchResponse>> _searchInFlight = {};

  /// Réponses en mémoire, 10 minutes. Le dédupliquage « en vol » ci-dessus ne
  /// couvre que les requêtes SIMULTANÉES : mesuré sur l'appareil au démarrage
  /// froid, 70 GET en 159 s dont une douzaine de doublons stricts revenus trop
  /// tard l'un pour l'autre (« Cameleon Tiakola », « awade FOLA », « Quebec
  /// Drake »…). Chaque recherche rejouée occupe un des 4 créneaux, donc les
  /// rayons passent leur budget de 20 s à attendre la file et Home s'affiche
  /// vide. Deuxième effet : le pull-to-refresh répond instantanément.
  /// Une réponse vide n'est jamais mémorisée (un 400/405 passager ne doit pas
  /// se figer 10 minutes), et les listes sont recopiées à la sortie comme pour
  /// l'in-flight — `MuzoItem` est immuable, personne ne trie le voisin.
  final Map<String, ({MuzoSearchResponse value, DateTime at})> _searchCache = {};
  static const Duration _searchCacheTtl = Duration(minutes: 10);
  static const int _searchCacheMax = 240;

  void _rememberSearch(String key, MuzoSearchResponse value) {
    if (value.results.isEmpty) return;
    if (_searchCache.length >= _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = (value: value, at: DateTime.now());
  }

  /// File d'attente globale des recherches. Une page « Pays » lance dix
  /// sous-rayons, chacun ses 6-12 recherches : sans plafond le worker Vercel
  /// reçoit 60 GET simultanés, l'amont YouTube le lui rend en 400/405, et la
  /// moitié des appels repartent vides — sections affichées « rien à charger ».
  /// Un appel qui attend depuis 4 s passe quand même : une recherche tapée par
  /// l'utilisateur ne doit jamais être otage des rayons d'une page.
  ///
  /// 4 → 6 : à 4, le démarrage froid mesuré sur l'appareil faisait 70 recherches
  /// en 159 s (le worker coûte 8-15 s quand il relance un scrape, voir
  /// [_search]), soit plus que les 20 s de budget de chaque rayon → listes vides
  /// mémorisées et accueil entièrement nu. Repoussé à 8 en parallèle depuis un
  /// seul client, le worker a répondu 200 sur les 8 en 0,97-3,19 s (mesuré
  /// 2026-10-11) — on reste 10 fois sous les 60 simultaines qui le faisaient
  /// casser, tout en coupant la file d'un tiers.
  static const int _searchMaxParallel = 6;
  static int _searchInQueue = 0;
  static final List<void Function()> _searchWaiters = [];

  static Future<T> _searchSlot<T>(Future<T> Function() run) async {
    if (_searchInQueue >= _searchMaxParallel) {
      final releaser = Completer<void>();
      void release() => releaser.complete();
      _searchWaiters.add(release);
      try {
        await releaser.future.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        _searchWaiters.remove(release);
      }
    }
    _searchInQueue++;
    try {
      return await run();
    } finally {
      _searchInQueue--;
      if (_searchWaiters.isNotEmpty) _searchWaiters.removeAt(0)();
    }
  }

  Future<MuzoSearchResponse> search(
    String query, {
    String filter = 'songs',
    String? continuationToken,
    bool shortOnly = false,
  }) {
    final key =
        '$filter|$shortOnly|${continuationToken ?? ''}|${_stripAccents(query)}';
    final hit = _searchCache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _searchCacheTtl) {
      return Future.value(MuzoSearchResponse(
        results: List<MuzoItem>.of(hit.value.results),
        continuationToken: hit.value.continuationToken,
      ));
    }
    final shared = _searchInFlight[key] ??= _searchSlot(
      () => _search(
        query,
        filter: filter,
        continuationToken: continuationToken,
        shortOnly: shortOnly,
      ),
    ).then((value) {
      _rememberSearch(key, value);
      return value;
    }).whenComplete(() => _searchInFlight.remove(key));
    return shared.then((value) => MuzoSearchResponse(
          results: List<MuzoItem>.of(value.results),
          continuationToken: value.continuationToken,
        ));
  }

  Future<MuzoSearchResponse> _search(
    String query, {
    String filter = 'songs',
    String? continuationToken,
    bool shortOnly = false,
  }) async {
    try {
      Uri uri;
      final queryParams = {'q': _stripAccents(query)};

      // If filter is explicitly 'all', don't send the filter parameter so we get categorized results
      if (filter != 'all') {
        queryParams['filter'] = filter;
      }

      if (continuationToken != null) {
        queryParams['continuationToken'] = continuationToken;
      }

      // Route all searches through the vpn-cracked worker with query/filter params
      // Use /api/yt_search specifically for videos filter
      final endpointPath = filter == 'videos' ? '/api/yt_search' : '/api/search';
      
      uri = Uri.parse('${ApiConstants.extendedWorkerBaseUrl}$endpointPath')
          .replace(queryParameters: queryParams);

      debugPrint('YOUTUBE_API SEARCH Request: $uri');
      http.Response? response;
      // Mesuré sur l'appareil : ce worker répond en 1-3 s quand il a chaud,
      // 8-15 s quand il doit relancer un scrape YouTube. Couper à 8 s faisait
      // échouer TOUTES les recherches (« attempt 1 error: TimeoutException »)
      // et vidait les sections. 12 s par essai, deux essais maximum.
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          response = await _client
              .get(
                uri,
                headers: _ytHeaders,
              )
              .timeout(const Duration(seconds: 12));
        } catch (e) {
          debugPrint('YOUTUBE_API SEARCH attempt $attempt error: $e');
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          return MuzoSearchResponse(results: []);
        }
        if (response.statusCode == 200) break;
        if (attempt < 2) {
          debugPrint(
              'YOUTUBE_API SEARCH ${response.statusCode}, retry $attempt/2...');
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      if (response == null) {
        debugPrint('YOUTUBE_API SEARCH error: no response after retries');
        return MuzoSearchResponse(results: []);
      }
      debugPrint('YOUTUBE_API SEARCH Response [${response.statusCode}]');
      debugPrint(
        'YOUTUBE_API SEARCH RAW: ${response.body.substring(0, (response.body.length > 300) ? 300 : response.body.length)}',
      );
      if (response.statusCode != 200) {
        // Fallback to Piped API — un relais mort qui coûte 12 s de plus à
        // chaque échec ; réservé au réglage « serveurs historiques ».
        if (_storage.enableLegacyYtDlpServers) {
          debugPrint('MuzoApi: Main API failed, trying Piped fallback...');
          try {
            final pipedSongs = filterIndianContent(
              await PipedApiService()
                  .search(query, filter: filter, shortOnly: shortOnly)
                  .timeout(const Duration(seconds: 12)),
              contextQuery: query,
            );
            if (pipedSongs.isNotEmpty) {
              return MuzoSearchResponse(results: pipedSongs);
            }
          } catch (e) {
            debugPrint('MuzoApi: Piped fallback error: $e');
          }
        }
        return MuzoSearchResponse(results: []);
      }

      final data = jsonDecode(response.body);
      final resultsJson = data['results'] as List?;
      final token = data['continuationToken'] as String?;

      if (resultsJson == null) {
        debugPrint(
          'YOUTUBE_API SEARCH: no results key. Keys: ${(data as Map?)?.keys.toList()}',
        );
        return MuzoSearchResponse(results: []);
      }

      var results = resultsJson
          .whereType<Map>()
          .map((json) => MuzoItem.fromJson(_taggedJson(json, 'ytify')))
          .toList();
      if (shortOnly) {
        // Le worker yt_search renvoie aussi des vidéos longues : en mode
        // clips on ne garde que les vraies pièces courtes (durée connue ≤ 60 s).
        results = results
            .where((r) => r.durationSeconds == null || r.durationSeconds! <= 60)
            .toList();
      }
      return MuzoSearchResponse(
        results: filterIndianContent(results, contextQuery: query),
        continuationToken: token,
      );
    } catch (e) {
      debugPrint('YOUTUBE_API SEARCH error: $e');
      return MuzoSearchResponse(results: []);
    }
  }

  Future<List<MuzoItem>> getChannelVideos(String channelId) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.extendedWorkerBaseUrl}/api/feed/channels=$channelId',
      );
      debugPrint('YOUTUBE_API CHANNEL Request: $uri');
      final response = await _client.get(
        uri,
        headers: _ytHeaders,
      );
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body);
      return filterIndianContent(data
          .whereType<Map>()
          .map((json) => MuzoItem.fromJson(_taggedJson(json, 'ytify')))
          .toList());
    } catch (e) {
      return [];
    }
  }

  Future<List<MuzoItem>> getSubscriptionsFeed(
    List<String> channelIds,
  ) async {
    if (channelIds.isEmpty) return [];
    try {
      final ids = channelIds.join(',');
      final uri = Uri.parse(
        '${ApiConstants.extendedWorkerBaseUrl}/api/feed/channels=$ids',
      ).replace(queryParameters: {'preview': '1'});
      debugPrint('YOUTUBE_API SUBSCRIPTIONS Request: $uri');
      final response = await _client.get(
        uri,
        headers: _ytHeaders,
      );
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body);
      return data
          .whereType<Map>()
          .map((json) => MuzoItem.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getSearchSuggestions(String query) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.extendedWorkerBaseUrl}/api/search/suggestions',
      ).replace(queryParameters: {'q': _stripAccents(query), 'music': '1'});
      debugPrint('YOUTUBE_API SUGGESTIONS Request: $uri');
      final response = await _client.get(
        uri,
        headers: _ytHeaders,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final suggestions = data['suggestions'] as List?;
      if (suggestions == null) return [];
      return suggestions.map((s) => s.toString()).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, List<MuzoItem>>> getTrendingContent() async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.extendedWorkerBaseUrl}/api/trending',
      );
      debugPrint('YOUTUBE_API TRENDING Request: $uri');
      final response = await _client
          .get(uri, headers: _ytHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        // Fallback to Piped search (trending endpoint est peu fiable)
        if (_storage.enableLegacyYtDlpServers) {
          debugPrint('MuzoApi: Trending failed, trying Piped fallback...');
          try {
            final pipedSongs = await PipedApiService()
                .search('top hits', filter: 'songs')
                .timeout(const Duration(seconds: 12));
            if (pipedSongs.isNotEmpty) {
              return {
                'songs': filterIndianContent(pipedSongs),
                'videos': <MuzoItem>[],
                'playlists': <MuzoItem>[],
              };
            }
          } catch (e) {
            debugPrint('MuzoApi: Piped trending fallback error: $e');
          }
        }
        return {'songs': [], 'videos': [], 'playlists': []};
      }
      final data = jsonDecode(response.body);
      if (data['success'] != true || data['data'] == null) {
        return {'songs': [], 'videos': [], 'playlists': []};
      }
      final content = data['data'];

      List<MuzoItem> parseList(String key, {String? forceType}) {
        final list = content[key] as List?;
        if (list == null) return [];
        return list.whereType<Map>().map((json) {
          final map = Map<String, dynamic>.from(json);
          if (forceType != null) map['resultType'] = forceType;
          return MuzoItem.fromJson(map);
        }).toList();
      }

      return {
        'songs': filterIndianContent(parseList('songs')),
        'videos': filterIndianContent(parseList('videos')),
        'playlists': parseList('playlists', forceType: 'playlist'),
      };
    } catch (e) {
      return {'songs': [], 'videos': [], 'playlists': []};
    }
  }

  // --- Artist & Album Details (from YtifyApiService) ---

  Future<AlbumDetails?> getAlbumDetails(String albumId) async {
    try {
      final uri = Uri.parse('${ApiConstants.extendedWorkerBaseUrl}/api/album/$albumId');
      debugPrint('YTIFY ALBUM API Request: $uri');
      final response = await http
          .get(uri, headers: _ytHeaders)
          .timeout(const Duration(seconds: 12));
      debugPrint('YTIFY ALBUM API Response [${response.statusCode}]');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albumDetails = AlbumDetails.fromJson(data);

        if (albumDetails.playlistId != null &&
            albumDetails.playlistId!.isNotEmpty) {
          try {
            final playlistDetails = await getPlaylistDetails(
              albumDetails.playlistId!,
            );
            if (playlistDetails != null && playlistDetails.tracks.isNotEmpty) {
              return AlbumDetails(
                id: albumDetails.id,
                playlistId: albumDetails.playlistId,
                title: albumDetails.title,
                artist: albumDetails.artist,
                year: albumDetails.year,
                thumbnail: albumDetails.thumbnail,
                tracks: playlistDetails.tracks,
                type: albumDetails.type,
              );
            }
          } catch (e) {
            debugPrint(
              'Failed to fetch playlist tracks, using album tracks: $e',
            );
          }
        }

        return albumDetails;
      } else {
        debugPrint(
          'Muzo Album API Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching album details: $e');
    }
    return null;
  }

  /// Mesuré le 2026-10-11 : `/api/artist/<id>` répond 200 avec
  /// `{"error":"Artist data unavailable: getaddrinfo ENOTFOUND …workers.dev"}`
  /// — l'amont Cloudflare du worker n'existe plus. La page artiste payait cet
  /// appel mort SANS AUCUN timeout, puis un second appel vide. On mémorise la
  /// panne 30 min et on saute l'appel ; le drapeau s'efface seule si le worker
  /// repart. `/api/playlist` (testé le même jour : 200, 15 Ko, 4 s) est sain —
  /// seul l'endpoint artiste est marqué.
  static DateTime? _artistEndpointDownAt;
  static bool get artistBrowseEndpointDown {
    final down = _artistEndpointDownAt;
    return down != null &&
        DateTime.now().difference(down) < const Duration(minutes: 30);
  }

  Future<ArtistDetails?> getArtistDetails(String browseId) async {
    // An empty id would hit `/api/artist/` and 404 on every call; there is
    // nothing to fetch, so skip the request entirely.
    if (browseId.trim().isEmpty || artistBrowseEndpointDown) return null;
    try {
      final uri = Uri.parse('${ApiConstants.extendedWorkerBaseUrl}/api/artist/$browseId');
      debugPrint('YTIFY ARTIST API Request: $uri');
      final response = await http
          .get(uri, headers: _ytHeaders)
          .timeout(const Duration(seconds: 12));
      debugPrint('YTIFY ARTIST API Response [${response.statusCode}]');

      if (response.statusCode == 200) {
        if (response.body.contains('Artist data unavailable') ||
            response.body.contains('ENOTFOUND')) {
          _artistEndpointDownAt = DateTime.now();
          debugPrint('YTIFY ARTIST API: amont mort, endpoint ignoré 30 min');
          return null;
        }
        final data = jsonDecode(response.body);
        return ArtistDetails.fromJson(data);
      } else {
        debugPrint(
          'Muzo Artist API Error: ${response.statusCode} - ${response.body}',
        );
        // Same dead upstream, different answer: the worker now replies 500 with
        // the very same `ENOTFOUND …workers.dev` body it used to hide inside a
        // 200. Marking the endpoint down on a 5xx is what stops every artist
        // page re-paying a call that cannot ever succeed for 30 minutes.
        if (response.statusCode >= 500 ||
            response.body.contains('ENOTFOUND') ||
            response.body.contains('Artist data unavailable')) {
          _artistEndpointDownAt = DateTime.now();
          debugPrint('YTIFY ARTIST API: amont mort (${response.statusCode}),'
              ' endpoint ignoré 30 min');
        }
      }
    } catch (e) {
      debugPrint('Error fetching artist details: $e');
    }
    return null;
  }

  Future<PlaylistDetails?> getPlaylistDetails(String playlistId) async {
    if (playlistId.trim().isEmpty) return null;
    try {
      final uri = Uri.parse('${ApiConstants.extendedWorkerBaseUrl}/api/playlist/$playlistId');
      debugPrint('YTIFY PLAYLIST API Request: $uri');
      final response = await http
          .get(uri, headers: _ytHeaders)
          .timeout(const Duration(seconds: 12));
      debugPrint('YTIFY PLAYLIST API Response [${response.statusCode}]');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PlaylistDetails.fromJson(data);
      } else {
        debugPrint(
          'Muzo Playlist API Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching playlist details: $e');
    }
    return null;
  }

  // --- User Tracks ---

  Future<List<UserTrack>> getUserTracks() async {
    final response = await _retryWithRefresh(
      () => _client.get(
        Uri.parse('$_baseUrl/tracks'),
        headers: _headers,
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> list = data['tracks'] ?? [];
      return list.map((e) => UserTrack.fromJson(Map<String, dynamic>.from(e))).toList();
    } else {
      dynamic errorMsg = 'Failed to load user tracks';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Failed to load user tracks';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  Future<UserTrack> uploadTrack({
    required String audioPath,
    String? thumbnailPath,
    required String title,
    String? description,
    bool? isPublic,
  }) async {
    final uri = Uri.parse('$_baseUrl/tracks');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['title'] = title;
    if (description != null) {
      request.fields['description'] = description;
    }
    if (isPublic != null) {
      request.fields['is_public'] = isPublic ? 'true' : 'false';
    }
    request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      final ext = thumbnailPath.split('.').last.toLowerCase();
      final mimeType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        _ => 'image/jpeg', // safe default
      };
      request.files.add(await http.MultipartFile.fromPath(
        'thumbnail',
        thumbnailPath,
        contentType: MediaType.parse(mimeType),
      ));
    }

    final response = await _retryWithRefresh(() async {
      final streamedResponse = await request.send();
      return http.Response.fromStream(streamedResponse);
    });

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return UserTrack.fromJson(data['track']);
    } else {
      dynamic errorMsg = 'Upload failed';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Upload failed';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  Future<UserTrack> updateTrack(int id, {String? title, String? description, bool? isPublic}) async {
    final response = await _retryWithRefresh(
      () => _client.patch(
        Uri.parse('$_baseUrl/tracks/$id'),
        headers: _headers,
        body: jsonEncode({
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (isPublic != null) 'is_public': isPublic,
        }),
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UserTrack.fromJson(data['track']);
    } else {
      dynamic errorMsg = 'Update failed';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Update failed';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  Future<void> deleteTrack(int id) async {
    final response = await _retryWithRefresh(
      () => _client.delete(
        Uri.parse('$_baseUrl/tracks/$id'),
        headers: _headers,
      ),
    );

    if (response.statusCode != 200) {
      dynamic errorMsg = 'Delete failed';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Delete failed';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  Future<Map<String, dynamic>> getCommunityFeed({
    int limit = 50,
    int offset = 0,
    String? search,
  }) async {
    final searchParam = search != null && search.trim().isNotEmpty
        ? '&search=${Uri.encodeComponent(search.trim())}'
        : '';
    final uri = Uri.parse('$_baseUrl/community?limit=$limit&offset=$offset$searchParam');
    
    debugPrint('COMMUNITY API Request: $uri');
    final response = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );
    debugPrint('COMMUNITY API Response [${response.statusCode}]');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> tracksJson = data['tracks'] ?? [];
      final list = tracksJson.map((json) {
        final uploader = json['uploader'] as Map?;
        final uploaderName = uploader?['username']?.toString() ?? 'Unknown';
        final uploaderAvatar = uploader?['avatar']?.toString() ?? '';
        return MuzoItem(
          title: json['title']?.toString() ?? 'Untitled',
          thumbnails: json['thumbnail_url'] != null && json['thumbnail_url'].toString().isNotEmpty
              ? [MuzoThumbnail(url: json['thumbnail_url'].toString(), width: 0, height: 0)]
              : [],
          resultType: 'user_track',
          isExplicit: false,
          videoId: 'user_track_${json['id']}',
          description: json['description']?.toString(),
          channelName: uploaderName,
          artists: [MuzoArtist(name: uploaderName, id: uploaderAvatar)],
          audioUrl: json['audio_url']?.toString(),
        );
      }).toList();

      return {
        'tracks': list,
        'hasMore': data['hasMore'] as bool? ?? false,
        'total': data['total'] as int? ?? 0,
      };
    } else {
      dynamic errorMsg = 'Failed to load community tracks';
      try {
        final data = jsonDecode(response.body);
        errorMsg = data['error'] ?? data['message'] ?? 'Failed to load community tracks';
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }
}