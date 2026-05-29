import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../item_detail_page.dart';
import '../item_edit_page.dart';
import '../seller_session.dart';
import '../story_repository.dart';
import '../widgets/media_carousel.dart';
import '../widgets/price_with_currency.dart';

class SellerListingsTab extends StatefulWidget {
  const SellerListingsTab({super.key});

  @override
  State<SellerListingsTab> createState() => _SellerListingsTabState();
}

class _SellerListingsTabState extends State<SellerListingsTab> {
  late final Future<SellerSession?> _sessionFuture;
  late DateTime _now;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _sessionFuture = SellerSession.current();
    _now = DateTime.now();
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  DateTime? _createdAt(Map<String, dynamic> item) {
    final createdAt = item['created_at'];
    if (createdAt is Timestamp) {
      return createdAt.toDate();
    }
    if (createdAt is DateTime) {
      return createdAt;
    }
    return null;
  }

  DateTime? _expiryAt(Map<String, dynamic> item) {
    final expiresAt = item['expires_at'];
    if (expiresAt is Timestamp) {
      return expiresAt.toDate();
    }
    if (expiresAt is DateTime) {
      return expiresAt;
    }

    final postedAt = _createdAt(item);
    final timePeriodHours = item['time_period_hours'];
    if (postedAt == null || timePeriodHours is! num) {
      return null;
    }
    return postedAt.add(Duration(hours: timePeriodHours.toInt()));
  }

  bool _isItemActive(Map<String, dynamic> item) {
    final expiryAt = _expiryAt(item);
    return expiryAt == null || expiryAt.isAfter(_now);
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

    final difference = _now.difference(uploadedAt);
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
    return '${difference.inDays ~/ 7} weeks ago';
  }

  String _expiryText(Map<String, dynamic> item) {
    final expiryAt = _expiryAt(item);
    if (expiryAt == null) {
      return 'Exp. not set';
    }
    final remaining = expiryAt.difference(_now);
    if (remaining <= Duration.zero) {
      return 'Exp. expired';
    }

    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes < 60) {
      return 'Exp. $minutes ${minutes == 1 ? 'min' : 'mins'}';
    }

    final hours = minutes ~/ 60;
    final extraMinutes = minutes % 60;
    if (extraMinutes == 0) {
      return 'Exp. $hours ${hours == 1 ? 'hr' : 'hrs'}';
    }
    return 'Exp. $hours ${hours == 1 ? 'hr' : 'hrs'} $extraMinutes mins';
  }

  String _formatPrice(Object? value) {
    final text = value?.toString() ?? '';
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
    if (match != null && (double.tryParse(match.group(0) ?? '') ?? -1) == 0) {
      return 'Contact for Price';
    }
    return text
        .replaceAll(RegExp(r'\s+per\s+', caseSensitive: false), ' / ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _deleteItem(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  ) async {
    final sellerId = item['seller_uid']?.toString() ?? '';
    if (sellerId.isNotEmpty) {
      await const StoryRepository().removeItemVideos(
        sellerId: sellerId,
        itemId: docId,
      );
    }
    await FirebaseFirestore.instance.collection('items').doc(docId).delete();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Item deleted'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'Delete !',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'No',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'Yes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && context.mounted) {
      await _deleteItem(context, docId, item);
    }
  }

  void _openEdit(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemEditPage(docId: docId, itemData: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: _sessionFuture,
      builder: (context, sessionSnapshot) {
        if (sessionSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final session = sessionSnapshot.data;
        if (session == null) {
          return const Center(child: Text('Please login again'));
        }

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _ListingsScrollableHeader()),
                SliverToBoxAdapter(child: _SellerInfoHeader(session: session)),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('items')
                      .where('seller_uid', isEqualTo: session.sellerId)
                      .snapshots(),
                  builder: (context, itemsSnapshot) {
                    if (itemsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (itemsSnapshot.hasError) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text('Error: ${itemsSnapshot.error}'),
                        ),
                      );
                    }

                    final docs = (itemsSnapshot.data?.docs ?? [])
                        .where((doc) => _isItemActive(doc.data()))
                        .toList()
                      ..sort((a, b) {
                        final aDate =
                            _createdAt(a.data()) ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final bDate =
                            _createdAt(b.data()) ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return bDate.compareTo(aDate);
                      });

                    if (docs.isEmpty) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'No items listed yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                      sliver: SliverToBoxAdapter(
                        child: _ListingsGrid(
                          docs: docs,
                          uploadedAgo: _uploadedAgo,
                          expiryText: _expiryText,
                          formatPrice: _formatPrice,
                          onEdit: _openEdit,
                          onDelete: _confirmDelete,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Positioned(
              top: 8,
              right: 14,
              child: _FloatingShareButton(),
            ),
          ],
        );
      },
    );
  }
}

