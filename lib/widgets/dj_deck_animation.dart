import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated DJ deck: a spinning vinyl with a drifting tonearm over a live
/// equalizer. Used as the hero of the Tunefy DJ page — the static `graphic_eq`
/// icon made the feature look like a settings panel rather than a DJ.
///
/// [active] slows the bars down when nothing is happening; the disc keeps
/// turning so the page never looks frozen.
class DjDeckAnimation extends StatefulWidget {
  const DjDeckAnimation({
    super.key,
    this.size = 132,
    this.active = true,
  });

  final double size;
  final bool active;

  @override
  State<DjDeckAnimation> createState() => _DjDeckAnimationState();
}

class _DjDeckAnimationState extends State<DjDeckAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  /// La platine ne doit pas continuer à se repeindre quand la page est
  /// couverte (mix ouvert par-dessus, onglet changé) : TickerMode le signale.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _DjDeckPainter(
              progress: _controller.value,
              energy: widget.active ? 1.0 : 0.45,
            ),
          );
        },
      ),
    );
  }
}

class _DjDeckPainter extends CustomPainter {
  _DjDeckPainter({required this.progress, required this.energy});

  final double progress;
  final double energy;

  static const Color _green = Color(0xFF1DB954);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final discRadius = w * 0.36;
    final center = Offset(w * 0.5, h * 0.42);

    // Glow under the deck.
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [_green.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: discRadius * 1.9));
    canvas.drawCircle(center, discRadius * 1.9, glow);

    // Vinyl: black disc, grooves, label, spindle.
    canvas.drawCircle(
        center,
        discRadius,
        Paint()..color = const Color(0xFF0B0B0B));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.10);
    for (var r = discRadius * 0.55; r < discRadius; r += discRadius * 0.07) {
      canvas.drawCircle(center, r, groove);
    }
    canvas.drawCircle(center, discRadius * 0.42, Paint()..color = _green);
    canvas.drawCircle(
        center,
        discRadius * 0.05,
        Paint()..color = const Color(0xFF0B0B0B));

    // Highlight sweeping around the disc, so the rotation is readable.
    final angle = progress * 2 * math.pi;
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = discRadius * 0.16
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: discRadius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: discRadius * 0.82),
      angle,
      math.pi * 0.6,
      false,
      highlight,
    );

    // Tonearm, pivoting slightly as the record spins.
    final pivot = Offset(w * 0.88, h * 0.14);
    final sway = math.sin(angle) * 0.05;
    final tip = Offset(
      center.dx + discRadius * 0.35 * math.cos(angle * 0.2 + sway),
      center.dy + discRadius * 0.35 * math.sin(angle * 0.2 + sway),
    );
    final arm = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = w * 0.022
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pivot, tip, arm);
    canvas.drawCircle(pivot, w * 0.04, Paint()..color = const Color(0xFF2A2A2A));
    canvas.drawCircle(pivot, w * 0.018, Paint()..color = _green);

    // Equalizer: bars whose heights come from a few desynchronized sines, so
    // the motion looks organic instead of a repeating pattern.
    final bars = 15;
    final baseY = h * 0.92;
    final barWidth = (w * 0.86) / bars * 0.55;
    final left = w * 0.07;
    for (var i = 0; i < bars; i++) {
      final phase = progress * 2 * math.pi + i * 0.7;
      final shaped = (math.sin(phase) * 0.5 + 0.5) *
          (math.sin(phase * 0.37 + i) * 0.35 + 0.65);
      final height = (h * 0.10) + shaped * (h * 0.20) * energy;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + i * (w * 0.86 / bars),
          baseY - height,
          barWidth,
          height,
        ),
        Radius.circular(barWidth * 0.45),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i.isEven
              ? _green.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DjDeckPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.energy != energy;
}
