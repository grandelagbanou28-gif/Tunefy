import 'package:flutter/material.dart';

/// A custom page route that provides a smooth slide transition from right to left
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  /// Optional route arguments. Carried so a route can declare what it is (see
  /// `SceneArg`): `PlayerSceneObserver` reads them, which is what lets the
  /// layout know a full-screen player surface is open without any screen having
  /// to set a flag it might forget to clear.
  final Object? arguments;

  SlidePageRoute({required this.page, this.arguments})
    : super(
        settings: RouteSettings(arguments: arguments),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0); // Start from right
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          var fadeAnimation = CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.55, curve: Curves.easeOut),
          );

          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(opacity: fadeAnimation, child: child),
          );
        },
        // Volontairement court : une transition de 300 ms donne à chaque tap
        // l'impression que l'app met du temps à répondre.
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
      );
}

/// A bottom-to-top slide transition (like a modal)
class ModalSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Object? arguments;

  ModalSlidePageRoute({required this.page, this.arguments})
    : super(
        settings: RouteSettings(arguments: arguments),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0); // Start from bottom
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(position: offsetAnimation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      );
}
