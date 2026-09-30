import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/models/benin_artist.dart';
import 'package:muzo/services/gospel_artist_database.dart';
import 'package:muzo/services/supabase_store.dart';

/// Loads the real Benin artists (Supabase `artists`, country_code=BJ) and
/// feeds them to the gospel gate (`gospel_artist_database.dart`).
///
/// Order of preference: live REST -> Hive cache -> built-in curated list. The
/// app therefore works offline and before the DB is seeded.
class BeninCatalogService {
  static const String _cacheKey = 'benin_catalog';
  static const String _scopedUrl =
      '${SupabaseStore.url}/rest/v1/artists'
      '?select=name,image_url,genres,verified,country,country_code'
      '&country_code=eq.BJ&order=name.asc&limit=4000';

  /// Process-wide singleton so the gate init (StorageService) and any screen
  /// share a single fetch/cache instead of hitting the network twice.
  static final BeninCatalogService instance = BeninCatalogService();

  static const Map<String, String> _geoByCode = {
    'BJ': 'benin',
    'NG': 'nigeria',
    'GH': 'ghana',
    'ZA': 'south africa',
    'KE': 'kenya',
    'US': 'usa',
    'FR': 'france',
    'CA': 'canada',
    'CI': 'africa',
    'CD': 'africa',
    'GB': 'africa',
    'BE': 'africa',
  };

  List<BeninArtist> _catalog = const [];
  Future<List<BeninArtist>>? _loading;

  List<BeninArtist> get catalog => _catalog;

  Future<List<BeninArtist>> loadAll() {
    final existing = _loading;
    if (existing != null) return existing;
    final future = _loadAll();
    _loading = future;
    return future;
  }

  Future<List<BeninArtist>> _loadAll() async {
    try {
      final resp = await http.get(
        Uri.parse(_scopedUrl),
        headers: {
          'apikey': SupabaseStore.anonKey,
          'Authorization': 'Bearer ${SupabaseStore.anonKey}',
        },
      );
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final rows = (jsonDecode(resp.body) as List)
            .map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              return BeninArtist.fromJson({
                ...m,
                'categories': m['genres'],
                'languages': const [],
              });
            })
            .toList();
        if (rows.isNotEmpty) {
          _cache(rows);
          _catalog = rows;
          return rows;
        }
      }
    } catch (e) {
      debugPrint('Benin catalog REST failed: $e');
    }

    final cached = _readCache();
    if (cached.isNotEmpty) {
      _catalog = cached;
      return cached;
    }
    return _builtin();
  }

  Future<void> init() async {
    final all = await loadAll();
    if (all.isEmpty) return;
    final byGeo = <String, List<String>>{};
    for (final a in all) {
      final geo = _geoByCode[(a.countryCode ?? '').toUpperCase()];
      if (geo == null) continue;
      byGeo.putIfAbsent(geo, () => []).add(a.name);
    }
    setGospelSupplement(byGeo);
    debugPrint('Benin catalog loaded: ${all.length} artists from DB');
  }

  List<BeninArtist> _builtin() {
    final rows = <BeninArtist>[];
    builtinGospelByGeo().forEach((geo, names) {
      for (final name in names) {
        rows.add(BeninArtist(name: name, type: 'artist', verified: false));
      }
    });
    _catalog = rows;
    return rows;
  }

  void _cache(List<BeninArtist> rows) {
    try {
      Hive.box('settings').put(
        _cacheKey,
        jsonEncode(rows.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Could not cache benin catalog: $e');
    }
  }

  List<BeninArtist> _readCache() {
    try {
      final raw = Hive.box('settings').get(_cacheKey);
      if (raw is String && raw.isNotEmpty) {
        return (jsonDecode(raw) as List)
            .map((e) => BeninArtist.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Benin catalog cache read failed: $e');
    }
    return const [];
  }
}

/// The full verified Benin-artist catalog (Supabase REST -> Hive cache ->
/// built-in list).
final beninCatalogProvider = FutureProvider<List<BeninArtist>>(
  (ref) => BeninCatalogService.instance.loadAll(),
);
