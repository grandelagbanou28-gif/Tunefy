import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/content_cache_service.dart';

/// Radio Browser — thousands of real internet radio stations, **no key, no
/// account, no card** (https://api.radio-browser.info), CORS-friendly and
/// documented as rate-limit-free.
///
/// Why it matters here: a station's `url_resolved` is a **direct MP3/AAC
/// stream**. It plays with no YouTube id, no worker, no yt-dlp relay and no
/// server of ours — the one content type in the app that satisfies "aucun son
/// ne doit échouer" without any backend at all. `resultType` is set to
/// `radio`; the audio handler has a branch for it that skips the
/// "downloaded titles only" rule (a live stream is never bytes on disk) while
/// still refusing anything when the device is really offline.
///
/// Only HTTPS stations are ever returned (`onlyssl=true`): Android blocks
/// cleartext traffic, so an `http://` stream would look like a broken player.
class RadioBrowserService {
  RadioBrowserService._();
  static final RadioBrowserService instance = RadioBrowserService._();

  /// `all.` answers from a rotating pool of mirrors; individual mirrors
  /// intermittently reset connections, so a failure moves to the next host.
  static const List<String> _mirrors = [
    'all.api.radio-browser.info',
    'de2.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'de1.api.radio-browser.info',
  ];

  static const Duration _timeout = Duration(seconds: 10);
  static const String _ua = 'MuzoTunefy/1.0 (app musique perso, 1 requete/utilisateur)';

  final Map<String, List<MuzoItem>> _memory = {};

  /// Stations for one genre tag, optionally narrowed to one country. At least
  /// one of the two must be given (a country-only row is how "Radios du Bénin"
  /// works — those stations carry no useful genre tag).
  /// Ranked by real listener clicks, deduplicated by stream endpoint (the
  /// registry carries the same station several times), cached for
  /// [ContentCacheService.browseTtl] like every other browse row.
  Future<List<MuzoItem>> stations({
    String tag = '',
    String? countryCode,
    int limit = 24,
  }) async {
    final t = tag.trim().toLowerCase();
    final cc = (countryCode ?? '').trim().toUpperCase();
    if (t.isEmpty && cc.isEmpty) return const [];
    final key = 'rad|$t|${cc.toLowerCase()}|$limit';
    final memKey = '$t|${cc.toLowerCase()}';
    final cached = _memory[memKey];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final fresh = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.browseTtl);
      if (fresh != null && fresh.isNotEmpty) {
        final items = _decode(fresh);
        if (items.isNotEmpty) {
          _memory[memKey] = items;
          return items;
        }
      }
    } catch (_) {}

    final params = <String, String>{
      'hidebroken': 'true',
      'onlyssl': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      // The registry indexes one station under dozens of tags; asking for more
      // rows than we display keeps the usable ones after dedup and the
      // "must have a stream URL" filter.
      'limit': '${(limit * 3).clamp(limit, 100)}',
    };
    if (t.isNotEmpty) params['tag'] = t;
    if (cc.isNotEmpty) params['countrycode'] = cc;

    final stations = await _getJson(
        '/json/stations/search', params, label: 'radio $t ${cc.isEmpty ? '' : cc}');
    if (stations == null || stations.isEmpty) {
      final stale = await ContentCacheService.instance
          .readJsonStale(key, maxAge: ContentCacheService.offlineCeiling);
      return stale == null ? const [] : _decode(stale);
    }

    final items = _toItems(stations, limit);
    if (items.isNotEmpty) {
      await ContentCacheService.instance
          .writeJson(key, items.map((e) => e.toJson()).toList());
      _memory[memKey] = items;
    }
    return items;
  }

  /// Queries the registry, moving to the next mirror on failure.
  ///
  /// An **empty answer counts as a failure**: measured on 2026-10-11, the
  /// mirrors do not agree — the same `tag=amapiano` query returned 13 stations
  /// on one mirror and 0 on another, seconds apart. Taking the first mirror
  /// that answers with data is what keeps a row from looking dead.
  Future<List<Map<String, dynamic>>?> _getJson(
    String path,
    Map<String, String> params, {
    required String label,
  }) async {
    for (final host in _mirrors) {
      try {
        final uri =
            Uri.https(host, path, Map<String, dynamic>.from(params));
        final resp =
            await http.get(uri, headers: {'User-Agent': _ua}).timeout(_timeout);
        if (resp.statusCode != 200) continue;
        // Never trust the status alone: a mirror under load answers 200 with an
        // error page.
        final decoded = json.decode(resp.body);
        if (decoded is List && decoded.isNotEmpty) return decoded.cast();
      } catch (e) {
        debugPrint('[Radio] $label on $host: $e');
      }
    }
    return null;
  }

  List<MuzoItem> _toItems(List<Map<String, dynamic>> raw, int limit) {
    final out = <MuzoItem>[];
    final seenStreams = <String>{};
    final seenNames = <String>{};
    for (final s in raw) {
      final name = (s['name'] as String? ?? '').trim();
      final stream = (s['url_resolved'] as String? ?? '').trim();
      if (name.isEmpty || stream.isEmpty) continue;
      if (!stream.toLowerCase().startsWith('https://')) continue;
      final favicon = (s['favicon'] as String? ?? '').trim();
      final country = (s['countrycode'] as String? ?? '').trim();
      final codec = (s['codec'] as String? ?? 'MP3').trim();
      final bitrate = s['bitrate'] is int ? s['bitrate'] as int : 0;
      final endpoint = stream.split('?').first.toLowerCase();
      if (!seenStreams.add(endpoint)) continue;
      if (!seenNames.add(name.toLowerCase())) continue;
      out.add(MuzoItem(
        // A station is not a YouTube video: the id is namespaced so no path
        // ever tries to resolve it, and it stays a stable cache/favourite key.
        videoId: 'ra_${s['stationuuid'] ?? name.hashCode}',
        title: name,
        artists: [MuzoArtist(name: _subtitle(country, codec, bitrate), id: null)],
        audioUrl: stream,
        thumbnails: favicon.isEmpty
            ? const []
            : [MuzoThumbnail(url: favicon, width: 200, height: 200)],
        resultType: 'radio',
        isExplicit: false,
        source: 'radio-browser',
        sourceId: (s['stationuuid'] ?? '').toString(),
        sourceUrl: (s['homepage'] as String? ?? '').trim(),
        metadata: {
          'tags': (s['tags'] ?? '').toString(),
          'codec': codec,
          'bitrate': bitrate,
          'country': country,
        },
        fetchedAt: DateTime.now(),
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  String _subtitle(String countryCode, String codec, int bitrate) {
    final parts = <String>[];
    if (countryCode.isNotEmpty) parts.add(countryCode);
    if (codec.trim().isNotEmpty) parts.add(codec.trim().toUpperCase());
    if (bitrate > 0) parts.add('$bitrate kbps');
    return parts.isEmpty ? 'radio' : parts.join(' · ');
  }

  List<MuzoItem> _decode(List<dynamic> raw) {
    return [
      for (final m in raw.whereType<Map>())
        MuzoItem.fromJson(Map<String, dynamic>.from(m)),
    ];
  }
}
