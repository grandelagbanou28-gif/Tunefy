import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/piped_api_service.dart';
import 'package:muzo/services/stream_endpoint_resolver.dart';
import 'package:muzo/services/youtube_api_service.dart';
import 'package:muzo/services/youtube_music_auth.dart';

class _SourceHealth {
  int failures = 0;
  int successes = 0;
  DateTime downUntil = DateTime.fromMillisecondsSinceEpoch(0);
}

class StreamExtractionService {
  static final Map<String, bool> isSaavnCache = {};

  // ─── Pré-check de jouabilité (sections du Home) ────────────────────────────
  // Mémoïsé par videoId avec un TTL court : certaines pistes (géo-bloquées,
  // IP cloud bot-checkée) ne sont simplement pas résolvables à un instant T.
  static final Map<String, bool> _playableMemo = {};
  static final Map<String, DateTime> _playableMemoAt = {};

  /// Metadata-only seed ids (iTunes `it_`, Spotify `sp_`, Deezer `dz_`, …)
  /// that are NOT YouTube video ids — no extraction source can ever stream
  /// them, so callers must resolve them to a real videoId first.
  static final RegExp _metadataSeedRe =
      RegExp(r'^(it_|sp_|sp:|yr_|al_|user_track_|dz_)');

  static bool isMetadataSeedId(String videoId) =>
      videoId.isNotEmpty && _metadataSeedRe.hasMatch(videoId);

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
    if (isMetadataSeedId(videoId)) {
      _playableMemo[videoId] = false;
      _playableMemoAt[videoId] = now;
      return false;
    }
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
    final preferLowBitrate = _preferLowBitratePref;
    try {
      final localCached = await _localCachedStreamUrl(videoId);
      if (localCached != null) return localCached;

      try {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) return null;
      } catch (_) {}

