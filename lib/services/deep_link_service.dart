import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/models/muzo_item.dart';
import 'package:muzo/providers/auth_gate_provider.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/screens/album_screen.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/screens/global_search_screen.dart';
import 'package:muzo/screens/player_screen.dart';
import 'package:muzo/screens/playlist_screen.dart';
import 'package:muzo/services/auth_service.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/navigator_key.dart';
import 'package:muzo/utils/app_colors.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/widgets/glass_snackbar.dart';

enum DeepLinkType { track, playlist, album, artist, search, unknown }

@immutable
class DeepLinkTarget {
  const DeepLinkTarget({required this.type, this.id, this.query});

  final DeepLinkType type;
  final String? id;
  final String? query;

  static const Map<String, DeepLinkType> _prefixes = <String, DeepLinkType>{
    'track': DeepLinkType.track,
    'playlist': DeepLinkType.playlist,
    'album': DeepLinkType.album,
    'artist': DeepLinkType.artist,
    'search': DeepLinkType.search,
    'open': DeepLinkType.unknown,
  };

  static DeepLinkTarget? tryParse(Uri? uri) {
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final isCustomScheme = scheme == customScheme;
    final isAppLink = scheme == 'https' && host == appLinkHost;
    if (!isCustomScheme && !isAppLink) return null;

    final segments = <String>[
      if (isAppLink)
        ...uri.pathSegments
      else if (uri.host.isNotEmpty)
        uri.host,
      ...uri.pathSegments,
    ].where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    final type = _prefixes[segments.first.toLowerCase()];
    if (type == null) return null;

    final rest = segments.skip(1).toList();
    if (type == DeepLinkType.unknown) {
      return DeepLinkTarget(type: type);
    }
    if (type == DeepLinkType.search) {
      final query = uri.queryParameters['q'] ?? (rest.isEmpty ? '' : rest.first);
      return DeepLinkTarget(type: type, query: query.trim());
    }
    if (rest.isEmpty) return null;
    return DeepLinkTarget(type: type, id: rest.first);
  }

  @override
  String toString() =>
      'DeepLinkTarget(${type.name}, id: $id, query: $query)';

  @override
  bool operator ==(Object other) =>
      other is DeepLinkTarget &&
      other.type == type &&
      other.id == id &&
      other.query == query;

  @override
  int get hashCode => Object.hash(type, id, query);

  static const String customScheme = 'muzo';
  static const String appLinkHost = 'tunefy.app';
}

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  static const int _maxReadyAttempts = 12;

  final AppLinks _appLinks = AppLinks();
  final StreamController<DeepLinkTarget> _controller =
      StreamController<DeepLinkTarget>.broadcast();

  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<DeepLinkTarget>? _targetSubscription;
  bool _started = false;
  String? _coldStartUri;

  Stream<DeepLinkTarget> get links => _controller.stream;

  bool get isStarted => _started;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _targetSubscription = _controller.stream.listen(_handleTarget);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      debugPrint('Deep links unavailable on this platform');
      return;
    }

    final pending = <Uri>[];
    var flushed = false;

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        if (flushed) {
          _emit(uri);
          return;
        }
        pending.add(uri);
      },
      onError: (Object err) {
        debugPrint('Deep link stream error: $err');
      },
    );

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _coldStartUri = initial.toString();
        debugPrint('Deep link cold start: $initial');
        _emit(initial);
      }
    } catch (e) {
      debugPrint('Deep link initial link failed (non-fatal): $e');
    }

    flushed = true;
    for (final uri in pending) {
      if (uri.toString() == _coldStartUri) continue;
      _emit(uri);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _targetSubscription?.cancel();
    _controller.close();
  }

  void _emit(Uri uri) {
    final target = DeepLinkTarget.tryParse(uri);
    if (target == null || target.type == DeepLinkType.unknown) {
      debugPrint('Ignoring deep link: $uri');
      return;
    }
    debugPrint('Deep link resolved: $target');
    if (_controller.isClosed) return;
    _controller.add(target);
  }

  Future<void> _handleTarget(DeepLinkTarget target) async {
    try {
      final ready = await _awaitReady();
      if (!ready) {
        debugPrint('Deep link dropped, app never became ready: $target');
        return;
      }
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final container = _containerOf(context);
      if (container == null) return;
      switch (target.type) {
        case DeepLinkType.search:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GlobalSearchScreen(initialQuery: target.query),
            ),
          );
        case DeepLinkType.playlist:
          Navigator.of(context).push(
            SlidePageRoute(page: PlaylistScreen(playlistId: target.id!)),
          );
        case DeepLinkType.album:
          Navigator.of(context).push(
            SlidePageRoute(page: AlbumScreen(albumId: target.id!)),
          );
        case DeepLinkType.artist:
          await _openArtist(context, container, target.id!);
        case DeepLinkType.track:
          await _openTrack(context, container, target.id!);
        case DeepLinkType.unknown:
          return;
      }
    } catch (e) {
      debugPrint('Deep link handling failed for $target: $e');
    }
  }

  Future<void> _openArtist(
    BuildContext context,
    ProviderContainer container,
    String browseId,
  ) async {
    showGlassSnackBar(context, 'Loading artist...');
    final details = await container
        .read(muzoApiServiceProvider)
        .getArtistDetails(browseId);
    if (!context.mounted) return;
    final name = details?.artistName ?? '';
    if (name.isEmpty) {
      showGlassSnackBar(context, 'Artist not found', error: true);
      return;
    }
    Navigator.of(context).push(
      SlidePageRoute(
        page: ArtistPageScreen(
          artistName: name,
          imageUrl: details?.artistAvatar,
        ),
      ),
    );
  }

  Future<void> _openTrack(
    BuildContext context,
    ProviderContainer container,
    String videoId,
  ) async {
    showGlassSnackBar(context, 'Fetching track...');
    MuzoItem? item;
    try {
      final related = await container
          .read(muzoApiServiceProvider)
          .getUpNext(videoId);
      if (related.isNotEmpty) item = related.first;
    } catch (e) {
      debugPrint('Deep link metadata lookup failed: $e');
    }
    if (!context.mounted) return;
    item ??= MuzoItem(
      videoId: videoId,
      title: 'Deep Link Track',
      artists: [MuzoArtist(name: 'Unknown', id: '')],
      thumbnails: [],
      duration: '0:00',
      resultType: 'video',
      isExplicit: false,
    );
    unawaited(container.read(audioHandlerProvider).playVideo(item));
    if (!context.mounted) return;
    _openFullPlayer(context);
  }

  void _openFullPlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black12,
      builder: (sheetContext) {
        return SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Stack(
            children: [
              Container(color: AppColors.cardTranslucent),
              Align(
                alignment: Alignment.bottomCenter,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: const ExpandedPlayer(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _awaitReady() async {
    for (var attempt = 0; attempt < _maxReadyAttempts; attempt++) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted && _sessionStarted(context)) {
        return true;
      }
      await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
    return false;
  }

  bool _sessionStarted(BuildContext context) {
    final container = _containerOf(context);
    if (container == null) return false;
    try {
      return container.read(authServiceProvider).isAuthenticated ||
          container.read(isGuestModeProvider);
    } catch (e) {
      debugPrint('Deep link session check failed: $e');
      return false;
    }
  }

  ProviderContainer? _containerOf(BuildContext context) {
    try {
      return ProviderScope.containerOf(context);
    } catch (e) {
      debugPrint('Deep link container lookup failed: $e');
      return null;
    }
  }
}
