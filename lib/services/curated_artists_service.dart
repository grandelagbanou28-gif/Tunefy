import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/services/supabase_store.dart';

/// Riverpod view of the catalog singleton. Watching this provider inside a
/// section provider re-runs it whenever the 72h refresh (or initial load)
/// finishes, so Home/Search shelves fill up automatically without a manual
/// pull-to-refresh.
final curatedArtistsServiceProvider =
    ChangeNotifierProvider<CuratedArtistsService>((ref) {
  final service = CuratedArtistsService.instance;
  service.init();
  return service;
});

/// A curated artist from the public `artists` catalog table.
class CuratedArtist {
  final String name;
  final String? imageUrl;
  final List<String> genres;
  final int followers;
  final bool verified;
  final String? countryCode;

  const CuratedArtist({
    required this.name,
    this.imageUrl,
    this.genres = const [],
    this.followers = 0,
    this.verified = false,
    this.countryCode,
  });

  factory CuratedArtist.fromJson(Map<String, dynamic> json) => CuratedArtist(
        name: (json['name'] ?? '').toString(),
        imageUrl:
            (json['image_url'] as String?)?.isNotEmpty == true
                ? json['image_url'].toString()
                : null,
        genres:
            (json['genres'] as List?)?.map((g) => g.toString()).toList() ??
                const [],
        followers: (json['followers'] as num?)?.toInt() ?? 0,
        verified: (json['verified'] as bool?) ?? false,
        countryCode: (json['country_code'] as String?)?.isNotEmpty == true
            ? json['country_code'].toString()
            : null,
      );

  /// First genre, lowercased, used as the category key (e.g. `afrobeats`).
  String get primaryGenre =>
      genres.isNotEmpty ? genres.first.toLowerCase() : '';
}

/// Loads the public `artists` catalog from Supabase (REST → Hive cache → empty)
/// and groups artists by their primary genre so a category screen can show
/// "X qui font du Y" with their real images. Never throws.
///
/// Notifies listeners after every successful (re)load so Home shelves that
/// derive queries from the catalog re-query on refresh.
class CuratedArtistsService extends ChangeNotifier {
  static const String _cacheKey = 'curated_artists';
  static const String _cacheTimeKey = 'curated_artists_checked_at';

  /// Refresh the Supabase artist catalog at most once every 12h. 72h pinned
  /// the Rap FR / Rap US / Rap Afro / Afrobeats rows to the same artist list
  /// for three days straight, so those shelves never appeared to change.
  static const Duration _refreshInterval = Duration(hours: 12);

  static final CuratedArtistsService instance = CuratedArtistsService();

  Map<String, List<CuratedArtist>> _byGenre = const {};
  Future<void>? _loading;
  Timer? _refreshTimer;

  /// Incremented after every (re)load so Home providers that key off the
  /// catalog can re-query exactly when the 72h refresh happens.
  int _catalogRevision = 0;
  int get catalogRevision => _catalogRevision;

  /// Artists for a category (genre key), sorted top listeners first.
  List<CuratedArtist> artistsFor(String genre) =>
      List.unmodifiable(_byGenre[genre.toLowerCase()] ?? const []);

  /// Artists of [genre] restricted to a country (case-insensitive) when
  /// [country] is provided, preserving the popularity-first order.
  List<CuratedArtist> artistsWhere(String genre, {String? country}) {
    final list = artistsFor(genre);
    if (country == null || country.isEmpty) return list;
    final cc = country.toUpperCase();
    return list.where((a) => (a.countryCode ?? '').toUpperCase() == cc).toList();
  }

  /// All genre keys that contain at least one artist.
  List<String> get availableGenres =>
      List.unmodifiable(_byGenre.keys.toList());

  /// True when a catalog load has data (used as a cheap presence flag).
  bool get hasData => _byGenre.isNotEmpty;