class _ListingsScrollableHeader extends StatelessWidget {
  const _ListingsScrollableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      color: const Color(0xFFF4FBF7),
      alignment: Alignment.center,
      child: const SizedBox(
        height: 56,
        width: 152,
        child: Image(
          image: AssetImage('assets/branding/logo.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _FloatingShareButton extends StatelessWidget {
  const _FloatingShareButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFFFF7801),
        foregroundColor: Colors.white,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(82, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text(
        'Share',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SellerInfoHeader extends StatelessWidget {
  const _SellerInfoHeader({required this.session});

  final SellerSession session;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sellers')
          .doc(session.sellerId)
          .snapshots(),
      builder: (context, snapshot) {
        final seller = snapshot.data?.data() ?? {};
        final sellerName = seller['name']?.toString().trim() ?? session.name;
        final crNumber =
            seller['cr_number']?.toString().trim().isNotEmpty == true
            ? seller['cr_number'].toString().trim()
            : seller['crNumber']?.toString().trim() ?? '';
        final topLine = [
          if (sellerName.trim().isNotEmpty) sellerName.trim(),
          if (crNumber.isNotEmpty) 'CR No. $crNumber',
        ].join(' | ');
        final phoneNumber = _formatSellerPhone(session.phoneNumber);

        return Container(
          width: double.infinity,
          color: const Color(0xFFF4FBF7),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (topLine.isNotEmpty)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    topLine,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (phoneNumber.isNotEmpty) ...[
                if (topLine.isNotEmpty) const SizedBox(height: 5),
                Text(
                  phoneNumber,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ListingsGrid extends StatelessWidget {
  const _ListingsGrid({
    required this.docs,
    required this.uploadedAgo,
    required this.expiryText,
    required this.formatPrice,
    required this.onEdit,
    required this.onDelete,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String Function(Object? value) uploadedAgo;
  final String Function(Map<String, dynamic> item) expiryText;
  final String Function(Object? value) formatPrice;
  final void Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  )
  onEdit;
  final void Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  )
  onDelete;

  @override
  Widget build(BuildContext context) {
    final leftDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final rightDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < docs.length; i++) {
      if (i.isEven) {
        leftDocs.add(docs[i]);
      } else {
        rightDocs.add(docs[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ListingsColumn(
            docs: leftDocs,
            uploadedAgo: uploadedAgo,
            expiryText: expiryText,
            formatPrice: formatPrice,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _ListingsColumn(
            docs: rightDocs,
            uploadedAgo: uploadedAgo,
            expiryText: expiryText,
            formatPrice: formatPrice,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      ],
    );
  }
}

class _ListingsColumn extends StatelessWidget {
  const _ListingsColumn({
    required this.docs,
    required this.uploadedAgo,
    required this.expiryText,
    required this.formatPrice,
    required this.onEdit,
    required this.onDelete,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String Function(Object? value) uploadedAgo;
  final String Function(Map<String, dynamic> item) expiryText;
  final String Function(Object? value) formatPrice;
  final void Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  )
  onEdit;
  final void Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  )
  onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: docs
          .map(
            (doc) => _ListingManageCard(
              docId: doc.id,
              item: doc.data(),
              uploadedAgo: uploadedAgo(doc.data()['created_at']),
              expiryText: expiryText(doc.data()),
              formatPrice: formatPrice,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          )
          .toList(),
    );
  }
}

class _ListingManageCard extends StatelessWidget {
  const _ListingManageCard({
    required this.docId,
    required this.item,
    required this.uploadedAgo,
    required this.expiryText,
    required this.formatPrice,
    required this.onEdit,
    required this.onDelete,
  });

  final String docId;
  final Map<String, dynamic> item;
  final String uploadedAgo;
  final String expiryText;
  final String Function(Object? value) formatPrice;
  final void Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  )
  onEdit;
  final void Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  )
  onDelete;

  @override
  Widget build(BuildContext context) {
    final mediaItems = mediaItemsFromMap(item);
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
          final cardHeight = (constraints.maxWidth * 1.48).clamp(245.0, 310.0);

          return Card(
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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
                    top: 7,
                    left: 7,
                    child: _MediaCountBadges(
                      imageCount: imageCount,
                      videoCount: videoCount,
                    ),
                  ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: _ManageActions(
                      uploadedAgo: uploadedAgo,
                      expiryText: expiryText,
                      onEdit: () => onEdit(context, docId, item),
                      onDelete: () => onDelete(context, docId, item),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 10,
                    child: _ImageFilledDetails(
                      item: item,
                      formatPrice: formatPrice,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ManageActions extends StatelessWidget {
  const _ManageActions({
    required this.uploadedAgo,
    required this.expiryText,
    required this.onEdit,
    required this.onDelete,
  });

  final String uploadedAgo;
  final String expiryText;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _DarkBadge(text: uploadedAgo),
        const SizedBox(height: 4),
        _DarkBadge(text: expiryText),
        const SizedBox(height: 7),
        _ActionPill(text: 'Edit', color: const Color(0xFF128CFF), onTap: onEdit),
        const SizedBox(height: 12),
        _ActionPill(text: 'Delete', color: Colors.red, onTap: onDelete),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.text,
    required this.color,
    required this.onTap,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.black, width: 1.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkBadge extends StatelessWidget {
  const _DarkBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ImageFilledDetails extends StatelessWidget {
  const _ImageFilledDetails({
    required this.item,
    required this.formatPrice,
  });

  final Map<String, dynamic> item;
  final String Function(Object? value) formatPrice;

  @override
  Widget build(BuildContext context) {
    final itemName = item['item_name']?.toString().trim() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TextChip(
          child: _OverlayInfoRow(text: item['location']?.toString() ?? ''),
        ),
        const SizedBox(height: 5),
        _TextChip(
          child: PriceWithCurrency(
            price: formatPrice(item['item_price']),
            style: const TextStyle(
              color: Color(0xFFD00000),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (itemName.isNotEmpty) ...[
          const SizedBox(height: 7),
          _TextChip(
            child: Text(
              itemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TextChip extends StatelessWidget {
  const _TextChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _OverlayInfoRow extends StatelessWidget {
  const _OverlayInfoRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('📍', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
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
        if (imageCount > 0 && videoCount > 0) const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSellerPhone(Object? value) {
  final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  if (digits.isEmpty) {
    return '';
  }
  if (digits.startsWith('968') && digits.length > 3) {
    return '+968 ${digits.substring(3)}';
  }
  return '+968 $digits';
}
