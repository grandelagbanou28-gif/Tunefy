import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/concert_event.dart';

/// Below this the artist page retry asks for a bigger batch, so the archive
/// always has a usable number of dates. The artist page targets 19+.
const int kMinConcerts = 19;

/// Below this many *upcoming* dates, Gemini is asked for the tour. Past dates
/// are real archive data, so this is the only gap worth spending quota on.
const int kMinUpcoming = 3;

/// Concert lookup shaped like Freedify's ConcertService (normalized events,
/// upcoming-first sort, single `searchEvents` entry point).
///
/// Sources, in order:
/// 1. Ticketmaster Discovery API — when `--dart-define=TICKETMASTER_API_KEY=...`.
/// 2. SeatGeek API — when `--dart-define=SEATGEEK_CLIENT_ID=...`.
/// 3. Gemini (key baked in) — always tried as fallback so events stay real
///    even with no ticketing keys configured.
class ConcertService {
  ConcertService._();
  static final ConcertService instance = ConcertService._();

  /// GEMINI_API_KEY — injectée au build via
  /// `--dart-define-from-file=secrets.json` (jamais commitée).
  static const String _rawApiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// A leftover placeholder from `secrets.example.json` must read as "no key".
  /// A non-empty but invalid key is worse than none: every request fails and
  /// the artist page silently loses its concerts.
  static bool _isUsableKey(String value) {
    if (value.isEmpty) return false;
    final v = value.trim().toLowerCase();
    if (v.startsWith('ta_cle') || v.contains('your_') || v.contains('changeme')) {
      debugPrint('ConcertService: ignoring placeholder key, not configured');
      return false;
    }
    return true;
  }

  static final String _apiKey = _isUsableKey(_rawApiKey) ? _rawApiKey.trim() : '';

  /// Optional ticketing keys passed at build/run time, e.g.:
  /// flutter build apk --dart-define=TICKETMASTER_API_KEY=xxx \
  ///                    --dart-define=SEATGEEK_CLIENT_ID=yyy
  static const String _rawTmKey = String.fromEnvironment('TICKETMASTER_API_KEY');
  static const String _rawSgKey = String.fromEnvironment('SEATGEEK_CLIENT_ID');
  static const String _rawSetlistKey =
      String.fromEnvironment('SETLISTFM_API_KEY');
  static final String _tmKey =
      _isUsableKey(_rawTmKey) ? _rawTmKey.trim() : '';
  static final String _sgKey =
      _isUsableKey(_rawSgKey) ? _rawSgKey.trim() : '';
  static final String _setlistKey =
      _isUsableKey(_rawSetlistKey) ? _rawSetlistKey.trim() : '';

  /// True when at least one real event source is available. Without it the
  /// artist page has nothing to show, and says so instead of looking broken.
  static bool get isConfigured =>
      _apiKey.isNotEmpty ||
      _tmKey.isNotEmpty ||
      _sgKey.isNotEmpty ||
      _setlistKey.isNotEmpty;

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const String _model = 'gemini-2.5-flash';
  static const Duration _timeout = Duration(seconds: 18);
  static const Duration _ticketingTimeout = Duration(seconds: 15);

