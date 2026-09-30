import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/services/supabase_store.dart';

/// Loads the curated `category_artist_seeds` catalog from Supabase
/// (REST → Hive cache → in-memory empty) and feeds it to the sub-category seed
/// resolution (`sub_category_seeds.dart`).
///
/// The built-in seed maps remain the fallback when the DB is empty/unreachable,
/// exactly like the gospel catalog flow.
class CategoryArtistsService {
  static const String _cacheKey = 'category_artist_seeds';

  /// Process-wide singleton, shared with `subCategorySeeds()`.
  static final CategoryArtistsService instance = CategoryArtistsService();

  /// Browse cards pass the *query* as the category name (e.g. "Mood" card →
  /// query `chill mood`; "Chansons" card → query `chanson francaise`) while the
  /// seed rows are filed under the display title. This bridges the two,
  /// mirroring [`sub_category_seeds`].
  static const Map<String, String> _canonicalCategory = {
    'music': 'Music',
    'amapiano': 'Amapiano',
    'benin hits': 'Hit Benin',
    'chill mix': 'Made For You',
    'new release': 'New Releases',
    'pop': 'Pop',
    'hip hop': 'Hip-Hop',
    'rock': 'Rock',
    'latin': 'Latin',
    'chill mood': 'Mood',
    'top hits': 'Charts',
    'oldies': 'Decades',
    'country': 'Country',
    'r&b': 'R&B',
    'k-pop': 'K-Pop',
    'indie': 'Indie',
    'workout': 'Workout',
    'focus': 'Focus',
    'sleep': 'Sleep',
    'party': 'Party',
    'bande originale': 'Bande Originale',
    'afro hits': 'Afro Hits',
    'chanson francaise': 'Chansons',
    'rap francais': 'Rap Français',
    'afrobeats': 'Afrobeats',
    'reggae': 'Reggae',
    'jazz': 'Jazz',
    'classical': 'Classical',
    'electronic': 'Electronic',
    'rap': 'Rap',
    'soul': 'Soul',
    'chill': 'Chill',
    'metal': 'Metal',
    'blues': 'Blues',
    'folk acoustic': 'Folk & Acoustic',
    'gospel': 'Gospel',
    'funk': 'Funk',
    'house music': 'House',
    'lofi beats': 'Lo-Fi Beats',
    'dancehall': 'Dancehall',
    'romantic love songs': 'Romance',
    'desi hits': 'Desi',
    'caribbean': 'Caribbean',
    'meditation': 'Meditation',
    'musique arabe': 'Musique Arabe',
    'rumba congolaise': 'Rumba Congolaise',
    'drill': 'Drill',
    'comedy': 'Comedy',
    'news': 'News & Politics',
    'trending': 'Trending',
  };

  Map<String, List<String>> _byKey = const {};
  Future<void>? _loading;

  /// Test-only: inject a seed catalog without touching the network.
  @visibleForTesting
  void seedForTest(Map<String, List<String>> byKey) {
    _byKey = Map.unmodifiable(byKey);
  }

  /// Artists for `'<canonical category> > sub'`, or `null` when unknown.
  List<String>? seedFor(String category, String sub) {
    final canon =
        _canonicalCategory[category.trim().toLowerCase()] ?? category.trim();
    return _byKey['$canon > $sub'.trim()];
  }

  /// True when [artistName] is one of the curated seeds of that exact section.
  ///
  /// Curated seed artists are hand-verified for their (category, sub), so the
  /// strict category gate may accept a song by them even when the song title
  /// never spells the country/genre word (e.g. "Folies" by Fanicko inside a
  /// Benin sub). Normalization folds accents so "Angélique Kidjo" matches the
  /// seed "Angelique Kidjo". Never throws: unknown sections return false.
  bool containsArtist(String category, String sub, String artistName) {
    final seeds = seedFor(category, sub);
    if (seeds == null || seeds.isEmpty) return false;
    final needle = _normalize(artistName);
    if (needle.isEmpty) return false;
    for (final s in seeds) {
      if (_normalize(s) == needle) return true;
    }
    return false;
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ç', 'c')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Concurrent-safe load: REST → Hive cache → empty (built-in seeds remain the
  /// fallback in `sub_category_seeds.dart`). Never throws.
  Future<void> init() {
    final existing = _loading;
    if (existing != null) return existing;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final resp = await http.get(
        Uri.parse(
          '${SupabaseStore.url}/rest/v1/category_artist_seeds?select=*&limit=4000',
        ),
        headers: {'apikey': SupabaseStore.anonKey},
      );
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final rows = jsonDecode(resp.body) as List;
        final byKey = <String, List<String>>{};
        for (final e in rows) {
          final m = Map<String, dynamic>.from(e as Map);
          final artists = (m['artists'] as List?)?.map((x) => x.toString()).toList();
          if (m['category'] == null || m['sub'] == null || artists == null) {
            continue;
          }
          byKey['${m['category']} > ${m['sub']}'.trim()] = artists;
        }
        _byKey = Map.unmodifiable(byKey);
        _cache(_byKey);
        debugPrint('Category artist seeds loaded: ${_byKey.length} rows from DB');
        return;
      }
    } catch (e) {
      debugPrint('Category artist seeds REST failed: $e');
    }
    _byKey = _readCache();
  }

  void _cache(Map<String, List<String>> byKey) {
    try {
      Hive.box('settings').put(_cacheKey, jsonEncode(byKey));
    } catch (e) {
      debugPrint('Could not cache category artist seeds: $e');
    }
  }

  Map<String, List<String>> _readCache() {
    try {
      final raw = Hive.box('settings').get(_cacheKey);
      if (raw is String && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        return Map.unmodifiable(data.map((k, v) => MapEntry(
              k,
              (v as List).map((x) => x.toString()).toList(),
            )));
      }
    } catch (e) {
      debugPrint('Category artist seeds cache read failed: $e');
    }
    return const {};
  }
}