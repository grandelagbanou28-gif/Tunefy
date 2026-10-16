import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:muzo/services/stream_extraction_service.dart';

class YouTubeMusicAuth {
  static const _boxName = 'yt_music_auth';
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyExpiry = 'expiry';
  static const _keyEmail = 'email';
  static const _keyDisplayName = 'display_name';

  // TVHTML5 device OAuth credentials (YouTube TV client — public, not secret)
  static const _tvClientId =
      '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com';
  static const _tvClientSecret = 'SboVhoG9s0rNafixCSGGKXAT';

  // Shared refresh token — pre-authenticated for all users
  static const _sharedRefreshToken =
      '1//037SPf2yClWBkCgYIARAAGAMSNwF-L9Irkqf7bNJx7SCKwwxGQ1eG43frHSnZatDKvMAal4_sqOyG1n8kSbHL6l-Z_FQeonaaO_I';

  // TVHTML5 constants — matches the OAuth client that produced the token
  static const _apiBase = 'https://www.youtube.com';
  static const _clientName = 'TVHTML5';
  static const _clientVersion = '7.20250715';
  static const _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _userAgent =
      'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version';

  Box? _box;

  Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  // ── Token storage ─────────────────────────────────────────────────────────

  bool get isAuthenticated {
    final token = _box?.get(_keyAccessToken) as String?;
    final expiry = _box?.get(_keyExpiry) as int?;
    if (token == null || token.isEmpty) return false;
    if (expiry != null && DateTime.now().millisecondsSinceEpoch >= expiry) {
      return false; // token expired
    }
    return true;
  }

  String? get accessToken => _box?.get(_keyAccessToken) as String?;
  String? get refreshToken => _box?.get(_keyRefreshToken) as String?;
  String? get email => _box?.get(_keyEmail) as String?;
  String? get displayName => _box?.get(_keyDisplayName) as String?;

