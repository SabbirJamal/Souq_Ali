import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum UploadStatusType { uploading, success, error }

class UploadStatus {
  const UploadStatus({
    required this.id,
    required this.type,
    required this.message,
    this.thumbnail,
    this.progress = 0,
  });

  final String id;
  final UploadStatusType type;
  final String message;
  final File? thumbnail;
  final double progress;

  UploadStatus copyWith({
    UploadStatusType? type,
    String? message,
    File? thumbnail,
    double? progress,
  }) {
    return UploadStatus(
      id: id,
      type: type ?? this.type,
      message: message ?? this.message,
      thumbnail: thumbnail ?? this.thumbnail,
      progress: progress ?? this.progress,
    );
  }
}

class UploadStatusManager {
  UploadStatusManager._();

  static final ValueNotifier<UploadStatus?> current =
      ValueNotifier<UploadStatus?>(null);
  static final ValueNotifier<List<UploadStatus>> active =
      ValueNotifier<List<UploadStatus>>(<UploadStatus>[]);
  static final Map<String, Timer> _clearTimers = <String, Timer>{};

  static String uploading({
    String message = 'Uploading item',
    File? thumbnail,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _set(UploadStatus(
      id: id,
      type: UploadStatusType.uploading,
      message: message,
      thumbnail: thumbnail,
      progress: 0.01,
    ));
    return id;
  }

  static void progress(String id, double value) {
    final index = active.value.indexWhere((status) => status.id == id);
    if (index == -1) {
      return;
    }
    final currentStatus = active.value[index];
    if (currentStatus.type != UploadStatusType.uploading) return;
    final next = value.clamp(0.01, 0.95);
    if ((next - currentStatus.progress).abs() < 0.01) return;
    _replace(index, currentStatus.copyWith(progress: next));
  }

  static void success(String id, [String message = 'Item uploaded successfully']) {
    final index = active.value.indexWhere((status) => status.id == id);
    if (index == -1) return;
    _replace(index, active.value[index].copyWith(
      type: UploadStatusType.success,
      message: message,
      progress: 1,
    ));
    _clearAfterDelay(id);
  }

  static void error(String id, String message) {
    final index = active.value.indexWhere((status) => status.id == id);
    if (index == -1) {
      _set(UploadStatus(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: UploadStatusType.error,
        message: message,
      ));
      return;
    }
    _replace(index, active.value[index].copyWith(
      type: UploadStatusType.error,
      message: message,
    ));
    _clearAfterDelay(id);
  }

  static void _set(UploadStatus status) {
    _clearTimers.remove(status.id)?.cancel();
    active.value = <UploadStatus>[status, ...active.value];
    _syncCurrent();
  }

  static void _replace(int index, UploadStatus status) {
    final next = List<UploadStatus>.of(active.value);
    next[index] = status;
    active.value = next;
    _syncCurrent();
  }

  static void _clearAfterDelay(String id) {
    _clearTimers.remove(id)?.cancel();
    _clearTimers[id] = Timer(const Duration(seconds: 3), () {
      _clearTimers.remove(id);
      active.value = active.value.where((status) => status.id != id).toList(growable: false);
      _syncCurrent();
    });
  }

  static void _syncCurrent() {
    current.value = active.value.isEmpty ? null : active.value.first;
  }
}
