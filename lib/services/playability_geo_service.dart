import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/content_cache_service.dart';
import 'package:muzo/utils/api_constants.dart';

/// Can this YouTube upload be streamed from the country the device leaves on?
enum UploadGeo { open, closed, unknown }

/// An upload of the same song that is NOT closed to us.
class OpenAlternate {
  const OpenAlternate({
    required this.videoId,
    required this.title,
    required this.channel,
  });

  final String videoId;
  final String title;
  final String channel;
}

/// Geo verdict for YouTube uploads — the durable answer to « les sons Bénin
/// échouent ».
///
/// Measured on the user's own exit IP (137.255.199.25, AS328228, Abomey-Calavi)
/// on 2026-10-15, against the real resolver (`backend/local_stream_server.py`,
/// yt-dlp) — 6 ids, correlation 6/6:
///   `availableCountries` WITHOUT BJ  ->  `Video unavailable` (6-8 s wasted)
///   `availableCountries` WITH BJ     ->  googlevideo stream served (6-11 s)
/// The licence list is readable from an unauthenticated InnerTube `player`
/// response in ~400 ms, with no stream extraction, and it survives the
/// bot-check that makes the `playabilityStatus` itself useless from this IP
/// (`dQw4w9WgXcQ` answers UNPLAYABLE here for every client, yet plays).
///
/// So the verdict is cheap, and a closed upload is closed for EVERY id-based
/// resolver at once — which is why a rap FR / rap BJ title used to burn 30-65 s
/// and land on the 30 s Deezer excerpt. With the verdict, the same tap has a
/// chance at the full track: a label's `- Topic` upload is usually whitelisted
/// to ~120 countries, while the artist's own channel upload of that very song
/// is world-wide.
class PlayabilityGeoService {
  PlayabilityGeoService._();

  static const String _playerUrl = 'https://www.youtube.com/youtubei/v1/player';

  /// Public InnerTube web key (no secret, ships in every youtubei client).
  static const String _playerKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  static const Duration _verdictTtl = Duration(days: 30);
  static const Duration _countryTtl = Duration(days: 30);
  static const int _alternateProbeLimit = 5;

  static final Map<String, UploadGeo> _memo = <String, UploadGeo>{};
  static final Map<String, Future<UploadGeo>> _inFlight =
      <String, Future<UploadGeo>>{};
  static String? _country;
  static Future<String>? _countryFetch;

  /// Pure: the licence list inside a player response. Kept separate so the
  /// verdict can be tested without a network.
  static List<String> countriesOf(Map<String, dynamic> playerJson) {
    final mf = playerJson['microformat'];
    final renderer = mf is Map ? mf['playerMicroformatRenderer'] : null;
    final list = renderer is Map ? renderer['availableCountries'] : null;
    if (list is! List) return const <String>[];
    return list.whereType<String>().toList();
  }

  /// Pure: an empty list means YouTube told us nothing — that must never be
  /// read as « fermé », or a title would be exiled to the excerpt path.
  static UploadGeo verdictForCountries(
    List<String> countries,
    String deviceCountry,
  ) {
    if (countries.isEmpty || deviceCountry.isEmpty) return UploadGeo.unknown;
    final want = deviceCountry.toUpperCase();
    return countries.any((c) => c.toUpperCase() == want)
        ? UploadGeo.open
        : UploadGeo.closed;
  }

  /// Country the DEVICE exits on — not the phone's locale, not the SIM. This is
  /// the value YouTube compares `availableCountries` against.
  static Future<String> deviceCountry() async {
    final known = _country;
    if (known != null && known.isNotEmpty) return known;
    return _countryFetch ??= _readCountry()
        .then((c) => _country = c)
        .whenComplete(() => _countryFetch = null);
  }

