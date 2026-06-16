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
import 'widgets/app_status_bar.dart';
import 'widgets/detail/detail_media_header.dart';
import 'widgets/media_carousel.dart';

const _itemDetailSurfaceColor = Color(0xFFF4FBF7);

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, required this.itemData, required this.itemId});
  final Map<String, dynamic> itemData;
  final String itemId;
  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage>
    with WidgetsBindingObserver {
  final Map<String, VideoPlayerController> _preloadedVideoControllers = {};
  final Map<String, Future<void>> _preloadedVideoInitializers = {};
  late final List<MediaItem> _media = mediaItemsFromMap(widget.itemData);
  bool _isPreparingDetail = true, _didStartPreparingDetail = false, _lockDetailScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preloadDetailVideos();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopDetailPlayback(updateUi: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didStartPreparingDetail) { _didStartPreparingDetail = true; _prepareDetailMedia(); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDetailPlayback(updateUi: false);
    for (final c in _preloadedVideoControllers.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _prepareDetailMedia() async {
    final media = _media;
    if (media.isEmpty) {
      if (mounted) setState(() => _isPreparingDetail = false);
      return;
    }
    final first = media.first;
    final firstVid = first.isVideo ? _preloadedVideoInitializers[first.url]?.then((_) {
      _preloadedVideoControllers[first.url]?.play();
    }).catchError((_) {}) : null;

    final firstImageUrl = first.isVideo ? first.thumbnailUrl?.trim() ?? '' : first.url.trim();
    final firstImage = firstImageUrl.isNotEmpty
        ? _precacheDetailImage(firstImageUrl).catchError((_) {})
        : Future.value();
    final remainingImages = media.skip(1).map((m) {
      final url = m.isVideo ? m.thumbnailUrl?.trim() ?? '' : m.url.trim();
      return url.isEmpty ? Future.value() : _precacheDetailImage(url).catchError((_) {});
    });

    await Future.any([
      Future.wait([firstImage, ?firstVid, ...remainingImages]),
      Future.delayed(const Duration(milliseconds: 1300)),
    ]);
    if (mounted) setState(() => _isPreparingDetail = false);
    _precacheRemainingDetailMedia(media.skip(1));
  }

  Future<void> _precacheDetailImage(String url) {
    return precacheImage(
      CachedNetworkImageProvider(url, maxWidth: 1600),
      context,
    );
  }

  void _precacheRemainingDetailMedia(Iterable<MediaItem> media) {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      for (final m in media) {
        final url = m.isVideo ? m.thumbnailUrl?.trim() ?? '' : m.url.trim();
        if (url.isNotEmpty) {
          _precacheDetailImage(url).catchError((_) {});
        }
      }
    });
  }

  void _preloadDetailVideos() {
    final media = _media;
    MediaItem? firstVideo;
    for (final m in media) {
      if (m.isVideo) {
        firstVideo = m;
        break;
      }
    }
    if (firstVideo != null && !_preloadedVideoControllers.containsKey(firstVideo.url)) {
      final c = VideoPlayerController.networkUrl(Uri.parse(firstVideo.url));
      _preloadedVideoControllers[firstVideo.url] = c;
      _preloadedVideoInitializers[firstVideo.url] = c.initialize().catchError((_) {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadRemainingVideos(media, firstVideo);
    });
  }

  void _preloadRemainingVideos(List<MediaItem> media, MediaItem? firstVideo) {
    // Stagger init 400ms apart so multiple videos don't spin up decoders at once.
    var delayMs = 500;
    for (final m in media.where((m) => m.isVideo && m.url != firstVideo?.url)) {
      if (_preloadedVideoControllers.containsKey(m.url)) continue;
      final c = VideoPlayerController.networkUrl(Uri.parse(m.url));
      _preloadedVideoControllers[m.url] = c;
      _preloadedVideoInitializers[m.url] = Future.delayed(Duration(milliseconds: delayMs), () => c.initialize()).catchError((_) {});
      delayMs += 400;
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
    final media = _media;
    final phone = widget.itemData['seller_phone']?.toString() ?? '';
    return PopScope(
      canPop: false, onPopInvokedWithResult: (d, r) { if (!d) _goToFeed(context); },
      child: Scaffold(
        backgroundColor: _itemDetailSurfaceColor,
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
          const Positioned(top: 0, left: 0, right: 0, child: AppStatusBar()),
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
  Widget build(BuildContext context) => SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8, 7, 8, 8), child: Row(children: [
      Expanded(child: ElevatedButton(onPressed: phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: phone)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A84FF), foregroundColor: Colors.white, fixedSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Icon(Icons.phone, size: 27))),
      const SizedBox(width: 6),
      Expanded(child: ElevatedButton(onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, fixedSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const FaIcon(FontAwesomeIcons.whatsapp, size: 26))),
      const SizedBox(width: 6),
      Expanded(child: ElevatedButton(onPressed: onShare, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7801), foregroundColor: Colors.white, fixedSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Share', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)))),
    ])));
}

class _SellerAvatarIcon extends StatefulWidget {
  const _SellerAvatarIcon({required this.name, required this.sellerId, required this.sellerPhone, required this.onOpenProfile});
  final Object? name, sellerId, sellerPhone; final VoidCallback onOpenProfile;

  @override
  State<_SellerAvatarIcon> createState() => _SellerAvatarIconState();
}

class _SellerAvatarIconState extends State<_SellerAvatarIcon> {
  Object? get name => widget.name;
  Object? get sellerPhone => widget.sellerPhone;
  VoidCallback get onOpenProfile => widget.onOpenProfile;

  late final String _sid = widget.sellerId?.toString().trim().isNotEmpty == true
      ? widget.sellerId!.toString().trim()
      : widget.sellerPhone?.toString().trim() ?? '';
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _sellerStream =
      _sid.isEmpty ? null : FirebaseFirestore.instance.collection('sellers').doc(_sid).snapshots();

  Route<void> _profileRoute(String sid, String fallbackName) {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => SellerProfilePage(
        sellerId: sid,
        sellerPhone: sellerPhone?.toString().trim() ?? '',
        fallbackName: fallbackName,
        isOwnProfile: false,
      ),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sid = _sid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _sellerStream,
      builder: (ctx, snap) {
        final data = snap.data?.data() ?? {};
        final n = data['name']?.toString().trim().isNotEmpty == true ? data['name'] : name?.toString().trim() ?? '';
        final cr = data['cr_number']?.toString().trim() ?? data['crNumber']?.toString().trim() ?? '';
        final ph = formatSellerPhone(sellerPhone);
        final top = [if (n.isNotEmpty) n, if (cr.isNotEmpty) 'CR No. $cr'].join(' | ');
        return InkWell(borderRadius: BorderRadius.circular(14), onTap: sid.isEmpty ? null : () { onOpenProfile(); Navigator.pushReplacement(context, _profileRoute(sid, n.toString())); }, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
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
