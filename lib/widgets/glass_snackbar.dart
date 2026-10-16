import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:muzo/services/navigator_key.dart';

OverlayEntry? _currentToast;

/// Messages courts et lisibles : aucun « -- » (le double tiret dessinait un
/// trait sous le texte) et aucune saut de ligne parasite. Idempotent, puisque
/// le chemin de retry repasse par [showGlassSnackBar].
String _sanitizeMessage(String message) {
  var s = message.replaceAll(RegExp(r'-{2,}'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

/// Affiche la notification verre en HAUT de l'écran (sous la barre de statut),
/// via l'overlay racine — jamais cachée par le panel Home/Search/Library.
/// L'overlay du [navigatorKey] est privilégié (toujours présent, quel que
/// soit le contexte), puis l'overlay résolu depuis le contexte, puis un
/// dernier recours différé d'un frame.
void showGlassSnackBar(
  BuildContext context,
  String rawMessage, {
  bool error = false,
}) {
  final message = _sanitizeMessage(rawMessage);
  OverlayState? overlay = navigatorKey.currentState?.overlay;
  overlay ??= Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    // Frame tardif : le overlay de l'app est parfois indisponible pendant le
    // démontage d'un dialogue/route ; on réessaie une fois après l'animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final retry = navigatorKey.currentState?.overlay;
      if (retry != null) {
        showGlassSnackBar(context, message, error: error);
        return;
      }
      _showBottomFallback(context, message, error);
    });
    return;
  }
  _showTopToast(overlay, message, error);
}

void _showBottomFallback(
    BuildContext context, String message, bool error) {
  ScaffoldMessenger.of(context)
    // Couverture de secours (aucun overlay disponible) : snackbar flottante
    // classique, relevée pour rester au-dessus des panels.
    ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: EdgeInsets.zero,
          duration: const Duration(seconds: 3),
          content: _GlassSnackBarContent(message: message, error: error),
        ),
      );
}

void _showTopToast(OverlayState overlay, String message, bool error) {
  if (_currentToast?.mounted ?? false) _currentToast!.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final top = MediaQuery.of(ctx).padding.top + 10;
      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, -12 * (1 - v)),
              child: child,
            ),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => entry.remove(),
            child: _GlassSnackBarContent(message: message, error: error),
          ),
        ),
      );
    },
  );
  _currentToast = entry;
  overlay.insert(entry);
  Timer(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

class _GlassSnackBarContent extends StatelessWidget {
  final String message;
  final bool error;

  const _GlassSnackBarContent({required this.message, required this.error});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Accent fixe (vert Tunefy), pas le primary dynamique : la couleur Material
    // You du fond d'écran peut être jaune. La bordure utilise donc elle aussi
    // une constante — elle ne peut jamais repasser en jaune.
    final accentColor = const Color(0xFF1DB954);

    final tint = error ? Colors.redAccent : accentColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              tint.withValues(alpha: 0.10),
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.35),
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ConstrainedBox(
            // Garde-fou : le toast ne peut jamais dépasser la hauteur utile
            // au-dessus du mini-player, donc aucun débordement RenderFlex
            // (bandes jaunes) quelle que soit la longueur du message.
            constraints: const BoxConstraints(maxHeight: 120),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      error
                          ? Icons.error_outline_rounded
                          : Icons.info_outline_rounded,
                      color: error ? Colors.redAccent : accentColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      height: 1.25,
                      // Aucun soulignement hérité (une Decoration d'erreur
                      // Material peut peindre un trait jaune sous le texte).
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}