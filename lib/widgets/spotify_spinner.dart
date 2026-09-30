import 'package:flutter/material.dart';

/// Spinner de chargement « façon Spotify » : un anneau déterminé qui se remplit
/// (0 → 1) en boucle tout en tournant, au lieu de l'arc indéterminé par défaut.
///
/// Si une vraie [value] (0.0–1.0) est fournie (téléchargement, tampon…) l'anneau
/// devient déterministe et ne s'anime pas tout seul.
class SpotifySpinner extends StatefulWidget {
  const SpotifySpinner({
    super.key,
    this.value,
    this.size,
    this.strokeWidth = 2.5,
    this.color = const Color(0xFF1DB954),
    this.backgroundColor,
  });

  final double? value;

  /// Diamètre forcé ; si null, la taille suit les contraintes du parent,
  /// comme [CircularProgressIndicator].
  final double? size;

  final double strokeWidth;
  final Color color;
  final Color? backgroundColor;

  @override
  State<SpotifySpinner> createState() => _SpotifySpinnerState();
}

class _SpotifySpinnerState extends State<SpotifySpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _ring(double value) {
    return RotationTransition(
      turns: AlwaysStoppedAnimation(value * 0.35),
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: widget.strokeWidth,
        color: widget.color,
        backgroundColor: widget.backgroundColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget ring = widget.value != null
        ? _ring(widget.value!)
        : AnimatedBuilder(
            animation: _controller,
            child: _ring(0),
            builder: (context, child) {
              final t = Curves.easeInOutCubic.transform(_controller.value);
              return _ring(t);
            },
          );

    if (widget.size == null) return ring;
    return SizedBox(width: widget.size, height: widget.size, child: ring);
  }
}