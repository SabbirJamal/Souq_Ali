import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../media_carousel.dart';

class EditableMediaTile extends StatelessWidget {
  const EditableMediaTile({
    super.key,
    required this.media,
    required this.sequenceNumber,
    required this.isDropTarget,
    required this.onRemove,
  });

  final EditableMedia media;
  final int sequenceNumber;
  final bool isDropTarget;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: isDropTarget
            ? Border.all(color: const Color(0xFF25D366), width: 3)
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: media.isVideo
                ? const VideoPlaceholder()
                : media.isExisting
                    ? CachedNetworkImage(
                        imageUrl: media.existing!.url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: const Color(0xFFEFF4F1),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFFDCF8C6),
                          child: const Icon(Icons.broken_image),
                        ),
                      )
                    : Image.file(media.selected!.file, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF25D366),
              child: Text(
                '$sequenceNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.red,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPlaceholder extends StatelessWidget {
  const VideoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 42),
    );
  }
}

class MediaSheetButton extends StatelessWidget {
  const MediaSheetButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF202523),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF25D366), size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class EditableMedia {
  const EditableMedia.existing(this.existing) : selected = null;

  const EditableMedia.newMedia(this.selected) : existing = null;

  final MediaItem? existing;
  final SelectedMedia? selected;

  bool get isExisting => existing != null;

  bool get isVideo => isExisting ? existing!.isVideo : selected!.isVideo;
}

class SelectedMedia {
  const SelectedMedia({required this.file, required this.type, this.assetId});

  factory SelectedMedia.fromXFile(XFile file) {
    final type =
        _isVideoPath(file.path) || file.mimeType?.startsWith('video/') == true
        ? 'video'
        : 'image';
    return SelectedMedia(file: File(file.path), type: type);
  }

  final File file;
  final String type;
  final String? assetId;

  bool get isVideo => type == 'video';

  static bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }
}
