import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared chrome for the artist and album pages, so both read as the same
/// screen: an animated-underlined tab bar and the round action buttons.
class SectionTabBar extends StatelessWidget {
  const SectionTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// Pairs of (label, index) in display order.
  final List<(String, int)> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          for (final tab in tabs)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(tab.$2);
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 26, top: 6, bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.$1,
                      style: TextStyle(
                        color: selectedIndex == tab.$2
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFF777777).withValues(alpha: 0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      height: 3,
                      width: selectedIndex == tab.$2 ? 26 : 0,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DDA63),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The round action button used for Shuffle and Play across the detail pages:
/// a filled green disc with a black glyph, the way the artist page does it.
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 24,
    this.padding = 10,
    this.filled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double padding;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? const Color(0xFF1DDA63).withValues(alpha: enabled ? 1 : 0.4)
              : const Color(0xFFFFFFFF).withValues(alpha: .08),
        ),
        child: Icon(
          icon,
          size: size,
          color: filled
              ? const Color(0xFF000000).withValues(alpha: enabled ? 1 : 0.5)
              : const Color(0xFFFFFFFF).withValues(alpha: enabled ? 1 : 0.35),
        ),
      ),
    );
  }
}

/// Play / pause disc driven by the real engine state, so the glyph can never
/// drift from what is actually audible.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onTap,
    this.enabled = true,
  });

  final bool isPlaying;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return RoundActionButton(
      icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow,
      onTap: enabled ? onTap : null,
      size: 30,
    );
  }
}
