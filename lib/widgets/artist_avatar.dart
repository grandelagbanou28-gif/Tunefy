import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/services/muzo_api_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/brand_badge.dart';
import 'package:muzo/widgets/spotify_chips.dart';

const List<Color> _palette = [
  Color(0xFF7C4DFF),
  Color(0xFF26A69A),
  Color(0xFF5C6BC0),
  Color(0xFFEF5350),
  Color(0xFF42A5F5),
  Color(0xFFEC407A),
  Color(0xFF66BB6A),
  Color(0xFFFFA726),
];

/// A real artist avatar — never a category / playlist artwork.
///
/// Resolution order: provided [imageUrl] (iTunes / Supabase) → cached real
/// image → real image resolved through an artist search on YouTube → a
/// professional initials block. It never falls back to a cover image.
class ArtistAvatar extends ConsumerStatefulWidget {
  const ArtistAvatar({
    super.key,
    required this.artistName,
    required this.size,
    this.imageUrl,
    this.circle = false,
  });

  final String artistName;
  final double size;
  final String? imageUrl;
  final bool circle;

  @override
  ConsumerState<ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends ConsumerState<ArtistAvatar> {
  static final Map<String, Future<void>> _inflight = {};

  String? _url;

  String get _initial {
    final n = widget.artistName.trim();
    if (n.isEmpty) return '?';
    final parts =
        n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    return n.substring(0, 1).toUpperCase();
  }

  Color get _color {
    var h = 0;
    for (final c in widget.artistName.toLowerCase().codeUnits) {
      h = h * 31 + c;
    }
    return _palette[h.abs() % _palette.length];
  }

  @override
  void initState() {
    super.initState();
    final known = widget.imageUrl;
    if (known == null || known.isEmpty) {
      _resolveFromCachedOrSearch();
    } else {
      _url = known;
    }
  }

  @override
  void didUpdateWidget(covariant ArtistAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final known = widget.imageUrl;
    if (known != null && known.isNotEmpty && known != oldWidget.imageUrl) {
      _url = known;
    }
  }

  Future<void> _resolveFromCachedOrSearch() async {
    final name = widget.artistName;
    final storage = ref.read(storageServiceProvider);
    final cached = storage.getArtistImage(name);
    if (cached != null && _isValidImage(cached)) {
      _apply(cached);
      return;
    }
    final inFlight = _inflight[name];
    if (inFlight != null) {
      await inFlight;
      _apply(storage.getArtistImage(name));
      return;
    }
    final future = _doResolve(name, storage);
    _inflight[name] = future;
    try {
      await future;
    } finally {
      _inflight.remove(name);
    }
    _apply(storage.getArtistImage(name));
  }

  Future<void> _doResolve(String name, StorageService storage) async {
    try {
      final api = ref.read(muzoApiServiceProvider);
      final res = await api.search(name, filter: 'all');
      final channel = res.results.where((r) => r.resultType == 'channel' || (r.browseId != null && r.browseId!.startsWith('UC'))).firstOrNull;
      if (channel != null && channel.thumbnails.isNotEmpty) {
        final highRes = _highRes(channel.thumbnails.last.url);
        await storage.setArtistImage(name, highRes);
        return;
      }
      if (res.results.isNotEmpty && res.results.first.thumbnails.isNotEmpty) {
        final highRes = _highRes(res.results.first.thumbnails.last.url);
        await storage.setArtistImage(name, highRes);
      }
    } catch (_) {}
  }

  /// Rebuilds the YouTube image URL at 800px. Simple `=s800` string swaps
  /// conflict with multi-param sizes like `=w60-h60-p-l90-rj`, so we keep the
  /// base path and set a single canonical size descriptor.
  static String _highRes(String url) {
    final base = url.split('=').first;
    if (base == url) return url;
    return '$base=s800-c-k-no';
  }

  void _apply(String? stored) {
    final fine =
        stored != null && stored.isNotEmpty && _isValidImage(stored);
    if (!mounted) return;
    setState(() {
      _url = fine ? stored : null;
    });
  }

  /// Cached URLs produced by the old `=s800-h120-...` swap are malformed and
  /// rejected by YouTube: exclude them so a stale Hive entry can never keep an
  /// artist stuck on their initials. Valid forms: `=s800-c-k-no`,
  /// `=s900-c-k-c0x00ffffff-no-rj`, `.../hqdefault.jpg`, etc.
  static bool _isValidImage(String url) {
    if (!url.startsWith('http')) return false;
    return !RegExp(r'=[sh]\d+-[hw]\d+').hasMatch(url);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final url = _url;

    Widget child;
    if (url != null && url.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _initialsAvatar(),
      );
    } else {
      child = _initialsAvatar();
    }

    // Brand badge, kept fully inside the avatar: a circle only contains its
    // inscribed square, so the inset grows for round avatars. Tiny avatars
    // (chips, dense lists) stay clean and get no badge.
    if (size >= 40) {
      final badgeSize = (size * 0.34).clamp(14.0, 32.0);
      final inset = widget.circle ? size * 0.16 : size * 0.07;
      child = BrandBadged(
        imageUrl: url,
        badgeSize: badgeSize,
        opacity: 0.9,
        inset: inset,
        child: child,
      );
    }

    if (widget.circle) return ClipOval(child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: child,
    );
  }

  Widget _initialsAvatar() {
    final size = widget.size;
    final color = _color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, spotifyBlack, 0.45)!],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: TextStyle(
          color: spotifyWhite,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}