import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Brand mark used as an overlay badge on every content cover (artists,
/// albums, playlists, podcasts). `assets/brand_mark.png` is a white, fully
/// transparent-background silhouette of the app logo, so it can be tinted to
/// any colour at runtime with a `srcIn` colour filter.
const String brandMarkAsset = 'assets/brand_mark.png';

/// The three allowed badge tints. The picker below chooses, per image, the one
/// that stays most legible against that image's own colours.
const Color brandTintWhite = Color(0xFFFFFFFF);
const Color brandTintGreen = Color(0xFF1DDA63);
const Color brandTintBlue = Color(0xFF1D9BF0);

const List<Color> _brandTints = <Color>[
  brandTintWhite,
  brandTintGreen,
  brandTintBlue,
];

/// Resolves and memoises the badge tint for a given cover URL.
///
/// The image is decoded once at a tiny resolution (its average colour does not
/// need detail), and the average is compared against the three brand tints so
/// the most contrasting one wins. Results are cached forever for the session,
/// keyed by URL, so each cover is analysed at most once.
class CoverTint {
  CoverTint._();

  static final Map<String, Color> _cache = <String, Color>{};

  static Color? peek(String url) => _cache[url];

  static Future<Color> resolve(String url) {
    final cached = _cache[url];
    if (cached != null) return Future<Color>.value(cached);

    final completer = Completer<Color>();
    late ImageStreamListener listener;
    ImageStream? stream;
    try {
      final provider = ResizeImage(
        NetworkImage(url),
        width: 16,
        height: 16,
        allowUpscaling: false,
      );
      stream = provider.resolve(ImageConfiguration.empty);
      listener = ImageStreamListener(
        (ImageInfo info, bool _) async {
          final image = info.image;
          Color tint = brandTintWhite;
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (data != null) {
              tint = _pick(data.buffer.asUint8List());
            }
          } catch (_) {
            tint = brandTintWhite;
          }
          if (!completer.isCompleted) completer.complete(tint);
        },
        onError: (Object _, StackTrace? __) {
          if (!completer.isCompleted) completer.complete(brandTintWhite);
        },
      );
      stream.addListener(listener);
    } catch (_) {
      if (!completer.isCompleted) completer.complete(brandTintWhite);
    }

    return completer.future
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => brandTintWhite,
        )
        .then((tint) {
          _cache[url] = tint;
          try {
            if (stream != null) stream.removeListener(listener);
          } catch (_) {}
          return tint;
        });
  }

  static Color _pick(Uint8List rgba) {
    if (rgba.length < 4) return brandTintWhite;
    int r = 0, g = 0, b = 0, n = 0;
    for (int i = 0; i + 3 < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a < 40) continue;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
    if (n == 0) return brandTintWhite;
    final avg = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);

    // Choose the tint whose luminance contrasts most with the average colour.
    final avgLum = avg.computeLuminance();
    Color best = _brandTints.first;
    double bestScore = -1;
    for (final tint in _brandTints) {
      final l1 = tint.computeLuminance();
      final l2 = avgLum;
      final ratio = (l1 > l2 ? l1 + 0.05 : l2 + 0.05) /
          (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
      if (ratio > bestScore) {
        bestScore = ratio;
        best = tint;
      }
    }
    return best;
  }
}

/// The tinted brand mark, used as a corner badge over a cover.
class BrandBadge extends StatelessWidget {
  const BrandBadge({
    super.key,
    required this.tint,
    this.size = 26,
    this.opacity = 0.95,
  });

  final Color tint;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
          // The mark is wider than tall (the Tunefy glyph, not a disc), so it is
          // sized by width and keeps its own aspect ratio.
          child: Image.asset(
            brandMarkAsset,
            width: size,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

/// Overlays a [BrandBadge] in the top-left corner of [child] (usually a cover).
/// The tint is resolved asynchronously from [imageUrl]; until it is known the
/// white tint is used so the badge never flashes a wrong colour.
class BrandBadged extends StatefulWidget {
  const BrandBadged({
    super.key,
    required this.imageUrl,
    required this.child,
    this.badgeSize = 22,
    this.opacity = 0.92,
    this.inset = 6,
  });

  final String? imageUrl;
  final Widget child;
  final double badgeSize;
  final double opacity;
  final double inset;

  @override
  State<BrandBadged> createState() => _BrandBadgedState();
}

class _BrandBadgedState extends State<BrandBadged> {
  Color _tint = brandTintWhite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BrandBadged oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _load();
  }

  void _load() {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      if (_tint != brandTintWhite) {
        setState(() => _tint = brandTintWhite);
      }
      return;
    }
    final known = CoverTint.peek(url);
    if (known != null) {
      if (_tint != known) setState(() => _tint = known);
      return;
    }
    unawaited(
      CoverTint.resolve(url).then((tint) {
        if (!mounted || widget.imageUrl != url) return;
        if (_tint != tint) setState(() => _tint = tint);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          top: widget.inset,
          left: widget.inset,
          child: BrandBadge(
            tint: _tint,
            size: widget.badgeSize,
            opacity: widget.opacity,
          ),
        ),
      ],
    );
  }
}

/// A cover image (network, with the app's usual grey placeholder fallback)
/// carrying the brand badge in its top-left corner. Handy for the many
/// `CachedNetworkImage` call sites spread across the app.
class BrandCover extends StatelessWidget {
  const BrandCover({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.badgeSize = 22,
    this.opacity = 0.92,
    this.inset = 6,
    this.borderRadius,
  });

  final String? imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final double badgeSize;
  final double opacity;
  final double inset;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    Widget image = hasImage
        ? CachedNetworkImage(
            imageUrl: url,
            fit: fit,
            placeholder: (_, __) => placeholder ?? _fallback(context),
            errorWidget: (_, __, ___) => placeholder ?? _fallback(context),
          )
        : (placeholder ?? _fallback(context));
    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return BrandBadged(
      imageUrl: url,
      badgeSize: badgeSize,
      opacity: opacity,
      inset: inset,
      child: image,
    );
  }

  Widget _fallback(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0x33282828)),
      child: SizedBox.expand(),
    );
  }
}
