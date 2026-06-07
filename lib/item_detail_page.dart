import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'seller_home_page.dart';
import 'seller_profile_page.dart';
import 'seller_session.dart';
import 'share_listing_page.dart';
import 'utils/formatters.dart';
import 'widgets/detail/detail_media_header.dart';
import 'widgets/media_carousel.dart';

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, required this.itemData, required this.itemId});
  final Map<String, dynamic> itemData;
  final String itemId;
  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  final Map<String, VideoPlayerController> _preloadedVideoControllers = {};
  final Map<String, Future<void>> _preloadedVideoInitializers = {};
  bool _isPreparingDetail = true, _didStartPreparingDetail = false, _lockDetailScroll = false;

  @override
  void initState() {
    super.initState();
    _preloadDetailVideos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didStartPreparingDetail) { _didStartPreparingDetail = true; _prepareDetailMedia(); }
  }

  @override
  void dispose() {
    _stopDetailPlayback(updateUi: false);
    for (final c in _preloadedVideoControllers.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _prepareDetailMedia() async {
    final media = mediaItemsFromMap(widget.itemData);
    final futures = media.map((m) {
      final url = m.isVideo ? m.thumbnailUrl?.trim() ?? '' : (m.thumbnailUrl?.trim().isNotEmpty == true ? m.thumbnailUrl!.trim() : m.url);
      return url.isEmpty ? Future.value() : precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {});
    });
    final first = media.isEmpty ? null : media.first;
    final firstVid = first?.isVideo == true ? _preloadedVideoInitializers[first!.url]?.then((_) {
      _preloadedVideoControllers[first.url]?.play();
    }).catchError((_) {}) : null;
    
    await Future.any([Future.wait([...futures, if (firstVid != null) firstVid]), Future.delayed(const Duration(milliseconds: 1600))]);
    if (mounted) setState(() => _isPreparingDetail = false);
  }

  void _preloadDetailVideos() {
    final media = mediaItemsFromMap(widget.itemData);
    final first = media.isEmpty ? null : media.first;
    for (final m in media.where((m) => m.isVideo)) {
      if (_preloadedVideoControllers.containsKey(m.url)) continue;
      final c = VideoPlayerController.networkUrl(Uri.parse(m.url));
      _preloadedVideoControllers[m.url] = c;
      _preloadedVideoInitializers[m.url] = (first?.url == m.url ? c.initialize() : Future.delayed(const Duration(milliseconds: 300), () => c.initialize())).catchError((_) {});
    }
  }

  void _stopDetailPlayback({bool updateUi = true}) {
    for (final c in _preloadedVideoControllers.values) { if (c.value.isInitialized) c.pause(); }
  }

  Future<void> _goToFeed(BuildContext context) async {
    _stopDetailPlayback();
    final nav = Navigator.of(context);
    if (nav.canPop()) { nav.pop(); return; }
    final s = await SellerSession.current();
    if (context.mounted) nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => SellerHomePage(isSellerMode: s != null)), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreparingDetail) return const _ItemDetailWarmupSkeleton();
    final media = mediaItemsFromMap(widget.itemData);
    final phone = widget.itemData['seller_phone']?.toString() ?? '';
    return PopScope(
      canPop: false, onPopInvokedWithResult: (d, r) { if (!d) _goToFeed(context); },
      child: Scaffold(
        body: Stack(children: [
          Column(children: [
            Expanded(child: ListView(padding: EdgeInsets.zero, physics: _lockDetailScroll ? const NeverScrollableScrollPhysics() : null, children: [
              DetailMediaHeader(
                mediaItems: media, preloadedVideoControllers: _preloadedVideoControllers, preloadedVideoInitializers: _preloadedVideoInitializers,
                itemName: widget.itemData['item_name']?.toString().trim() ?? '', price: formatPrice(widget.itemData['item_price']),
                location: widget.itemData['location']?.toString() ?? '', isLiveItem: widget.itemData['status']?.toString() == 'live',
                isTransitItem: widget.itemData['is_transit'] == true || (widget.itemData['location']?.toString().toLowerCase().contains('transit') ?? false),
                onZoomActiveChanged: (a) => setState(() => _lockDetailScroll = a),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _SellerAvatarIcon(name: widget.itemData['seller_name'], sellerId: widget.itemData['seller_uid'], sellerPhone: phone, onOpenProfile: _stopDetailPlayback)),
              const SizedBox(height: 8),
            ])),
            _FixedActionBar(phone: phone, onShare: () { _stopDetailPlayback(); Navigator.push(context, MaterialPageRoute(builder: (_) => ShareListingPage(itemId: widget.itemId, itemData: widget.itemData, mediaItems: media))); }),
          ]),
          _DetailHeader(onBack: () => _goToFeed(context)),
        ]),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(height: top + 56, padding: EdgeInsets.only(top: top, left: 14, right: 14), alignment: Alignment.centerLeft, child: Material(color: Colors.white, shape: const CircleBorder(), elevation: 3, child: InkWell(customBorder: const CircleBorder(), onTap: onBack, child: const SizedBox(width: 42, height: 42, child: Icon(Icons.arrow_back)))));
  }
}

