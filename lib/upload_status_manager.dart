import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum UploadStatusType { uploading, success, error }

class UploadStatus {
  const UploadStatus({
    required this.type,
    required this.message,
    this.thumbnail,
    this.progress = 0,
  });

  final UploadStatusType type;
  final String message;
  final File? thumbnail;
  final double progress;
}

class UploadStatusManager {
  UploadStatusManager._();

  static final ValueNotifier<UploadStatus?> current =
      ValueNotifier<UploadStatus?>(null);
  static Timer? _clearTimer;

  static void uploading({
    String message = 'Uploading item',
    File? thumbnail,
  }) {
    _set(UploadStatus(
      type: UploadStatusType.uploading,
      message: message,
      thumbnail: thumbnail,
      progress: 0.01,
    ));
  }

  static void progress(double value) {
    final currentStatus = current.value;
    if (currentStatus == null || currentStatus.type != UploadStatusType.uploading) {
      return;
    }
    final next = value.clamp(0.01, 0.95);
    if ((next - currentStatus.progress).abs() < 0.01) return;
    current.value = UploadStatus(
      type: currentStatus.type,
      message: currentStatus.message,
      thumbnail: currentStatus.thumbnail,
      progress: next,
    );
  }

  static void success([String message = 'Item uploaded successfully']) {
    final currentStatus = current.value;
    _set(UploadStatus(
      type: UploadStatusType.success,
      message: message,
      thumbnail: currentStatus?.thumbnail,
      progress: 1,
    ));
    _clearAfterDelay();
  }

  static void error(String message) {
    final currentStatus = current.value;
    _set(UploadStatus(
      type: UploadStatusType.error,
      message: message,
      thumbnail: currentStatus?.thumbnail,
      progress: currentStatus?.progress ?? 0,
    ));
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
