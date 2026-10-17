import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:muzo/utils/net_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/utils/api_constants.dart';
import 'package:muzo/services/deezer_api_service.dart';
import 'package:muzo/services/jamendo_api_service.dart';
import 'package:muzo/services/audius_api_service.dart';
import 'package:muzo/services/playability_geo_service.dart';
import 'package:muzo/services/stream_endpoint_resolver.dart';
import 'package:muzo/services/youtube_api_service.dart';
import 'package:muzo/services/youtube_music_auth.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class _SourceHealth {
  int failures = 0;
  int successes = 0;
  DateTime downUntil = DateTime.fromMillisecondsSinceEpoch(0);
}

class StreamExtractionService {
  static final Map<String, bool> isSaavnCache = {};

  /// Jitter source for Saavn retry backoff, so a burst of simultaneous
  /// resolves does not strike the rate limiter at the same instant.
  static final Random _rng = Random();

  // ─── Pré-check de jouabilité (sections du Home) ────────────────────────────
  // Mémoïsé par videoId avec un TTL court : certaines pistes (géo-bloquées,
  // IP cloud bot-checkée) ne sont simplement pas résolvables à un instant T.
  static final Map<String, bool> _playableMemo = {};
  static final Map<String, DateTime> _playableMemoAt = {};

  /// Metadata-only seed ids (iTunes `it_`, Spotify `sp_`, Deezer `dz_`, the
  /// title-only `tt_` fallback, …) that are NOT YouTube video ids. No video
  /// resolver can stream them; they are played by title+artist instead (see
  /// [getStreamUrlByTitle]).
  static final RegExp _metadataSeedRe =
      RegExp(r'^(it_|sp_|sp:|yr_|al_|user_track_|dz_|tt_)');

  static bool isMetadataSeedId(String videoId) =>
      videoId.isNotEmpty && _metadataSeedRe.hasMatch(videoId);

  // ─── Verdict « cette vidéo n'existe plus » ────────────────────────────────
  // Un résolveur qui répond « Video unavailable » ne rend pas un timeout : il
  // rend un verdict sur LA vidéo (upload supprimé, privé, région fermée). Sans
  // ce signal la cascade attendait les huit branches jusqu'au bout — mesuré sur
  // l'appareil : « All sources failed after 65368ms » de silence avant le toast.
  // Deux verdicts concordants suffisent pour conclure, et les sources trouvées
  // par TITRE (Saavn en tête) gardent la main.
  static final Map<String, Set<String>> _videoGoneBy = {};
  static final Map<String, int> _videoGoneAt = {};
  static const Duration _videoGoneTtl = Duration(minutes: 30);

  /// [source] est le label du résolveur (`relay`, `explode`, `ytapi`,
  /// `innertube`). Un seed metadata (`dz_`, `it_`…) n'est pas une vidéo : il ne
  /// peut pas être « mort », il se joue par titre.
  static void reportVideoGone(String videoId, String source) {
    if (videoId.isEmpty || isMetadataSeedId(videoId)) return;
    (_videoGoneBy[videoId] ??= <String>{}).add(source);
    _videoGoneAt[videoId] = DateTime.now().millisecondsSinceEpoch;
  }

  /// Le relais yt-dlp tourne sur le PC avec son propre client : quand il dit
  /// « Video unavailable », c'est la vidéo qui est en cause, pas l'IP du
  /// téléphone. Un seul client de l'app refusant tout (déjà arrivé : l'IP de
  /// l'appareil était revenue UNPLAYABLE sur toutes les pistes) ne doit donc
  /// jamais déclencher le raccourcissement — il en faut deux distincts.
  static bool isVideoGone(String videoId) {
    final at = _videoGoneAt[videoId];
    if (at == null) return false;
    if (DateTime.now().millisecondsSinceEpoch - at >
        _videoGoneTtl.inMilliseconds) {
      _videoGoneBy.remove(videoId);
      _videoGoneAt.remove(videoId);
      return false;
    }
    final sources = _videoGoneBy[videoId] ?? const <String>{};
    return sources.contains('relay') || sources.length >= 2;
  }

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
      // Not worth ten seconds of race for an upload two resolvers already
      // reported as removed.
      if (isVideoGone(videoId)) return null;