class _FixedActionBar extends StatelessWidget {
  const _FixedActionBar({required this.phone, required this.onShare});
  final String phone; final VoidCallback onShare;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: const Offset(0, -4))]),
    child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(28, 7, 28, 8), child: Row(children: [
      Expanded(child: ElevatedButton(onPressed: phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: phone)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A84FF), foregroundColor: Colors.white, fixedSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Icon(Icons.phone, size: 27))),
      const SizedBox(width: 12),
      Expanded(child: ElevatedButton(onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, fixedSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const FaIcon(FontAwesomeIcons.whatsapp, size: 26))),
      const SizedBox(width: 12),
      Expanded(child: ElevatedButton(onPressed: onShare, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7801), foregroundColor: Colors.white, fixedSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Share', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))),
    ]))),
  );
}

class _SellerAvatarIcon extends StatelessWidget {
  const _SellerAvatarIcon({required this.name, required this.sellerId, required this.sellerPhone, required this.onOpenProfile});
  final Object? name, sellerId, sellerPhone; final VoidCallback onOpenProfile;
  @override
  Widget build(BuildContext context) {
    final sid = sellerId?.toString().trim().isNotEmpty == true ? sellerId!.toString().trim() : sellerPhone?.toString().trim() ?? '';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: sid.isEmpty ? null : FirebaseFirestore.instance.collection('sellers').doc(sid).snapshots(),
      builder: (ctx, snap) {
        final data = snap.data?.data() ?? {};
        final n = data['name']?.toString().trim().isNotEmpty == true ? data['name'] : name?.toString().trim() ?? '';
        final cr = data['cr_number']?.toString().trim() ?? data['crNumber']?.toString().trim() ?? '';
        final ph = formatSellerPhone(sellerPhone);
        final top = [if (n.isNotEmpty) n, if (cr.isNotEmpty) 'CR No. $cr'].join(' | ');
        return InkWell(borderRadius: BorderRadius.circular(14), onTap: sid.isEmpty ? null : () { onOpenProfile(); Navigator.push(context, MaterialPageRoute(builder: (_) => SellerProfilePage(sellerId: sid, sellerPhone: sellerPhone?.toString().trim() ?? '', fallbackName: n, isOwnProfile: false))); }, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
          if (top.isNotEmpty) FittedBox(child: Text(top, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          if (ph.isNotEmpty) Text(ph, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ])));
      },
    );
  }
}

class _ItemDetailWarmupSkeleton extends StatelessWidget {
  const _ItemDetailWarmupSkeleton();
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.8;
    return Scaffold(backgroundColor: const Color(0xFFF4FBF7), body: Column(children: [
      SizedBox(height: h, child: Stack(children: [
        const Positioned.fill(child: MediaSkeletonPlaceholder()),
        Positioned(top: MediaQuery.paddingOf(context).top + 12, left: 14, child: const CircleAvatar(radius: 21, backgroundColor: Colors.white, child: Icon(Icons.arrow_back))),
        const Positioned(left: 14, right: 110, bottom: 48, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_WarmupChip(width: 42), SizedBox(height: 8), _WarmupChip(width: 150), SizedBox(height: 8), _WarmupChip(width: 118), SizedBox(height: 8), _WarmupChip(width: 130)]))
      ])),
      const Padding(padding: EdgeInsets.fromLTRB(22, 22, 22, 0), child: _WarmupChip(width: double.infinity, height: 42))
    ]));
  }
}

class _WarmupChip extends StatelessWidget {
  const _WarmupChip({required this.width, this.height = 30});
  final double width, height;
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: width, height: height, child: const MediaSkeletonPlaceholder()));
}