  static Future<String> _readCountry() async {
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh('geo|country', maxAge: _countryTtl);
      if (cached != null && cached.isNotEmpty) {
        final code = '${cached.first}'.toUpperCase();
        if (code.length == 2) return code;
      }
    } catch (_) {}
    final client = http.Client();
    try {
      final geojs = await client
          .get(Uri.parse('https://get.geojs.io/v1/ip/country.json'))
          .timeout(const Duration(seconds: 6));
      if (geojs.statusCode == 200) {
        final code =
            '${(jsonDecode(geojs.body) as Map?)?['country'] ?? ''}'.toUpperCase();
        if (code.length == 2) {
          await ContentCacheService.instance
              .writeJson('geo|country', <dynamic>[code]);
          debugPrint('[Geo] pays de sortie de l appareil: $code');
          return code;
        }
      }
    } catch (e) {
      debugPrint('[Geo] geojs indisponible: $e');
    } finally {
      client.close();
    }
    try {
      final alt = http.Client();
      try {
        final ipinfo = await alt
            .get(Uri.parse('https://ipinfo.io/country'))
            .timeout(const Duration(seconds: 6));
        final code = ipinfo.body.trim().toUpperCase();
        if (code.length == 2) {
          await ContentCacheService.instance
              .writeJson('geo|country', <dynamic>[code]);
          debugPrint('[Geo] pays de sortie de l appareil: $code (ipinfo)');
          return code;
        }
      } finally {
        alt.close();
      }
    } catch (e) {
      debugPrint('[Geo] ipinfo indisponible: $e');
    }
    return '';
  }

  /// Verdict for one upload, from memory, then disk, then InnerTube. Never
  /// throws, never longer than its probe budget.
  static Future<UploadGeo> verdictFor(String videoId) {
    final cached = _memo[videoId];
    if (cached != null) return Future.value(cached);
    final running = _inFlight[videoId];
    if (running != null) return running;
    final future = _verdictFor(videoId);
    _inFlight[videoId] = future;
    return future.whenComplete(() => _inFlight.remove(videoId));
  }

  static Future<UploadGeo> _verdictFor(String videoId) async {
    final store = ContentCacheService.instance;
    try {
      final cached = await store.readJsonIfFresh('geo|$videoId',
          maxAge: _verdictTtl);
      if (cached != null && cached.isNotEmpty) {
        final mark = '${cached.first}';
        final answer = mark == 'o'
            ? UploadGeo.open
            : mark == 'c'
                ? UploadGeo.closed
                : null;
        if (answer != null) {
          _memo[videoId] = answer;
          return answer;
        }
      }
    } catch (_) {}

    final clock = Stopwatch()..start();
    final country = await deviceCountry();
    final client = http.Client();
    try {
      final resp = await client
          .post(
            Uri.parse('$_playerUrl?key=$_playerKey&prettyPrint=false'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'context': <String, dynamic>{
                'client': <String, dynamic>{
                  'clientName': 'WEB',
                  'clientVersion': '2.20251001.00.00',
                  'hl': 'en',
                  'gl': country.isEmpty ? 'US' : country,
                },
              },
              'videoId': videoId,
            }),
          )
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return UploadGeo.unknown;
      final verdict = verdictForCountries(
        countriesOf(
            (jsonDecode(resp.body) as Map).cast<String, dynamic>()),
        country,
      );
      if (verdict != UploadGeo.unknown) {
        _memo[videoId] = verdict;
        await store.writeJson(
            'geo|$videoId', <dynamic>[verdict == UploadGeo.open ? 'o' : 'c']);
        debugPrint('[Geo] $videoId: ${verdict.name} pour $country '
            '(${clock.elapsedMilliseconds}ms)');
      }
      return verdict;
    } catch (e) {
      debugPrint('[Geo] verdict indisponible pour $videoId: $e');
      return UploadGeo.unknown;
    } finally {
      client.close();
    }
  }

  /// True only when the upload is PROVEN closed here. An unknown verdict keeps
  /// every resolver available, so this feature can only ever save time, never
  /// cost a title its normal chances.
  static Future<bool> isClosedHere(String videoId) async =>
      await verdictFor(videoId) == UploadGeo.closed;

  /// The same song on an upload that IS open here. `filter=videos` on purpose:
  /// `filter=songs` returns only the label's `- Topic` uploads, which are the
  /// ones carrying the whitelist. Verified 2026-10-15 — `FIAlvJKc3Y0` (Ronisia
  /// « Ennemi », Topic, 122 pays sans BJ) is `Video unavailable`, while the
  /// artist's own channel upload of the same clip (`smrKejClj5M`, 248 pays)
  /// yields a googlevideo stream from this IP.
  ///
  /// The chosen id is remembered under the blocked one, so the search is paid
  /// once per song, not once per tap.
  static Future<OpenAlternate?> findOpenAlternate({
    required String title,
    required String artist,
    required String skipId,
  }) async {
    if (title.trim().isEmpty) return null;
    final remembered = await _rememberedAlternate(skipId);
    if (remembered != null) return remembered;

    final query = artist.trim().isEmpty ? title : '$title $artist';
    final candidates =
        await _videoCandidates(query, title: title, artist: artist, skipId: skipId);
    if (candidates.isEmpty) {
      debugPrint('[Geo] aucun doublon trouvé pour « $query »');
      return null;
    }
    final verdicts = await Future.wait(<Future<_Scored?>>[
      for (final c in candidates)
        verdictFor(c.videoId!).then((v) => _Scored(c, v)),
    ]);
    for (final scored in verdicts.whereType<_Scored>()) {
      if (scored.geo != UploadGeo.open) continue;
      await _remember(skipId, scored.item);
      debugPrint('[Geo] $skipId ferme ici, « ${scored.item.title} » '
          '(${scored.item.channelName}) est ouvert — upload échangé');
      return OpenAlternate(
        videoId: scored.item.videoId!,
        title: scored.item.title,
        channel: scored.item.channelName ?? '',
      );
    }
    debugPrint('[Geo] ${candidates.length} doublons de « $query », tous fermés');
    return null;
  }

  static Future<List<MuzoItem>> _videoCandidates(
    String query, {
    required String title,
    required String artist,
    required String skipId,
  }) async {
    final client = http.Client();
    try {
      final uri =
          Uri.parse('${ApiConstants.extendedWorkerBaseUrl}/api/yt_search')
              .replace(queryParameters: {
        'q': _ascii(query),
        'filter': 'videos',
      });
      final resp =
          await client.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const <MuzoItem>[];
      final data = jsonDecode(resp.body);
      final results = data is Map ? data['results'] : null;
      if (results is! List) return const <MuzoItem>[];
      final items = results
          .whereType<Map>()
          .map((json) => MuzoItem.fromJson(json.cast<String, dynamic>()))
          .where((item) =>
              item.videoId != null &&
              item.videoId!.isNotEmpty &&
              item.videoId != skipId &&
              matchesNamedEntity(item, title, artist))
          .toList()
        ..sort((a, b) => scoreAlternate(b) - scoreAlternate(a));
      return items.take(_alternateProbeLimit).toList();
    } catch (e) {
      debugPrint('[Geo] recherche de doublons échouée: $e');
      return const <MuzoItem>[];
    } finally {
      client.close();
    }
  }

  /// Prefer the artist's own / official channel, then a real song length, then
  /// whatever has been watched the most — a 2-view re-encode is a last resort.
  static int scoreAlternate(MuzoItem item) {
    final channel = (item.channelName ?? '').toLowerCase();
    final title = item.title.toLowerCase();
    var score = 0;
    if (channel.contains('topic') || title.contains('clip officiel')) {
      score += 6;
    }
    if (channel.contains('official') || channel.contains('vevo')) score += 5;
    final seconds = item.durationSeconds ?? 0;
    if (seconds >= 90 && seconds <= 480) score += 4;
    if (title.contains('parole') ||
        title.contains('lyric') ||
        title.contains('slowed') ||
        title.contains('speed')) {
      score -= 5;
    }
    score += (_viewsOf(item) ~/ 100000).clamp(0, 6);
    return score;
  }

  static int _viewsOf(MuzoItem item) =>
      int.tryParse((item.views ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  static Future<OpenAlternate?> _rememberedAlternate(String blockedId) async {
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh('geo|swap|$blockedId', maxAge: _verdictTtl);
      if (cached == null || cached.length < 3) return null;
      return OpenAlternate(
        videoId: '${cached[0]}',
        title: '${cached[1]}',
        channel: '${cached[2]}',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _remember(String blockedId, MuzoItem alt) async {
    try {
      await ContentCacheService.instance.writeJson('geo|swap|$blockedId',
          <dynamic>[alt.videoId ?? '', alt.title, alt.channelName ?? '']);
    } catch (_) {}
  }

  /// The worker answers HTTP 400/500 for a `q` with accents, so queries built
  /// from French titles are folded to ASCII here as everywhere else.
  static String _ascii(String value) {
    final folded = value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ë', 'e')
        .replaceAll('ç', 'c')
        .replaceAll('œ', 'oe');
    final stripped =
        folded.replaceAll(RegExp(r"[^a-z0-9 &\-().,']"), ' ').trim();
    return stripped.isEmpty ? value : stripped;
  }

}

class _Scored {
  const _Scored(this.item, this.geo);
  final MuzoItem item;
  final UploadGeo geo;
}
