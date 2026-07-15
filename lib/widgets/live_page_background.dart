import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LivePageBackground extends StatelessWidget {
  const LivePageBackground({
    super.key,
    required this.isLive,
    required this.child,
  });

  final bool isLive;
  final Widget child;

  static const normalColor = Color(0xFFF4FBF7);
  static const liveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFE9EC), normalColor],
  );

  @override
  Widget build(BuildContext context) {
    if (!isLive || defaultTargetPlatform != TargetPlatform.iOS) {
      return child;
    }

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: liveGradient),
      child: child,
    );
  }
}
