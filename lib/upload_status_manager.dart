import 'dart:async';

import 'package:flutter/foundation.dart';

enum UploadStatusType { uploading, success, error }

class UploadStatus {
  const UploadStatus({required this.type, required this.message});

  final UploadStatusType type;
  final String message;
}

class UploadStatusManager {
  UploadStatusManager._();

  static final ValueNotifier<UploadStatus?> current =
      ValueNotifier<UploadStatus?>(null);
  static Timer? _clearTimer;

  static void uploading([String message = 'Uploading your item...']) {
    _set(UploadStatus(type: UploadStatusType.uploading, message: message));
  }

  static void success([String message = 'Item uploaded successfully']) {
    _set(UploadStatus(type: UploadStatusType.success, message: message));
    _clearAfterDelay();
  }

  static void error(String message) {
    _set(UploadStatus(type: UploadStatusType.error, message: message));
    _clearAfterDelay();
  }

  static void _set(UploadStatus status) {
    _clearTimer?.cancel();
    current.value = status;
  }

  static void _clearAfterDelay() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 3), () {
      current.value = null;
    });
  }
}
