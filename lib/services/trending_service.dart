import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/services/content_cache_service.dart';

/// One current chart entry from an Apple storefront.
@immutable
class TrendSong {
  final String title;
  final String artist;
  final String genre; // iTunes genre label, e.g. "Hip-Hop/Rap"
  final String art;

  /// Real `im:releaseDate` from the RSS entry — without it every chart seed
  /// is dropped by the "new releases" date window (undated ⇒ invisible).
  final DateTime? releaseDate;

  const TrendSong({
    required this.title,
    required this.artist,
    required this.genre,
    required this.art,
    this.releaseDate,
  });

  Map<String, dynamic> toJson() => {
        't': title,
        'a': artist,
        'g': genre,
        'c': art,
        if (releaseDate != null) 'd': releaseDate!.toIso8601String(),
      };

  static TrendSong fromJson(Map<String, dynamic> j) => TrendSong(
        title: j['t'] as String? ?? '',
        artist: j['a'] as String? ?? '',
        genre: j['g'] as String? ?? '',
        art: j['c'] as String? ?? '',
        releaseDate: j['d'] is String
            ? DateTime.tryParse(j['d'] as String)
            : null,
      );
}

/// One editorial album from an Apple storefront (RSS top albums).
@immutable
class RssAlbum {
  final String title;
  final String artist;
  final String cover;

  /// iTunes genre label from the feed's `category` term ("Hip-Hop/Rap",
  /// "Rock", …). Empty for rows fetched before this field existed.
  final String genre;
  final DateTime? releaseDate;

  const RssAlbum({
    required this.title,
    required this.artist,
    required this.cover,
    this.genre = '',
    this.releaseDate,
  });

  Map<String, dynamic> toJson() => {
        't': title,
        'a': artist,
        'c': cover,
        if (genre.isNotEmpty) 'g': genre,
        if (releaseDate != null) 'd': releaseDate!.toIso8601String(),
      };

  static RssAlbum fromJson(Map<String, dynamic> j) => RssAlbum(
        title: j['t'] as String? ?? '',
        artist: j['a'] as String? ?? '',
        cover: j['c'] as String? ?? '',
        genre: j['g'] as String? ?? '',
        releaseDate: j['d'] is String
            ? DateTime.tryParse(j['d'] as String)
            : null,
      );
}

/// An artist read out of the storefront charts themselves: the name Apple
/// credits, the artwork of the song that carries it, and the best chart
/// position any storefront gave that artist.
@immutable
class ChartArtist {
  final String name;
  final String art;

  /// Zero-based best position across the storefronts that were read.
  final int rank;

  const ChartArtist({
    required this.name,
    required this.art,
    required this.rank,
  });
}

/// One editorial genre and the real charts that carry it.
@immutable
class GenreChartSpec {
  /// Apple storefronts whose most-played chart IS this music (afro rap reads
  /// NG/GH/CI, not the worldwide pool).
  final List<String> countries;

  /// Lower-cased fragments matched against each song's own chart genre label.
  final List<String> tokens;

  /// Deezer chart id used when a storefront feed is unreachable.
  final int deezerGenre;

  const GenreChartSpec(this.countries, this.tokens, this.deezerGenre);
}

/// One editorial playlist from an Apple storefront (RSS top playlists).
@immutable
class RssPlaylist {
  final String title;
  final String author;
  final String cover;

  const RssPlaylist({
    required this.title,
    required this.author,
    required this.cover,
  });

  Map<String, dynamic> toJson() => {'t': title, 'a': author, 'c': cover};

  static RssPlaylist fromJson(Map<String, dynamic> j) => RssPlaylist(
        title: j['t'] as String? ?? '',
        author: j['a'] as String? ?? '',
        cover: j['c'] as String? ?? '',
      );
}

/// Modern-artist source: Apple's public iTunes RSS song charts.
///
/// `https://itunes.apple.com/<store>/rss/topsongs/limit=50/json` returns the
/// REAL current top songs of any storefront (fr, us, ng, ci, za...) — no key,
/// no quota. This is what powers:
///  • the Charts / Trending categories (true daily tops), and
///  • the "modern boost" that injects a couple of current chart-matching
///    tracks into every music sub-category so pages never feel dated.
///
/// Charts are cached on disk for 24h — release shelves need a daily refresh
/// so "Nouveaux albums / sorties" never serve a multi-day-old snapshot.
class TrendingService {
  TrendingService._();

