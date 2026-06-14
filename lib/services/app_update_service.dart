import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.isRequired,
    required this.storeUrl,
    required this.message,
  });

  final bool isRequired;
  final String storeUrl;
  final String message;
}

class AppUpdateService {
  const AppUpdateService._();

  static const _defaultAndroidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.bizsooq.app';
  static const _defaultMessage =
      'A new update is available. Please update to continue.';

  static Future<AppUpdateDecision> check() async {
    try {
      final platform = _platformConfigId;
      if (platform == null) {
        return const AppUpdateDecision(
          isRequired: false,
          storeUrl: '',
          message: _defaultMessage,
        );
      }

      final results = await Future.wait([
        PackageInfo.fromPlatform(),
        FirebaseFirestore.instance.collection('app_config').doc(platform).get(),
      ]);

      final packageInfo = results[0] as PackageInfo;
      final snapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final data = snapshot.data();
      if (data == null) {
        return const AppUpdateDecision(
          isRequired: false,
          storeUrl: _defaultAndroidStoreUrl,
          message: _defaultMessage,
        );
      }

      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final minimumBuild = _readInt(data['minimum_version_code']);
      final forceUpdate = data['force_update'] == true;

      return AppUpdateDecision(
        isRequired: forceUpdate && currentBuild < minimumBuild,
        storeUrl: _readString(data['play_store_url']) ?? _defaultAndroidStoreUrl,
        message: _readString(data['message']) ?? _defaultMessage,
      );
    } catch (error) {
      debugPrint('Update check skipped: $error');
      return const AppUpdateDecision(
        isRequired: false,
        storeUrl: _defaultAndroidStoreUrl,
        message: _defaultMessage,
      );
    }
  }

  static String? get _platformConfigId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _readString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
