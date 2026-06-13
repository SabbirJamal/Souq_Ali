import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppStatusBar extends StatelessWidget {
  const AppStatusBar({super.key, this.color = Colors.black});

  final Color color;

  static double heightOf(BuildContext context) {
    final view = View.of(context);
    final viewPaddingTop = view.viewPadding.top / view.devicePixelRatio;
    final mediaViewPaddingTop = MediaQuery.viewPaddingOf(context).top;
    final mediaPaddingTop = MediaQuery.paddingOf(context).top;
    final height = [
      viewPaddingTop,
      mediaViewPaddingTop,
      mediaPaddingTop,
      24.0,
    ].reduce((value, element) => value > element ? value : element);
    return height;
  }

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
        height: heightOf(context),
        child: ColoredBox(color: color),
      ),
    );
  }
}