      try {
        final connectivity = await safeConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) return null;
      } catch (_) {}

      // Race Saavn + YoutubeExplode + InnerTube + Jamendo/Audius (fallbacks).
      return await _race([
        if (title != null && title.isNotEmpty)
          getSaavnStreamUrl(title, artist ?? '', durationSeconds: durationSeconds)
              .timeout(const Duration(seconds: 15)),
        _getYoutubeExplodeAudioUrl(videoId),
        _getInvidiousStreamUrl(videoId).timeout(const Duration(seconds: 12)),
        _getYouTubeMusicStreamUrl(videoId),
        _getCobaltStreamUrl(videoId).timeout(const Duration(seconds: 15)),
        _youtubeSlot(
            () => YouTubeMusicAuth.instance.getStreamUrlInnerTubeNoAuth(videoId),
            timeout: const Duration(seconds: 15)),
        _youtubeSlot(
            () => YouTubeApiService().getStreamUrl(videoId,
                title: title, artist: artist, preferLowBitrate: preferLowBitrate),
            timeout: const Duration(seconds: 20)),
        // The loopback relay (PC via `adb reverse`) is the resolver that still
        // works when YouTube bot-checks every direct source, and asking it costs
        // under a second when no relay is running. It used to be consulted only
        // at playback time, so a playable shelf was rated unplayable here.
        // The relay path budgets ~45s: the Render instance itself may still be
        // booting (~27s) on top of yt-dlp's 5–20s resolve. Under-budgeting this
        // is what silently killed every play made while the PC was off.
        _quiet(_getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 45))),
        if (title != null && title.isNotEmpty)
          _getJamendoFallbackUrl(title, artist ?? '')
              .timeout(const Duration(seconds: 14)),
        if (title != null && title.isNotEmpty)
          _getAudiusFallbackUrl(title, artist ?? '')
              .timeout(const Duration(seconds: 14)),
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
      if (isVideoGone(videoId)) return null;

      try {
        final connectivity = await safeConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) return null;
      } catch (_) {}

      // Cache miss: hit Saavn (fast, no YouTube bot-check) so shelf
      // enrichment actually attaches an audioUrl instead of always
      // returning null and deferring every resolve to tap time. The loopback
      // relay runs alongside it — it is the source that resolves the titles
      // YouTube refuses, and it is refused in under a second when the PC is not
      // attached. The full multi-source race still runs inside getStreamUrl at
      // playback.
      return await _race([
        if (title != null && title.isNotEmpty)
          _quiet(getSaavnStreamUrl(
            title,
            artist ?? '',
            durationSeconds: durationSeconds,
          ).timeout(const Duration(seconds: 15))),
        // A seed id is not a YouTube video, so the relay can only burn its full
        // budget on it; those items are matched by title alone. This is shelf
        // enrichment, resolved in batches of three while the home screen waits:
        // a shorter budget than playback's (45s) keeps a fully dead cascade
        // from freezing the home for minutes, and the tap itself re-resolves
        // with the full budget anyway.
        if (!isMetadataSeedId(videoId))
          _quiet(
              _getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 32))),
      ]);
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
    warmCloudRelay(); // boots the relay while the user is still browsing
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
    // Le worker tronque parfois une parenthèse (« Finesse Out The Gang Way ( »)
    // et Saavn matche le titre littéral : un crochet orphelin suffit à ne rien
    // trouver. On retire les ouvrants jamais refermés, les paires intactes
    // restent.
    cleaned = cleaned
        .replaceAll(RegExp(r'[()\[\]–—-]+\s*$'), '')
        .replaceAll(RegExp(r'\((?![^)]*\))'), '')
        .replaceAll(RegExp(r'\[(?![^\]]*\])'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }

  static Future<String?> getSaavnStreamUrl(String title, String artist, {int? durationSeconds}) async {
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

    // fast-saavn is the one free Saavn proxy that still answers from a phone's
    // residential IP (saavn.dev / saavn.me are rate-limited or dead). It returns
    // an empty body both for "no such song" and for a transient upstream
    // failure, and the two are indistinguishable — so retry once after a short
    // pause before giving up. A random jitter keeps many simultaneous resolves
    // (an artist page floods them) from hitting the limiter in lockstep.
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(
          Duration(milliseconds: 250 + _rng.nextInt(400)),
        );
      }
      final url = await _saavnOnce(queryParams, cleanTitle, cleanArtist,
          durationString, attempt);
      if (url != null) return url;
    }
    return null;
  }

  /// One fast-saavn request. Returns the built 320 URL on a real hit, null on
  /// an empty/errored body. The caller owns the retry loop.
  static Future<String?> _saavnOnce(
    Map<String, String> queryParams,
    String cleanTitle,
    String cleanArtist,
    String? durationString,
    int attempt,
  ) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    try {
      if (attempt == 0) {
        debugPrint('SaavnExtraction: Requesting stream for "$cleanTitle" by "$cleanArtist" (${durationString ?? "unknown"})');
      } else {
        debugPrint('SaavnExtraction: retrying "$cleanTitle" (attempt ${attempt + 1})');
      }
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
  /// `&kind=video` for the video track).
  ///
  /// Débranchés le 2026-10-17, mesurés depuis le réseau de l'utilisateur :
  /// `tunefy-ytdlp.vercel.app` répond 502 `Sign in to confirm you're not a
  /// bot` en 17,9 s et `vercel-proxy-murex-tau` 404 `no stream found` en
  /// 17,2 s. La cause n'est pas l'hébergeur : YouTube refuse les IP de
  /// datacenter sans cookies, donc Render, Railway ou Cloudflare échoueraient
  /// de la même façon. Liste vide = plus aucun sondage de 12 s ni course
  /// perdue d'avance. Pour brancher un relais qui marche (un PC de la maison),
  /// Settings → `ytdlpServerUrl`, ou la table `app_config` côté Supabase, sans
  /// recompiler.
  static const List<String> cloudYtDlpBases = <String>[];

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
  // Le relais local réellement fourni par le dépôt : backend/local_stream_server.py
  // (outils start_local_stream.ps1 / stream_watchdog.ps1), qui resolve avec yt-dlp
  // sur le PC et répond {"url": …} sur GET /stream. Joint du téléphone grâce à
  // `adb reverse tcp:9877 tcp:9877`.
  static const String localServerBase = 'http://127.0.0.1:9877';

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

  // ─── Filet de parallélisme YouTube ───
  // Un titre en race dix résolveurs, dont plusieurs qui frappent youtube.com
  // depuis CETTE IP ; la mise en file attendue en ajoute plusieurs autres. Le
  // plafonnement tombe en « rate limiting » en quelques secondes, et alors
  // PLUS AUCUN son ne se résout — l'impression d'une app cassée. Deux requêtes
  // YouTube à la fois suffisent ; les autres attendent leur tour. Cobalt et
  // Invidious sont volontairement hors file : ce sont des serveurs tiers, ils
  // ne salissent pas l'IP de l'appareil et les faire attendre affamerait les
  // résolveurs qui marchent.
  static const int _youtubeMaxParallel = 2;
  static int _youtubeInFlight = 0;
  static final List<Completer<void>> _youtubeWaiters = [];

  /// Le chronomètre démarre à l'obtention du créneau, pas avant : sinon un
  /// résolveur qui attend sagement son tour expire en file et l'échec est
  /// attribué à la source alors qu'elle n'a jamais eu sa chance.
  static Future<String?> _youtubeSlot(
    Future<String?> Function() resolve, {
    Duration timeout = const Duration(seconds: 20),
    bool priority = false,
  }) async {
    if (_youtubeInFlight >= _youtubeMaxParallel) {
      final releaser = Completer<void>();
      // File FIFO, SAUF pour ce que l'utilisateur attend à l'instant : posé en
      // tête, sinon un titre tapé derrière dix enrichissements de rayon
      // patientait ~57 s (mesuré) avant sa première requête YouTube.
      if (priority) {
        _youtubeWaiters.insert(0, releaser);
      } else {
        _youtubeWaiters.add(releaser);
      }
      // L'attente elle-même doit être bornée. Mesuré sur l'appareil : une
      // branche de fond avait patienté 323 s en file, le futur appelant
      // resté vivant d'autant — et le rayon suivant avec lui.
      final wait = priority
          ? const Duration(seconds: 10)
          : const Duration(seconds: 5);
      try {
        await releaser.future.timeout(wait);
      } on TimeoutException {
        _youtubeWaiters.remove(releaser);
        debugPrint('StreamExtraction: [YouTubeSlot] saturated ${wait.inSeconds}s, '
            'branch skipped (priority=$priority)');
        return null;
      }
    }
    _youtubeInFlight++;
    try {
      return await resolve().timeout(timeout);
    } finally {
      _youtubeInFlight--;
      if (_youtubeWaiters.isNotEmpty) _youtubeWaiters.removeAt(0).complete();
    }
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

  /// [verifyBytes] est pour la route de LECTURE uniquement : l'URL va être
  /// confiée à ExoPlayer, donc on sentinelle aussi les hôtes « longue vie »
  /// (relais loopback, CDNs) dont une copie périmée rend une page d'erreur 200
  /// au lieu d'un morceau — le « None of the available extractors » du log
  /// appareil. Le préchauffage (`isWarm`) laisse `false` : sonder dix URL par
  /// rayon consumait le budget réseau sans jamais jouer le son.
  static Future<String?> _localCachedStreamUrl(String videoId,
      {bool verifyBytes = false}) async {
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
      } else if (verifyBytes && url.startsWith('http')) {
        // Le statut HTTP ne dit rien du contenu : un relais qui répond 200 avec
        // son message d'erreur empoisonnait la file (rejoué à chaque tap tant
        // que l'entrée avait moins de 30 min). Un doute (pas de réponse à
        // temps) laisse la copie en place : mieux vaut tenter un son lent
        // que relancer une chasse de 60 s.
        if (await sniffAudio(url) == false) {
          debugPrint(
              'StreamExtraction: [LocalCache] $videoId ne rend plus d\'audio — purge');
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

  /// Probes the loopback relay (`http://127.0.0.1:8000`, the user's own PC via
  /// `adb reverse`). HEAD only — never GET the body, which would pull the whole
  /// track into memory just to inspect its type. Returns the proxy URL when the
  /// relay answers with audio, else null.
  static Future<String?> _tryFreedify(String videoId) async {
    final client = http.Client();
    try {
      final fdUri = Uri.parse('$freedifyBase/api/stream/ytm_$videoId');
      final fdResp =
          await client.head(fdUri).timeout(const Duration(seconds: 25));
      if (fdResp.statusCode == 200) {
        final ct = (fdResp.headers['content-type'] ?? '').toLowerCase();
        final okAudio = ct.startsWith('audio/') ||
            ct.contains('octet-stream') ||
            ct.contains('flac') ||
            ct.contains('mpeg') ||
            ct.contains('mp4') ||
            ct.contains('wav');
        if (okAudio) {
          // The player streams the proxy URL directly (Range supported), and
          // the bytes are fetched by the PC, so they are not IP-bound here.
          debugPrint('StreamExtraction: [Freedify] proxy ready ($ct)');
          return fdUri.toString();
        }
        debugPrint('StreamExtraction: [Freedify] unexpected CT: $ct');
      } else if (fdResp.statusCode != 404) {
        debugPrint('StreamExtraction: [Freedify] HTTP ${fdResp.statusCode}');
      }
    } catch (_) {
      // Connection refused is the normal "no relay running" case — keep it quiet
      // so a phone without the PC server does not spam the log on every track.
      debugPrint('StreamExtraction: [Freedify] unavailable');
    } finally {
      client.close();
    }
    return null;
  }

  /// Probes the local relay this project actually ships
  /// (`backend/local_stream_server.py`, port 9877, reachable through
  /// `adb reverse tcp:9877 tcp:9877`). It resolves with yt-dlp on the PC and
  /// answers `{"url": …}`; the phone and the PC share the same public IP, so
  /// that URL plays from the phone even though YouTube bot-checks the phone's
  /// own requests. GET is cheap here — only a small JSON body is fetched, the
  /// audio itself is streamed by the player from the returned URL.
  static Future<String?> _tryLocalServer(String videoId) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('$localServerBase/stream')
          .replace(queryParameters: {'videoId': videoId, 'kind': 'audio'});
      final resp = await client
          .get(uri)
          // yt-dlp needs 10-20s to extract a page on a cold cache; the caller's
          // 30s race budget governs, so stay just under it rather than cutting
          // a working resolve short.
          .timeout(const Duration(seconds: 28));
      if (resp.statusCode == 200) {
        final body = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
        final url = body['url'] as String?;
        if (url != null && url.isNotEmpty) {
          debugPrint('StreamExtraction: [LocalRelay] resolved via 9877');
          return url;
        }
      } else if (resp.statusCode != 404) {
        debugPrint(
            'StreamExtraction: [LocalRelay] HTTP ${resp.statusCode} ${resp.body}');
        if (resp.statusCode == 502 && _relaySaysGone(resp.body)) {
          reportVideoGone(videoId, 'relay');
        }
      }
    } on TimeoutException {
      // The relay was still inside yt-dlp; that is a slow PC, not a dead video.
      debugPrint('StreamExtraction: [LocalRelay] no answer in 28s');
    } catch (e) {
      final text = e.toString();
      if (text.contains('Connection refused') ||
          text.contains('Failed host lookup')) {
        // Nothing listening on 9877: the normal case on a phone used standalone.
        debugPrint('StreamExtraction: [LocalRelay] not running');
      } else {
        // The relay answered and then lost the connection. Saying "unavailable"
        // here is what hid the real cause for a whole session.
        debugPrint('StreamExtraction: [LocalRelay] $text');
      }
    } finally {
      client.close();
    }
    return null;
  }

  /// Pings the Render relay without waiting for it. The free instance sleeps
  /// after 15 idle minutes and needs ~27s to boot (measured on the live
  /// service), while a play only budgets ~45s for the whole yt-dlp path — so a
  /// play issued right after idle used to lose the race against the boot and
  /// report "no stream" even though the relay was healthy. Firing this when a
  /// shelf resolves (i.e. the moment the app opens) boots the instance while
  /// the user is still browsing, so the tap that follows lands on a warm
  /// relay. Throttled to one ping per 10 minutes.
  static DateTime? _lastRelayWarmAt;

  static void warmCloudRelay() {
    final base = ApiConstants.relayBaseUrl;
    if (base.isEmpty) return;
    final now = DateTime.now();
    final last = _lastRelayWarmAt;
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      return;
    }
    _lastRelayWarmAt = now;
    _pingRelayHealth(base);
  }

  static Future<void> _pingRelayHealth(String base) async {
    final client = http.Client();
    try {
      await client
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      // Speculative either way: a cold instance answers late, a dead one never
      // answers, and the play itself re-runs the whole cascade regardless.
    } finally {
      client.close();
    }
  }

  /// Cloud relay on Render (server/main.py). It resolves AND relays the audio
  /// bytes, so the phone's requests leave from the relay's public IP — this is
  /// what avoids the HTTP 403 a bare googlevideo URL returns when the phone's
  /// IP differs from the one that resolved it. Runs right after the PC-local
  /// relay (which only exists when the PC is on + gnirehtet). Skipped entirely
  /// until [ApiConstants.relayBaseUrl] is set, so a build without the relay
  /// pays nothing.
  static Future<String?> _tryCloudRelay(String videoId) async {
    final base = ApiConstants.relayBaseUrl;
    if (base.isEmpty) return null;
    final client = http.Client();
    try {
      final uri = Uri.parse('$base/stream').replace(queryParameters: {
        'videoId': videoId,
        'kind': 'audio',
        if (ApiConstants.relayKey.isNotEmpty) 'key': ApiConstants.relayKey,
      });
      final resp = await client
          .get(uri)
          // /stream resolves via yt-dlp (5–20s) and the instance itself may
          // still be booting (~27s cold). 40s leaves room for both while
          // staying under the caller's 45s race budget.
          .timeout(const Duration(seconds: 40));
      if (resp.statusCode == 200) {
        final body = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
        final url = body['url'] as String?;
        if (url != null && url.isNotEmpty) {
          debugPrint('StreamExtraction: [CloudRelay] resolved via Render relay');
          return url;
        }
      } else if (resp.statusCode == 401) {
        debugPrint('StreamExtraction: [CloudRelay] RELAY_KEY mismatch (401)');
      } else {
        debugPrint('StreamExtraction: [CloudRelay] HTTP ${resp.statusCode}');
        if (resp.statusCode == 502 && _relaySaysGone(resp.body)) {
          reportVideoGone(videoId, 'cloudrelay');
        }
      }
    } on TimeoutException {
      // Render free tier cold-starts ~30s after idle; that is slow, not dead.
      debugPrint('StreamExtraction: [CloudRelay] no answer in 28s');
    } catch (e) {
      debugPrint('StreamExtraction: [CloudRelay] $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// The relay runs yt-dlp with its own client, so its "unavailable" is a
  /// verdict about the upload (removed, private, or — the common case here — a
  /// label whose country whitelist excludes this one). `gone` is the explicit
  /// flag; the text checks stay because an older relay only has the message.
  static bool _relaySaysGone(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['gone'] == true) return true;
    } catch (_) {
      // Truncated body: fall through to the substring test.
    }
    return body.contains('Video unavailable') ||
        body.contains('not available') ||
        body.contains('UNPLAYABLE');
  }

  static Future<String?> _getYtDlpStreamUrl(String videoId) async {
    // 1. Loopback relay on the user's own PC (started with tools/relay_server.py
    //    and reachable through `adb reverse tcp:8000 tcp:8000`). Always probed:
    //    a HEAD against 127.0.0.1 fails in <1s when nothing is listening, so it
    //    costs nothing while absent and fixes YouTube-blocked playback when up.
    final local = await _tryLocalServer(videoId);
    if (local != null) return local;
    final cloudRelay = await _tryCloudRelay(videoId);
    if (cloudRelay != null) return cloudRelay;
    final loopback = await _tryFreedify(videoId);
    if (loopback != null) return loopback;

    String? cloudBase;
    bool legacyEnabled = false;
    try {
      final Box box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final saved = box.get('ytdlpServerUrl') as String?;
      if (saved != null && saved.trim().isNotEmpty) cloudBase = saved;
      legacyEnabled =
          box.get('enableLegacyYtDlpServers', defaultValue: false) == true;
    } catch (_) {}

    // 2. Expensive legacy cloud relays (config server, Vercel workers, Supabase
    //    shared cache) stay behind the explicit opt-in: they are usually dead
    //    and each probe burns 5–30s of the resolve budget before failing.
    if (!legacyEnabled) {
      debugPrint('StreamExtraction: [YtDlp] cloud relays disabled — skipping');
      return null;
    }

    // The cloud list comes from StreamEndpointResolver, which probes the
    // candidates in order and remembers the one that answered — so a redeploy
    // to a new domain is picked up without shipping a new build.
    final healthy = await _endpoints.healthyBases();
    final candidates = <String>[
      // Loopback (freedifyBase) already handled above; do not probe it twice.
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
    bool legacyEnabled = false;
    try {
      final Box box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final saved = box.get('ytdlpServerUrl') as String?;
      if (saved != null && saved.trim().isNotEmpty) configured = saved.trim();
      legacyEnabled =
          box.get('enableLegacyYtDlpServers', defaultValue: false) == true;
    } catch (_) {}

    // Same resolver as audio: probed, last known good first.
    final healthy = await _endpoints.healthyBases();

    // Deduplicated: `configured`, `healthy` and `cloudYtDlpBases` usually
    // overlap, and a host listed twice used to be awaited twice.
    final candidates = <String>{
      // Le relais local (adb reverse 9877) connaît kind=video et répond en
      // <1 s quand rien n'écoute : toujours sondé, contrairement au cloud.
      localServerBase,
      if (configured != null &&
          configured.isNotEmpty &&
          !configured.contains('trycloudflare.com'))
        configured,
      // Les relais cloud publics sont derrière l'opt-in, exactement comme pour
      // l'audio : ils sont presque toujours morts et chaque sonde brûle 15 s
      // du budget — c'est ce qui faisait « bugger » l'app à l'activation de la
      // vidéo. Sans opt-in, on tombe directement sur YoutubeExplode.
      if (legacyEnabled) ...healthy,
      if (legacyEnabled) ...cloudYtDlpBases,
    };

    // Raced, not sequential: the cloud hosts answer a bot-check 502 after
    // ~19s (or hang for the whole budget), and waiting for them before
    // reaching the loopback server meant minutes of frozen playback before
    // "Vidéo indisponible". First valid URL wins, the rest settle silently.
    final viaServer = await _race(
      candidates.map((c) => _tryVideoSource(c, videoId)).toList(),
    );
    return viaServer ?? await getSmallVideoUrlWithoutServer(videoId);
  }

  /// Résolution vidéo **sans aucun serveur** : YoutubeExplode demande la
  /// page player de YouTube et renvoie une URL déjà signée pour l'IP de
  /// l'appareil.
  ///
  /// La plus petite vidéo muxée compatible est choisie (≤ 45 Mo) : ce flux
  /// alimente une pochette animée ou un fond de paroles, jamais un plein
  /// écran — décoder du 1080p en boucle suffit à saturer un téléphone.
  static Future<String?> getSmallVideoUrlWithoutServer(String videoId) =>
      _youtubeSlot(() => _resolveSmallVideoUrl(videoId),
          timeout: const Duration(seconds: 20));

  static Future<String?> _resolveSmallVideoUrl(String videoId) async {
    if (videoId.trim().isEmpty) return null;
    try {
      final manifest = await _ytExplode.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 14));
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
      for (final stream in muxed) {
        if (stream.size.totalBytes <= _canvasMaxBytes) {
          debugPrint('StreamExtraction: [YoutubeExplode] video '
              '${stream.container} ${stream.bitrate.kiloBitsPerSecond.toInt()}kbps'
              ' sans serveur');
          return stream.url.toString();
        }
      }
      if (muxed.isNotEmpty) return muxed.first.url.toString();
    } catch (e) {
      debugPrint('StreamExtraction: [YoutubeExplode-video] $e');
    }
    return null;
  }

  static const int _canvasMaxBytes = 45 * 1024 * 1024;

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

  // Singleton YoutubeExplode — une seule session HTTP réutilisée partout.
  static final YoutubeExplode _ytExplode = YoutubeExplode();

  /// YoutubeExplode direct — résout l'audio/vidéo **sans aucun serveur**.
  ///
  /// Le package interroge youtube.com/player et renvoie l'URL googlevideo
  /// déjà signée pour l'IP de l'appareil. C'est la source la plus rapide
  /// quand elle fonctionne (~1-2 s), et elle ne dépend d'aucune infra.
  static Future<String?> _getYoutubeExplodeAudioUrl(String videoId) =>
      _youtubeSlot(() => _resolveYoutubeExplodeAudio(videoId),
          timeout: const Duration(seconds: 12));

  static Future<String?> _resolveYoutubeExplodeAudio(String videoId) async {
    try {
      final manifest =
          await _ytExplode.videos.streamsClient.getManifest(videoId);
      // Audio mp4a (compatible iOS/Android) de préférence, sinon best.
      final streams = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.kiloBitsPerSecond
            .compareTo(a.bitrate.kiloBitsPerSecond));
      if (streams.isNotEmpty) {
        final url = streams.first.url.toString();
        debugPrint(
            'StreamExtraction: [YoutubeExplode] audio ${streams.first.bitrate.kiloBitsPerSecond}kbps');
        return url;
      }
    } catch (e) {
      debugPrint('StreamExtraction: [YoutubeExplode] $e');
      if (e is VideoUnplayableException ||
          '$e'.contains('unplayable') ||
          '$e'.contains('not available')) {
        reportVideoGone(videoId, 'explode');
      }
    }
    return null;
  }

  /// Jamendo/Audius hold Creative-Commons catalogues, not the requested song.
  /// Without this gate a search for "Ma copine" happily returned the first CC
  /// track — a different artist, sometimes even a premium URL that serves an
  /// HTML body, which the player then reported as "Source error". So a fallback
  /// only counts when it carries the sought title and really serves media.
  static bool _sameTitle(String wanted, String candidate) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u00c0-\u017f]+'), ' ')
        .trim();
    final w = norm(wanted);
    final c = norm(candidate);
    if (w.isEmpty || c.isEmpty) return false;
    // Short generic words ("New", "Sad") are substrings of hundreds of
    // unrelated titles, so they only count as an exact match.
    if (w.length < 5) return c == w;
    return c == w || c.contains(w) || w.contains(c);
  }

  /// Le HEAD n'est pas une preuve : le CDN d'extraits Deezer et le validator
  /// Audius répondent 405 ou se taisent sur cette requête alors que le mp3
  /// coule parfaitement en GET. Mesuré le 2026-10-17 sur l'appareil —
  /// « [Deezer] https://cdnt-preview.dzcdn.net/… .mp3 does not serve media »
  /// sur une vraie URL d'extrait — et ce secours est précisément ce qui
  /// garantit un son quand YouTube refuse l'upload. Un refus de HEAD est donc
  /// revérifié sur les octets, pas accepté.
  static Future<String?> _validatedFallback(String url, String label) async {
    if (url.isEmpty) return null;
    final client = http.Client();
    try {
      if (await _servesMedia(client, Uri.parse(url))) return url;
    } finally {
      client.close();
    }
    if (await sniffAudio(url) == true) {
      debugPrint('StreamExtraction: [$label] HEAD refusé, GET audio confirmé');
      return url;
    }
    debugPrint('StreamExtraction: [$label] $url does not serve media');
    return null;
  }

  /// L'entête client qu'ExoPlayer envoie à la lecture : un sniff qui utilise un
  /// autre entête peut être refusé par un CDN qui joue très bien la même URL.
  static const String playerUserAgent =
      'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36';

  /// Trois réponses, pas deux : `true` = l'entête est un conteneur audio,
  /// `false` = le serveur refuse (statut non-2xx) ou rend autre chose (page
  /// HTML), `null` = il n'a pas répondu à temps. Le doute ne purge JAMAIS une
  /// URL — un CDN lent se joue très bien — seul un refus avéré écarte le
  /// secours ou la copie en cache.
  static Future<bool?> sniffAudio(String url) async {
    if (url.isEmpty) return false;
    final client = http.Client();
    final head = <int>[];
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Range'] = 'bytes=0-31'
        ..headers['User-Agent'] = playerUserAgent;
      final response =
          await client.send(request).timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      await _readLead(response.stream, head)
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } on TimeoutException {
      return null;
    } catch (e) {
      debugPrint('StreamExtraction: [Sniff] $url — $e');
      return null;
    } finally {
      client.close();
    }
    if (head.length < 12) return null;
    return looksLikeAudioBytes(Uint8List.fromList(head));
  }

  /// Lit au plus [want] octets puis se détache : `break` dans l'`await for`
  /// annule l'abonnement, donc le corps du morceau n'est jamais téléchargé
  /// pour une simple vérification d'entête.
  static Future<void> _readLead(
      Stream<List<int>> stream, List<int> sink,
      {int want = 32}) async {
    try {
      await for (final chunk in stream) {
        sink.addAll(chunk);
        if (sink.length >= want) break;
      }
    } catch (_) {
      // client.close() peut interrompre le flux pendant l'abandon du sniff :
      // rien d'exploitable à remonter.
    }
  }

  /// Sniff d'entête de conteneur audio — une page d'erreur HTTP renvoyée 200
  /// par un proxy mourant ne doit jamais atteindre ExoPlayer (il échoue en
  /// « None of the available extractors could read the stream »), et à
  /// l'inverse un vrai flux ne doit pas être jeté.
  static bool looksLikeAudioBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final b = bytes;
    // MP4/M4A/MOV: box size followed by 'ftyp'
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return true;
    }
    // MP3: ID3 tag or MPEG audio frame sync
    if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return true;
    if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return true;
    // WebM/Matroska EBML header
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
      return true;
    }
    // Ogg/Opus
    if (b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return true;
    }
    // FLAC, WAV
    if (b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43) {
      return true;
    }
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
      return true;
    }
    // AAC (ADTS)
    if (b.length > 3 && b[0] == 0xFF && (b[1] & 0xF6) == 0xF0) return true;
    return false;
  }

  /// Jamendo fallback — cherche par titre+artiste dans le catalogue CC.
  /// Retourne une URL directe (CDN statique, jamais IP-bound).
  static Future<String?> _getJamendoFallbackUrl(
      String title, String artist) async {
    try {
      final jamendo = JamendoApiService();
      final query = artist.isNotEmpty ? '$title $artist' : title;
      final tracks = await jamendo.searchTracks(query, limit: 3);
      for (final t in tracks) {
        if (!_sameTitle(title, t.name)) continue;
        final url = await _validatedFallback(t.audioUrl, 'Jamendo');
        if (url != null) {
          debugPrint('StreamExtraction: [Jamendo] "${t.name}" — direct CDN');
          return url;
        }
      }
    } catch (e) {
      debugPrint('StreamExtraction: [Jamendo] $e');
    }
    return null;
  }

  /// Audius fallback — cherche le titre exact dans le catalogue décentralisé
  /// et rend la signed stream URL: full file, no YouTube, no relay.
  static Future<String?> _getAudiusFallbackUrl(
      String title, String artist) async {
    try {
      final audius = AudiusApiService();
      // Audius' genre filter only matches its own declared tokens, so a title
      // word passed as a genre answered 0 hits every time — the endpoint that
      // understands a song name is the full-text search.
      final queries = <String>[
        if (artist.trim().isNotEmpty) '$title $artist',
        title,
      ];
      for (final q in queries) {
        final tracks = await audius.searchTracks(q, limit: 5);
        for (final t in tracks) {
          if (t.streamUrl.isEmpty || !_sameTitle(title, t.title)) continue;
          final url = await _validatedFallback(t.streamUrl, 'Audius');
          if (url != null) {
            debugPrint('StreamExtraction: [Audius] "${t.title}" — signed stream');
            return url;
          }
        }
      }
    } catch (e) {
      debugPrint('StreamExtraction: [Audius] $e');
    }
    return null;
  }

  /// Deezer's 30-second clip — the one audio this network can always fetch.
  /// French "- Topic" uploads are licensed to a country whitelist that does not
  /// include Benin, so YouTube answers `UNPLAYABLE`/"Video unavailable" for them
  /// from here (verified on the PC's own IP) while `cdnt-preview.dzcdn.net`
  /// answers 200 in two seconds. An extract the user hears beats a full track
  /// that never starts, and it is the only honest answer when every
  /// full-track resolver has already said no.
  /// Public door to the clip, for the one caller that has already exhausted the
  /// full-length hunt (`ResolvingAudioSource`, after its own retry). Keeping it
  /// out of [getStreamUrl] matters: the dead-URL retries inside the player call
  /// that method expecting a full track, and handing them a 30 s extract would
  /// make them stop looking for audio that does exist.
  static Future<String?> catalogClipUrl(String title, String artist) async {
    if (title.isEmpty || _isDown('deezer')) return null;
    final clip = await _quiet(
        _getDeezerClipUrl(title, _cleanArtist(artist))
            .timeout(const Duration(seconds: 12)));
    if (clip != null) {
      _recordOk('deezer');
      return clip;
    }
    // "No clip for this title" is a content answer, not an outage — same
    // generous threshold as Saavn, so one artist page cannot park the source.
    _recordFail('deezer', threshold: 6);
    return null;
  }

  static Future<String?> _getDeezerClipUrl(String title, String artist) async {
    try {
      final queries = <String>[
        if (artist.trim().isNotEmpty) '$title ${artist.trim()}',
        title,
      ];
      for (final q in queries) {
        final tracks = await DeezerApiService().searchTracks(q, limit: 6);
        for (final t in tracks) {
          final clip = t.metadata?['dzPreview']?.toString() ?? '';
          if (clip.isEmpty || !_sameTitle(title, t.title)) continue;
          final url = await _validatedFallback(clip, 'Deezer');
          if (url != null) {
            debugPrint('StreamExtraction: [Deezer] "${t.title}" — 30s clip');
            return url;
          }
        }
      }
    } catch (e) {
      debugPrint('StreamExtraction: [Deezer] $e');
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
  static Future<String?> _getYouTubeMusicStreamUrl(String videoId,
          {bool priority = false}) =>
      _youtubeSlot(() => _resolveYouTubeMusic(videoId),
          timeout: const Duration(seconds: 15), priority: priority);

  static Future<String?> _resolveYouTubeMusic(String videoId) async {
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

  static void _recordFail(String source, {int? threshold}) {
    final h = _health.putIfAbsent(source, () => _SourceHealth());
    h.failures++;
    // A caller-supplied threshold is for sources whose "no result" is a normal
    // content answer rather than an outage (see Saavn below): parking the one
    // resolver that still works from a phone starves every next track.
    if (h.failures >= (threshold ?? _failureThreshold)) {
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

  /// Title-driven sources only. A metadata seed (`dz_`, `it_`, `sp_`…) carries
  /// no YouTube id, so no video resolver can help it — but its title and artist
  /// are real, and these three answer to those alone. Without this path every
  /// Deezer/iTunes card the home sections now show would report "unavailable".
  static Future<String?> getStreamUrlByTitle(
    String videoId, {
    required String? title,
    String? artist,
    int? durationSeconds,
    Set<String> avoidSources = const {},
  }) async {
    if (title == null || title.isEmpty) return null;
    final cached =
        await _localCachedStreamUrl(videoId, verifyBytes: true);
    if (cached != null) {
      debugPrint('StreamExtraction: [LocalCache] served seed $videoId');
      return cached;
    }
    final cleanArtist = _cleanArtist(artist ?? '');
    final attempts = <(String, Future<String?>)>[
      if (!avoidSources.contains('saavn') && !_isDown('saavn'))
        (
          'saavn',
          _quiet(getSaavnStreamUrl(title, cleanArtist,
                  durationSeconds: durationSeconds)
              .timeout(const Duration(seconds: 18)))
        ),
      if (!avoidSources.contains('jamendo') && !_isDown('jamendo'))
        (
          'jamendo',
          _quiet(_getJamendoFallbackUrl(title, cleanArtist)
              .timeout(const Duration(seconds: 14)))
        ),
      if (!avoidSources.contains('audius') && !_isDown('audius'))
        (
          'audius',
          _quiet(_getAudiusFallbackUrl(title, cleanArtist)
              .timeout(const Duration(seconds: 14)))
        ),
      // Guarantor of audible sound: Saavn/Jamendo/Audius simply do not carry
      // most French catalog titles, and this device's IP cannot get YouTube.
      if (!avoidSources.contains('deezer'))
        (
          'deezer',
          _quiet(_getDeezerClipUrl(title, cleanArtist)
              .timeout(const Duration(seconds: 12)))
        ),
    ];
    if (attempts.isEmpty) return null;

    String? hitSource;
    Future<String?> guarded(String label, Future<String?> task) async {
      final url = await task;
      if (url == null || url.isEmpty) return null;
      hitSource ??= label;
      return url;
    }

    final winner =
        await _race(attempts.map((a) => guarded(a.$1, a.$2)).toList());
    if (winner != null && hitSource != null) {
      _recordOk(hitSource!);
      debugPrint('StreamExtraction: seed $videoId streamed via $hitSource');
      isSaavnCache[videoId] = hitSource == 'saavn';
      await _cacheStreamUrl(videoId, winner);
      return winner;
    }
    for (final a in attempts) {
      _recordFail(a.$1, threshold: 6);
    }
    debugPrint('StreamExtraction: no title source for seed $videoId');
    return null;
  }

  static Future<String?> getStreamUrl(
  String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
    bool skipSaavn = false,
    bool priority = false,
    bool allowGeoSwap = true,
    Set<String> avoidSources = const {},
  }) async {
    final overallStopwatch = Stopwatch()..start();
    debugPrint('StreamExtraction: --- getStreamUrl started for $videoId ---');
    final lowBitrate = _preferLowBitratePref;

    // Metadata seeds (dz_/it_/sp_…) are not YouTube ids — the video resolvers
    // below can never answer for them. They can still be streamed by title, so
    // try the title-driven sources instead of refusing the track outright.
    if (isMetadataSeedId(videoId)) {
      debugPrint('StreamExtraction: metadata seed $videoId — title-only resolve');
      return getStreamUrlByTitle(
        videoId,
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
        avoidSources: avoidSources,
      );
    }

    // 0. Local disk cache — instant, zero network
    final localCached =
        await _localCachedStreamUrl(videoId, verifyBytes: true);
    if (localCached != null) {
      debugPrint('StreamExtraction: [LocalCache] served in ${overallStopwatch.elapsedMilliseconds}ms');
      return localCached;
    }

    // Fast offline guard
    try {
      final connectivity = await safeConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        debugPrint('StreamExtraction: offline — skipping network cascade for $videoId');
        return null;
      }
    } catch (_) {}

    // Upload confirmé retiré (deux verdicts concordants) : plus aucun résolveur
    // par id ne peut répondre pour lui. Le morceau vit peut-être ailleurs →
    // chasse par titre+artiste, immédiate au lieu des 65 s de cascade morte.
    if (isVideoGone(videoId)) {
      debugPrint('StreamExtraction: $videoId already gone — title-only resolve');
      return getStreamUrlByTitle(
        videoId,
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
        avoidSources: avoidSources,
      );
    }

    // 1. Saavn gets a short HEAD START instead of a serial await. Its static CDN
    // URLs are not IP-bound, so when it answers the track is instantly
    // playable — but waiting the full 18s for a title it does not carry used to
    // delay every other source by that much, which is what the user heard as
    // "le son ne se lance pas". The rest of the cascade is started BEFORE we
    // wait, so a Saavn miss costs nothing.
    final saavnEligible = title != null &&
        title.isNotEmpty &&
        !skipSaavn &&
        !avoidSources.contains('saavn') &&
        !_isDown('saavn');
    final Future<String?>? saavnTask = saavnEligible
        ? _quiet(getSaavnStreamUrl(
            title,
            artist ?? '',
            durationSeconds: durationSeconds,
          ).timeout(const Duration(seconds: 18)))
        : null;

    // 2. Every remaining source runs concurrently, each labelled so a dead URL
    // is blamed on the resolver that produced it. They were all charged to
    // "ytdlp" before, so one expired InnerTube link parked the loopback relay —
    // the one resolver that always works with the PC attached — and every
    // following track failed with it.
    //
    // Verdict géo d'abord, quand un échange de voie reste possible : un upload
    // dont `availableCountries` exclut le pays de l'appareil est fermé pour
    // TOUTES les résolutions par id, simultanément (mesuré 6/6 contre le relais
    // yt-dlp depuis l'IP béninoise, le 2026-10-15 : « Video unavailable » en
    // 6-8 s sur les trois ids fermés, flux googlevideo livré sur les trois
    // ouverts). Le verdict coûte ~400 ms et se paie une fois par upload
    // (mémoire + disque, 30 j), alors que la cascade morte coûte 30-65 s de
    // silence à chaque écoute. Saavn est déjà parti au-dessus : lui joue par
    // TITRE et ne dépend pas de cette vidéo.
    final geoSwapPossible = allowGeoSwap && title != null && title.isNotEmpty;
    final geoClosed =
        geoSwapPossible && await PlayabilityGeoService.isClosedHere(videoId);
    final attempts = <(String, Future<String?>)>[
      if (!avoidSources.contains('explode') && !_isDown('explode'))
        (
          'explode',
          _quiet(_youtubeSlot(
              () => _resolveYoutubeExplodeAudio(videoId),
              timeout: const Duration(seconds: 12),
              priority: priority))
        ),
      if (!avoidSources.contains('innertube') && !_isDown('innertube'))
        (
          'innertube',
          _quiet(_youtubeSlot(
              () => YouTubeMusicAuth.instance
                  .getStreamUrlInnerTubeNoAuth(videoId),
              timeout: const Duration(seconds: 15),
              priority: priority))
        ),
      if (!avoidSources.contains('ytmusic') && !_isDown('ytmusic'))
        (
          'ytmusic',
          _quiet(_getYouTubeMusicStreamUrl(videoId, priority: priority))
        ),
      // Loopback relay (user's PC via adb reverse) consulted directly here, not
      // only as the dead-googlevideo retry: when YouTube bot-checks every direct
      // source it returns no URL at all, so the retry never fired and the relay
      // went unused. Cheap when absent (<1s refused), the fix when present.
      // 45s, not 30: on a phone with the PC off this is the cloud relay, which
      // may still be booting (~27s on Render's free tier) on top of yt-dlp's
      // 5–20s resolve. The old 30s budget cut it off every single time, which
      // is what made playback fail while the PC was off.
      if (!avoidSources.contains('ytdlp'))
        ('ytdlp', _quiet(_getYtDlpStreamUrl(videoId).timeout(const Duration(seconds: 45)))),
      if (!avoidSources.contains('invidious') && !_isDown('invidious'))
        (
          'invidious',
          _quiet(
              _getInvidiousStreamUrl(videoId).timeout(const Duration(seconds: 14)))
        ),
      if (!avoidSources.contains('cobalt') && !_isDown('cobalt'))
        (
          'cobalt',
          _quiet(_getCobaltStreamUrl(videoId).timeout(const Duration(seconds: 20)))
        ),
      (
        'ytapi',
        _quiet(_youtubeSlot(
            () => YouTubeApiService().getStreamUrl(videoId,
                title: title, artist: artist, preferLowBitrate: lowBitrate),
            timeout: const Duration(seconds: 20),
            priority: priority))
      ),
      // Fallback non-YouTube : catalogue CC/décentralisé, URLs statiques.
      if (title != null && title.isNotEmpty && !avoidSources.contains('jamendo'))
        (
          'jamendo',
          _quiet(
              _getJamendoFallbackUrl(title, artist ?? '').timeout(const Duration(seconds: 14)))
        ),
      if (title != null && title.isNotEmpty && !avoidSources.contains('audius'))
        (
          'audius',
          _quiet(_getAudiusFallbackUrl(title, artist ?? '').timeout(const Duration(seconds: 14)))
        ),
    ];

    // Whoever answers first wins — but Saavn keeps a 6s priority window, because
    // its link needs no probe while a googlevideo one can still 403 on this
    // device. Waiting past that only reproduces the old serial stall.
    String? winner;
    String? winnerSource;
    if (saavnTask != null) {
      final grace = Future.delayed(const Duration(seconds: 6), () => null);
      String? early;
      try {
        early = await Future.any(<Future<String?>>[saavnTask, grace]);
      } catch (_) {}
      if (early != null && early.isNotEmpty) {
        winner = early;
        winnerSource = 'saavn';
      }
    }
    // First resolver whose link actually plays wins; the others keep running in
    // the background. Waiting for all of them (the old Future.wait) made a track
    // cost the slowest source's full budget even when YoutubeExplode had the
    // answer in two seconds.
    String? hitSource;
    // Deux verdicts concordants « cette vidéo est retirée » : on cesse
    // d'attendre les branches YouTube (14-30 s chacune, 65 s au total mesuré sur
    // l'appareil) et il ne reste que ce qui répond par TITRE — Saavn, dont la
    // fenêtre est déjà ouverte.
    final gone = Completer<String?>();
    void noteVerdicts() {
      if (!isVideoGone(videoId) || gone.isCompleted) return;
      debugPrint('StreamExtraction: $videoId confirmed gone — cascade cut at '
          '${overallStopwatch.elapsedMilliseconds}ms');
      _playableMemo[videoId] = false;
      _playableMemoAt[videoId] = DateTime.now();
      gone.complete(null);
    }

    Future<String?> guarded(String label, Future<String?> task) async {
      final candidate = await task;
      if (candidate == null || candidate.isEmpty) {
        noteVerdicts();
        return null;
      }
      final ensured = await ensurePlayableUrl(videoId, candidate);
      if (ensured == null || ensured.isEmpty) {
        // The URL came back but would not play here: whatever produced it is
        // either dead or resolving on an IP this device cannot use. Park it —
        // and only it — so the next track does not pay the same price.
        _recordFail(label);
        debugPrint('StreamExtraction: dead link from $label for $videoId');
        return null;
      }
      hitSource ??= label;
      return ensured;
    }

    // Upload fermé au pays : les sept résolveurs PAR ID sont retirés d'un coup
    // (les garder ferait payer 12-30 s de plus à une piste qui ne peut pas
    // aboutir) et remplacés par la seule voie qui reste — un AUTRE upload du
    // même morceau, ouvert ici. Les branches par TITRE (jamendo, audius) et
    // Saavn gardent leur place : elles ne dépendent pas de cette vidéo.
    final liveAttempts = <(String, Future<String?>)>[
      for (final attempt in attempts)
        if (!geoClosed || !_byIdResolvers.contains(attempt.$1)) attempt,
      if (geoClosed)
        (
          'geoswap',
          _quiet(_geoSwapStream(videoId,
              title: title,
              artist: artist,
              durationSeconds: durationSeconds,
              priority: priority))
        ),
    ];
    if (winner == null) {
      winner = await Future.any(<Future<String?>>[
        _race(liveAttempts.map((a) => guarded(a.$1, a.$2)).toList()),
        gone.future,
      ]);
      winnerSource = hitSource;
    }
    // Saavn may still answer after its priority window (a slow dio box): take it
    // rather than reporting a failure the relay could have avoided.
    if (winner == null && saavnTask != null) {
      final String? late;
      if (gone.isCompleted) {
        // The video itself is gone — Saavn keeps only a short remaining window
        // instead of its full 18 s, which is what turned a dead upload into a
        // minute of silence.
        late = await Future.any(<Future<String?>>[
          saavnTask,
          Future.delayed(const Duration(seconds: 4), () => null),
        ]);
      } else {
        late = await saavnTask;
      }
      if (late != null && late.isNotEmpty) {
        winner = late;
        winnerSource = 'saavn';
      }
    }

    if (winner != null && winnerSource != null) {
      _recordOk(winnerSource);
      debugPrint('StreamExtraction: succeeded via $winnerSource in '
          '${overallStopwatch.elapsedMilliseconds}ms');
      isSaavnCache[videoId] = winnerSource == 'saavn';
      await _cacheStreamUrl(videoId, winner);
      return winner;
    }

    // A Saavn miss is usually "this title is not on Saavn" (karaoke and cover
    // versions dominate that), not "the proxy is down" — and the two are
    // indistinguishable from the response. Park after 6 consecutive misses
    // instead of 2: with 2, one artist page full of karaoke titles parked
    // Saavn for 30s, and it is currently the only source that still
    // resolves from a phone, so every subsequent track failed.
    isSaavnCache[videoId] = false;
    if (saavnEligible) _recordFail('saavn', threshold: 6);

    debugPrint('StreamExtraction: All sources failed after ${overallStopwatch.elapsedMilliseconds}ms');
    return null;
  }

  /// Résolveurs qui ne savent répondre que « donne-moi le flux de CETTE
  /// vidéo » : quand l'upload est fermé au pays du téléphone, ils échouent
  /// tous en même temps et ne méritent pas leur budget cumulé (12-30 s).
  /// Les branches par TITRE (saavn, jamendo, audius, deezer) en sont exclues :
  /// elles trouvent le morceau chez un autre distributeur.
  static const Set<String> _byIdResolvers = {
    'explode',
    'innertube',
    'ytmusic',
    'ytdlp',
    'invidious',
    'cobalt',
    'ytapi',
  };

  /// L'échange de voie : le même morceau existe presque toujours en upload
  /// OUVERT (chaîne artiste / VEVO) alors que l'upload « - Topic » sous
  /// licence est bloqué hors de sa liste de pays. Une fois trouvé, le couple
  /// id ferme -> id ouvert est mémorisé, donc la piste ne repaie plus la
  /// recherche. [allowGeoSwap] est coupé à la récursion pour qu'un ouvert
  /// supposé ne puisse pas déclencher une seconde chasse.
  static Future<String?> _geoSwapStream(
    String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
    bool priority = false,
  }) async {
    final alt = await PlayabilityGeoService.findOpenAlternate(
      title: title ?? '',
      artist: artist ?? '',
      skipId: videoId,
    );
    if (alt == null) return null;
    debugPrint('StreamExtraction: [Geo] $videoId fermé ici -> upload ouvert '
        '${alt.videoId} (« ${alt.title} » • ${alt.channel})');
    return getStreamUrl(
      alt.videoId,
      title: title,
      artist: artist,
      durationSeconds: durationSeconds,
      skipSaavn: true,
      priority: priority,
      allowGeoSwap: false,
    ).timeout(const Duration(seconds: 45));
  }

  /// Awaits [future] and reports any failure (including the timeout that raised
  /// it) as "no answer", so one dead resolver cannot abort the whole cascade.
  static Future<String?> _quiet(Future<String?> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }
}

