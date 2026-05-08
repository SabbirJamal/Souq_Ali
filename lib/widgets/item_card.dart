import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../item_detail_page.dart';
import 'media_carousel.dart';

class ItemCard extends StatefulWidget {
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
    final isCompact = widget.isCompact;

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
                    height: isCompact ? 150 : 280,
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