  static const _timeout = Duration(seconds: 10);

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  // ─── Fetch ────────────────────────────────────────────────────────────────

  /// Un appel au flux Apple, retenté une fois.
  ///
  /// Le magasin répond quelquefois 200 pour un pays et expire pour le suivant.
  /// Sans second essai le pays disparaît de la ligne, et c'est précisément ce
  /// qui laissait « hip-hop » avec un seul artiste quand `us` ne répondait
  /// pas : la ligne ne était pas vide, elle était amputée.
  static Future<String?> _fetchChart(String url) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(attempt == 0 ? _timeout : const Duration(seconds: 6));
        if (resp.statusCode == 200) return resp.body;
      } catch (_) {}
    }
    return null;
  }

  /// Current top songs of one storefront (daily disk cache).
  ///
  /// Reads Apple's modern most-played chart. The legacy
  /// `itunes.apple.com/{cc}/rss/topsongs` feed kept as a fallback is a Store
  /// sales top-line that today mostly lists self-released SEO singles ("Imael
  /// Angel", "Bjorn Bonebreaker"), which is why the shelves built from it read
  /// as fake content instead of the real current rap/afro hits.
  static Future<List<TrendSong>> topSongs(String countryCode) async {
    final modern = await mostPlayed(countryCode);
    if (modern.isNotEmpty) return modern;
    final cc = countryCode.toLowerCase();
    final key = 'trends|$cc|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map((e) => TrendSong.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    try {
      final uri =
          Uri.parse('https://itunes.apple.com/$cc/rss/topsongs/limit=50/json');
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final feed = (body['feed'] as Map?) ?? const {};
      final entries = (feed['entry'] as List?) ?? const [];
      final songs = <TrendSong>[];
      for (final e in entries) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final name =
              (((m['im:name'] as Map?) ?? const {})['label'] as String?) ?? '';
          final artist =
              (((m['im:artist'] as Map?) ?? const {})['label'] as String?) ??
                  '';
          if (name.isEmpty || artist.isEmpty) continue;
          final genre =
              ((((m['category'] as Map?) ?? const {})['attributes'] as Map?) ??
                      const {})['label'] as String? ??
                  '';
          var art = '';
          final images = (m['im:image'] as List?) ?? const [];
          if (images.isNotEmpty) {
            art = ((images.last as Map)['label'] as String?) ?? '';
            art = art.replaceFirst(RegExp(r'/\d+x\d+BB'), '/600x600BB');
          }
          DateTime? rel;
          final relRaw =
              (((m['im:releaseDate'] as Map?) ?? const {})['label'] as String?);
          if (relRaw != null && relRaw.isNotEmpty) {
            rel = DateTime.tryParse(relRaw);
          }
          songs.add(TrendSong(
              title: name, artist: artist, genre: genre, art: art,
              releaseDate: rel));
        } catch (_) {}
      }
      if (songs.isNotEmpty) {
        await ContentCacheService.instance
            .writeJson(key, songs.map((s) => s.toJson()).toList());
      }
      return songs;
    } catch (e) {
      debugPrint('TRENDS $cc fail :: $e');
      return const [];
    }
  }

  /// Apple Music's real most-played song chart for one storefront
  /// (`rss.marketingtools.apple.com/api/v2/{cc}/music/most-played/{limit}/songs.json`).
  ///
  /// Keyless, current, country-accurate and genre-labelled: the FR list is the
  /// French rap top (Tiakola, Ninho, Aya Nakamura, Vacra, Ronisia), the US one
  /// is the American top, NG/GH/CI are the African ones. Each row carries a
  /// `genres[]` array whose first non-generic name is the song's genre, which
  /// is what lets a shelf claim "rap français" or "afro rap" honestly.
  static Future<List<TrendSong>> mostPlayed(String countryCode,
      {int limit = 100}) async {
    final cc = countryCode.toLowerCase();
    final key = 'trendsm2|$cc|$limit|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map((e) => TrendSong.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    try {
      final raw = await _fetchChart(
          'https://rss.marketingtools.apple.com/api/v2/$cc/music/most-played/$limit/songs.json');
      if (raw == null) return const [];
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final results =
          (((body['feed'] as Map?) ?? const {})['results'] as List?) ??
              const [];
      final songs = <TrendSong>[];
      for (final e in results) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final title = m['name'] as String? ?? '';
          final artist = m['artistName'] as String? ?? '';
          if (title.isEmpty || artist.isEmpty) continue;
          var cover = m['artworkUrl100'] as String? ?? '';
          if (cover.isNotEmpty) {
            cover = cover.replaceFirst('/100x100bb', '/600x600bb');
          }
          // The storefront buckets the song into the actual genre first and
          // then lists the container ("Musique"/"Music").
          final relRaw = m['releaseDate'] as String?;
          songs.add(TrendSong(
              title: title,
              artist: artist,
              genre: _primaryGenreName(m['genres']),
              art: cover,
              releaseDate: (relRaw == null || relRaw.isEmpty)
                  ? null
                  : DateTime.tryParse(relRaw)));
        } catch (_) {}
      }
      if (songs.isNotEmpty) {
        await ContentCacheService.instance
            .writeJson(key, songs.map((s) => s.toJson()).toList());
      }
      debugPrint('MostPlayed $cc: ${songs.length} chart songs');
      return songs;
    } catch (e) {
      debugPrint('MOSTPLAYED $cc fail :: $e');
      return const [];
    }
  }

  /// Songs of [countries] whose chart genre matches one of [tokens]
  /// (lower-cased fragments like `hip-hop`, `rap`, `afro`), at most one per
  /// artist so a shelf is a row of different people rather than one album's
  /// tracklist. Never throws — an unreachable storefront just contributes
  /// nothing.
  static Future<List<TrendSong>> chartSongsFor(
    List<String> countries,
    List<String> tokens, {
    int perArtist = 1,
  }) async {
    final pools = await Future.wait(
        countries.map((cc) => topSongs(cc).catchError((_) => const <TrendSong>[])));
    final perArtistCount = <String, int>{};
    final seenSong = <String>{};
    final out = <TrendSong>[];
    for (final pool in pools) {
      for (final t in pool) {
        final g = t.genre.toLowerCase();
        if (g.isEmpty || !tokens.any(g.contains)) continue;
        final songKey = '${t.title}|${t.artist}'.toLowerCase();
        if (!seenSong.add(songKey)) continue;
        // Apple credits features in `artistName` ("Tiakola & Theodora"); the
        // lead name is what identifies the slot's owner.
        final artistKey =
            t.artist.split(RegExp(r'[,&#]')).first.trim().toLowerCase();
        final used = perArtistCount[artistKey] ?? 0;
        if (used >= perArtist) continue;
        perArtistCount[artistKey] = used + 1;
        out.add(t);
      }
    }
    return out;
  }

  /// Albums of [countries] whose chart genre matches one of [tokens] AND whose
  /// real `releaseDate` sits inside [days] — the same storefront pools the
  /// genre shelves read, windowed for "Nouveaux albums". Both the genre and the
  /// date come from Apple's own feed, so this is not a hand-typed list.
  static Future<List<RssAlbum>> chartAlbumsFor(
    List<String> countries,
    List<String> tokens, {
    int days = 45,
    int perArtist = 1,
  }) async {
    final pools = await Future.wait(countries
        .map((cc) => topAlbums(cc).catchError((_) => const <RssAlbum>[])));
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    // Pre-orders legitimately carry a near-future date.
    final horizon = now.add(const Duration(days: 7));
    final perArtistCount = <String, int>{};
    final seenAlbum = <String>{};
    final out = <RssAlbum>[];
    for (final pool in pools) {
      for (final a in pool) {
        final g = a.genre.toLowerCase();
        if (g.isEmpty || !tokens.any(g.contains)) continue;
        final rel = a.releaseDate;
        if (rel == null ||
            rel.isBefore(cutoff) ||
            rel.isAfter(horizon)) {
          continue;
        }
        final albumKey = '${a.title}|${a.artist}'.toLowerCase();
        if (!seenAlbum.add(albumKey)) continue;
        final artistKey =
            a.artist.split(RegExp(r'[,&#]')).first.trim().toLowerCase();
        final used = perArtistCount[artistKey] ?? 0;
        if (used >= perArtist) continue;
        perArtistCount[artistKey] = used + 1;
        out.add(a);
      }
    }
    out.sort((a, b) => (b.releaseDate ?? DateTime(2000))
        .compareTo(a.releaseDate ?? DateTime(2000)));
    return out;
  }

  /// Fresh, genre-correct songs for shelf labels ("fr rap", "hip-hop",
  /// "afro rap", "afrobeats", "afro hits"), merged across [labels] so one
  /// "Nouveauté" row can cover rap FR + rap US + afro at once. Newest first.
  static Future<List<TrendSong>> newSongsFor(
    List<String> labels, {
    int days = 30,
  }) async {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final horizon = now.add(const Duration(days: 7));
    final seen = <String>{};
    // Un artiste ne peut occuper qu'une seule ligne du rayon, toutes étiquettes
    // confondues. Le magasin de Côte d'Ivoire joue le rap français (Tiakola y
    // est n°1) et celui du Nigeria joue le rap américain : sans ce budget,
    // « Rap afro » répétait les titres déjà vus dans « Rap FR » et « Hip-hop »
    // au lieu de montrer les scènes locales. Les étiquettes sont parcourues
    // dans l'ordre reçu, donc la ligne la plus spécifique revendique l'artiste
    // en premier.
    final usedArtists = <String>{};
    final out = <TrendSong>[];
    for (final label in labels) {
      final spec = genreChartFor(label);
      if (spec == null) continue;
      final pool = await chartSongsFor(spec.countries, spec.tokens);
      for (final t in pool) {
        final rel = t.releaseDate;
        if (rel == null ||
            rel.isBefore(cutoff) ||
            rel.isAfter(horizon)) {
          continue;
        }
        if (!seen.add('${t.title}|${t.artist}'.toLowerCase())) continue;
        final artistKey =
            t.artist.split(RegExp(r'[,&#]')).first.trim().toLowerCase();
        if (artistKey.isNotEmpty && !usedArtists.add(artistKey)) continue;
        out.add(t);
      }
    }
    out.sort((a, b) => (b.releaseDate ?? DateTime(2000))
        .compareTo(a.releaseDate ?? DateTime(2000)));
    debugPrint('NewSongs ${labels.join("/")}: ${out.length} in <${days}d');
    return out;
  }

  /// The album counterpart of [newSongsFor]: same spec table, same genre
  /// tokens, same real release dates — just a wider window, because albums
  /// drop less often than singles.
  static Future<List<RssAlbum>> newAlbumsFor(
    List<String> labels, {
    int days = 45,
  }) async {
    final seen = <String>{};
    final usedArtists = <String>{};
    final out = <RssAlbum>[];
    for (final label in labels) {
      final spec = genreChartFor(label);
      if (spec == null) continue;
      final fresh =
          await chartAlbumsFor(spec.countries, spec.tokens, days: days);
      for (final a in fresh) {
        if (!seen.add('${a.title}|${a.artist}'.toLowerCase())) continue;
        final artistKey =
            a.artist.split(RegExp(r'[,&#]')).first.trim().toLowerCase();
        if (artistKey.isNotEmpty && !usedArtists.add(artistKey)) continue;
        out.add(a);
      }
    }
    out.sort((a, b) => (b.releaseDate ?? DateTime(2000))
        .compareTo(a.releaseDate ?? DateTime(2000)));
    debugPrint('NewAlbums ${labels.join("/")}: ${out.length} in <${days}d');
    return out;
  }

  /// Les artistes qui ont sorti dans [start]..[end] ET tiennent encore les
  /// magasins aujourd'hui — la seule façon honnête de nommer un « artiste du
  /// mois précédent » sans historique de classement : ni Apple ni Deezer ne
  /// rendent le chart d'un mois clos, ils ne rendent que le classement du jour.
  ///
  /// Les pools lus sont exactement ceux des lignes de genre (mêmes pays, même
  /// cache), donc aucun appel réseau de plus sur une machine à jour. Le rang
  /// retenu est la meilleure place obtenue dans un pays : un artiste n°1 côté
  /// FR passe devant une fin de tableau côté US. Jamagne le lead-artist n'est
  /// compté une fois (« Tiakola & Theodora » compte pour Tiakola).
  static Future<List<ChartArtist>> artistsActiveDuring(
    DateTime start,
    DateTime end, {
    int limit = 24,
  }) async {
    final countries = <String>{};
    for (final spec in _genreCharts.values) {
      countries.addAll(spec.countries);
    }
    final pools = await Future.wait(countries.map(
        (cc) => topSongs(cc).catchError((_) => const <TrendSong>[])));
    final best = <String, ChartArtist>{};
    for (final pool in pools) {
      for (final (pos, t) in pool.indexed) {
        final rel = t.releaseDate;
        if (rel == null || rel.isBefore(start) || rel.isAfter(end)) continue;
        final name = t.artist.split(RegExp(r'[,&#]')).first.trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        final current = best[key];
        if (current == null || pos < current.rank) {
          best[key] = ChartArtist(name: name, art: t.art, rank: pos);
        }
      }
    }
    final out = best.values.toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    // Le pool est ~50 artistes pour un mois : sans décalage chaque installation
    // afficherait exactement les 24 mêmes. La rotation choisit QUELS artistes
    // entrent dans la fenêtre (par installation et par jour), l'affichage garde
    // l'ordre du classement. La liste tournante est renvoyée à la lecture, jamais
    // écrite dans une clé de cache — le cache est partagé.
    final window = ContentCacheService.rotate(
        out.take(limit * 2).toList(), ContentCacheService.refreshBucket);
    final shown = window.take(limit).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    debugPrint('ArtistsActive ${out.length} in ${start.year}-'
        '${start.month.toString().padLeft(2, '0')} -> ${shown.length} shown');
    return shown;
  }

  // ─── Sub-category → storefront mapping ───────────────────────────────────

  /// Current top albums of one storefront (daily disk cache — release dates
  /// and chart membership must roll every day for "Nouveaux albums").
  ///
  /// Reads Apple's modern most-played album chart first: the legacy storefront
  /// feed is a sales top-line that lists anniversary reissues and 2010
  /// catalogue titles (Céline Dion, Kanye reissues, gospel back-catalogue) with
  /// brand-new release dates, which is what leaked non-urban and non-new
  /// records into "Nouveaux albums".
  static Future<List<RssAlbum>> topAlbums(String countryCode) async {
    final modern = await mostPlayedAlbums(countryCode);
    if (modern.isNotEmpty) return modern;
    final cc = countryCode.toLowerCase();
    // `v2` invalidates the day's snapshot: entries cached before the genre
    // label existed would all read as '' and be filtered out.
    final key = 'trendalbv2|$cc|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map((e) => RssAlbum.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    try {
      final uri =
          Uri.parse('https://itunes.apple.com/$cc/rss/topalbums/limit=25/json');
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final feed = (body['feed'] as Map?) ?? const {};
      final entries = (feed['entry'] as List?) ?? const [];
      final albums = <RssAlbum>[];
      for (final e in entries) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final name =
              (((m['im:name'] as Map?) ?? const {})['label'] as String?) ?? '';
          final artist =
              (((m['im:artist'] as Map?) ?? const {})['label'] as String?) ??
                  '';
          if (name.isEmpty || artist.isEmpty) continue;
          var art = '';
          final images = (m['im:image'] as List?) ?? const [];
          if (images.isNotEmpty) {
            art = ((images.last as Map)['label'] as String?) ?? '';
            art = art.replaceFirst(RegExp(r'/\d+x\d+BB'), '/600x600BB');
          }
          DateTime? rel;
          final relRaw =
              (((m['im:releaseDate'] as Map?) ?? const {})['label'] as String?);
          if (relRaw != null && relRaw.isNotEmpty) {
            rel = DateTime.tryParse(relRaw);
          }
          // Apple puts the primary genre in `category.attributes.term`
          // ("Hip-Hop/Rap", "R&B/Soul", "Afrobeats", "Rock", …).
          var genre = '';
          final cat = m['category'];
          final catAttrs = cat is List
              ? ((cat.isNotEmpty ? cat.first : const {}))
              : cat;
          genre = (((catAttrs as Map?)?['attributes'] as Map?)?['term']
                  as String?) ??
              '';
          albums.add(RssAlbum(
            title: name,
            artist: artist,
            cover: art,
            genre: genre,
            releaseDate: rel,
          ));
        } catch (_) {}
      }
      if (albums.isNotEmpty) {
        await ContentCacheService.instance
            .writeJson(key, albums.map((a) => a.toJson()).toList());
      }
      return albums;
    } catch (e) {
      debugPrint('TRENDALB $cc fail :: $e');
      return const [];
    }
  }

  /// Apple Music's real most-played album chart for one storefront: current
  /// 2026 releases with their true `releaseDate` and their own genre name,
  /// which is what the rap/afro windows filter on.
  static Future<List<RssAlbum>> mostPlayedAlbums(String countryCode,
      {int limit = 50}) async {
    final cc = countryCode.toLowerCase();
    final key = 'trendalbm2|$cc|$limit|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map((e) => RssAlbum.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    try {
      final raw = await _fetchChart(
          'https://rss.marketingtools.apple.com/api/v2/$cc/music/most-played/$limit/albums.json');
      if (raw == null) return const [];
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final results =
          (((body['feed'] as Map?) ?? const {})['results'] as List?) ??
              const [];
      final albums = <RssAlbum>[];
      for (final e in results) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final title = m['name'] as String? ?? '';
          final artist = m['artistName'] as String? ?? '';
          if (title.isEmpty || artist.isEmpty) continue;
          var cover = m['artworkUrl100'] as String? ?? '';
          if (cover.isNotEmpty) {
            cover = cover.replaceFirst('/100x100bb', '/600x600bb');
          }
          final relRaw = m['releaseDate'] as String?;
          albums.add(RssAlbum(
            title: title,
            artist: artist,
            cover: cover,
            genre: _primaryGenreName(m['genres']),
            releaseDate: (relRaw == null || relRaw.isEmpty)
                ? null
                : DateTime.tryParse(relRaw),
          ));
        } catch (_) {}
      }
      if (albums.isNotEmpty) {
        await ContentCacheService.instance
            .writeJson(key, albums.map((a) => a.toJson()).toList());
      }
      debugPrint('MostPlayedAlbums $cc: ${albums.length} chart albums');
      return albums;
    } catch (e) {
      debugPrint('TRENDALBM $cc fail :: $e');
      return const [];
    }
  }

  /// The item's own genre: Apple lists the real bucket first and the generic
  /// "Music"/"Musique" container after it.
  static String _primaryGenreName(Object? genresField) {
    for (final g in (genresField as List?) ?? const []) {
      final name = ((g as Map?)?['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final low = name.toLowerCase();
      if (low == 'music' || low == 'musique') continue;
      return name;
    }
    return '';
  }

  /// Current top playlists of one storefront (daily disk cache).
  static Future<List<RssPlaylist>> topPlaylists(String countryCode) async {
    final cc = countryCode.toLowerCase();
    final key = 'trendpl|$cc|d${ContentCacheService.dayBucket}';
    try {
      final cached = await ContentCacheService.instance
          .readJsonIfFresh(key, maxAge: ContentCacheService.dailyTtl);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map((e) => RssPlaylist.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(
          'https://itunes.apple.com/$cc/rss/topplaylists/limit=25/json');
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final feed = (body['feed'] as Map?) ?? const {};
      final entries = (feed['entry'] as List?) ?? const [];
      final playlists = <RssPlaylist>[];
      for (final e in entries) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final name =
              (((m['im:name'] as Map?) ?? const {})['label'] as String?) ?? '';
          final author =
              (((m['im:artist'] as Map?) ?? const {})['label'] as String?) ??
                  '';
          if (name.isEmpty) continue;
          var art = '';
          final images = (m['im:image'] as List?) ?? const [];
          if (images.isNotEmpty) {
            art = ((images.last as Map)['label'] as String?) ?? '';
            art = art.replaceFirst(RegExp(r'/\d+x\d+BB'), '/600x600BB');
          }
          playlists.add(
              RssPlaylist(title: name, author: author, cover: art));
        } catch (_) {}
      }
      if (playlists.isNotEmpty) {
        await ContentCacheService.instance
            .writeJson(key, playlists.map((p) => p.toJson()).toList());
      }
      return playlists;
    } catch (e) {
      debugPrint('TRENDPL $cc fail :: $e');
      return const [];
    }
  }

  // ─── Sub-category → storefront mapping ───────────────────────────────────

  // ─── Genre → real chart ──────────────────────────────────────────────────

  /// The urban shelves this app serves, each pointed at the storefronts whose
  /// chart genuinely is that music.
  ///
  /// They used to be built from a hand-typed artist list, which is why "Afro
  /// Rap" answered with UK drill, "Afrobeats" contained Queen and Dire Straits,
  /// and no woman ever reached the visible cards. A chart answers with whoever
  /// is actually playing that genre in that country this week.
  static const Map<String, GenreChartSpec> _genreCharts = <String, GenreChartSpec>{
    'fr-rap': GenreChartSpec(
      ['fr'],
      ['hip-hop', 'hip hop', 'rap', 'drill', 'trap', 'grime'],
      116,
    ),
    'us-rap': GenreChartSpec(
      ['us', 'ca'],
      ['hip-hop', 'hip hop', 'rap', 'drill', 'trap'],
      116,
    ),
    // Real African hip-hop: Ghanaian, Nigerian, Ivorian and Cameroonian rap.
    // The afro buckets stay on the rap labels only — letting "afrobeats"
    // through is what made this shelf a copy of the Afrobeats row.
    'afro-rap': GenreChartSpec(
      ['ng', 'gh', 'ci', 'cm', 'bj'],
      ['hip-hop', 'hip hop', 'rap', 'trap', 'drill'],
      2,
    ),
    'afrobeats': GenreChartSpec(
      ['ng', 'gh'],
      ['afro', 'african', 'amapiano'],
      2,
    ),
    // The southern/eastern African side (amapiano, kwaito, rumba) so the three
    // afro rows never repeat the same Nigerian tops.
    'afro-hits': GenreChartSpec(
      ['za', 'ke', 'tz', 'bj'],
      ['afro', 'african', 'amapiano', 'rumba', 'konpa', 'zouk', 'highlife'],
      2,
    ),
  };

  /// Display names / search phrases → the table key above.
  static const Map<String, String> _genreChartAliases = <String, String>{
    'fr rap': 'fr-rap',
    'french rap': 'fr-rap',
    'rap francais': 'fr-rap',
    'rap fr': 'fr-rap',
    'rap france': 'fr-rap',
    'hip-hop': 'us-rap',
    'hip hop': 'us-rap',
    'rap': 'us-rap',
    'us rap': 'us-rap',
    'rap us': 'us-rap',
    'drill': 'us-rap',
    'trap': 'us-rap',
    'afro rap': 'afro-rap',
    'african rap': 'afro-rap',
    'afrobeats': 'afrobeats',
    'afrobeat': 'afrobeats',
    'afro hits': 'afro-hits',
    'afro-hit': 'afro-hits',
  };

  /// The chart that carries [label] (an editorial name, a search phrase or a
  /// catalog key), or null when neither Apple nor Deezer has one for it.
  static GenreChartSpec? genreChartFor(String label) {
    final raw = label.toLowerCase().trim();
    if (raw.isEmpty) return null;
    final spaced = raw.replaceAll('-', ' ');
    final hyphen = raw.replaceAll(' ', '-');
    for (final key in [raw, hyphen, spaced]) {
      final direct = _genreCharts[key];
      if (direct != null) return direct;
      final alias = _genreChartAliases[key];
      if (alias != null) return _genreCharts[alias];
    }
    return null;
  }

  /// Maps a Charts/Trending sub name to the Apple storefront(s) it should
  /// mirror. Unknown/global subs blend FR + US. More specific keys come
  /// first because matching is substring-based.
  static List<String> countriesForSub(String sub) {
    final s = _norm(sub);
    const map = <String, List<String>>{
      'south africa': ['za'],
      'naija': ['ng'],
      'afro bangers': ['ng', 'ci', 'gh'],
      'viral now': ['gb', 'us'],
      'fr du jour': ['fr'],
      'rising france': ['fr'],
      'top us': ['us'],
      'france': ['fr'],
      'usa': ['us'],
      'uk': ['gb'],
      'nigeria': ['ng'],
      'ghana': ['gh'],
      "cote d ivoire": ['ci'],
      'benin': ['bj'],
      'africa': ['ng', 'za'],
    };
    for (final k in map.keys) {
      if (s.contains(k)) return map[k]!;
    }
    return ['fr', 'us'];
  }

  // ─── Genre-matched picks ("modern boost") ────────────────────────────────

  /// Our category keys → iTunes chart genre labels. Categories absent here
  /// simply receive no injection.
  static const Map<String, List<String>> _genreByCategory = {
    'hip-hop': ['Hip-Hop/Rap'],
    'rap': ['Hip-Hop/Rap'],
    'rap francais': ['Hip-Hop/Rap'],
    'pop': ['Pop', 'K-Pop'],
    'k-pop': ['K-Pop', 'Pop'],
    'r&b': ['R&B/Soul'],
    'soul': ['R&B/Soul'],
    'rock': ['Rock', 'Alternative'],
    'indie': ['Alternative', 'Indie'],
    'latin': ['Latin'],
    'country': ['Country'],
    'reggae': ['Reggae'],
    'electronic': ['Dance', 'Electronic'],
    'house': ['Dance', 'Electronic'],
    'metal': ['Metal', 'Rock'],
    'blues': ['Blues'],
    'jazz': ['Jazz'],
    'classical': ['Classical'],
    'gospel': ['Christian', 'Gospel'],
    'afrobeats': ['Afrobeats'],
    'afro hits': ['Afrobeats'],
    'amapiano': ['Afrobeats', 'Dance'],
    'dancehall': ['Reggae'],
    'rumba congolaise': ['Afrobeats', 'Worldwide'],
    'musique arabe': ['Worldwide'],
    'bande originale': ['Soundtrack'],
    'drill': ['Hip-Hop/Rap'],
    'chanson francaise': ['French Pop'],
    'folk & acoustic': ['Singer/Songwriter', 'Alternative'],
    'funk': ['R&B/Soul', 'Funk'],
    'romance': ['Pop', 'R&B/Soul'],
  };

  /// Genre fragments that mark the urban / afro family. The iTunes feeds are
  /// inconsistent about spelling — `term` says "Hip Hop/Rap" while `label`
  /// says "Hip-hop/Rap", and the African bucket appears as "Afrobeats",
  /// "Afro-Beat", "Afro House", "African" or "Amapiano" — so matching is done
  /// on lower-cased substrings rather than one exact label set.
  static const List<String> urbanGenreTokens = <String>[
    'hip hop', 'hip-hop', 'hiphop', 'rap', 'r&b', 'soul', 'funk', 'g-funk',
    'afro', 'african', 'amapiano', 'zouk', 'konpa', 'highlife', 'trap',
    'drill', 'grime', 'rumba',
  ];

  /// True when an iTunes chart label belongs to the urban/afro family.
  static bool isUrbanGenre(String label) {
    final norm = label.toLowerCase().trim();
    if (norm.isEmpty) return false;
    return urbanGenreTokens.any(norm.contains);
  }

  /// Up to [n] current-chart tracks whose iTunes genre matches [category].
  /// Rotation is driven by the shared 3-day bucket so picks change at every
  /// content refresh; [rotationOffset] diversifies the pick window between
  /// sub-categories so sibling rows don't all lead with the same chart songs.
  static Future<List<TrendSong>> picksForCategory(
    String category,
    int bucket,
    int n, {
    int rotationOffset = 0,
  }) async {
    final labels = _genreByCategory[category.trim().toLowerCase()];
    if (labels == null || labels.isEmpty || n <= 0) return const [];
    // Storefront labels differ by case ("Hip-Hop/Rap" vs "Hip-hop/Rap") and by
    // breadth ("Christian" vs "Christian & Gospel", "World" vs "Worldwide"), so
    // a label matches when either side contains the other.
    final want = labels.map((l) => l.toLowerCase()).toSet();
    final pools =
        await Future.wait([topSongs('us'), topSongs('fr'), topSongs('gb')]);
    final seen = <String>{};
    final matches = <TrendSong>[];
    for (final pool in pools) {
      for (final t in pool) {
        final g = t.genre.toLowerCase();
        if (!want.any((l) =>
            g == l || (g.length >= 4 && g.contains(l)) ||
                (l.length >= 4 && l.contains(g)))) {
          continue;
        }
        final key = '${t.title}|${t.artist}'.toLowerCase();
        if (seen.contains(key)) continue;
        seen.add(key);
        matches.add(t);
      }
    }
    if (matches.isEmpty) return const [];
    return ContentCacheService.rotate(matches, bucket * 3 + rotationOffset)
        .take(n)
        .toList();
  }

  // ─── helpers ──────────────────────────────────────────────────────────────

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[’'`-]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
