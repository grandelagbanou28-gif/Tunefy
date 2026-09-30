import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:muzo/services/muzo_api_service.dart'; // Ensure valid import
import 'package:muzo/widgets/library_tile.dart';
import 'package:muzo/screens/artist_page_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/l10n/app_localizations.dart';

class ArtistTile extends ConsumerStatefulWidget {
  final String artistName;
  final String artistId;

  const ArtistTile({
    super.key,
    required this.artistName,
    required this.artistId,
  });

  @override
  ConsumerState<ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends ConsumerState<ArtistTile> {
  late final _muzoService = ref.read(muzoApiServiceProvider);
  String? _avatarUrl;
  late String _navChannelId;

  @override
  void initState() {
    super.initState();
    _navChannelId = widget.artistId;
    _fetchAvatar();
  }

  Future<void> _fetchAvatar() async {
    final storage = ref.read(storageServiceProvider);

    // Check cache first
    final cachedUrl = storage.getArtistImage(widget.artistName);
    if (cachedUrl != null) {
      if (mounted) {
        setState(() {
          _avatarUrl = cachedUrl;
        });
      }
    }

    // If we have both ID and Image, no need to fetch
    if (_avatarUrl != null && _navChannelId.isNotEmpty) return;

    if (mounted) {
      try {
        if (_navChannelId.isNotEmpty) {
          final details = await _muzoService.getArtistDetails(_navChannelId);
          if (mounted && details != null && details.artistAvatar.isNotEmpty) {
            setState(() {
              // Try to get high-res image
              final highResUrl = details.artistAvatar.replaceAll(
                RegExp(r'=[sw]\d+(-h\d+)?'),
                '=s800',
              );
              _avatarUrl = highResUrl;
              storage.setArtistImage(widget.artistName, highResUrl);
            });
          }
        } else {
          // Fallback if we only have the artistName (rare but possible)
          final apiService = ref.read(muzoApiServiceProvider);
          final response = await apiService.search(
            widget.artistName,
            filter: 'artists',
          );
          if (mounted && response.results.isNotEmpty) {
            final result = response.results.first;
            setState(() {
              if (result.thumbnails.isNotEmpty) {
                final highResUrl = _highRes(result.thumbnails.last.url);
                _avatarUrl = highResUrl;
                storage.setArtistImage(widget.artistName, highResUrl);
              }
              if (_navChannelId.isEmpty && result.browseId != null) {
                _navChannelId = result.browseId!;
              }
            });
          }
        }
      } catch (e) {
        // Ignore error
      }
    }
  }

  /// Rebuilds the YouTube image URL at 800px. Simple `=s800` string swaps
  /// conflict with multi-param sizes like `=w60-h60-p-l90-rj`, so we keep the
  /// base path and set a single canonical size descriptor.
  static String _highRes(String url) {
    final base = url.split('=').first;
    if (base == url) return url;
    return '$base=s800-c-k-no';
  }

  @override
  Widget build(BuildContext context) {
    return LibraryTile(
      title: widget.artistName,
      subtitle: AppLocalizations.of(context).artistType,
      imageUrl: _avatarUrl,
      isRound: true,
      placeholderIcon: FluentIcons.person_24_regular,
      onTap: () {
        final id = _navChannelId.isNotEmpty ? _navChannelId : widget.artistId;
        final nav = Navigator.of(context);
        if (id.isNotEmpty) {
          nav.push(
            SlidePageRoute(
              page: ArtistPageScreen(
                artistName: widget.artistName,
                imageUrl: _avatarUrl,
              ),
            ),
          );
        }
      },
    );
  }
}
