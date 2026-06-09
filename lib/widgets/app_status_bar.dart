import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppStatusBar extends StatelessWidget {
  const AppStatusBar({super.key, this.color = Colors.black});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final isLightBackground = color.computeLuminance() > 0.5;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: color,
        statusBarIconBrightness:
            isLightBackground ? Brightness.dark : Brightness.light,
        statusBarBrightness:
            isLightBackground ? Brightness.light : Brightness.dark,
      ),
      child: SizedBox(
        height: MediaQuery.viewPaddingOf(context).top,
        child: ColoredBox(color: color),
      ),
    );
  }
}
