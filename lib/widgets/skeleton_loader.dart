import 'package:flutter/material.dart';

class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool forceDark;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.forceDark = false,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = widget.forceDark || theme.brightness == Brightness.dark;
    final surface = widget.forceDark ? const Color(0xFF121212) : scheme.surface;
    final onSurface = widget.forceDark ? Colors.white : scheme.onSurface;
    final baseColor = Color.alphaBlend(
      onSurface.withValues(alpha: isDark ? 0.12 : 0.10),
      surface,
    );
    final highlightColor = Color.alphaBlend(
      onSurface.withValues(alpha: isDark ? 0.30 : 0.04),
      surface,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

class HomeSkeletonSection extends StatelessWidget {
  final bool showTitle;
  final double rowHeight;
  final double itemSpacing;
  final bool forceDark;

  const HomeSkeletonSection({
    super.key,
    this.showTitle = true,
    this.rowHeight = 180,
    this.itemSpacing = 16,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: SkeletonLoader(
              width: 200,
              height: 24,
              borderRadius: 4,
              forceDark: forceDark,
            ),
          ),
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, __) => SizedBox(width: itemSpacing),
            itemBuilder: (context, index) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(
                    width: 140,
                    height: 140,
                    borderRadius: 12,
                    forceDark: forceDark,
                  ),
                  const SizedBox(height: 8),
                  SkeletonLoader(
                    width: 120,
                    height: 14,
                    borderRadius: 4,
                    forceDark: forceDark,
                  ),
                  const SizedBox(height: 4),
                  SkeletonLoader(
                    width: 80,
                    height: 12,
                    borderRadius: 4,
                    forceDark: forceDark,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class HomeSkeletonList extends StatelessWidget {
  const HomeSkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (index) => const HomeSkeletonSection()),
    );
  }
}
