import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../item_detail_page.dart';
import 'media_carousel.dart';

enum ItemCardStyle { standard, compact, imageFilled }

class ItemCard extends StatefulWidget {
  const ItemCard({
    super.key,
    required this.docId,
    required this.item,
    this.isCompact = false,
    this.style,
  });

  final String docId;
  final Map<String, dynamic> item;
  final bool isCompact;
  final ItemCardStyle? style;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  Future<void> _launchPhone(String phoneNumber) async {
    final phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    await launchUrl(phoneUri);
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanNumber');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final mediaItems = mediaItemsFromMap(item);
    final sellerPhone = item['seller_phone'] ?? '';
    final uploadedAgo = _uploadedAgo(item['created_at']);
    final cardStyle = widget.style ??
        (widget.isCompact ? ItemCardStyle.compact : ItemCardStyle.standard);
    final isCompact = cardStyle == ItemCardStyle.compact;
    final imageCount = mediaItems.where((media) => !media.isVideo).length;
    final videoCount = mediaItems.where((media) => media.isVideo).length;

    if (cardStyle == ItemCardStyle.imageFilled) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ItemDetailPage(itemData: item, itemId: widget.docId),
            ),
          );
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight = (constraints.maxWidth * 1.36).clamp(445.0, 595.0);

            return Card(
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
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
                      top: 10,
                      left: 10,
                      child: _MediaCountBadges(
                        imageCount: imageCount,
                        videoCount: videoCount,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _UploadedAgoBadge(uploadedAgo: uploadedAgo),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 18,
                      child: _ImageFilledDetails(item: item),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ItemDetailPage(itemData: item, itemId: widget.docId),
          ),
        );
      },
      child: Card(
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        color: Colors.white,
        margin: EdgeInsets.only(bottom: isCompact ? 16 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                0,
              ),
              child: Stack(
                children: [
                  MediaCarousel(
                    mediaItems: mediaItems,
                    height: isCompact ? 168 : 298,
                    peekSideItems: false,
                    borderRadius: 0,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _UploadedAgoBadge(uploadedAgo: uploadedAgo),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 8 : 12,
                isCompact ? 8 : 12,
                isCompact ? 8 : 12,
                isCompact ? 8 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['item_name'] ?? 'No name',
                    style: TextStyle(
                      fontSize: isCompact ? 16 : 21,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: isCompact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isCompact ? 5 : 8),
                  Text(
                    item['item_price'] ?? '',
                    style: TextStyle(
                      fontSize: isCompact ? 13 : 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD00000),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
                  _InfoRow(
                    icon: Icons.place,
                    text: 'Origin: ${item['origin'] ?? ''}',
                    isCompact: isCompact,
                  ),
                  SizedBox(height: isCompact ? 4 : 6),
                  _InfoRow(
                    icon: Icons.location_on,
                    text: item['location']?.toString() ?? '',
                    isCompact: isCompact,
                  ),
                  SizedBox(height: isCompact ? 9 : 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: sellerPhone.isEmpty
                              ? null
                              : () => _launchPhone(sellerPhone),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A84FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.symmetric(
                              vertical: isCompact ? 10 : 12,
                            ),
                          ),
                          child: Icon(Icons.phone, size: isCompact ? 18 : 22),
                        ),
                      ),
                      SizedBox(width: isCompact ? 8 : 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: sellerPhone.isEmpty
                              ? null
                              : () => _launchWhatsApp(sellerPhone),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: FaIcon(
                            FontAwesomeIcons.whatsapp,
                            size: isCompact ? 18 : 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          ),
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
  const _ImageFilledDetails({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.sizeOf(context).width * 0.58,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['item_name'] ?? 'No name',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item['item_price'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD00000),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _OverlayInfoRow(
            icon: Icons.place,
            text: 'Origin: ${item['origin'] ?? ''}',
          ),
          const SizedBox(height: 7),
          _OverlayInfoRow(
            icon: Icons.location_on,
            text: item['location']?.toString() ?? '',
          ),
        ],
      ),
    );
  }
}

class _OverlayInfoRow extends StatelessWidget {
  const _OverlayInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 18,
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
  });

  final int imageCount;
  final int videoCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageCount > 0)
          _TopMediaBadge(icon: Icons.photo_camera, count: imageCount),
        if (imageCount > 0 && videoCount > 0) const SizedBox(width: 8),
        if (videoCount > 0)
          _TopMediaBadge(icon: Icons.videocam, count: videoCount),
      ],
    );
  }
}

class _TopMediaBadge extends StatelessWidget {
  const _TopMediaBadge({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadedAgoBadge extends StatelessWidget {
  const _UploadedAgoBadge({required this.uploadedAgo});

  final String uploadedAgo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        uploadedAgo,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    required this.isCompact,
  });

  final IconData icon;
  final String text;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: isCompact ? 11 : 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
