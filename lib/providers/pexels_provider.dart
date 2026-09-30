import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/services/pexels_api_service.dart';

final pexelsApiServiceProvider = Provider<PexelsApiService>((ref) {
  return PexelsApiService();
});

/// Cached stock clip used to decorate a page whose music video cannot be
/// resolved. Null while disabled, loading or when nothing was found.
final pexelsBackdropProvider =
    FutureProvider.family<PexelsClip?, ({String videoId, String query})>(
        (ref, key) async {
  final service = ref.watch(pexelsApiServiceProvider);
  if (!service.isConfigured) return null;
  return service.findClip(key.query, cacheKey: 'clip:${key.videoId}');
});