      // Race Cloud Vercel + Invidious (parallel) + YoutubeExplode + YouTube Music Auth for fast pre-check.
      // Outer timeouts must stay ABOVE each source's internal work budget so
      // a slow-but-alive source is not cut off before it can answer.
      return await _race([
        if (title != null && title.isNotEmpty)
          getSaavnStreamUrl(title, artist ?? '', durationSeconds: durationSeconds)
              .timeout(const Duration(seconds: 18)),
        _getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 35)),
        _getInvidiousStreamUrl(videoId).timeout(const Duration(seconds: 12)),
        _getYouTubeMusicStreamUrl(videoId).timeout(const Duration(seconds: 18)),
        _getCobaltStreamUrl(videoId).timeout(const Duration(seconds: 20)),
        YouTubeMusicAuth.instance
            .getStreamUrlInnerTubeNoAuth(videoId)
            .timeout(const Duration(seconds: 18)),
        YouTubeApiService()
            .getStreamUrl(videoId,
                title: title, artist: artist, preferLowBitrate: preferLowBitrate)
            .timeout(const Duration(seconds: 25)),
        _getPipedStreamUrl(videoId).timeout(const Duration(seconds: 12)),
      ]);
    } catch (_) {}
    return null;
  }

  /// Reads the persisted "audio quality" preference. Only the data-saver tier
  /// actually changes which stream is picked, and only on the resolvers that
  /// expose a bitrate choice; the proxy-based ones serve whatever the backend
  /// decided. The value is `AudioQuality { high, medium, low }.index`, stored
  /// by SettingsNotifier.
  static bool get _preferLowBitratePref {
    try {
      final box = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
      if (box == null) return false;
      final value = box.get('audioQuality', defaultValue: 0);
      return value is int && value == 2;
    } catch (_) {
      return false;
    }
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

      // Cache miss: hit Saavn (fast, no YouTube bot-check) so shelf
      // enrichment actually attaches an audioUrl instead of always
      // returning null and deferring every resolve to tap time. The full
      // multi-source race still runs inside getStreamUrl at playback.
      if (title != null && title.isNotEmpty) {
        final url = await getSaavnStreamUrl(
          title,
          artist ?? '',
          durationSeconds: durationSeconds,
        ).timeout(const Duration(seconds: 15));
        if (url != null && url.isNotEmpty) return url;
      }
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

  /// yt-dlp proxies, all answering `GET /api/stream?videoId=…` (and
  /// `&kind=video` for the video track). The old onrender.com host is gone —
  /// the project moved to Vercel — which is why playback had no source left.
  static const List<String> cloudYtDlpBases = [
    'https://tunefy-ytdlp.vercel.app',
    'https://vercel-proxy-murex-tau.vercel.app',
  ];

  static const String cloudYtDlpBase = 'https://tunefy-ytdlp.vercel.app';

  static const String cloudBackupYtDlpBase =
      'https://vercel-proxy-murex-tau.vercel.app';

  /// Owns the cloud candidate list, the last known good base and the circuit
  /// breaker, so a moved server is handled at runtime instead of by a rebuild.
  static final StreamEndpointResolver _endpoints = StreamEndpointResolver();
  // DEAD (DNS errno 7 depuis des jours) — conservé seulement pour migrer
  // d'anciens settings vers le serveur local / Vercel, jamais joué.
  static const String tunnelYtDlpBase =
      'https://established-based-enabled-virtually.trycloudflare.com';
  static const String defaultYtDlpBase = '';
  // Freedify — backend Python (Docker biohaphazard/freedify:latest, port 8000)
  // qui resolve yt-dlp hors de l'IP de l'app et proxifie le flux (Range OK).
  // Circuit-breaker local via adb reverse, sinon désactivé.
  static const String freedifyBase = 'http://127.0.0.1:8000';

  /// Race multiple futures — returns the first non-null result instantly.
  /// Error-tolerant: a single timeout/failure never kills the race (the old
  /// `Future.wait(eagerError: true)` completed with null as soon as the FIRST
  /// source timed out, silently dropping tracks whose slower source — yt-dlp,
  /// Cobalt — would have succeeded). Remaining futures keep running in the
  /// background; null is returned only after every future has settled.
  static Future<String?> _race(List<Future<String?>> futures) async {
    if (futures.isEmpty) return null;
    final completer = Completer<String?>();
    var done = false;
    var remaining = futures.length;
    for (final f in futures) {
      f.then((url) {
        if (!done && url != null && url.isNotEmpty) {
          done = true;
          completer.complete(url);
        }
      }).catchError((Object _) {}).whenComplete(() {
        remaining--;
        if (!done && remaining <= 0) {
          done = true;
          completer.complete(null);
        }
      });
    }
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

  /// True when a usable URL is already cached for [videoId].
  ///
  /// The prewarmer asks this before doing any network work, so scrolling a
  /// shelf that is already warm costs nothing.
  static Future<bool> isWarm(String videoId) async {
    if (videoId.isEmpty) return false;
    final url = await _localCachedStreamUrl(videoId);
    return url != null && url.isNotEmpty;
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
      // googlevideo URLs are IP-bound + expiring: even a fresh copy can be
      // dead (signature expired, IP rotated). Without this probe the player
      // gets "Source error" AND the retry re-reads the same poisoned entry.
      if (isGooglevideo) {
        if (!await probeStreamUrl(url)) {
          debugPrint(
              'StreamExtraction: [LocalCache] dead googlevideo for $videoId — purging');
          await box.delete(videoId);
          return null;
        }
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

  /// Probe device-side : vérifie qu'une URL googlevideo raw répond toujours
/// (Range bytes=0-1). Les URLs YouTube sont IP-bound — Invidious/Cobalt les
/// résolvent sur leur propre IP, donc l'appareil reçoit 403 au playback.
/// Retourne false si morte → l'appelant doit re-résoudre.
/// Ne s'applique qu'aux hosts googlevideo directs (pas nos proxy qui
/// *contiennent* une googlevideo encodée dans la query).
static bool isRawGooglevideo(String url) {
  if (url.isEmpty) return false;
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host.endsWith('googlevideo.com');
}

static Future<bool> probeStreamUrl(String url) async {
  if (url.isEmpty) return false;
  try {
    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request('GET', Uri.parse(url))
            ..headers['Range'] = 'bytes=0-1')
          .timeout(const Duration(seconds: 3));
      return resp.statusCode == 200 || resp.statusCode == 206;
    } finally {
      client.close();
    }
  } catch (_) {
    return false;
  }
}

/// Si [url] est une googlevideo raw, probe sur l'appareil ; si morte, re-résout
/// via le serveur yt-dlp local (proxy loopback → jamais IP-bound). Retourne
/// l'URL jouable ou null si rien de jouable (ne jamais reposer un 403).
static Future<String?> ensurePlayableUrl(
    String videoId, String? url) async {
  if (url == null || url.isEmpty) return null;
  if (!isRawGooglevideo(url)) return url; // CDN Saavn / proxy local / tunnel
  if (await probeStreamUrl(url)) return url;
  debugPrint(
      'StreamExtraction: [Verify] googlevideo dead for $videoId — retry via local yt-dlp');
  try {
    // Queue on the local server (semaphore 4) can push cold resolution past
    // 18s when the artist page floods it — match the main race budget.
    final retry = await _getYtDlpStreamUrl(videoId)
        .timeout(const Duration(seconds: 35));
    if (retry != null && retry.isNotEmpty) {
      debugPrint('StreamExtraction: [Verify] retry OK for $videoId');
      return retry;
    }
  } catch (_) {}
  return null;
}

  /// HEADs [uri] and reports whether it really serves media bytes.
  ///
  /// A resolver that answers `application/json` at a URL the player is about
  /// to consume is worse than no answer at all: the player waits out its full
  /// timeout on a payload that can never play.
  static Future<bool> _servesMedia(http.Client client, Uri uri) async {
    try {
      final resp = await client.head(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return false;
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      if (ct.isEmpty) return true; // no declaration: let the player try
      return !ct.contains('json') && !ct.contains('html');
    } catch (_) {
      return false;
    }
  }

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
    // DEAD trycloudflare tunnels (DNS errno 7) must NEVER be replayed —
    // ExoPlayer gets Source error on the first byte.
    if (u.contains('trycloudflare.com')) return false;
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
    // reverse / client embarqué), puis Freedify (backend Python équilibré),
    // puis le serveur configuré (réglages), puis le cloud Vercel. Le probe
    // loopback échoue en <1s quand il est absent.
    //
    // The cloud list comes from StreamEndpointResolver, which probes the
    // candidates in order and remembers the one that answered — so a redeploy
    // to a new domain is picked up without shipping a new build.
    final healthy = await _endpoints.healthyBases();
    final candidates = <String>[
      'http://127.0.0.1:9877',
      freedifyBase,
      if (cloudBase != null &&
          cloudBase.trim().isNotEmpty &&
          !cloudBase.contains('trycloudflare.com'))
        cloudBase,
      ...healthy, // probed, last known good first
      ...cloudYtDlpBases, // last resort: untried built-ins
      // tunnelYtDlpBase intentionally omitted: DNS dead (errno 7), only
      // wastes the race budget and hands Source errors to the player.
    ];

    for (final candidate in candidates) {
      final client = http.Client();
      try {
        // Freedify: resolve via yt-dlp hors IP-device + proxy Range-friendly.
        if (candidate == freedifyBase) {
          try {
            final fdUri = Uri.parse('$candidate/api/stream/ytm_$videoId');
            // HEAD only — never GET the body (would buffer the whole audio
            // into memory just to inspect Content-Type). Freedify supports
            // HEAD on /api/stream/{isrc} and still resolves yt-dlp server-side.
            final fdResp = await client
                .head(fdUri)
                .timeout(const Duration(seconds: 25));
            if (fdResp.statusCode == 200) {
              final ct = (fdResp.headers['content-type'] ?? '').toLowerCase();
              final okAudio = ct.startsWith('audio/') ||
                  ct.contains('octet-stream') ||
                  ct.contains('flac') ||
                  ct.contains('mpeg') ||
                  ct.contains('mp4') ||
                  ct.contains('wav');
              if (okAudio) {
                // Player streams the proxy URL directly (Range supported).
                debugPrint('StreamExtraction: [Freedify] proxy ready ($ct)');
                return fdUri.toString();
              }
              debugPrint('StreamExtraction: [Freedify] unexpected CT: $ct');
            } else {
              debugPrint(
                  'StreamExtraction: [Freedify] HTTP ${fdResp.statusCode}');
            }
          } catch (e) {
            debugPrint('StreamExtraction: [Freedify] $e');
          }
          continue;
        }
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
                // The worker is supposed to relay the bytes here. Verified,
                // because when it does not it simply re-answers the resolve
                // JSON — and handing that URL to the player costs a 45 s
                // stall and a dead track for every single title. Checking
                // costs one HEAD request and turns a silent failure into a
                // clean fallthrough to the next source.
                if (await _servesMedia(client, proxyUri)) {
                  debugPrint('StreamExtraction: [Proxy] streaming via $proxyUri');
                  return proxyUri.toString();
                }
                debugPrint(
                    'StreamExtraction: [Proxy] no relay mode — answer is not media, skipping');
              } else {
                debugPrint('StreamExtraction: [Proxy] no url: ${data['error']}');
              }
            } else {
              debugPrint('StreamExtraction: [Proxy] HTTP ${resolveResp.statusCode}');
            }
          } catch (e) {
            debugPrint('StreamExtraction: [Proxy] $e');
          }
        } else {
          // Local yt-dlp server: get the URL directly. Cold extraction
          // (yt-dlp + verify) can take 5–25s when many songs resolve at
          // once — a 10s cap was killing valid responses (TimeoutException
          // on 127.0.0.1:9877). Server budget is 90s; 30s covers normal
          // cold runs without hanging the race forever.
          final uri = Uri.parse('$candidate/stream')
              .replace(queryParameters: {'videoId': videoId});
          final response = await client
              .get(uri)
              .timeout(const Duration(seconds: 30));
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
              // Shared cache holds googlevideo bound to OTHER devices' IPs —
              // never hand it back raw; only reuse if it still probes OK here.
              if (!isRawGooglevideo(url) || await probeStreamUrl(url)) {
                debugPrint('StreamExtraction: [SupabaseCache] hit for $videoId');
                return url;
              }
              debugPrint(
                  'StreamExtraction: [SupabaseCache] dead googlevideo for $videoId — ignoring');
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

  /// URL **vidéo** jouable pour le feed de clips (le vrai clip de l'artiste).
  ///
  /// [getStreamUrl] ne renvoie que de l'audio : un VideoPlayer ne peut pas
  /// dessiner une piste audio, la page resterait sur la pochette. On demande
  /// donc au serveur yt-dlp une rendition muxée (`kind=video`, 480p max) via
  /// son endpoint `/api/proxy`, qui supporte les requêtes Range — l'ExoPlayer
  /// peut donc seeker normalement.
  static Future<String?> getVideoStreamUrl(String videoId) async {
    if (videoId.trim().isEmpty) return null;
    String? configured;
    try {
      final Box box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final saved = box.get('ytdlpServerUrl') as String?;
      if (saved != null && saved.trim().isNotEmpty) configured = saved.trim();
    } catch (_) {}

    // Same resolver as audio: probed, last known good first.
    final healthy = await _endpoints.healthyBases();

    // Deduplicated: `configured`, `healthy` and `cloudYtDlpBases` usually
    // overlap, and a host listed twice used to be awaited twice.
    final candidates = <String>{
      'http://127.0.0.1:9877',
      if (configured != null &&
          configured.isNotEmpty &&
          !configured.contains('trycloudflare.com'))
        configured,
      ...healthy,
      ...cloudYtDlpBases,
    };

    // Raced, not sequential: the cloud hosts answer a bot-check 502 after
    // ~19s (or hang for the whole budget), and waiting for them before
    // reaching the loopback server meant minutes of frozen playback before
    // "Vidéo indisponible". First valid URL wins, the rest settle silently.
    return _race(
      candidates.map((c) => _tryVideoSource(c, videoId)).toList(),
    );
  }

  /// One candidate of the video cascade. Loopback gets a long budget (cold
  /// yt-dlp runs take 5–25s); cloud hosts either answer in ~2s or are dead,
  /// so 15s is plenty and keeps a broken host from eating the whole session.
  static Future<String?> _tryVideoSource(String candidate, String videoId) async {
    final isLoopback = candidate.startsWith('http://127.0.0.1');
    // Loopback gets a long budget because the local server may have to merge
    // video and audio on a cold miss before it can answer. It costs nothing
    // extra: same machine, via adb reverse.
    final budget = Duration(seconds: isLoopback ? 120 : 15);
    final client = http.Client();
    try {
      for (final path in const ['/api/stream', '/stream']) {
        final uri = Uri.parse('$candidate$path')
            .replace(queryParameters: {'videoId': videoId, 'kind': 'video'});
        final resp = await client.get(uri).timeout(budget);
        if (resp.statusCode != 200) continue;
        final data = jsonDecode(resp.body);
        final url = data is Map ? data['url'] as String? : null;
        if (url != null && url.isNotEmpty) {
          debugPrint('StreamExtraction: [Video] $url via $uri');
          return url;
        }
      }
    } catch (e) {
      debugPrint('StreamExtraction: [Video] $e on $candidate');
    } finally {
      client.close();
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

  /// Piped instances expose `/streams/{id}` with the real audio and video
  /// renditions. Most public instances are down, so the whole list is raced
  /// and the first answer wins — the same strategy as the other resolvers.
  static Future<String?> _getPipedStreamUrl(String videoId) async {
    const instances = [
      'api.piped.private.coffee',
      'pipedapi.reallyaweso.me',
      'pipedapi.adminforge.de',
      'pipedapi.kavin.rocks',
      'pipedapi-libre.kavin.rocks',
      'pipedapi.ducks.party',
    ];
    for (final instance in instances) {
      final client = http.Client();
      try {
        final uri = Uri.parse('https://$instance/streams/$videoId');
        final response = await client
            .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        if (data is! Map) continue;
        final audios = (data['audioStreams'] as List?) ?? const [];
        String? bestUrl;
        var bestBitrate = 0;
        for (final a in audios) {
          if (a is! Map) continue;
          final url = a['url']?.toString() ?? '';
          if (url.isEmpty) continue;
          final bitrate = (a['bitrate'] as num?)?.toInt() ?? 0;
          if (bitrate >= bestBitrate) {
            bestBitrate = bitrate;
            bestUrl = url;
          }
        }
        if (bestUrl != null) {
          debugPrint('StreamExtraction: [Piped] $instance ($bestBitrate bps)');
          return bestUrl;
        }
      } catch (e) {
        debugPrint('StreamExtraction: [Piped] $instance: $e');
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

    // Newer Invidious builds answer 403 on /api/v1 for non-browser clients,
    // so the /latest_version redirect is tried first: it needs a browser
    // User-Agent and returns the real googlevideo URL.
    const ua =
        'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';
    for (final instance in invidiousInstances) {
      final client = http.Client();
      try {
        final uri = Uri.parse(
          'https://$instance/latest_version',
        ).replace(queryParameters: {'id': videoId, 'itag': '18'});
        final response = await client.get(
          uri,
          headers: {'User-Agent': ua, 'Accept': '*/*'},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;
        final location = response.headers['location'] ?? '';
        if (location.startsWith('http') &&
            location.contains('googlevideo.com')) {
          debugPrint('StreamExtraction: [Invidious] $instance redirect OK');
          return location;
        }
      } catch (e) {
        debugPrint('StreamExtraction: [Invidious-v] $instance: $e');
      } finally {
        client.close();
      }
    }

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

/// Per-source health, keyed by source name.
  ///
  /// Without it, one dead source costs its full timeout (12-40 s) on *every*
  /// track, which is what turned a single failing resolver into "the whole app
  /// feels broken". A source that fails is parked for a cool-off instead.
  static final Map<String, _SourceHealth> _health = {};

  /// Consecutive failures before a source is considered dead.
  static const int _failureThreshold = 2;

  /// How long a dead source is skipped, growing with each failure so a source
  /// that is genuinely gone stops costing anything.
  static Duration _cooldown(int failures) =>
      Duration(seconds: 30 * (1 << (failures - _failureThreshold).clamp(0, 5)));

  static bool _isDown(String source) {
    final h = _health[source];
    if (h == null || h.failures < _failureThreshold) return false;
    if (DateTime.now().isBefore(h.downUntil)) return true;
    // Cool-off elapsed: give it a fresh chance rather than a permanent ban.
    h.failures = 0;
    return false;
  }

  static void _recordOk(String source) {
    final h = _health.putIfAbsent(source, () => _SourceHealth());
    h.failures = 0;
    h.successes++;
  }

  static void _recordFail(String source) {
    final h = _health.putIfAbsent(source, () => _SourceHealth());
    h.failures++;
    if (h.failures >= _failureThreshold) {
      h.downUntil = DateTime.now().add(_cooldown(h.failures));
      debugPrint('StreamExtraction: source "$source" parked until '
          '${h.downUntil.toIso8601String()} ($source)');
    }
  }

  /// Source health snapshot for the diagnostics screen.
  static Map<String, String> sourceHealthReport() {
    final now = DateTime.now();
    final report = <String, String>{};
    for (final entry in _health.entries) {
      final h = entry.value;
      if (h.failures < _failureThreshold) {
        report[entry.key] = h.successes == 0 ? 'jamais testé' : 'ok';
      } else if (now.isBefore(h.downUntil)) {
        report[entry.key] = 'hors service (${h.failures} échecs)';
      } else {
        report[entry.key] = 'à réessayer';
      }
    }
    return report;
  }

  /// Forces every source back into rotation — used by the diagnostics screen.
  static void resetSourceHealth() {
    _health.clear();
    debugPrint('StreamExtraction: source health reset');
  }

  static Future<String?> getStreamUrl(
  String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
    bool skipSaavn = false,
    Set<String> avoidSources = const {},
  }) async {
    final overallStopwatch = Stopwatch()..start();
    debugPrint('StreamExtraction: --- getStreamUrl started for $videoId ---');
    final lowBitrate = _preferLowBitratePref;

    // Metadata seeds (dz_/it_/sp_…) are not YouTube ids — fail fast instead
    // of racing eight sources that can never resolve them.
    if (isMetadataSeedId(videoId)) {
      debugPrint('StreamExtraction: metadata seed id, not streamable: $videoId');
      return null;
    }

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
    // Outer timeouts must stay ABOVE each source's internal work budget
    // (Saavn dio 15s, Cobalt 2×15s, Piped 3×6s, YT API receive 30s) so a
    // slow source is never cut off before it finishes.
    // 1. Direct-CDN sources first, and alone. Saavn (and friends) hand out
    // static CDN URLs that are not IP-bound, so when one resolves the track is
    // instantly playable. Racing it against the YouTube chain used to hand a
    // fast-but-dead 403 URL to the player and throw this result away.
    if (title != null && title.isNotEmpty && !skipSaavn && !avoidSources.contains('saavn')) {
      final saavnUp = !_isDown('saavn');
      try {
        final direct = saavnUp
            ? await getSaavnStreamUrl(
                title,
                artist ?? '',
                durationSeconds: durationSeconds,
              ).timeout(const Duration(seconds: 18))
            : null;
        if (direct != null && direct.isNotEmpty) {
          _recordOk('saavn');
          debugPrint('StreamExtraction: direct CDN hit in '
              '${overallStopwatch.elapsedMilliseconds}ms');
          isSaavnCache[videoId] = true;
          await _cacheStreamUrl(videoId, direct);
          return direct;
        }
        if (saavnUp) _recordFail('saavn');
      } catch (_) {
        if (saavnUp) _recordFail('saavn');
      }
    }

    // 2. YouTube-derived sources, all in parallel, but every result is kept.
    // A blind race is only safe if the winner is also the best candidate: here
    // the YouTube chain answers fastest with a URL resolved on *its* server's
    // IP, which this device then gets a 403 for. So the candidates are verified
    // one after another and the first that really plays wins.
    final futures = <Future<String?>>[
      if (!avoidSources.contains('ytdlp') && !_isDown('ytdlp'))
        _getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 40)),
      if (!avoidSources.contains('invidious') && !_isDown('invidious'))
        _getInvidiousStreamUrl(videoId).timeout(const Duration(seconds: 12)),
      if (!avoidSources.contains('ytmusic') && !_isDown('ytmusic'))
        _getYouTubeMusicStreamUrl(videoId).timeout(const Duration(seconds: 18)),
      // Cobalt public backend — resolves OFF the device IP (bypasses the
      // bot-check that kills the other YouTube sources), returns a fresh
      // file URL that plays directly.
      if (!avoidSources.contains('cobalt') && !_isDown('cobalt'))
        _getCobaltStreamUrl(videoId).timeout(const Duration(seconds: 32)),
      // Piped API — proxy YouTube gratuit, dernier recours (streams souvent 500)
      if (!avoidSources.contains('piped') && !_isDown('piped'))
        PipedApiService()
            .getStreamUrl(videoId)
            .timeout(const Duration(seconds: 18)),
      if (!avoidSources.contains('innertube') && !_isDown('innertube'))
        YouTubeMusicAuth.instance
            .getStreamUrlInnerTubeNoAuth(videoId)
            .timeout(const Duration(seconds: 20)),
      YouTubeApiService()
          .getStreamUrl(videoId,
              title: title, artist: artist, preferLowBitrate: lowBitrate)
          .timeout(const Duration(seconds: 30)),
    ];
    final results = await Future.wait(futures, eagerError: false);
    isSaavnCache[videoId] = false;

    for (final candidate in results) {
      if (candidate == null || candidate.isEmpty) continue;
      final ensured = await ensurePlayableUrl(videoId, candidate);
      if (ensured != null && ensured.isNotEmpty) {
        _recordOk('ytdlp');
        debugPrint('StreamExtraction: succeeded in '
            '${overallStopwatch.elapsedMilliseconds}ms');
        await _cacheStreamUrl(videoId, ensured);
        return ensured;
      }
      // The URL came back but would not play here: whatever produced it is
      // either dead or resolving on an IP this device cannot use. Parking it
      // is what stops the next track from paying the same price.
      _recordFail('ytdlp');
      debugPrint(
          'StreamExtraction: dead googlevideo only for $videoId after ${overallStopwatch.elapsedMilliseconds}ms');
    }

    debugPrint('StreamExtraction: All sources failed after ${overallStopwatch.elapsedMilliseconds}ms');
    return null;
  }
}

