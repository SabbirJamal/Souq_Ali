import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
                        memCacheWidth: 360,
                        maxWidthDiskCache: 512,
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
                    : Image.file(
                        media.selected!.file,
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        cacheHeight: 360,
                      ),
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

  final File file;
  final String type;
  final String? assetId;

  bool get isVideo => type == 'video';
}