  /// Upcoming concerts first (soonest → latest), then past (newest → oldest).
  /// Dedupes by a stable key so the same night is not listed twice.
  static List<ConcertEvent> sortUpcomingFirst(List<ConcertEvent> events) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final seen = <String>{};
    final upcoming = <ConcertEvent>[];
    final past = <ConcertEvent>[];
    for (final e in events) {
      if (e.date == null && e.venue.isEmpty && e.name.isEmpty) continue;
      final key =
          '${e.date?.toIso8601String() ?? ''}|${e.venue.toLowerCase()}|${e.city.toLowerCase()}';
      if (!seen.add(key)) continue;
      if (e.date != null && !e.date!.isBefore(today)) {
        upcoming.add(e);
      } else {
        past.add(e);
      }
    }
    upcoming.sort((a, b) => (a.date ?? DateTime(2100))
        .compareTo(b.date ?? DateTime(2100)));
    past.sort((a, b) => (b.date ?? DateTime(1970))
        .compareTo(a.date ?? DateTime(1970)));
    return [...upcoming, ...past];
  }

  /// Search concerts for [artist] (optional [city] filter). Returns
  /// normalized events with upcoming dates first.
  ///
  /// Setlist.fm (real past shows) + Ticketmaster/SeatGeek (upcoming,
  /// ticketed) are queried in parallel and merged. Gemini is asked **only** to
  /// fill the upcoming gap: the archive already supplies real past dates, and
  /// the free Gemini tier is 20 requests per day for the whole app.
  Future<List<ConcertEvent>> searchEvents(
    String artist, {
    String? city,
    int limit = 20,
  }) async {
    final name = artist.trim();
    if (name.isEmpty) return const [];

    final futures = <Future<List<ConcertEvent>>>[
      if (_setlistKey.isNotEmpty) _searchSetlistFm(name),
      if (_tmKey.isNotEmpty) _searchTicketmaster(name, city: city),
      if (_sgKey.isNotEmpty) _searchSeatGeek(name, city: city),
    ];
    final collected = futures.isEmpty
        ? const <ConcertEvent>[]
        : (await Future.wait(futures)).expand((e) => e).toList();
    // Cross-source dedupe: the same show is often listed by both the archive
    // and the ticketing API. Same id, or same day at the same venue, is one.
    final events = <ConcertEvent>[];
    for (final e in collected) {
      final duplicate = events.any((x) =>
          x.id == e.id ||
          (e.venue.isNotEmpty && x.date != null && x.date == e.date && x.venue == e.venue));
      if (!duplicate) events.add(e);
    }

    final upcoming = events.where((e) => e.isUpcoming).length;
    if (upcoming < kMinUpcoming && !geminiQuotaBlocked) {
      // A single pass, asking for future dates only: past dates are real data
      // now, so the remaining gap is exactly the tour that has not happened.
      final body = await _generate(
        _buildPrompt(name, city: city, limit: 12, upcomingOnly: true),
      );
      if (body != null) {
        for (final e in _parseEvents(body, artist: name)) {
          final duplicate = events.any(
            (x) => x.id == e.id || (x.date != null && x.date == e.date && x.venue == e.venue),
          );
          if (duplicate) continue;
          events.add(e);
        }
      }
    }
    // One line per artist: which source is even configured, and what each one
    // really answered. Concerts going missing is otherwise impossible to tell
    // apart from "this artist has no known dates".
    debugPrint('ConcertService: $name -> '
        'setlist=${_setlistKey.isEmpty ? "no-key" : collected.length} '
        'tm=${_tmKey.isEmpty ? "no-key" : ""} '
        'gemini=${geminiQuotaBlocked ? "quota-blocked" : "ok"} '
        'total=${events.length}');

    return sortUpcomingFirst(events).take(limit).toList();
  }

  /// Ticketmaster Discovery — `keyword` + `classificationName=music`,
  /// `sort=date,asc`. Mirrors Freedify's mapping (venues[0], dates.start,
  /// priceRanges[0], 16:9 images).
  ///
  /// Paged: a busy artist has far more than one page of dates, and the
  /// artist page needs 15+, so we walk the pages until we have enough or run
  /// out. Ticketmaster caps a page at 100 events.
  Future<List<ConcertEvent>> _searchTicketmaster(
    String artist, {
    String? city,
    int wanted = 40,
  }) async {
    final baseParams = <String, String>{
      'apikey': _tmKey,
      'keyword': artist,
      'classificationName': 'music',
      'size': '100',
      'sort': 'date,asc',
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
    };

    var params = Map<String, String>.from(baseParams);
    var out = <ConcertEvent>[];

    for (var page = 0; page < 4 && out.length < wanted; page++) {
      final events = await _ticketmasterPage(params, artist);
      if (events == null) {
        // First page failed with the city filter: retry once without it.
        if (params.containsKey('city')) {
          params = Map<String, String>.from(baseParams)..remove('city');
          page = 0;
          continue;
        }
        break;
      }
      if (events.isEmpty) break;
      final seen = out.map((e) => e.id).toSet();
      for (final e in events) {
        if (seen.add(e.id)) out.add(e);
      }
      params['page'] = '${int.tryParse(params['page'] ?? '0')! + 1}';
    }
    return out;
  }

  /// One Ticketmaster page, or null when the request itself failed (as opposed
  /// to a page that simply has no events).
  Future<List<ConcertEvent>?> _ticketmasterPage(
    Map<String, String> params,
    String artist,
  ) async {
    try {
      final uri = Uri.https(
          'app.ticketmaster.com', '/discovery/v2/events.json', params);
      final resp = await http.get(uri).timeout(_ticketingTimeout);
      if (resp.statusCode != 200) {
        debugPrint('ConcertService TM HTTP ${resp.statusCode}');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      final embedded = decoded['_embedded'];
      if (embedded is! Map || embedded['events'] is! List) return const [];
      final out = <ConcertEvent>[];
      for (final raw in embedded['events'] as List) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final venues =
            ((map['_embedded'] ?? const {})['venues'] as List?) ?? const [];
        final v = venues.isNotEmpty && venues.first is Map
            ? Map<String, dynamic>.from(venues.first as Map)
            : const <String, dynamic>{};
        final dates = (map['dates'] ?? const {})['start'];
        final start = dates is Map ? Map<String, dynamic>.from(dates) : const {};
        final images = (map['images'] as List?) ?? const [];
        String img = '';
        for (final im in images) {
          if (im is Map && '${im['ratio']}' == '16_9') {
            img = im['url']?.toString() ?? img;
            if (img.isNotEmpty) break;
          }
        }
        if (img.isEmpty && images.isNotEmpty && images.first is Map) {
          img = (images.first as Map)['url']?.toString() ?? '';
        }
        final prices = (map['priceRanges'] as List?) ?? const [];
        final pr = prices.isNotEmpty && prices.first is Map
            ? Map<String, dynamic>.from(prices.first as Map)
            : <String, dynamic>{};
        // Ticketmaster's `keyword` is a fuzzy match: searching "Jul" happily
        // returns Oasis and Bon Jovi. Showing another artist's date on their
        // page is worse than showing nothing, so the hit has to actually name
        // the artist (event title or listed attraction).
        final attractions = ((map['_embedded'] ?? const {})['attractions'] as List?)
                ?.whereType<Map>()
                .map((a) => a['name']?.toString() ?? '')
                .join(' ') ??
            '';
        if (!_namesArtist(
          [map['name']?.toString() ?? '', attractions],
          artist,
        )) {
          continue;
        }
        out.add(ConcertEvent(

          id: 'tm_${map['id'] ?? ''}',
          name: map['name']?.toString() ?? '',
          artist: artist,
          venue: v['name']?.toString() ?? '',
          city: (v['city'] ?? const {})['name']?.toString() ?? '',
          state: (v['state'] ?? const {})['stateCode']?.toString() ??
              (v['state'] ?? const {})['name']?.toString() ??
              '',
          country: (v['country'] ?? const {})['countryCode']?.toString() ?? '',
          date: DateTime.tryParse(start['localDate']?.toString() ?? ''),
          time: start['localTime']?.toString() ?? '',
          ticketUrl: map['url']?.toString() ?? '',
          priceMin: (pr['min'] as num?)?.toDouble(),
          priceMax: (pr['max'] as num?)?.toDouble(),
          currency: pr['currency']?.toString() ?? '',
          image: img,
          source: 'Ticketmaster',
        ));
      }
      return out;
    } catch (e) {
      debugPrint('ConcertService Ticketmaster error: $e');
      return null;
    }
  }

  /// Testing seam for the artist filter, which decides whether a ticket page
  /// hit is shown on an artist page at all.
  @visibleForTesting
  static bool debugNamesArtist(List<String> haystacks, String artist) =>
      _namesArtist(haystacks, artist);

  /// Testing seam for Setlist.fm's own date format.
  @visibleForTesting
  static DateTime? debugParseSetlistDate(String raw) => _parseSetlistDate(raw);

  /// Whether any of [haystacks] really names [artist].
  ///
  /// Short names are the trap: "Jul" appears inside "Julius", "Jules" and
  /// "Juliette", so a plain substring test would hand an artist someone else's
  /// concert. Under four characters the match must be a whole word; longer
  /// names can match inside a title ("Damso at Zénith").
  static bool _namesArtist(List<String> haystacks, String artist) {
    final needle = _slugArtist(artist);
    if (needle.isEmpty) return true;
    for (final hay in haystacks) {
      final text = _slugArtist(hay);
      if (text.isEmpty) continue;
      if (needle.length < 4) {
        if (RegExp('(^|[^a-z0-9])$needle([^a-z0-9]|\$)').hasMatch(text)) {
          return true;
        }
      } else if (text.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  /// Lowercase, accent-free, with every punctuation mark turned into a space.
  /// Spaces are kept on purpose: they are the word boundaries the short-name
  /// whole-word test relies on.
  static String _slugArtist(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp('[̀-ͯ]'), '')
        .replaceAll(RegExp('[^a-z0-9]+'), ' ')
        .trim();
    return normalized;
  }

  /// Setlist.fm — the concert *archive*: a setlist per show, with the real
  /// venue, city, country and date. This is the backbone of the tab, because
  /// unlike a generative model it cannot invent a date, and unlike
  /// Ticketmaster it actually covers francophone and non-US tours.
  ///
  /// It is a past-events source: it answers "where has this artist played",
  /// not "where will they play". Upcoming dates still come from the
  /// ticketing APIs (and, if quota allows, from Gemini).
  Future<List<ConcertEvent>> _searchSetlistFm(
    String artist, {
    int wanted = 60,
  }) async {
    if (_setlistKey.isEmpty) return const [];
    final out = <ConcertEvent>[];
    const perPage = 100;
    for (var page = 1; page <= 3 && out.length < wanted; page++) {
      List<dynamic>? setlists;
      try {
        final uri = Uri.https('api.setlist.fm', '/rest/1.0/search/setlists', {
          'artistName': artist,
          'sort': 'date',
          'order': 'desc',
          'per_page': '$perPage',
          'page': '$page',
        });
        final resp = await http.get(
          uri,
          headers: {
            'x-api-key': _setlistKey,
            'Accept': 'application/json',
          },
        ).timeout(_ticketingTimeout);
        if (resp.statusCode == 429) {
          debugPrint('ConcertService Setlist.fm rate limited');
          break;
        }
        if (resp.statusCode != 200) {
          debugPrint('ConcertService Setlist.fm HTTP ${resp.statusCode}');
          break;
        }
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map || decoded['setlist'] is! List) break;
        setlists = decoded['setlist'] as List;
      } catch (e) {
        debugPrint('ConcertService Setlist.fm error: $e');
        break;
      }
      if (setlists.isEmpty) break;

      for (final raw in setlists) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final venue = map['venue'] is Map
            ? Map<String, dynamic>.from(map['venue'] as Map)
            : const <String, dynamic>{};
        final city = venue['city'] is Map
            ? Map<String, dynamic>.from(venue['city'] as Map)
            : const <String, dynamic>{};
        final date = _parseSetlistDate(map['eventDate']?.toString() ?? '');
        if (date == null) continue;

        // Same fuzzy-name trap as Ticketmaster: the query is a search term, so
        // the response's own `artist.name` has to really be the artist we asked
        // about. "Jul" must not match "Julius Caesar".
        final eventName = [
          map['artist'] is Map
              ? Map<String, dynamic>.from(map['artist'] as Map)['name']
                      ?.toString() ??
                  ''
              : '',
          map['title']?.toString() ?? '',
          venue['name']?.toString() ?? '',
        ];
        if (!_namesArtist(eventName, artist)) continue;

        out.add(ConcertEvent(
          id: 'slf_${map['id'] ?? ''}',
          name: map['title']?.toString() ?? artist,
          artist: artist,
          venue: venue['name']?.toString() ?? '',
          city: city['name']?.toString() ?? '',
          country: venue['country']?.toString() ?? '',
          date: date,
          // A setlist URL is a real, verifiable page for the show.
          ticketUrl: map['url']?.toString() ?? '',
          image: _setlistImage(map),
          source: 'Setlist.fm',
        ));
      }
    }
    return out;
  }

  /// Setlist.fm dates are `dd-MM-yyyy`, which Dart cannot parse, and the
  /// festival entries come as a free-text range (`12-07-2026/14-07-2026`).
  /// Only the first day of a range is kept, as the show's start.
  static DateTime? _parseSetlistDate(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.contains('/')) value = value.split('/').first.trim();
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  static String _setlistImage(Map<String, dynamic> map) {
    for (final raw in (map['cover'] as List?) ?? const []) {
      if (raw is Map && raw['url'] != null) return raw['url'].toString();
    }
    return '';
  }

  /// SeatGeek — `performers.slug` when possible (Freedify's exact call),
  /// `q` + `type=concert` as the slug fallback.
  Future<List<ConcertEvent>> _searchSeatGeek(
    String artist, {
    String? city,
  }) async {
    try {
      final slug = artist
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '-');
      Map<String, String> params(String q, {String? slugParam}) => {
            'client_id': _sgKey,
            if (slugParam != null) 'performers.slug': slugParam else 'q': q,
            'q': q,
            'type': 'concert',
            'per_page': '25',
            'sort': 'datetime_utc.asc',
            if (city != null && city.trim().isNotEmpty) 'venue.city': city.trim(),
          };
      var uri = Uri.https('api.seatgeek.com', '/2/events', params(artist, slugParam: slug));
      var resp = await http.get(uri).timeout(_ticketingTimeout);
      if (resp.statusCode == 404 || resp.statusCode == 422) {
        uri = Uri.https('api.seatgeek.com', '/2/events', params(artist));
        resp = await http.get(uri).timeout(_ticketingTimeout);
      }
      if (resp.statusCode != 200) {
        debugPrint('ConcertService SeatGeek HTTP ${resp.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map || decoded['events'] is! List) return const [];
      final out = <ConcertEvent>[];
      for (final raw in decoded['events'] as List) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final v = (map['venue'] is Map)
            ? Map<String, dynamic>.from(map['venue'] as Map)
            : const <String, dynamic>{};
        final performers = (map['performers'] as List?) ?? const [];
        String img = '';
        String headliner = '';
        for (final p in performers) {
          if (p is! Map) continue;
          if (p['image'] is String && (p['image'] as String).isNotEmpty) {
            img = p['image'] as String;
          }
          if (p['headliner'] == true) {
            headliner = p['name']?.toString() ?? '';
            if (img.isNotEmpty) break;
          }
        }
        final stats = (map['stats'] ?? const {})['lowest_price'];
        final highest = (map['stats'] ?? const {})['highest_price'];
        final iso = map['datetime_utc']?.toString() ?? '';
        out.add(ConcertEvent(
          id: 'sg_${map['id'] ?? ''}',
          name: (headliner.isNotEmpty ? headliner : map['title']?.toString()) ?? '',
          artist: artist,
          venue: v['name']?.toString() ?? '',
          city: v['city']?.toString() ?? '',
          state: v['state']?.toString() ?? '',
          country: (v['country'] ?? v['country_code'])?.toString() ?? '',
          date: DateTime.tryParse(iso.replaceFirst('Z', '')),
          time: '',
          ticketUrl: map['url']?.toString() ?? '',
          priceMin: (stats as num?)?.toDouble(),
          priceMax: (highest as num?)?.toDouble(),
          currency: 'USD',
          image: img,
          source: 'SeatGeek',
        ));
      }
      return out;
    } catch (e) {
      debugPrint('ConcertService SeatGeek error: $e');
      return const [];
    }
  }

  /// Same multi-artist helper shape as Freedify (`get_events_for_artists`).
  Future<List<ConcertEvent>> getEventsForArtists(
    List<String> artists, {
    String? city,
    int limitPerArtist = 5,
  }) async {
    final all = <ConcertEvent>[];
    for (final a in artists.take(10)) {
      final list = await searchEvents(a, city: city, limit: limitPerArtist);
      all.addAll(list);
    }
    return sortUpcomingFirst(all);
  }

  String _buildPrompt(
    String artist, {
    String? city,
    required int limit,
    String angle = '',
    bool upcomingOnly = false,
  }) {
    final today = DateTime.now().toIso8601String().split('T').first;
    final cityLine = (city != null && city.trim().isNotEmpty)
        ? ' Focus on concerts in or near "${city.trim()}".'
        : '';
    final angleLine = angle.isEmpty
        ? ''
        : ' Search specifically for their $angle (dates, cities and venues).';
    // The archive already answered the past, so the default ask is future dates
    // only: a shorter, more precise question wastes far fewer output tokens on
    // a 4096-token budget.
    final scope = upcomingOnly
        ? '''- ONLY UPCOMING dates (on/after $today), up to $limit of them.
  Do NOT list past concerts.'''
        : '''- UPCOMING dates (on/after today) — priority, they lead the list.
- RECENT PAST dates (last 24 months) — up to $limit upcoming past dates too,
  they power the "past concert videos" section.''';
    return '''
You are a live concert listings API. Find real tour dates for "$artist".

Today: $today.$cityLine$angleLine
Return up to $limit events for THIS exact artist only.

Include BOTH:
$scope
For each: real venue, city, optional state/country, date YYYY-MM-DD, optional time HH:MM.
Ticket price: numbers only + separate ISO currency (EUR/USD/XOF…).
Ticket URL: only if you are sure (Ticketmaster, Dice, SeeTickets, venue site). Never invent — use "" if unsure.

Respond with ONLY a JSON array (no markdown). Each element:
{"id":"...","name":"...","artist":"$artist","venue":"...","city":"...","state":"","country":"","date":"YYYY-MM-DD","time":"","ticket_url":"","price_min":null,"price_max":null,"currency":"","image":""}

If none found, return [].
''';
  }

  /// True once Gemini answered 429. The free tier allows only 20 generation
  /// requests per day per model, so after the first refusal every further call
  /// is guaranteed to fail the same way: better to stop asking for the rest of
  /// the day and serve the ticketing sources alone than to burn the remaining
  /// quota on guaranteed 429s.
  static bool geminiQuotaBlocked = false;

  Future<String?> _generate(String prompt) async {
    if (_apiKey.isEmpty || geminiQuotaBlocked) return null;
    final uri = Uri.parse('$_base/$_model:generateContent?key=$_apiKey');
    final payload = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 4096,
        'responseMimeType': 'application/json',
      },
    });

    try {
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(_timeout);
      if (resp.statusCode == 429) {
        geminiQuotaBlocked = true;
        debugPrint(
            'ConcertService: Gemini daily quota exhausted, disabled for today');
        return null;
      }
      if (resp.statusCode != 200) {
        debugPrint(
            'ConcertService Gemini HTTP ${resp.statusCode}: ${resp.body}');
        return null;
      }
      return resp.body;
    } catch (e) {
      debugPrint('ConcertService Gemini error: $e');
      return null;
    }
  }

  List<ConcertEvent> _parseEvents(String body, {required String artist}) {
    try {
      final decoded = jsonDecode(body);
      final List<dynamic> raw;
      if (decoded is List) {
        raw = decoded;
      } else if (decoded is Map) {
        // Gemini sometimes wraps the array: {"events": [...]} or text field.
        final cand = decoded['events'] ?? decoded['concerts'] ?? decoded['items'];
        if (cand is List) {
          raw = cand;
        } else {
          final text = _textFromCandidate(decoded);
          if (text == null) return const [];
          return _parseEvents(text, artist: artist);
        }
      } else {
        return const [];
      }

      final events = <ConcertEvent>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        var e = ConcertEvent.fromJson({
          ...map,
          'id': map['id']?.toString().isNotEmpty == true
              ? map['id']
              : 'g_$artist$i',
          if (map['artist'] == null || '${map['artist']}'.isEmpty)
            'artist': artist,
          if (map['name'] == null || '${map['name']}'.isEmpty)
            'name': map['venue']?.toString() ?? artist,
        });
        // Soft-validate: drop rows that are clearly not concerts.
        if (e.venue.isEmpty && e.ticketUrl.isEmpty && e.date == null) {
          continue;
        }
        events.add(e);
      }
      return events;
    } catch (e) {
      debugPrint('ConcertService parse error: $e');
      // Last chance: extract a JSON array from free text.
      final start = body.indexOf('[');
      final end = body.lastIndexOf(']');
      if (start >= 0 && end > start) {
        try {
          final arr = jsonDecode(body.substring(start, end + 1));
          if (arr is List) {
            return arr
                .whereType<Map>()
                .map((m) => ConcertEvent.fromJson(Map<String, dynamic>.from(m)))
                .toList();
          }
        } catch (_) {}
      }
      return const [];
    }
  }

  String? _textFromCandidate(Map decoded) {
    try {
      final cands = decoded['candidates'];
      if (cands is List && cands.isNotEmpty) {
        final parts = cands.first['content']['parts'];
        if (parts is List) {
          final buf = StringBuffer();
          for (final p in parts) {
            if (p is Map && p['text'] is String) buf.write(p['text']);
          }
          final t = buf.toString().trim();
          if (t.isNotEmpty) return t;
        }
      }
    } catch (_) {}
    return null;
  }
}
