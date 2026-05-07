import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'share_listing_page.dart';
import 'widgets/media_carousel.dart';

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
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StackedMediaPage(
          mediaItems: mediaItems,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaItems = mediaItemsFromMap(itemData);
    final sellerPhone = itemData['seller_phone']?.toString() ?? '';

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              MediaCarousel(
                mediaItems: mediaItems,
                height: 390,
                borderRadius: 0,
                fit: BoxFit.cover,
                showCountBadge: true,
                onMediaTap: (media, index) =>
                    _openFullscreen(context, mediaItems, index),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      itemData['item_name'] ?? 'No name',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      itemData['item_price'] ?? '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD00000),
                      ),
                    ),
                    const SizedBox(height: 18),
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
                              padding: const EdgeInsets.symmetric(vertical: 15),
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
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const FaIcon(
                              FontAwesomeIcons.whatsapp,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
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
                        icon: const Icon(Icons.ios_share),
                        label: const Text(
                          'Share Post',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          side: const BorderSide(color: Colors.black, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _DetailsCard(
                      rows: [
                        _DetailData(label: 'Origin', value: itemData['origin']),
                        _DetailData(
                          label: 'Location',
                          value: itemData['location'],
                        ),
                        _DetailData(
                          label: 'Quantity',
                          value: itemData['item_quantity'],
                        ),
                        _DetailData(
                          label: 'Price unit',
                          value: itemData['price_unit'],
                        ),
                        _DetailData(
                          label: 'Weight unit',
                          value: itemData['weight_unit'],
                        ),
                        _DetailData(
                          label: 'Seller',
                          value: itemData['seller_name'],
                        ),
                      ],
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 14,
            top: 14,
            child: SafeArea(
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back, color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
  });

  final List<MediaItem> mediaItems;
  final int initialIndex;

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
        builder: (_) => _SingleMediaPage(media: widget.mediaItems[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            itemCount: widget.mediaItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openSingleMedia(index),
                child: SizedBox(
                  width: double.infinity,
                  height: 390,
                  child: _FullscreenMediaView(media: widget.mediaItems[index]),
                ),
              );
            },
          ),
          Positioned(
            left: 14,
            top: 14,
            child: SafeArea(
              child: _FullscreenBackButton(onTap: () => Navigator.pop(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleMediaPage extends StatefulWidget {
  const _SingleMediaPage({required this.media});

  final MediaItem media;

  @override
  State<_SingleMediaPage> createState() => _SingleMediaPageState();
}

class _SingleMediaPageState extends State<_SingleMediaPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _FullscreenMediaView(media: widget.media)),
          Positioned(
            left: 14,
            top: 14,
            child: SafeArea(
              child: _FullscreenBackButton(onTap: () => Navigator.pop(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenMediaView extends StatelessWidget {
  const _FullscreenMediaView({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: VideoPreview(url: media.url, fit: BoxFit.contain),
        ),
      );
    }

    return Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: CachedNetworkImage(
          imageUrl: media.url,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) => const Icon(
            Icons.broken_image,
            color: Colors.white,
            size: 54,
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
