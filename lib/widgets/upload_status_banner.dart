import 'package:flutter/material.dart';

import '../upload_status_manager.dart';

class UploadStatusBanner extends StatelessWidget {
  const UploadStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UploadStatus?>(
      valueListenable: UploadStatusManager.current,
      builder: (context, status, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
          ),
          child: status == null
              ? const SizedBox.shrink()
              : _UploadStatusContent(
                  key: ValueKey(status.type),
                  status: status,
                ),
        );
      },
    );
  }
}

class _UploadStatusContent extends StatelessWidget {
  const _UploadStatusContent({super.key, required this.status});

  final UploadStatus status;

  @override
  Widget build(BuildContext context) {
    final progress = status.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).round().clamp(1, 100);
    return FractionallySizedBox(
      widthFactor: 0.95,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                _UploadThumbnail(status: status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: status.type == UploadStatusType.error ? null : progress,
                          backgroundColor: const Color(0xFFE9E9E9),
                          color: status.type == UploadStatusType.error
                              ? Colors.red
                              : const Color(0xFF25D366),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _UploadTrailing(status: status, percent: percent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadThumbnail extends StatelessWidget {
  const _UploadThumbnail({required this.status});

  final UploadStatus status;

  @override
  Widget build(BuildContext context) {
    final thumbnail = status.thumbnail;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 42,
        height: 42,
        child: thumbnail == null
            ? const ColoredBox(
                color: Color(0xFFEDEDED),
                child: Icon(Icons.image_rounded, size: 22, color: Colors.black45),
              )
            : Image.file(thumbnail, fit: BoxFit.cover),
      ),
    );
  }
}

class _UploadTrailing extends StatelessWidget {
  const _UploadTrailing({required this.status, required this.percent});

  final UploadStatus status;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: Center(
        child: switch (status.type) {
          UploadStatusType.success => const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF25D366),
              size: 26,
            ),
          UploadStatusType.error => const Icon(
              Icons.error_rounded,
              color: Colors.red,
              size: 24,
            ),
          UploadStatusType.uploading => Text(
              '$percent%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
        },
      ),
    );
  }
}
