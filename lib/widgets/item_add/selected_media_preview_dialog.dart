import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SelectedMediaPreviewItem {
  const SelectedMediaPreviewItem({
    required this.file,
    required this.isVideo,
  });

  final File file;
  final bool isVideo;
}

class SelectedMediaPreviewDialog extends StatefulWidget {
  const SelectedMediaPreviewDialog({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<SelectedMediaPreviewItem> items;
  final int initialIndex;

  @override
  State<SelectedMediaPreviewDialog> createState() =>
      _SelectedMediaPreviewDialogState();
}

class _SelectedMediaPreviewDialogState
    extends State<SelectedMediaPreviewDialog> {
  late int _currentIndex = widget.initialIndex;
  VideoPlayerController? _videoController;
  bool _showVideoControl = false;

  SelectedMediaPreviewItem get _current => widget.items[_currentIndex];

  @override
  void initState() {
    super.initState();
    _prepareVideoIfNeeded();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  Future<void> _disposeVideo() async {
    final controller = _videoController;
    _videoController = null;
    await controller?.pause();
    await controller?.dispose();
  }

  Future<void> _prepareVideoIfNeeded() async {
    await _disposeVideo();
    if (!_current.isVideo) {
      if (mounted) setState(() {});
      return;
    }

    final controller = VideoPlayerController.file(_current.file);
    _videoController = controller;
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();
    if (mounted) setState(() {});
  }

  void _selectIndex(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _showVideoControl = false;
    });
    _prepareVideoIfNeeded();
  }

  Future<void> _toggleVideo() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (!mounted) return;
    setState(() => _showVideoControl = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _videoController?.value.isPlaying == true) {
        setState(() => _showVideoControl = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxPreviewHeight = MediaQuery.sizeOf(context).height * 0.72;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPreviewHeight),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _MediaPreview(
                    item: _current,
                    videoController: _videoController,
                    showVideoControl: _showVideoControl,
                    onToggleVideo: _toggleVideo,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _PreviewThumb(
                  item: widget.items[index],
                  isSelected: index == _currentIndex,
                  onTap: () => _selectIndex(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.item,
    required this.videoController,
    required this.showVideoControl,
    required this.onToggleVideo,
  });

  final SelectedMediaPreviewItem item;
  final VideoPlayerController? videoController;
  final bool showVideoControl;
  final VoidCallback onToggleVideo;

  @override
  Widget build(BuildContext context) {
    if (!item.isVideo) {
      return Image.file(item.file, fit: BoxFit.cover);
    }

    final controller = videoController;
    final ready = controller != null && controller.value.isInitialized;
    return GestureDetector(
      onTap: onToggleVideo,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else
            const ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          if (ready && (showVideoControl || !controller.value.isPlaying))
            Center(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewThumb extends StatelessWidget {
  const _PreviewThumb({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final SelectedMediaPreviewItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF25D366) : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              item.isVideo
                  ? const ColoredBox(
                      color: Colors.black87,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 26,
                      ),
                    )
                  : Image.file(item.file, fit: BoxFit.cover),
            ],
          ),
        ),
      ),
    );
  }
}
