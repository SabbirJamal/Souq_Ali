import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppRefreshScrollPhysics {
  const AppRefreshScrollPhysics._();

  static ScrollPhysics get platform => defaultTargetPlatform == TargetPlatform.iOS
      ? const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
      : const AlwaysScrollableScrollPhysics();
}