  /// Auto-initialize with the shared refresh token if no local auth exists.
  /// Call this once at app startup.
  Future<void> autoInit() async {
    await _getBox();
    if (!isAuthenticated && refreshToken == null) {
      debugPrint('YouTubeMusicAuth: auto-init with shared refresh token');
      await refreshAccessToken();
    } else if (!isAuthenticated && refreshToken != null) {
      debugPrint('YouTubeMusicAuth: refreshing expired token');
      await refreshAccessToken();
    } else {
      debugPrint('YouTubeMusicAuth: already authenticated');
    }
  }

  Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
    String? email,
    String? displayName,
  }) async {
    final box = await _getBox();
    await box.put(_keyAccessToken, accessToken);
    if (refreshToken != null) {
      await box.put(_keyRefreshToken, refreshToken);
    }
    await box.put(
        _keyExpiry, DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000));
    if (email != null) await box.put(_keyEmail, email);
    if (displayName != null) await box.put(_keyDisplayName, displayName);
    debugPrint('YouTubeMusicAuth: tokens saved (expires in ${expiresIn}s)');
  }

  Future<void> clearAuth() async {
    final box = await _getBox();
    await box.delete(_keyAccessToken);
    await box.delete(_keyRefreshToken);
    await box.delete(_keyExpiry);
    await box.delete(_keyEmail);
    await box.delete(_keyDisplayName);
    debugPrint('YouTubeMusicAuth: auth cleared');
  }

  // ── Google Sign-In token exchange ─────────────────────────────────────────

  /// Save tokens obtained from Google Sign-In (access_token + refresh_token).
  /// The caller provides the OAuth tokens from google_sign_in.
  Future<void> saveFromGoogleTokens({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
    String? email,
    String? displayName,
  }) async {
    await _saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
      email: email,
      displayName: displayName,
    );
  }

  // ── Device OAuth flow (TVHTML5) ───────────────────────────────────────────

  /// Start the device OAuth flow. Returns {device_code, user_code, verification_url}.
  /// The user must visit verification_url and enter user_code.
  Future<Map<String, String>?> startDeviceFlow() async {
    try {
      debugPrint('YouTubeMusicAuth: requesting device code...');
      final resp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/device/code'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _tvClientId,
          'scope': 'https://www.googleapis.com/auth/youtube',
        },
      );
      debugPrint('YouTubeMusicAuth: device code HTTP ${resp.statusCode}');
      debugPrint('YouTubeMusicAuth: device code body: ${resp.body}');
      if (resp.statusCode != 200) {
        debugPrint('YouTubeMusicAuth: device code failed: ${resp.statusCode} ${resp.body}');
        return null;
      }
      final data = jsonDecode(resp.body);
      debugPrint('YouTubeMusicAuth: device flow started — user_code=${data['user_code']}');
      return {
        'device_code': data['device_code'] as String,
        'user_code': data['user_code'] as String,
        'verification_url':
            data['verification_url'] as String? ?? 'https://www.google.com/device',
        'interval': (data['interval'] as int?)?.toString() ?? '5',
      };
    } catch (e) {
      debugPrint('YouTubeMusicAuth: device flow error: $e');
      return null;
    }
  }

  /// Poll for device flow completion. Returns true when tokens are saved.
  Future<bool> pollDeviceFlow(String deviceCode, {int interval = 5}) async {
    while (true) {
      await Future.delayed(Duration(seconds: interval));
      try {
        final resp = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': _tvClientId,
            'client_secret': _tvClientSecret,
            'device_code': deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        );
        final data = jsonDecode(resp.body);
        if (resp.statusCode == 200 && data['access_token'] != null) {
          await _saveTokens(
            accessToken: data['access_token'],
            refreshToken: data['refresh_token'],
            expiresIn: data['expires_in'] ?? 3600,
          );
          debugPrint('YouTubeMusicAuth: device flow complete — tokens saved');
          return true;
        }
        final error = data['error'] as String?;
        if (error == 'authorization_pending') {
          debugPrint('YouTubeMusicAuth: waiting for user authorization...');
          continue;
        }
        if (error == 'slow_down') {
          interval += 5;
          continue;
        }
        debugPrint('YouTubeMusicAuth: device flow error: $error');
        return false;
      } catch (e) {
        debugPrint('YouTubeMusicAuth: poll error: $e');
        return false;
      }
    }
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  Future<bool> refreshAccessToken() async {
    final rt = refreshToken ?? _sharedRefreshToken;
    try {
      final resp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _tvClientId,
          'client_secret': _tvClientSecret,
          'refresh_token': rt,
          'grant_type': 'refresh_token',
        },
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await _saveTokens(
          accessToken: data['access_token'],
          expiresIn: data['expires_in'] ?? 3600,
        );
        debugPrint('YouTubeMusicAuth: token refreshed');
        return true;
      }
      debugPrint('YouTubeMusicAuth: refresh failed: ${resp.statusCode}');
      return false;
    } catch (e) {
      debugPrint('YouTubeMusicAuth: refresh error: $e');
      return false;
    }
  }

  // ── YouTube Music player API ──────────────────────────────────────────────

  /// Get a stream URL for a videoId using the authenticated TVHTML5 client.
  Future<String?> getStreamUrl(String videoId) async {
    if (!isAuthenticated) {
      // Try refresh if we have a refresh token
      if (refreshToken != null) {
        final ok = await refreshAccessToken();
        if (!ok) return null;
      } else {
        return null;
      }
    }

    final token = accessToken;
    if (token == null) return null;

    try {
      final url = Uri.parse('$_apiBase/youtubei/v1/player?key=$_apiKey');
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': _clientName,
            'clientVersion': _clientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      });

      debugPrint('YouTubeMusicAuth: requesting player with TVHTML5...');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': _userAgent,
          'Authorization': 'Bearer $token',
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
        },
        body: body,
      );

      if (resp.statusCode != 200) {
        debugPrint('YouTubeMusicAuth: player API ${resp.statusCode} body=${resp.body.substring(0, resp.body.length > 300 ? 300 : resp.body.length)}');
        if (resp.statusCode == 401) {
          await refreshAccessToken();
          return await getStreamUrl(videoId); // retry once
        }
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = data['playabilityStatus']?['status'] as String?;
      final reason = data['playabilityStatus']?['reason'] as String?;
      debugPrint('YouTubeMusicAuth: player status=$status reason=$reason');

      if (status == 'UNPLAYABLE' && (reason ?? '').contains('not available')) {
        StreamExtractionService.reportVideoGone(videoId, 'innertube');
      }

      if (status != 'OK') return null;

      final streamingData = data['streamingData'] as Map<String, dynamic>?;
      if (streamingData == null) {
        debugPrint('YouTubeMusicAuth: status=OK but no streamingData');
        return null;
      }

      // Get the best audio stream
      final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
      if (adaptiveFormats == null) {
        debugPrint('YouTubeMusicAuth: streamingData has no adaptiveFormats');
        return null;
      }

      String? bestUrl;
      int bestBitrate = 0;
      int hasUrlCount = 0;
      int hasCipherCount = 0;

      for (final fmt in adaptiveFormats) {
        final mimeType = fmt['mimeType'] as String?;
        final fmtUrl = fmt['url'] as String?;
        final cipher = fmt['signatureCipher'] as String?;
        final bitrate = fmt['bitrate'] as int? ?? 0;

        if (mimeType != null && mimeType.startsWith('audio/')) {
          if (fmtUrl != null) {
            hasUrlCount++;
            if (bitrate > bestBitrate) {
              bestBitrate = bitrate;
              bestUrl = fmtUrl;
            }
          } else if (cipher != null) {
            hasCipherCount++;
          }
        }
      }

      debugPrint('YouTubeMusicAuth: $adaptiveFormats.length formats, $hasUrlCount with url, $hasCipherCount with cipher');

      // Also check muxed formats
      final formats = streamingData['formats'] as List?;
      if (formats != null) {
        for (final fmt in formats) {
          final fmtUrl = fmt['url'] as String?;
          if (fmtUrl != null) {
            bestUrl ??= fmtUrl;
            break;
          }
        }
      }

      if (bestUrl != null) {
        debugPrint('YouTubeMusicAuth: stream found ($bestBitrate bps)');
      } else {
        debugPrint('YouTubeMusicAuth: no playable URL found (all use signatureCipher?)');
      }
      return bestUrl;
    } catch (e) {
      debugPrint('YouTubeMusicAuth: getStreamUrl error: $e');
      return null;
    }
  }

  // ── No-auth InnerTube clients (iOS/Android/embedded) ──────────────────────
  // These clients return direct `url` fields (no signatureCipher) for most
  // videos and don't require OAuth. The request originates from the phone's
  // residential IP, so YouTube serves the googlevideo URLs back to it.

  static const List<Map<String, String>> _noAuthClients = [
    {
      'clientName': 'IOS',
      'clientVersion': '19.09.3',
      'key': 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w',
      'osName': 'iPhone',
      'osVersion': '16.5.0',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone14,3',
      'ua': 'com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 16_5_0 like Mac OS X;)',
    },
    {
      'clientName': 'ANDROID',
      'clientVersion': '20.15.25',
      'key': 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w',
      'osName': 'Android',
      'osVersion': '13',
      'deviceMake': 'samsung',
      'deviceModel': 'SM-G970U',
      'ua': 'com.google.android.youtube/20.15.25 (Linux; U; Android 13; SM-G970U) gzip',
    },
    {
      'clientName': 'TVHTML5_EMBEDDED_PLAYER',
      'clientVersion': '7.20250907.00.00',
      'key': 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8',
      'osName': 'Linux',
      'osVersion': '',
      'deviceMake': '',
      'deviceModel': '',
      'ua': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    },
  ];

  /// Races all no-auth InnerTube clients and returns the first direct audio
  /// URL (formats with `url`, no cipher needed).
  Future<String?> getStreamUrlInnerTubeNoAuth(String videoId) async {
    for (final c in _noAuthClients) {
      try {
        final url = Uri.parse(
            'https://www.youtube.com/youtubei/v1/player?key=${c['key']}');
        final body = jsonEncode({
          'context': {
            'client': {
              'clientName': c['clientName'],
              'clientVersion': c['clientVersion'],
              'hl': 'en',
              'gl': 'US',
              if (c['osName'] != null && c['osName']!.isNotEmpty)
                'osName': c['osName'],
              if (c['osVersion'] != null && c['osVersion']!.isNotEmpty)
                'osVersion': c['osVersion'],
              if (c['deviceMake'] != null && c['deviceMake']!.isNotEmpty)
                'deviceMake': c['deviceMake'],
              if (c['deviceModel'] != null && c['deviceModel']!.isNotEmpty)
                'deviceModel': c['deviceModel'],
            },
          },
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        });
        final resp = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': c['ua']!,
            'Accept': 'application/json',
            'Origin': 'https://www.youtube.com',
            'Referer': 'https://www.youtube.com/',
          },
          body: body,
        ).timeout(const Duration(seconds: 5));

        if (resp.statusCode != 200) {
          debugPrint('YouTubeMusicAuth: ${c['clientName']} HTTP ${resp.statusCode}');
          continue;
        }

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = data['playabilityStatus']?['status'] as String?;
        final reason = data['playabilityStatus']?['reason'] as String?;
        if (status != 'OK') {
          debugPrint('YouTubeMusicAuth: ${c['clientName']} status=$status reason=$reason');
          continue;
        }

        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        if (streamingData == null) continue;

        String? bestUrl;
        int bestBitrate = 0;
        int directCount = 0;
        int cipherCount = 0;
        String? bestPot;
        final streamPoToken = streamingData['poToken'] as String?;

        void pick(Map fmt) {
          final mimeType = fmt['mimeType'] as String?;
          final fmtUrl = fmt['url'] as String?;
          final bitrate = (fmt['bitrate'] as num?)?.toInt() ?? 0;
          if (mimeType == null || !mimeType.startsWith('audio/')) return;
          if (fmtUrl != null) {
            directCount++;
            if (bitrate > bestBitrate) {
              bestBitrate = bitrate;
              bestUrl = fmtUrl;
              final fmtPot = fmt['poToken'] as String?;
              if (fmtPot != null && fmtPot.isNotEmpty) {
                bestPot = fmtPot;
              } else if (streamPoToken != null && streamPoToken.isNotEmpty) {
                bestPot = streamPoToken;
              }
            }
          } else if (fmt['signatureCipher'] != null || fmt['cipher'] != null) {
            cipherCount++;
          }
        }

        final adaptive = streamingData['adaptiveFormats'] as List?;
        if (adaptive != null) {
          for (final fmt in adaptive) {
            if (fmt is Map) pick(Map<dynamic, dynamic>.from(fmt));
          }
        }
        final formats = streamingData['formats'] as List?;
        if (bestUrl == null && formats != null) {
          for (final fmt in formats) {
            if (fmt is Map) pick(Map<dynamic, dynamic>.from(fmt));
          }
        }

        debugPrint('YouTubeMusicAuth: [${c['clientName']}] $directCount direct, $cipherCount ciphered');
        if (bestUrl != null) {
          // YouTube 403s app-client streams without the Proof-of-Origin (pot)
          // parameter. The player response carries it either per-format
          // (poToken) or at the streamingData root.
          final pot = bestPot ?? streamPoToken;
          if (pot != null && pot.isNotEmpty && !bestUrl!.contains('pot=')) {
            final sep = bestUrl!.contains('?') ? '&' : '?';
            bestUrl = '$bestUrl${sep}pot=${Uri.encodeComponent(pot)}';
          }
          debugPrint('YouTubeMusicAuth: [${c['clientName']}] got direct stream ($bestBitrate bps)');
          return bestUrl;
        }
      } catch (e) {
        debugPrint('YouTubeMusicAuth: ${c['clientName']} error: $e');
      }
    }
    return null;
  }

  /// Try to play with TVHTML5 using an existing Google access token.
  /// This is the main entry point: pass the Google OAuth access_token.
  Future<String?> getStreamUrlWithGoogleToken(
    String videoId, {
    required String googleAccessToken,
  }) async {
    try {
      final url = Uri.parse('$_apiBase/youtubei/v1/player?key=$_apiKey');
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': _clientName,
            'clientVersion': _clientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      });

      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': _userAgent,
          'Authorization': 'Bearer $googleAccessToken',
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
        },
        body: body,
      );

      if (resp.statusCode != 200) {
        debugPrint('YouTubeMusicAuth: player API (google token) ${resp.statusCode} body=${resp.body.substring(0, resp.body.length > 300 ? 300 : resp.body.length)}');
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = data['playabilityStatus']?['status'] as String?;
      final reason = data['playabilityStatus']?['reason'] as String?;
      debugPrint('YouTubeMusicAuth: player status=$status reason=$reason');

      if (status == 'UNPLAYABLE' && (reason ?? '').contains('not available')) {
        StreamExtractionService.reportVideoGone(videoId, 'innertube');
      }

      if (status != 'OK') return null;

      final streamingData = data['streamingData'] as Map<String, dynamic>?;
      if (streamingData == null) return null;

      final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
      if (adaptiveFormats == null) return null;

      String? bestUrl;
      int bestBitrate = 0;

      for (final fmt in adaptiveFormats) {
        final mimeType = fmt['mimeType'] as String?;
        final fmtUrl = fmt['url'] as String?;
        final bitrate = fmt['bitrate'] as int? ?? 0;

        if (mimeType != null && mimeType.startsWith('audio/') && fmtUrl != null) {
          if (bitrate > bestBitrate) {
            bestBitrate = bitrate;
            bestUrl = fmtUrl;
          }
        }
      }

      if (bestUrl != null) {
        debugPrint('YouTubeMusicAuth: stream found via Google token ($bestBitrate bps)');
      }
      return bestUrl;
    } catch (e) {
      debugPrint('YouTubeMusicAuth: getStreamUrlWithGoogleToken error: $e');
      return null;
    }
  }

  // ── Singleton ─────────────────────────────────────────────────────────────
  static final YouTubeMusicAuth instance = YouTubeMusicAuth._();
  YouTubeMusicAuth._();
}
