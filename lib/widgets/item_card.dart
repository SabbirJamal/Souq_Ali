import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../item_detail_page.dart';
import '../utils/formatters.dart';
import '../utils/transitions.dart';
import 'media_carousel.dart';
import 'price_with_currency.dart';

class ItemCard extends StatefulWidget {
  const ItemCard({
    super.key,
    required this.docId,
    required this.item,
    this.isCompact = false,
    this.isLivePage = false,
    this.liveMarkerTop = -36,
    this.uploadedAgoOverride,
  });

  final String docId;
  final Map<String, dynamic> item;
  final bool isCompact;
  final bool isLivePage;
  final double liveMarkerTop;
  final String? uploadedAgoOverride;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard>
    with AutomaticKeepAliveClientMixin<ItemCard> {
  @override
  void initState() {
    super.initState();
    // Pre-cache first image for detail page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheDetailMedia();
    });
  }

  void _precacheDetailMedia() {
    if (!mounted) {
      return;
    }
    final mediaItems = mediaItemsFromMap(widget.item);
    if (mediaItems.isNotEmpty) {
      final firstMedia = mediaItems.first;
      final url = firstMedia.isVideo
          ? firstMedia.thumbnailUrl?.trim()
          : firstMedia.url.trim();
      if (url != null && url.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mediaItems = mediaItemsFromMap(widget.item);
    final uploadedAgo = widget.uploadedAgoOverride ?? _uploadedAgo(widget.item['created_at']);
    final imageCount = mediaItems.where((media) => !media.isVideo).length;
    final videoCount = mediaItems.where((media) => media.isVideo).length;
    final isLiveItem = widget.item['status']?.toString() == 'live';
    final showLivePageMarker = widget.isLivePage && isLiveItem;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : constraints.maxWidth / (widget.isCompact ? 0.58 : 0.66);

          return SizedBox(
            height: cardHeight,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  QuickFadePageRoute(
                    child: ItemDetailPage(
                      itemData: widget.item,
                      itemId: widget.docId,
                    ),
                  ),
                );
              },
              child: Card(
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.18),
                  color: Colors.white,
                  margin: EdgeInsets.only(bottom: widget.isCompact ? 6 : 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: MediaPreview(
                          media: mediaItems.isEmpty ? null : mediaItems.first,
                          height: cardHeight,
                          borderRadius: 0,
                          isCompact: widget.isCompact,
                        ),
                      ),
                      Positioned(
                        top: widget.isCompact ? 7 : 10,
                        left: widget.isCompact ? 7 : 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MediaCountBadges(
                              imageCount: imageCount,
                              videoCount: videoCount,
                              isCompact: widget.isCompact,
                            ),
                            if (isLiveItem && !showLivePageMarker) ...[
                              SizedBox(height: widget.isCompact ? 4 : 7),
                              _LiveBadge(isCompact: widget.isCompact),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        top: showLivePageMarker
                            ? widget.liveMarkerTop
                            : widget.isCompact
                                ? 7
                                : 10,
                        right: showLivePageMarker
                            ? -82
                            : widget.isCompact
                                ? 7
                                : 10,
                        child: showLivePageMarker
                            ? const IgnorePointer(
                                child: _LiveCardAnimation(),
                              )
                            : _UploadedAgoBadge(
                                uploadedAgo: uploadedAgo,
                                isCompact: widget.isCompact,
                              ),
                      ),
                      Positioned(
                        left: widget.isCompact ? 8 : 14,
                        right: widget.isCompact ? 8 : 14,
                        bottom: widget.isCompact ? 10 : 18,
                        child: _ImageFilledDetails(
                          item: widget.item,
                          isCompact: widget.isCompact,
                        ),
                      ),
                    ],
                  ),
                ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

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

class ItemCardSkeleton extends StatelessWidget {
  const ItemCardSkeleton({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = isCompact
            ? (constraints.maxWidth * 1.48).clamp(245.0, 310.0)
            : (constraints.maxWidth * 1.36).clamp(445.0, 595.0);

        return RepaintBoundary(
          child: Card(
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.12),
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
                  const Positioned.fill(child: MediaSkeletonPlaceholder()),
                  Positioned(
                    left: isCompact ? 8 : 14,
                    bottom: isCompact ? 10 : 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SkeletonChip(width: isCompact ? 76 : 118),
                        SizedBox(height: isCompact ? 5 : 8),
                        _SkeletonChip(width: isCompact ? 94 : 150),
                        SizedBox(height: isCompact ? 7 : 12),
                        _SkeletonChip(width: isCompact ? 64 : 110),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonChip extends StatelessWidget {
  const _SkeletonChip({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: 28,
        child: const MediaSkeletonPlaceholder(),
      ),
    );
  }
}

class _ImageFilledDetails extends StatelessWidget {
  const _ImageFilledDetails({
    required this.item,
    required this.isCompact,
  });

  final Map<String, dynamic> item;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final itemName = item['item_name']?.toString().trim() ?? '';
    final isTransit = item['is_transit'] == true;
    final location = item['location']?.toString().trim() ?? '';
    final price = isTransit ? '' : formatPrice(item['item_price']);

    return IntrinsicWidth(
      stepWidth: 1,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (location.isNotEmpty) ...[
              _TextChip(
                child: _OverlayInfoRow(
                  text: location,
                  isCompact: isCompact,
                ),
                isCompact: isCompact,
              ),
            ],
            if (price.isNotEmpty) ...[
              SizedBox(height: isCompact ? 5 : 8),
              _TextChip(
                child: PriceWithCurrency(
                  price: price,
                  style: TextStyle(
                    color: const Color(0xFFD00000),
                    fontSize: isCompact ? 13 : 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                isCompact: isCompact,
              ),
            ],
            if (itemName.isNotEmpty) ...[
              SizedBox(height: isCompact ? 5 : 8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _OverlayInfoRow extends StatelessWidget {
  const _OverlayInfoRow({required this.text, required this.isCompact});

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
              color: Colors.black,
              fontSize: isCompact ? 13 : 20,
              fontWeight: FontWeight.w600,
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

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isCompact ? 22 : 34,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 7 : 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE92808),
        borderRadius: BorderRadius.circular(isCompact ? 7 : 11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors, color: Colors.white, size: isCompact ? 13 : 21),
          SizedBox(width: isCompact ? 4 : 7),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: isCompact ? 12 : 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCardAnimation extends StatelessWidget {
  const _LiveCardAnimation();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 225,
        height: 108,
        child: Lottie.asset(
          'assets/lottie/live2.json',
          fit: BoxFit.contain,
          repeat: true,
          animate: true,
        ),
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
