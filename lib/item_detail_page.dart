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
import 'widgets/profile_image.dart';

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
                      MediaCarousel(
                        mediaItems: mediaItems,
                        height: 455,
                        borderRadius: 0,
                        fit: BoxFit.cover,
                        showCountBadge: true,
                        showPageDots: true,
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
                            if (itemName.isNotEmpty) ...[
                              Text(
                                itemName,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            PriceWithCurrency(
                              price: _formatPrice(itemData['item_price']),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFD00000),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _LocationLine(location: itemData['location']),
                            const SizedBox(height: 16),
                            _SharePostButton(
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
                            const SizedBox(height: 18),
                        _SellerAvatarIcon(
                          name: itemData['seller_name'],
                          sellerId: itemData['seller_uid'],
                              sellerPhone: itemData['seller_phone'],
                              initialImageUrl:
                                  itemData['profile_image_url'] ??
                              itemData['seller_profile_image_url'],
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
                    ],
                  ),
                ),
                _FixedActionBar(
                  sellerPhone: sellerPhone,
                  onCall: () => _launchPhone(sellerPhone),
                  onWhatsApp: () => _launchWhatsApp(sellerPhone),
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

class _FixedActionBar extends StatelessWidget {
  const _FixedActionBar({
    required this.sellerPhone,
    required this.onCall,
    required this.onWhatsApp,
  });

  final String sellerPhone;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
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
                        padding: const EdgeInsets.symmetric(vertical: 11),
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
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const FaIcon(FontAwesomeIcons.whatsapp, size: 26),
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
    return OutlinedButton.icon(
      onPressed: onShare,
      icon: const Icon(Icons.ios_share),
      label: const Text(
        'Share Post',
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
    required this.initialImageUrl,
  });

  final Object? name;
  final Object? sellerId;
  final Object? sellerPhone;
  final Object? initialImageUrl;

  @override
  Widget build(BuildContext context) {
    final sellerName = name?.toString().trim() ?? '';
    final initialUrl = initialImageUrl?.toString().trim() ?? '';
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
          final profileImageUrl =
              seller['profile_image_url']?.toString().trim() ?? initialUrl;
          final visibleName =
              seller['name']?.toString().trim().isNotEmpty == true
              ? seller['name'].toString().trim()
              : sellerName;
          final crNumber =
              seller['cr_number']?.toString().trim().isNotEmpty == true
              ? seller['cr_number'].toString().trim()
              : seller['crNumber']?.toString().trim() ?? '';

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
                          fallbackImageUrl: profileImageUrl,
                        ),
                      ),
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SellerProfileImage(imageUrl: profileImageUrl),
                  if (visibleName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      visibleName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                  if (crNumber.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'CR No. $crNumber',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SellerProfileImage extends StatelessWidget {
  const _SellerProfileImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: ProfileImage(
        imageValue: imageUrl,
        size: 86,
        fallbackColor: Colors.teal,
      ),
    );
  }
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
          padding: const EdgeInsets.only(top: 4),
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
        const SizedBox(width: 2),
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
                          fit: BoxFit.cover,
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
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
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
        color: Colors.black.withValues(alpha: 0.72),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Icon(Icons.phone, size: 25),
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
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const FaIcon(FontAwesomeIcons.whatsapp, size: 24),
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
