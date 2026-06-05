import 'package:flutter/material.dart';

class QuickFadePageRoute<T> extends PageRouteBuilder<T> {
  QuickFadePageRoute({required Widget child, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => child,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      );
}

class FastZoomPageRoute<T> extends PageRouteBuilder<T> {
  FastZoomPageRoute({required Widget child, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => child,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation.drive(
                Tween<double>(begin: 0.95, end: 1.0).chain(
                  CurveTween(curve: Curves.easeOutCubic),
                ),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      );
}
