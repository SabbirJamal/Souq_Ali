import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.isRequired,
    required this.storeUrl,
    required this.message,
    this.shouldStartImmediateUpdate = false,
  });

  final bool isRequired;
  final String storeUrl;
  final String message;
  final bool shouldStartImmediateUpdate;
}

class AppUpdateService {
  const AppUpdateService._();

  static const _defaultAndroidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.bizsooq.app';
  static const _defaultMessage =
      'A new update is available. Please update to continue.';

  static Future<AppUpdateDecision> check() async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return _checkAndroidPlayUpdate();
        case TargetPlatform.iOS:
          return _checkIosFirestoreUpdate();
        default:
          return const AppUpdateDecision(
            isRequired: false,
            storeUrl: '',
            message: _defaultMessage,
          );
      }
    } catch (error) {
      debugPrint('Update check skipped: $error');
      return const AppUpdateDecision(
        isRequired: false,
        storeUrl: _defaultAndroidStoreUrl,
        message: _defaultMessage,
      );
    }
  }

  static Future<bool> startImmediateUpdate() async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      return result == AppUpdateResult.success;
    } catch (error) {
      debugPrint('Immediate update skipped: $error');
      return false;
    }
  }

  static Future<AppUpdateDecision> _checkAndroidPlayUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      final shouldStartImmediateUpdate =
          info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed;

      return AppUpdateDecision(
        isRequired: false,
        storeUrl: _defaultAndroidStoreUrl,
        message: _defaultMessage,
        shouldStartImmediateUpdate: shouldStartImmediateUpdate,
      );
    } catch (error) {
      debugPrint('Play in-app update check skipped: $error');
      return const AppUpdateDecision(
        isRequired: false,
        storeUrl: _defaultAndroidStoreUrl,
        message: _defaultMessage,
      );
    }
  }

  static Future<AppUpdateDecision> _checkIosFirestoreUpdate() async {
    final results = await Future.wait([
      PackageInfo.fromPlatform(),
      FirebaseFirestore.instance.collection('app_config').doc('ios').get(),
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
