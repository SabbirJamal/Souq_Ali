import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../item_detail_page.dart';
import 'media_carousel.dart';
import 'price_with_currency.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.docId,
    required this.item,
    this.isCompact = false,
  });

  final String docId;
  final Map<String, dynamic> item;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final mediaItems = mediaItemsFromMap(item);
    final uploadedAgo = _uploadedAgo(item['created_at']);
    final imageCount = mediaItems.where((media) => !media.isVideo).length;
    final videoCount = mediaItems.where((media) => media.isVideo).length;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ItemDetailPage(itemData: item, itemId: docId),
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardHeight = isCompact
              ? (constraints.maxWidth * 1.48).clamp(245.0, 310.0)
              : (constraints.maxWidth * 1.36).clamp(445.0, 595.0);

          return Card(
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            color: Colors.white,
            margin: EdgeInsets.only(bottom: isCompact ? 6 : 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: cardHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MediaCarousel(
                      mediaItems: mediaItems,
                      height: cardHeight,
                      peekSideItems: false,
                      borderRadius: 0,
                      showCountBadge: false,
                    ),
                  ),
                  Positioned(
                    top: isCompact ? 7 : 10,
                    left: isCompact ? 7 : 10,
                    child: _MediaCountBadges(
                      imageCount: imageCount,
                      videoCount: videoCount,
                      isCompact: isCompact,
                    ),
                  ),
                  Positioned(
                    top: isCompact ? 7 : 10,
                    right: isCompact ? 7 : 10,
                    child: _UploadedAgoBadge(
                      uploadedAgo: uploadedAgo,
                      isCompact: isCompact,
                    ),
                  ),
                  Positioned(
                    left: isCompact ? 8 : 14,
                    bottom: isCompact ? 10 : 18,
                    child: _ImageFilledDetails(item: item, isCompact: isCompact),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _uploadedAgo(Object? value) {
    DateTime? uploadedAt;
    if (value is Timestamp) {
      uploadedAt = value.toDate();
    } else if (value is DateTime) {
      uploadedAt = value;
    }

    if (uploadedAt == null) {
      return 'just now';
    }

    final difference = DateTime.now().difference(uploadedAt);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} hrs ago';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    }
    if (difference.inDays < 30) {
      return '${difference.inDays ~/ 7} weeks ago';
    }
    return '${difference.inDays ~/ 30} months ago';
  }
}

class _ImageFilledDetails extends StatelessWidget {
  const _ImageFilledDetails({required this.item, required this.isCompact});

  final Map<String, dynamic> item;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * (isCompact ? 0.38 : 0.72);
    final itemName = item['item_name']?.toString().trim() ?? '';

    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TextChip(
              child: _OverlayInfoRow(
                text: item['location']?.toString() ?? '',
                isCompact: isCompact,
              ),
              isCompact: isCompact,
            ),
            SizedBox(height: isCompact ? 5 : 8),
            _TextChip(
              child: PriceWithCurrency(
                price: _formatPrice(item['item_price']),
                style: TextStyle(
                  color: const Color(0xFFD00000),
                  fontSize: isCompact ? 13 : 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              isCompact: isCompact,
            ),
            if (itemName.isNotEmpty) ...[
              SizedBox(height: isCompact ? 7 : 12),
              _TextChip(
                child: Text(
                  itemName,
                  maxLines: isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: isCompact ? 14 : 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                isCompact: isCompact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatPrice(Object? value) {
  final text = value?.toString() ?? '';
  if (_isZeroPrice(text)) {
    return 'Contact for Price';
  }
  return text
      .replaceAll(RegExp(r'\s+per\s+', caseSensitive: false), ' / ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isZeroPrice(String value) {
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(value);
  if (match == null) {
    return false;
  }
  return (double.tryParse(match.group(0) ?? '') ?? -1) == 0;
}

class _TextChip extends StatelessWidget {
  const _TextChip({required this.child, required this.isCompact});

  final Widget child;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 9,
        vertical: isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _OverlayInfoRow extends StatelessWidget {
  const _OverlayInfoRow({
    required this.text,
    required this.isCompact,
  });

  final String text;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('📍', style: TextStyle(fontSize: isCompact ? 13 : 20)),
        SizedBox(width: isCompact ? 4 : 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: isCompact ? 11 : 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaCountBadges extends StatelessWidget {
  const _MediaCountBadges({
    required this.imageCount,
    required this.videoCount,
    required this.isCompact,
  });

  final int imageCount;
  final int videoCount;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageCount > 0)
          _TopMediaBadge(
            icon: Icons.photo_camera,
            count: imageCount,
            isCompact: isCompact,
          ),
        if (imageCount > 0 && videoCount > 0) SizedBox(width: isCompact ? 4 : 8),
        if (videoCount > 0)
          _TopMediaBadge(
            icon: Icons.videocam,
            count: videoCount,
            isCompact: isCompact,
          ),
      ],
    );
  }
}

class _TopMediaBadge extends StatelessWidget {
  const _TopMediaBadge({
    required this.icon,
    required this.count,
    required this.isCompact,
  });

  final IconData icon;
  final int count;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 10,
        vertical: isCompact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: isCompact ? 13 : 20),
          SizedBox(width: isCompact ? 3 : 5),
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white,
              fontSize: isCompact ? 12 : 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadedAgoBadge extends StatelessWidget {
  const _UploadedAgoBadge({
    required this.uploadedAgo,
    required this.isCompact,
  });

  final String uploadedAgo;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        uploadedAgo,
        style: TextStyle(
          color: Colors.white,
          fontSize: isCompact ? 10 : 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
