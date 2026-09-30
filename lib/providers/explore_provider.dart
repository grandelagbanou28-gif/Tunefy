import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/releases_service.dart';

final trendingContentProvider = FutureProvider<Map<String, List<MuzoItem>>>((
  ref,
) async {
  final apiService = ref.watch(muzoApiServiceProvider);
  return apiService.getTrendingContent();
});

/// Newest songs for Library → New Releases.
///
/// Primary: worker `/api/trending`. When that endpoint is down/empty (common
/// on device), fall back to ReleasesService (Deezer + MusicBrainz + Apple RSS
/// fr/us/ng/bj/ci) so the shelf never shows "Aucune nouveauté".
final newestSongsProvider = FutureProvider<List<MuzoItem>>((ref) async {
  try {
    final content = await ref.watch(trendingContentProvider.future);
    final songs = content['songs'] ?? [];
    if (songs.isNotEmpty) return songs;
  } catch (_) {}

  try {
    final resp = await ReleasesService.fetch(
      type: 'track',
      period: 'month',
      limit: 60,
    );
    if (resp.data.isNotEmpty) {
      return resp.data
          .map((r) => MuzoItem(
                title: r.title,
                thumbnails: [
                  if (r.coverUrl != null && r.coverUrl!.isNotEmpty)
                    MuzoThumbnail(url: r.coverUrl!, width: 300, height: 300),
                ],
                resultType: 'song',
                isExplicit: false,
                artists: [
                  if (r.artistName != null && r.artistName!.isNotEmpty)
                    MuzoArtist(name: r.artistName!),
                ],
                releaseDate: r.releaseDate,
                source: r.provider,
                sourceId: r.id,
                fetchedAt: DateTime.now(),
              ))
          .toList();
    }
  } catch (_) {}

  // Last resort: Apple current tops so the screen is never blank.
  try {
    final all = await ReleasesService.fetch(type: 'all', period: 'month', limit: 40);
    return all.data
        .where((r) => r.contentType == 'track' || r.contentType == 'album')
        .map((r) => MuzoItem(
              title: r.title,
              thumbnails: [
                if (r.coverUrl != null && r.coverUrl!.isNotEmpty)
                  MuzoThumbnail(url: r.coverUrl!, width: 300, height: 300),
              ],
              resultType: r.contentType == 'album' ? 'album' : 'song',
              isExplicit: false,
              artists: [
                if (r.artistName != null && r.artistName!.isNotEmpty)
                  MuzoArtist(name: r.artistName!),
              ],
              releaseDate: r.releaseDate,
              source: r.provider,
              sourceId: r.id,
              fetchedAt: DateTime.now(),
            ))
        .toList();
  } catch (_) {
    return <MuzoItem>[];
  }
});

final newestVideosProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final content = await ref.watch(trendingContentProvider.future);
  return content['videos'] ?? [];
});

final trendingPlaylistsProvider = FutureProvider<List<MuzoItem>>((
  ref,
) async {
  final content = await ref.watch(trendingContentProvider.future);
  return content['playlists'] ?? [];
});

// Keep this for backward compatibility if needed, or remove if unused.
// For now, I'll redefine it to combine everything or just deprecate it.
// Since HomeScreen will be rewritten, we might not need this anymore.
// But to avoid breaking other things immediately, let's leave a dummy or combined one.
final exploreContentProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final songs = await ref.watch(newestSongsProvider.future);
  final videos = await ref.watch(newestVideosProvider.future);
  return [...songs, ...videos]..shuffle();
});

final topOnMuzoProvider = FutureProvider<List<MuzoItem>>((ref) async {
  final apiService = ref.watch(muzoApiServiceProvider);
  return apiService.getTopOnMuzo();
});
