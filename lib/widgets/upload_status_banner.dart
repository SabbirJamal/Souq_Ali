import 'package:flutter/material.dart';

import '../upload_status_manager.dart';

class UploadStatusBanner extends StatefulWidget {
  const UploadStatusBanner({super.key, required this.target});

  final UploadStatusTarget target;

  @override
  State<UploadStatusBanner> createState() => _UploadStatusBannerState();
}

class _UploadStatusBannerState extends State<UploadStatusBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UploadStatus>>(
      valueListenable: UploadStatusManager.active,
      builder: (context, uploads, child) {
        final targetUploads = uploads
            .where((status) => status.target == widget.target)
            .toList(growable: false);
        if (targetUploads.isEmpty) {
          return const SizedBox.shrink();
        }
        final visibleUploads = _expanded
            ? targetUploads.take(4).toList()
            : targetUploads.take(1).toList();
        return FractionallySizedBox(
          widthFactor: 0.95,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: targetUploads.length > 1
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black, width: 1),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < visibleUploads.length; i++) ...[
                          _UploadStatusRow(
                            status: visibleUploads[i],
                            hiddenCount: !_expanded && targetUploads.length > 1 ? targetUploads.length - 1 : 0,
                          ),
                          if (i != visibleUploads.length - 1) const SizedBox(height: 7),
                        ],
                        if (_expanded && targetUploads.length > visibleUploads.length) ...[
                          const SizedBox(height: 7),
                          Text(
                            '+${targetUploads.length - visibleUploads.length} more uploading',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UploadStatusRow extends StatelessWidget {
  const _UploadStatusRow({required this.status, this.hiddenCount = 0});

  final UploadStatus status;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    final progress = status.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).round().clamp(1, 100);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _UploadThumbnail(status: status),
          const SizedBox(width: 10),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: progress),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: status.type == UploadStatusType.error ? null : value,
                        backgroundColor: const Color(0xFFE9E9E9),
                        color: status.type == UploadStatusType.error
                            ? Colors.red
                            : const Color(0xFF25D366),
                      ),
                    );
                  },
                ),
                if (hiddenCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '+$hiddenCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _UploadTrailing(status: status, percent: percent),
        ],
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
    final thumbnailUrl = status.thumbnailUrl?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 42,
        height: 42,
        child: thumbnail == null
            ? thumbnailUrl.isEmpty
                ? const ColoredBox(
                    color: Color(0xFFEDEDED),
                    child: Icon(
                      Icons.image_rounded,
                      size: 22,
                      color: Colors.black45,
                    ),
                  )
                : Image.network(thumbnailUrl, fit: BoxFit.cover)
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
