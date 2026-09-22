import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/piped_api_service.dart';
import 'package:muzo/services/youtube_api_service.dart';
import 'package:muzo/services/youtube_music_auth.dart';

class StreamExtractionService {
  static final Map<String, bool> isSaavnCache = {};

  // ─── Pré-check de jouabilité (sections du Home) ────────────────────────────
  // Mémoïsé par videoId avec un TTL court : certaines pistes (géo-bloquées,
  // IP cloud bot-checkée) ne sont simplement pas résolvables à un instant T.
  static final Map<String, bool> _playableMemo = {};
  static final Map<String, DateTime> _playableMemoAt = {};

  /// Résout le stream de façon synchrone rapide (cache local → yt-dlp/
  /// Supabase → Saavn), sans les fallbacks lourds (YoutubeExplode/Piped/
  /// Invidious). Vrai si un son est jouable immédiatement sur cette machine.
  static Future<bool> isQuicklyPlayable(
    String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
  }) async {
    final now = DateTime.now();
    final cached = _playableMemo[videoId];
    final cachedAt = _playableMemoAt[videoId];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    final url = await _quickStreamUrl(
      videoId,
      title: title,
      artist: artist,
      durationSeconds: durationSeconds,
    );
    _playableMemo[videoId] = url != null;
    _playableMemoAt[videoId] = now;
    return url != null;
  }

  static Future<String?> _quickStreamUrl(
    String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
  }) async {
    try {
      final localCached = await _localCachedStreamUrl(videoId);
      if (localCached != null) return localCached;

      try {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) return null;
      } catch (_) {}

      // Race Cloud Vercel + Invidious (parallel) + YoutubeExplode + YouTube Music Auth for fast pre-check.
      return await _race([
        if (title != null && title.isNotEmpty)
          getSaavnStreamUrl(title, artist ?? '', durationSeconds: durationSeconds)
              .timeout(const Duration(seconds: 12)),
        _getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 15)),
        _getInvidiousStreamUrl(videoId).timeout(const Duration(seconds: 10)),
        _getYouTubeMusicStreamUrl(videoId).timeout(const Duration(seconds: 12)),
        _getCobaltStreamUrl(videoId).timeout(const Duration(seconds: 14)),
        YouTubeMusicAuth.instance
            .getStreamUrlInnerTubeNoAuth(videoId)
            .timeout(const Duration(seconds: 14)),
        YouTubeApiService()
            .getStreamUrl(videoId, title: title, artist: artist)
            .timeout(const Duration(seconds: 12)),
      ]);
    } catch (_) {}
    return null;
  }

  /// Pre-check optimisé pour le web : sur cette machine le worker cloud est
  /// souvent bot-checké (lent). Saavn est CORS-safe et quasi-instantané, on le
  /// tente donc d'abord quand le titre est connu. Sinon, tentative au cache
  /// local + yt-dlp. Retourne l'URL réelle (pas juste un booléen) pour que
  /// l'appelant puisse l'attacher comme [MuzoItem.audioUrl].
  static Future<String?> _preResolveUrl(
    String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
  }) async {
    try {
      final localCached = await _localCachedStreamUrl(videoId);
      if (localCached != null && !kIsWeb) return localCached;

      try {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) return null;
      } catch (_) {}
    } catch (_) {}
    return null;
  }

  /// Résout un vrai son pour chaque item et renvoie une copie avec
  /// [MuzoItem.audioUrl] attaché quand c'est possible. Les items sans son
  /// résolu sont conservés (le gate du Home les masquera). Limité à [maxN].
  static final Map<String, MuzoItem> _resolvedMemo = {};
  static final Map<String, int> _resolvedMemoAt = {};
  static const int _resolvedMemoTtlMs = 15 * 60 * 1000; // 15 minutes

  static Future<List<MuzoItem>> resolvePlayableUrls(
    List<MuzoItem> items, {
    int maxN = 12,
  }) async {
    final out = <MuzoItem>[];
    final futures = <Future<void>>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in items.take(maxN)) {
      futures.add(() async {
        if (item.audioUrl != null && item.audioUrl!.isNotEmpty) {
          out.add(item);
          return;
        }
        final videoId = item.videoId ?? '';
        final key = '$videoId|${item.title}|${item.displayArtist}';
        final mem = _resolvedMemo[key];
        final memAt = _resolvedMemoAt[key];
        // Memoized URLs (esp. IP-bound googlevideo) must not be reused
        // forever — drop entries older than the TTL so they re-resolve.
        if (mem != null &&
            memAt != null &&
            (now - memAt) < _resolvedMemoTtlMs &&
            (isReusableStreamUrl(mem.audioUrl ?? '') ||
                mem.audioUrl!.toLowerCase().contains('googlevideo.com'))) {
          out.add(mem);
          return;
        }
        _resolvedMemo.remove(key);
        _resolvedMemoAt.remove(key);
        final url = await _preResolveUrl(
          videoId,
          title: item.title,
          artist: item.displayArtist,
          durationSeconds: item.durationSeconds,
        );
        final updated =
            url != null ? item.copyWith(audioUrl: url) : null;
        if (updated != null) {
          _resolvedMemo[key] = updated;
          _resolvedMemoAt[key] = now;
        }
        if (updated != null) out.add(updated);
      }());
      if (futures.length >= 3) {
        await Future.wait(futures, eagerError: false);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
    }
    return out;
  }

  static String _cleanArtist(String artist) {
    String cleaned = artist;
    cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    final featPattern = RegExp(
      r'\s*\b(?:feat\.?|ft\.?|featuring)\b.*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(featPattern, '');
    final primaryArtistPattern = RegExp(r'^([^,&]+)');
    final match = primaryArtistPattern.firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(1)!;
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : artist;
  }

  static String _cleanTitle(String title, String artist) {
    String cleaned = title;
    final bracketNoise = RegExp(
      r'\s*[([][^\])]*(?:video|audio|lyric|lyrics|mv|hd|4k|live|remix|official|music)[^\])]*[\])]',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(bracketNoise, '');
    final standaloneNoise = RegExp(
      r'\s*\b(?:official video|official audio|music video|lyric video|lyrics|official|mv)\b',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(standaloneNoise, '');
    final featPattern = RegExp(
      r'\s*\b(?:feat\.?|ft\.?|featuring)\b.*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(featPattern, '');
    if (artist.isNotEmpty) {
      final cleanedArtist = _cleanArtist(artist);
      if (cleaned.contains('-')) {
        final parts = cleaned.split('-');
        final firstPart = parts[0].trim();
        if (firstPart.toLowerCase() == cleanedArtist.toLowerCase() ||
            cleanedArtist.toLowerCase().contains(firstPart.toLowerCase()) ||
            firstPart.toLowerCase().contains(cleanedArtist.toLowerCase())) {
          cleaned = parts.skip(1).join('-').trim();
        } else {
          final lastPart = parts.last.trim();
          if (lastPart.toLowerCase() == cleanedArtist.toLowerCase() ||
              cleanedArtist.toLowerCase().contains(lastPart.toLowerCase()) ||
              lastPart.toLowerCase().contains(cleanedArtist.toLowerCase())) {
            cleaned = parts.take(parts.length - 1).join('-').trim();
          }
        }
      }
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }

  static Future<String?> getSaavnStreamUrl(String title, String artist, {int? durationSeconds}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final cleanTitle = _cleanTitle(title, artist);
      final cleanArtist = _cleanArtist(artist);
      String? durationString;
      if (durationSeconds != null && durationSeconds > 0) {
        final minutes = durationSeconds ~/ 60;
        final seconds = durationSeconds % 60;
        durationString = "$minutes:${seconds.toString().padLeft(2, '0')}";
      }
      final queryParams = {
        'title': cleanTitle,
        'artist': cleanArtist,
        if (durationString != null) 'duration': durationString,
      };
      debugPrint('SaavnExtraction: Requesting stream for "$cleanTitle" by "$cleanArtist" (${durationString ?? "unknown"})');
      final response = await dio.get<String>(
        'https://fast-saavn.vercel.app/',
        queryParameters: queryParams,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => true,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final path = response.data!.trim();
        if (path.isNotEmpty && !path.toLowerCase().contains('error') && !path.toLowerCase().contains('fail')) {
          final fullUrl = 'https://aac.saavncdn.com/${path}_320.mp4';
          debugPrint('SaavnExtraction: Found stream - $fullUrl');
          return fullUrl;
        }
      }
      debugPrint('SaavnExtraction: Empty or error response from Saavn API');
    } catch (e) {
      debugPrint('SaavnExtraction Error: $e');
    }
    return null;
  }

  static const String cloudYtDlpBase = 'https://vercel-proxy-murex-tau.vercel.app';
  static const String tunnelYtDlpBase =
      'https://established-based-enabled-virtually.trycloudflare.com';
  static const String defaultYtDlpBase = tunnelYtDlpBase;

  /// Race multiple futures — returns the first non-null result instantly.
  /// Remaining futures are left running in the background (they will be GC'd
  /// once their references drop) instead of blocking the caller.
  static Future<String?> _race(List<Future<String?>> futures) async {
    if (futures.isEmpty) return null;
    final completer = Completer<String?>();
    var done = false;
    for (final f in futures) {
      f.then((url) {
        if (!done && url != null && url.isNotEmpty) {
          done = true;
          completer.complete(url);
        }
      }).catchError((_) {});
    }
    // If all fail / return null, complete with null once all settle.
    Future.wait(futures, eagerError: true).whenComplete(() {
      if (!done) {
        done = true;
        completer.complete(null);
      }
    });
    return completer.future;
  }

  static Box? _streamUrlBox;
  static const String _streamBoxName = 'stream_url_cache_v3';

  static Future<Box> _streamBox() async {
    if (_streamUrlBox != null && _streamUrlBox!.isOpen) return _streamUrlBox!;
    // Use a new box name to completely discard old cached URLs (v1 had stale
    // Vercel proxy URLs that return 502).
    try {
      await Hive.deleteBoxFromDisk('stream_url_cache');
    } catch (_) {}
    final box = await Hive.openBox(_streamBoxName);
    _streamUrlBox = box;
    return box;
  }

  static Future<String?> _localCachedStreamUrl(String videoId) async {
    try {
      final box = await _streamBox();
      final raw = box.get(videoId) as String?;
      if (raw == null || raw.isEmpty) return null;
      // Entries are stored as JSON {url, ts} so stale URLs (IP-bound
      // googlevideo, dead proxies) expire instead of poisoning playback.
      String url = raw;
      int ts = 0;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          url = (decoded['url'] as String?) ?? '';
          ts = (decoded['ts'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {
        url = raw;
        ts = 0;
      }
      if (url.isEmpty) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (ts > 0 && age > streamCacheTtlMs) {
        debugPrint('StreamExtraction: [LocalCache] expired for $videoId');
        await box.delete(videoId);
        return null;
      }
      // Only serve from cache if it's still reusable. googlevideo URLs are
      // IP-bound to whatever IP generated them — they stay valid for hours
      // when generated on THIS device (the local cache is device-local), but
      // die fast if the entry is stale or came from another device.
      final isGooglevideo = url.toLowerCase().contains('googlevideo.com');
      final freshLocalGooglevideo = isGooglevideo && ts > 0 && age <= streamCacheTtlMs;
      if (!isReusableStreamUrl(url) && !freshLocalGooglevideo) {
        debugPrint('StreamExtraction: [LocalCache] unusable URL for $videoId — ignoring');
        await box.delete(videoId);
        return null;
      }
      debugPrint('StreamExtraction: [LocalCache] hit for $videoId');
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Whether a previously-stored stream URL is still worth feeding straight to
  /// the player without re-resolving.
  ///
  /// Only long-lived sources are trusted here:
  /// - file / loopback / cloudflare-tunnel endpoints (re-resolve on the fly)
  /// - static music CDNs (Saavn, Apple/iTunes, Jamendo, archive.org, …)
  ///
  /// Everything else is rejected so the pipeline re-resolves from scratch:
  /// - `googlevideo.com` URLs are IP-bound and die within ~6h — a copy stored
  ///   on another device (Supabase shared cache) or an old memo 403s instantly.
  /// - dead serverless workers (`vercel.app` / `netlify.app`) return 502/503.
  static const List<String> _longLivedHosts = [
    'saavncdn.com', // JioSaavn
    'mzstatic.com', // Apple Music / iTunes previews
    'apple.com', // iTunes
    'jamendo.com', // Jamendo
    'archive.org', // Internet Archive
    'ccmixter.org', // ccMixter
    'ccmixter.com',
    'audius.co', // Audius
    'dscdn.radio', // Deezer
    'deezer.com',
    'sndcdn.com', // SoundCloud
    'bandcamp.com', // Bandcamp
    'bcbits.com', // Bandcamp CDNs
    'r2.dev', // Cloudflare R2 (custom uploads)
    'onrender.com', // Tunefy stream proxy (yt-dlp / express, resolve a la volée)
    'cobalt', // Cobalt tunnel/stream URLs (self-served, short-lived but fresh)
    'wuk.sh', // Cobalt legacy instance
  ];

  static bool isReusableStreamUrl(String url) {
    if (url.isEmpty) return false;
    final u = url.toLowerCase();
    // Dead serverless workers are never reusable.
    if (u.contains('vercel.app')) return false;
    if (u.contains('netlify.app')) return false;
    if (u.contains('supabase.co')) return false;
    // Local / tunnel endpoints proxy a live resolution.
    if (u.startsWith('file://')) return true;
    if (u.startsWith('http://127.0.0.1')) return true;
    if (u.startsWith('http://localhost')) return true;
    if (u.contains('trycloudflare.com')) return true;
    // YouTube audio is IP-bound + expiring — never replay a stored copy.
    if (u.contains('googlevideo.com')) return false;
    // Long-lived static CDNs are safe to replay.
    return _longLivedHosts.any(u.contains);
  }

  static const int streamCacheTtlMs = 30 * 60 * 1000; // 30 minutes

  static Future<void> _cacheStreamUrl(String videoId, String url) async {
    if (videoId.isEmpty || url.isEmpty) return;
    try {
      final box = await _streamBox();
      final entry = jsonEncode({
        'url': url,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      await box.put(videoId, entry);
    } catch (_) {}
  }

  static Future<void> invalidateCache(String videoId) async {
    if (videoId.isEmpty) return;
    try {
      final box = await _streamBox();
      await box.delete(videoId);
    } catch (_) {}
  }

  static Future<void> _persistYtDlpServerUrl(String url) async {
    try {
      final Box box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final current = box.get('ytdlpServerUrl') as String?;
      if (current == url) return;
      await box.put('ytdlpServerUrl', url);
      debugPrint('StreamExtraction: [YtDlp] Server cached in settings: $url');
    } catch (_) {}
  }

  static Future<String?> _getYtDlpStreamUrl(String videoId) async {
    String? cloudBase;
    try {
      final Box box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final saved = box.get('ytdlpServerUrl') as String?;
      if (saved != null && saved.trim().isNotEmpty) cloudBase = saved;
    } catch (_) {}

    // Sur mobile, on tente d'abord le serveur local sur le loopback (adb
    // reverse / client embarqué), puis le serveur configuré (réglages), puis
    // le tunnel cloudflared actif, puis le cloud Vercel. Le probe loopback
    // échoue en <1s quand il est absent.
    final candidates = <String>[
      'http://127.0.0.1:9877',
      if (cloudBase != null && cloudBase.trim().isNotEmpty) cloudBase,
      if (cloudBase != tunnelYtDlpBase) tunnelYtDlpBase,
      cloudYtDlpBase, // Vercel worker — always try cloud
    ];

    for (final candidate in candidates) {
      final client = http.Client();
      try {
        // Vercel proxy: resolve + proxy in a single call to avoid re-resolution.
        if (candidate.contains('vercel.app')) {
          try {
            final ytMusicToken = YouTubeMusicAuth.instance.accessToken;
            // Step 1: resolve the stream URL
            final resolveParams = <String, String>{
              'videoId': videoId,
              if (ytMusicToken != null) 'token': ytMusicToken,
            };
            final resolveUri = Uri.parse('$candidate/api/stream')
                .replace(queryParameters: resolveParams);
            final resolveResp = await client
                .get(resolveUri)
                .timeout(const Duration(seconds: 15));
            if (resolveResp.statusCode == 200) {
              final data = jsonDecode(resolveResp.body);
              final resolvedUrl = data['url'] as String?;
              if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
                // Step 2: tell the proxy to stream this exact URL (no re-resolve).
                final proxyParams = <String, String>{
                  'videoId': videoId,
                  'streamUrl': resolvedUrl,
                };
                final proxyUri = Uri.parse('$candidate/api/stream')
                    .replace(queryParameters: proxyParams);
                debugPrint('StreamExtraction: [Proxy] resolved → streaming via $proxyUri');
                return proxyUri.toString();
              }
              debugPrint('StreamExtraction: [Proxy] no url: ${data['error']}');
            } else {
              debugPrint('StreamExtraction: [Proxy] HTTP ${resolveResp.statusCode}');
            }
          } catch (e) {
            debugPrint('StreamExtraction: [Proxy] $e');
          }
        } else {
          // Local yt-dlp server: get the URL directly.
          final uri = Uri.parse('$candidate/stream')
              .replace(queryParameters: {'videoId': videoId});
          final response = await client
              .get(uri)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final url = data['url'] as String?;
            if (url != null && url.isNotEmpty) {
              debugPrint('StreamExtraction: [YtDlp] Got stream from $uri');
              if (candidate != 'http://127.0.0.1:9877') {
                await _persistYtDlpServerUrl(candidate);
              }
              return url;
            }
          }
        }
      } catch (e) {
        debugPrint('StreamExtraction: [YtDlp] $e on $candidate');
      } finally {
        client.close();
      }
    }

    // Supabase shared cache
    try {
      final client = http.Client();
      try {
        final cacheUri = Uri.parse(
            'https://lvwwbuujvknzmstzmjam.supabase.co/rest/v1/stream_cache')
            .replace(queryParameters: {
          'select': 'url',
          'video_id': 'eq.$videoId',
          'limit': '1',
        });
        final resp = await client.get(cacheUri, headers: {
          'apikey':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx2d3didXVqdmtuem1zdHptamFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc5Mzg3NTUsImV4cCI6MjEwMzUxNDc1NX0.BsM8AaUi6GHAV6KsmS70ppFDFuyWa0Vl9mpveqyRyQA',
        }).timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final rows = jsonDecode(resp.body) as List;
          if (rows.isNotEmpty) {
            final url = (rows.first as Map)['url'] as String?;
            if (url != null && url.isNotEmpty) {
              debugPrint('StreamExtraction: [SupabaseCache] hit for $videoId');
              return url;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('StreamExtraction: [SupabaseCache] $e');
    }
    return null;
  }

  /// Cobalt public API — résout l'audio côté serveur (IP alternées, bot-checks
  /// contournés) puis rend une URL de fichier streamable direct. Rate-limiting
  /// possible sans clé, d'où deux instances publiques en secours.
  static Future<String?> _getCobaltStreamUrl(String videoId) async {
    for (final instance in const [
      'https://api.cobalt.tools/',
      'https://co.wuk.sh/',
    ]) {
      final client = http.Client();
      try {
        final resp = await client
            .post(
              Uri.parse(instance),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 15) Tunefy/1.0',
              },
              body: jsonEncode({
                'url': 'https://www.youtube.com/watch?v=$videoId',
                'videoQuality': 'best',
                'audioFormat': 'mp3',
                'isAudioOnly': true,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode >= 400) {
          debugPrint(
              'StreamExtraction: [Cobalt] HTTP ${resp.statusCode} on $instance');
          continue;
        }
        final data = jsonDecode(resp.body);
        final status = data['status'] as String?;
        if (status == 'stream' && data['url'] != null) {
          final url = data['url'].toString();
          if (url.startsWith('http')) {
            debugPrint(
                'StreamExtraction: [Cobalt] stream found via $instance');
            return url;
          }
        }
        debugPrint('StreamExtraction: [Cobalt] status=$status on $instance');
      } catch (e) {
        debugPrint('StreamExtraction: [Cobalt] $e on $instance');
      } finally {
        client.close();
      }
    }
    return null;
  }

  static Future<String?> _getInvidiousStreamUrl(String videoId) async {
    const invidiousInstances = [
      'inv.nadeko.net',
      'invidious.materialio.us',
      'yewtu.be',
      'invidious.nerdvpn.de',
      'iv.ggtyler.dev',
      'invidious.f5.si',
    ];

    // Race ALL instances in parallel — first valid stream wins.
    final futures = invidiousInstances.map((instance) async {
      try {
        final uri = Uri.parse('https://$instance/api/v1/videos/$videoId');
        final client = http.Client();
        try {
          final response = await client.get(uri).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) return null;

          final data = jsonDecode(response.body);
          final adaptiveFormats = data['adaptiveFormats'] as List?;
          if (adaptiveFormats == null) return null;

          String? bestUrl;
          int bestBitrate = 0;
          int bestItag = 0;

          for (final format in adaptiveFormats) {
            final type = (format['mimeType'] ?? format['type']) as String?;
            final url = format['url'] as String?;
            final bitrateVal = format['bitrate'];
            int bitrate = 0;
            if (bitrateVal is int) {
              bitrate = bitrateVal;
            } else if (bitrateVal is String) {
              bitrate = int.tryParse(bitrateVal) ?? 0;
            }

            if (type != null && type.startsWith('audio/') && url != null) {
              if (bitrate > bestBitrate) {
                bestBitrate = bitrate;
                bestUrl = url;
                final itagVal = format['itag'];
                if (itagVal is int) {
                  bestItag = itagVal;
                } else if (itagVal is String) {
                  bestItag = int.tryParse(itagVal) ?? 0;
                }
              }
            }
          }

          if (bestItag > 0 || bestUrl != null) {
            final itag = bestItag > 0 ? bestItag : 251;
            debugPrint('StreamExtraction: [Invidious] Found stream from $instance ($bestBitrate bps, itag=$itag)');
            // Use the raw googlevideo URL directly. The phone has a residential
            // IP so YouTube will serve it. The Invidious /latest_version proxy
            // is broken (500) because YouTube also blocks Invidious servers.
            return bestUrl;
          }
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('StreamExtraction: [Invidious] $instance failed: $e');
      }
      return null;
    }).toList();

    return await _race(futures);
  }

  /// Try YouTube Music authenticated player API.
  static Future<String?> _getYouTubeMusicStreamUrl(String videoId) async {
    try {
      final auth = YouTubeMusicAuth.instance;
      final url = await auth.getStreamUrl(videoId);
      if (url != null && url.isNotEmpty) {
        debugPrint('StreamExtraction: [YouTubeMusicAuth] stream found for $videoId');
        return url;
      }
    } catch (e) {
      debugPrint('StreamExtraction: [YouTubeMusicAuth] $e');
    }
    return null;
  }

  /// Extracts the best audio stream URL. Cascade order:
  /// 1. Local disk cache (instant)
  /// 2. Invidious (parallel race — only reliable source left)
  /// 3. YoutubeExplode direct API (might work for some videos)
  static Future<String?> getStreamUrl(
    String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
    bool skipSaavn = false,
  }) async {
    final overallStopwatch = Stopwatch()..start();
    debugPrint('StreamExtraction: --- getStreamUrl started for $videoId ---');

    // 0. Local disk cache — instant, zero network
    final localCached = await _localCachedStreamUrl(videoId);
    if (localCached != null) {
      debugPrint('StreamExtraction: [LocalCache] served in ${overallStopwatch.elapsedMilliseconds}ms');
      return localCached;
    }

    // Fast offline guard
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        debugPrint('StreamExtraction: offline — skipping network cascade for $videoId');
        return null;
      }
    } catch (_) {}

    // 1. Race Saavn + Cloud/yt-dlp + Invidious (parallel) + YouTube Music Auth — first valid URL wins.
    final futures = <Future<String?>>[
      if (title != null && title.isNotEmpty && !skipSaavn)
        getSaavnStreamUrl(title, artist ?? '', durationSeconds: durationSeconds)
            .timeout(const Duration(seconds: 12)),
      _getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 18)),
      _getInvidiousStreamUrl(videoId).timeout(const Duration(seconds: 12)),
      _getYouTubeMusicStreamUrl(videoId).timeout(const Duration(seconds: 12)),
      // Cobalt public backend — resolves OFF the device IP (bypasses the
      // bot-check that kills the other YouTube sources), returns a fresh
      // file URL that plays directly.
      _getCobaltStreamUrl(videoId).timeout(const Duration(seconds: 15)),
      // Piped API — proxy YouTube gratuit, dernier recours (streams souvent 500)
      PipedApiService()
          .getStreamUrl(videoId)
          .timeout(const Duration(seconds: 10)),
      YouTubeMusicAuth.instance
          .getStreamUrlInnerTubeNoAuth(videoId)
          .timeout(const Duration(seconds: 16)),
      YouTubeApiService()
          .getStreamUrl(videoId, title: title, artist: artist)
          .timeout(const Duration(seconds: 15)),
    ];
    final url = await _race(futures);
    if (url != null) {
      isSaavnCache[videoId] = false;
      debugPrint('StreamExtraction: succeeded in ${overallStopwatch.elapsedMilliseconds}ms');
      await _cacheStreamUrl(videoId, url);
      return url;
    }

    debugPrint('StreamExtraction: All sources failed after ${overallStopwatch.elapsedMilliseconds}ms');
    return null;
  }
}
