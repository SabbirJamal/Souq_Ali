import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'seller_home_page.dart';
import 'seller_profile_page.dart';
import 'seller_session.dart';
import 'share_listing_page.dart';
import 'widgets/item_card.dart';
import 'widgets/media_carousel.dart';
import 'widgets/price_with_currency.dart';

class ItemDetailPage extends StatelessWidget {
  const ItemDetailPage({super.key, required this.itemData, required this.itemId});

  final Map<String, dynamic> itemData;
  final String itemId;

  Future<void> _launchPhone(String phoneNumber) async {
    final phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    await launchUrl(phoneUri);
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanNumber');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openFullscreen(
    BuildContext context,
    List<MediaItem> mediaItems,
    int initialIndex,
    String sellerPhone,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StackedMediaPage(
          mediaItems: mediaItems,
          initialIndex: initialIndex,
          sellerPhone: sellerPhone,
        ),
      ),
    );
  }

  Future<void> _goToFeed(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final session = await SellerSession.current();
    if (!context.mounted) {
      return;
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SellerHomePage(isSellerMode: session != null),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaItems = mediaItemsFromMap(itemData);
    final sellerPhone = itemData['seller_phone']?.toString() ?? '';
    final itemName = itemData['item_name']?.toString().trim() ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _goToFeed(context);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _DetailMediaHeader(
                        mediaItems: mediaItems,
                        itemName: itemName,
                        price: _formatPrice(itemData['item_price']),
                        location: itemData['location']?.toString() ?? '',
                        onMediaTap: (media, index) => _openFullscreen(
                          context,
                          mediaItems,
                          index,
                          sellerPhone,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 2),
                            _SellerAvatarIcon(
                              name: itemData['seller_name'],
                              sellerId: itemData['seller_uid'],
                              sellerPhone: itemData['seller_phone'],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _SellerActiveItemsSection(
                        sellerId: itemData['seller_uid'],
                        sellerPhone: itemData['seller_phone'],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                _FixedActionBar(
                  sellerPhone: sellerPhone,
                  onCall: () => _launchPhone(sellerPhone),
                  onWhatsApp: () => _launchWhatsApp(sellerPhone),
                  onShare: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShareListingPage(
                          itemId: itemId,
                          itemData: itemData,
                          mediaItems: mediaItems,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            _DetailHeader(onBack: () => _goToFeed(context)),
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      height: topInset + 56,
      padding: EdgeInsets.only(top: topInset, left: 14, right: 14),
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onBack,
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.arrow_back, color: Colors.black),
          ),
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

class _DetailMediaHeader extends StatelessWidget {
  const _DetailMediaHeader({
    required this.mediaItems,
    required this.itemName,
    required this.price,
    required this.location,
    required this.onMediaTap,
  });

  final List<MediaItem> mediaItems;
  final String itemName;
  final String price;
  final String location;
  final void Function(MediaItem media, int index) onMediaTap;

  @override
  Widget build(BuildContext context) {
    final trimmedLocation = location.trim();
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.75;
    return SizedBox(
      height: mediaHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaCarousel(
            mediaItems: mediaItems,
            height: mediaHeight,
            borderRadius: 0,
            fit: BoxFit.cover,
            showCountBadge: true,
            showPageDots: true,
            onMediaTap: onMediaTap,
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trimmedLocation.isNotEmpty)
                  _DetailOverlayChip(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('📍', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            trimmedLocation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (price.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _DetailOverlayChip(
                    child: PriceWithCurrency(
                      price: price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD00000),
                      ),
                    ),
                  ),
                ],
                if (itemName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _DetailOverlayChip(
                    child: Text(
                      itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailOverlayChip extends StatelessWidget {
  const _DetailOverlayChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 28,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      child: child,
    );
  }
}

class _FixedActionBar extends StatelessWidget {
  const _FixedActionBar({
    required this.sellerPhone,
    required this.onCall,
    required this.onWhatsApp,
    required this.onShare,
  });

  final String sellerPhone;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 7, 28, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: sellerPhone.isEmpty ? null : onCall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        fixedSize: const Size.fromHeight(48),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Icon(Icons.phone, size: 27),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: sellerPhone.isEmpty ? null : onWhatsApp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        fixedSize: const Size.fromHeight(48),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const FaIcon(FontAwesomeIcons.whatsapp, size: 26),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onShare,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        fixedSize: const Size.fromHeight(48),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Share',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharePostButton extends StatelessWidget {
  const _SharePostButton({required this.onShare});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onShare,
      child: const Text(
        'Share',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 15),
        side: const BorderSide(color: Colors.black, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  const _LocationLine({required this.location});

  final Object? location;

  @override
  Widget build(BuildContext context) {
    final text = location?.toString().trim() ?? '';
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        const Text('📍', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SellerAvatarIcon extends StatelessWidget {
  const _SellerAvatarIcon({
    required this.name,
    required this.sellerId,
    required this.sellerPhone,
  });

  final Object? name;
  final Object? sellerId;
  final Object? sellerPhone;

  @override
  Widget build(BuildContext context) {
    final sellerName = name?.toString().trim() ?? '';
    final sellerDocId =
        sellerId?.toString().trim().isNotEmpty == true
            ? sellerId!.toString().trim()
            : sellerPhone?.toString().trim() ?? '';

    return Center(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: sellerDocId.isEmpty
            ? null
            : FirebaseFirestore.instance
                  .collection('sellers')
                  .doc(sellerDocId)
                  .snapshots(),
        builder: (context, snapshot) {
          final seller = snapshot.data?.data() ?? {};
          final visibleName =
              seller['name']?.toString().trim().isNotEmpty == true
              ? seller['name'].toString().trim()
              : sellerName;
          final crNumber =
              seller['cr_number']?.toString().trim().isNotEmpty == true
              ? seller['cr_number'].toString().trim()
              : seller['crNumber']?.toString().trim() ?? '';
          final phoneNumber = _formatSellerPhone(sellerPhone);
          final topLine = [
            if (visibleName.isNotEmpty) visibleName,
            if (crNumber.isNotEmpty) 'CR No. $crNumber',
          ].join(' | ');

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: sellerDocId.isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerProfilePage(
                          sellerId: sellerDocId,
                          sellerPhone: sellerPhone?.toString().trim() ?? '',
                          fallbackName: visibleName,
                          isOwnProfile: false,
                        ),
                      ),
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: topLine.isEmpty && phoneNumber.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (topLine.isNotEmpty)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                topLine,
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          if (phoneNumber.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              phoneNumber,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          );
        },
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

class _SellerActiveItemsSection extends StatelessWidget {
  const _SellerActiveItemsSection({
    required this.sellerId,
    required this.sellerPhone,
  });

  final Object? sellerId;
  final Object? sellerPhone;

  @override
  Widget build(BuildContext context) {
    final docId = sellerId?.toString().trim().isNotEmpty == true
        ? sellerId!.toString().trim()
        : sellerPhone?.toString().trim() ?? '';
    if (docId.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .where('seller_uid', isEqualTo: docId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => _isItemActive(doc.data(), now))
            .toList()
          ..sort((a, b) {
            final aTime = a.data()['created_at'];
            final bTime = b.data()['created_at'];
            final aDate = aTime is Timestamp
                ? aTime.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = bTime is Timestamp
                ? bTime.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          child: _SellerItemGrid(docs: docs),
        );
      },
    );
  }
}

class _SellerItemGrid extends StatelessWidget {
  const _SellerItemGrid({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

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
        Expanded(child: _SellerItemColumn(docs: leftDocs)),
        const SizedBox(width: 4),
        Expanded(child: _SellerItemColumn(docs: rightDocs)),
      ],
    );
  }
}

class _SellerItemColumn extends StatelessWidget {
  const _SellerItemColumn({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: docs
          .map((doc) => ItemCard(docId: doc.id, item: doc.data(), isCompact: true))
          .toList(),
    );
  }
}

bool _isItemActive(Map<String, dynamic> item, DateTime now) {
  final createdAt = item['created_at'];
  final timePeriodHours = item['time_period_hours'];
  if (createdAt is Timestamp && timePeriodHours is num) {
    return createdAt
        .toDate()
        .add(Duration(hours: timePeriodHours.toInt()))
        .isAfter(now);
  }
  final expiresAt = item['expires_at'];
  if (expiresAt is Timestamp) {
    return expiresAt.toDate().isAfter(now);
  }
  if (expiresAt is DateTime) {
    return expiresAt.isAfter(now);
  }
  return true;
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.rows});

  final List<_DetailData> rows;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows
        .where((row) => row.valueText.trim().isNotEmpty)
        .toList(growable: false);

    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E8E8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: List.generate(visibleRows.length, (index) {
            final row = visibleRows[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
              decoration: BoxDecoration(
                color: index.isEven
                    ? const Color(0xFFF5F5FA)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row.valueText,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _DetailData {
  _DetailData({required this.label, required Object? value})
    : valueText = value?.toString() ?? '';

  final String label;
  final String valueText;
}

class _StackedMediaPage extends StatefulWidget {
  const _StackedMediaPage({
    required this.mediaItems,
    required this.initialIndex,
    required this.sellerPhone,
  });

  final List<MediaItem> mediaItems;
  final int initialIndex;
  final String sellerPhone;

  @override
  State<_StackedMediaPage> createState() => _StackedMediaPageState();
}

class _StackedMediaPageState extends State<_StackedMediaPage> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || widget.initialIndex <= 0) {
        return;
      }
      _scrollController.jumpTo(398.0 * widget.initialIndex);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _openSingleMedia(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SingleMediaPage(
          mediaItems: widget.mediaItems,
          initialIndex: index,
          sellerPhone: widget.sellerPhone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: widget.mediaItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () => _openSingleMedia(index),
                            child: SizedBox(
                              width: double.infinity,
                              height: constraints.maxHeight,
                              child: _FullscreenMediaView(
                                media: widget.mediaItems[index],
                                allowZoom: false,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              _FullscreenContactBar(sellerPhone: widget.sellerPhone),
            ],
          ),
          _FullscreenHeader(onBack: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _SingleMediaPage extends StatefulWidget {
  const _SingleMediaPage({
    required this.mediaItems,
    required this.initialIndex,
    required this.sellerPhone,
  });

  final List<MediaItem> mediaItems;
  final int initialIndex;
  final String sellerPhone;

  @override
  State<_SingleMediaPage> createState() => _SingleMediaPageState();
}

class _SingleMediaPageState extends State<_SingleMediaPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaTopPadding = MediaQuery.paddingOf(context).top + 74;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: Padding(
                    padding: EdgeInsets.only(top: mediaTopPadding),
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                      },
                      itemCount: widget.mediaItems.length,
                      itemBuilder: (context, index) {
                        return _FullscreenMediaView(
                          media: widget.mediaItems[index],
                          allowZoom: true,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
                  ),
                ),
              ),
              _FullscreenContactBar(sellerPhone: widget.sellerPhone),
            ],
          ),
          _FullscreenHeader(onBack: () => Navigator.pop(context)),
          _MediaPositionCounter(
            currentIndex: _currentIndex,
            totalCount: widget.mediaItems.length,
          ),
        ],
      ),
    );
  }
}

class _MediaPositionCounter extends StatelessWidget {
  const _MediaPositionCounter({
    required this.currentIndex,
    required this.totalCount,
  });

  final int currentIndex;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: topInset + 36,
      child: Center(
        child: Text(
          '${currentIndex + 1} / $totalCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 5,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenHeader extends StatelessWidget {
  const _FullscreenHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      height: topInset + 56,
      padding: EdgeInsets.only(top: topInset, left: 14, right: 14),
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onBack,
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.arrow_back, color: Colors.black),
          ),
        ),
      ),
    );
  }
}

class _FullscreenMediaView extends StatelessWidget {
  const _FullscreenMediaView({
    required this.media,
    required this.allowZoom,
    this.fit = BoxFit.contain,
  });

  final MediaItem media;
  final bool allowZoom;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return SizedBox.expand(child: VideoPreview(url: media.url, fit: fit));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final image = CachedNetworkImage(
          imageUrl: media.url,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          fit: fit,
          placeholder: (context, url) => const MediaSkeletonPlaceholder(
            baseColor: Color(0xFF202421),
            highlightColor: Color(0xFF333A35),
          ),
          errorWidget: (context, url, error) => const Icon(
            Icons.broken_image,
            color: Colors.white,
            size: 54,
          ),
        );

        if (!allowZoom) {
          return image;
        }

        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: image,
          ),
        );
      },
    );
  }
}

class _FullscreenContactBar extends StatelessWidget {
  const _FullscreenContactBar({required this.sellerPhone});

  final String sellerPhone;

  Future<void> _launchPhone(String phoneNumber) async {
    await launchUrl(Uri(scheme: 'tel', path: phoneNumber));
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    await launchUrl(
      Uri.parse('https://wa.me/$cleanNumber'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 7, 28, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: sellerPhone.isEmpty
                      ? null
                      : () => _launchPhone(sellerPhone),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A84FF),
                    foregroundColor: Colors.white,
                    fixedSize: const Size.fromHeight(48),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Icon(Icons.phone, size: 27),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: sellerPhone.isEmpty
                      ? null
                      : () => _launchWhatsApp(sellerPhone),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    fixedSize: const Size.fromHeight(48),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const FaIcon(FontAwesomeIcons.whatsapp, size: 26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    fixedSize: const Size.fromHeight(48),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Share',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenBackButton extends StatelessWidget {
  const _FullscreenBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
    );
  }
}