  Future<void> init() {
    final existing = _loading;
    if (existing != null) return existing;
    _scheduleNextRefresh();
    final future = _load();
    _loading = future;
    return future;
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshInterval, () async {
      await instance._load();
      instance._scheduleNextRefresh();
    });
  }

  bool _shouldRefreshFromNetwork(DateTime now, DateTime? lastCheck) {
    if (lastCheck == null) return true;
    return now.difference(lastCheck) >= _refreshInterval;
  }

  /// Completes when the catalog has been loaded at least once (true), so a
  /// FutureBuilder can drive the UI. Never throws.
  Future<bool> whenReady() async {
    await init();
    return hasData;
  }

  Future<void> _load() async {
    // Respect the 72h cadence: if we already refreshed recently, reuse cache.
    if (!_shouldRefreshFromNetwork(DateTime.now(), _lastChecked())) {
      if (_byGenre.isNotEmpty) {
        _catalogRevision++;
        notifyListeners();
        return;
      }
      final cached = _readCache();
      if (cached.isNotEmpty) {
        _byGenre = cached;
        _catalogRevision++;
        notifyListeners();
        return;
      }
    }
    const pageSize = 1000;
    final byGenre = <String, List<CuratedArtist>>{};
    // Table par catégorie (migration 0013) : une table par catégorie Home v2,
    // limitée strictement aux 5 catégories genre servies par l'écran Home
    // (FR Rap, US Rap, Afro Rap, Afrobeats, Afro Hits — Benin Hits n'a pas de
    // table : il est servi par le pipeline seeds YT/iTunes existant).
    // Fallback sur la table groupée `artists` si les nouvelles tables n'ont
    // pas encore été créées en base (le REST renverra alors une erreur).
    const artistGenres = [
      'fr-rap',
      'us-rap',
      'afro-rap',
      'afrobeats',
      'afro-hits',
    ];

    /// `artists_hip-hop` -> `artists_hiphop` (no special chars in table names).
    String catTable(String genre) {
      final clean = genre.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
      return 'artists_$clean';
    }

    Future<void> fetchCategory(String genre) async {
      var offset = 0;
      var page = 0;
      while (true) {
        final resp = await http.get(
          Uri.parse(
            '${SupabaseStore.url}/rest/v1/${catTable(genre)}'
            '?select=name,image_url,genres,followers,verified,country_code'
            '&order=followers.desc&limit=$pageSize&offset=$offset',
          ),
          headers: {'apikey': SupabaseStore.anonKey},
        );
        if (resp.statusCode != 200) {
          throw http.ClientException(
            'Table ${catTable(genre)} unavailable (HTTP ${resp.statusCode})',
          );
        }
        if (resp.body.isEmpty) return;
        final rows = jsonDecode(resp.body) as List;
        if (rows.isEmpty) return;
        void addRow(dynamic e) {
          final artist = CuratedArtist.fromJson(
            Map<String, dynamic>.from(e as Map),
          );
          if (artist.name.isEmpty) return;
          byGenre.putIfAbsent(genre, () => []).add(artist);
        }

        for (final e in rows) {
          addRow(e);
        }
        // Pré-trier partiel (ordre followers.desc garanti par la requête),
        // puis dédoublonner par nom (un artiste = une entrée).
        offset += pageSize;
        page++;
        if (rows.length < pageSize) break;
        if (page > 50) break; // safety
      }
    }

    try {
      var fallbackError = false;
      for (final genre in artistGenres) {
        try {
          await fetchCategory(genre);
        } catch (e) {
          // Les tables par catégorie n'existent pas encore en base :
          // tout recharger depuis la table groupée (ancienne méthode).
          fallbackError = true;
          debugPrint('Table $genre indisponible ($e), fallback $artistGenres '
              'entier');
          break;
        }
      }
      if (fallbackError) {
        // Fallback : tout charger depuis la table groupée, comme avant.
        byGenre.clear();
        var offset = 0;
        var page = 0;
        while (true) {
          final resp = await http.get(
            Uri.parse(
              '${SupabaseStore.url}/rest/v1/artists'
              '?select=name,image_url,genres,followers,verified,country_code'
              '&genres=not.is.null&limit=$pageSize&offset=$offset',
            ),
            headers: {'apikey': SupabaseStore.anonKey},
          );
          if (resp.statusCode != 200 || resp.body.isEmpty) break;
          final rows = jsonDecode(resp.body) as List;
          if (rows.isEmpty) break;
          for (final e in rows) {
            final artist = CuratedArtist.fromJson(
              Map<String, dynamic>.from(e as Map),
            );
            if (artist.name.isEmpty) continue;
            final genre = artist.primaryGenre;
            if (genre.isEmpty) continue;
            byGenre.putIfAbsent(genre, () => []).add(artist);
          }
          offset += pageSize;
          page++;
          if (rows.length < pageSize) break;
          if (page > 20) break; // safety: 20 pages = 20k artists max
        }
      }
      // Dédoublonner par nom (1 artiste = 1 entrée par catégorie), puis trier
      // par popularité.
      byGenre.forEach((genre, list) {
        final seen = <String>{};
        list.retainWhere((a) => seen.add(a.name.toLowerCase().trim()));
        list.sort((a, b) => b.followers.compareTo(a.followers));
      });
      // Sort each bucket by popularity desc.
      byGenre.forEach((genre, list) {
        list.sort((a, b) => b.followers.compareTo(a.followers));
      });
      _registerAliasBuckets(byGenre);
      if (byGenre.isNotEmpty) {
        _byGenre = Map.unmodifiable(byGenre);
        _cache(_byGenre);
        _markChecked();
      }
      debugPrint('Curated artists loaded: ${_countArtists()} across '
          '${_byGenre.length} genres');
      _catalogRevision++;
      notifyListeners();
      return;
    } catch (e) {
      debugPrint('Curated artists REST failed: $e');
    }
    if (_byGenre.isEmpty) {
      final cached = _readCache();
      if (cached.isNotEmpty) _byGenre = cached;
      _catalogRevision++;
      notifyListeners();
    }
  }

  void _registerAliasBuckets(Map<String, List<CuratedArtist>> byGenre) {
    const stacks = {
      'us-rap': ['rap', 'hip-hop', 'drill', 'trap', 'rnb', 'r&b'],
      'afro-rap': ['afro rap', 'african rap', 'afro pop'],
      'afrobeats': ['afrobeats', 'afrobeat', 'afro pop', 'afropop'],
      'afro-hits': ['afrobeats', 'afrobeat', 'afro pop', 'afropop'],
    };
    stacks.forEach((alias, genreKeys) {
      final merged = <CuratedArtist>[];
      for (final key in genreKeys) {
        merged.addAll(byGenre[key] ?? const []);
      }
      if (merged.isEmpty) return;
      final seen = <String>{};
      merged.retainWhere((a) => seen.add(a.name.toLowerCase().trim()));
      merged.sort((a, b) => b.followers.compareTo(a.followers));
      byGenre[alias] = merged;
    });
  }

  DateTime? _lastChecked() {
    try {
      final raw = Hive.box('settings').get(_cacheTimeKey);
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    } catch (_) {}
    return null;
  }

  void _markChecked() {
    try {
      Hive.box('settings')
          .put(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Could not store checked time: $e');
    }
  }

  int _countArtists() =>
      _byGenre.values.fold(0, (sum, list) => sum + list.length);

  void _cache(Map<String, List<CuratedArtist>> byGenre) {
    try {
      final data = <String, List<Map<String, dynamic>>>{};
      byGenre.forEach((genre, list) {
        data[genre] = list
            .map((a) => {
                  'name': a.name,
                  'image_url': a.imageUrl,
                  'genres': a.genres,
                  'followers': a.followers,
                  'verified': a.verified,
                  'country_code': a.countryCode,
                })
            .toList();
      });
      Hive.box('settings').put(_cacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Could not cache curated artists: $e');
    }
  }

  Map<String, List<CuratedArtist>> _readCache() {
    try {
      final raw = Hive.box('settings').get(_cacheKey);
      if (raw is String && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final result = <String, List<CuratedArtist>>{};
        data.forEach((genre, list) {
          result[genre] = (list as List)
              .map((e) => CuratedArtist.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList();
        });
        return Map.unmodifiable(result);
      }
    } catch (e) {
      debugPrint('Curated artists cache read failed: $e');
    }
    return const {};
  }
}