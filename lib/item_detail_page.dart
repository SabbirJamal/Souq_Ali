import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'seller_home_page.dart';
import 'seller_profile_page.dart';
import 'seller_session.dart';
import 'share_listing_page.dart';
import 'widgets/media_carousel.dart';
import 'widgets/price_with_currency.dart';

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, required this.itemData, required this.itemId});

  final Map<String, dynamic> itemData;
  final String itemId;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late final AudioPlayer _audioPlayer;
  final Map<String, VideoPlayerController> _preloadedVideoControllers = {};
  final Map<String, Future<void>> _preloadedVideoInitializers = {};
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _isPreparingDetail = true;
  bool _didStartPreparingDetail = false;
  bool _isAudioPlaying = false;
  bool _showAudioProgress = false;
  bool _isAudioSourcePrepared = false;
  int _audioCompletionToken = 0;
  bool _lockDetailScroll = false;

  String get _audioUrl =>
      widget.itemData['audio_description_url']?.toString().trim() ?? '';

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _preloadDetailVideos();
    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() => _audioDuration = duration);
      }
    });
    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() => _audioPosition = position);
      }
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        final completionToken = ++_audioCompletionToken;
        setState(() {
          _isAudioPlaying = false;
          _showAudioProgress = true;
          _audioPosition = _audioDuration;
        });
        Future<void>.delayed(const Duration(milliseconds: 220), () {
          if (!mounted ||
              _isAudioPlaying ||
              completionToken != _audioCompletionToken) {
            return;
          }
          setState(() {
            _showAudioProgress = false;
            _audioPosition = Duration.zero;
          });
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didStartPreparingDetail) {
      return;
    }
    _didStartPreparingDetail = true;
    _prepareDetailMedia();
  }

  @override
  void dispose() {
    _stopDetailPlayback(updateUi: false);
    _audioPlayer.dispose();
    for (final controller in _preloadedVideoControllers.values) {
      controller
        ..setVolume(0)
        ..pause()
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _prepareDetailMedia() async {
    final mediaItems = mediaItemsFromMap(widget.itemData);
    final imageFutures = mediaItems.map((media) {
      final url = media.isVideo
          ? media.thumbnailUrl?.trim() ?? ''
          : media.thumbnailUrl?.trim().isNotEmpty == true
              ? media.thumbnailUrl!.trim()
              : media.url;
      if (url.isEmpty) {
        return Future<void>.value();
      }
      return precacheImage(CachedNetworkImageProvider(url), context).catchError(
        (_) {},
      );
    });
    final firstMedia = mediaItems.isEmpty ? null : mediaItems.first;
    final firstVideoWarmup = firstMedia?.isVideo == true
        ? _preloadedVideoInitializers[firstMedia!.url]?.then((_) {
            final controller = _preloadedVideoControllers[firstMedia.url];
            if (controller?.value.isInitialized == true) {
              controller!
                ..setVolume(1)
                ..play();
            }
          }).catchError((_) {})
        : null;
    _prepareAudioSource();
    final warmupFuture = Future.wait<void>([
      ...imageFutures,
      if (firstVideoWarmup != null) firstVideoWarmup,
    ]);

    await Future.any<void>([
      warmupFuture,
      Future<void>.delayed(const Duration(milliseconds: 1600)),
    ]);

    if (mounted) {
      setState(() => _isPreparingDetail = false);
    }
  }

  Future<void> _prepareAudioSource() async {
    if (_audioUrl.isEmpty) {
      return;
    }
    try {
      await _audioPlayer.setSource(UrlSource(_audioUrl));
      _isAudioSourcePrepared = true;
    } catch (_) {
      _isAudioSourcePrepared = false;
    }
  }

  void _preloadDetailVideos() {
    final mediaItems = mediaItemsFromMap(widget.itemData);
    final firstMedia = mediaItems.isEmpty ? null : mediaItems.first;
    final videos = mediaItems.where((media) => media.isVideo);
    for (final media in videos) {
      if (_preloadedVideoControllers.containsKey(media.url)) {
        continue;
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(media.url));
      _preloadedVideoControllers[media.url] = controller;
      final initializeNow =
          firstMedia?.isVideo == true && firstMedia?.url == media.url;
      final initializer = initializeNow
          ? controller.initialize()
          : Future<void>.delayed(const Duration(milliseconds: 300)).then((
              _,
            ) async {
              if (!mounted) {
                return;
              }
              await controller.initialize();
            });
      _preloadedVideoInitializers[media.url] = initializer.catchError((_) {});
    }
  }

  void _stopDetailPlayback({bool updateUi = true}) {
    _audioCompletionToken++;
    _audioPlayer.stop();
    _pauseDetailVideos();
    if (updateUi && mounted) {
      setState(() {
        _isAudioPlaying = false;
        _showAudioProgress = false;
        _audioPosition = Duration.zero;
      });
    }
  }

  void _pauseDetailVideos() {
    for (final controller in _preloadedVideoControllers.values) {
      if (controller.value.isInitialized) {
        controller
          ..setVolume(0)
          ..pause();
      }
    }
  }

  Future<void> _toggleAudio() async {
    if (_audioUrl.isEmpty) {
      return;
    }
    if (_isAudioPlaying) {
      await _audioPlayer.pause();
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
          _showAudioProgress = false;
        });
      }
      return;
    }
    _audioCompletionToken++;
    if (_isAudioSourcePrepared || _audioPosition > Duration.zero) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.play(UrlSource(_audioUrl));
      _isAudioSourcePrepared = true;
    }
    if (mounted) {
      setState(() {
        _isAudioPlaying = true;
        _showAudioProgress = true;
      });
    }
  }

  Future<void> _launchPhone(String phoneNumber) async {
    final phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    await launchUrl(phoneUri);
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanNumber');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _goToFeed(BuildContext context) async {
    _stopDetailPlayback();
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
    final mediaItems = mediaItemsFromMap(widget.itemData);
    final sellerPhone = widget.itemData['seller_phone']?.toString() ?? '';
    final itemName = widget.itemData['item_name']?.toString().trim() ?? '';
    final isLiveItem = widget.itemData['status']?.toString() == 'live';

    if (_isPreparingDetail) {
      return const _ItemDetailWarmupSkeleton();
    }

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
                    physics: _lockDetailScroll
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    children: [
                      _DetailMediaHeader(
                        mediaItems: mediaItems,
                        preloadedVideoControllers: _preloadedVideoControllers,
                        preloadedVideoInitializers: _preloadedVideoInitializers,
                        itemName: itemName,
                        price: _formatPrice(widget.itemData['item_price']),
                        location: widget.itemData['location']?.toString() ?? '',
                        isLiveItem: isLiveItem,
                        audioUrl: _audioUrl,
                        isAudioPlaying: _isAudioPlaying,
                        showAudioProgress: _showAudioProgress,
                        audioPosition: _audioPosition,
                        audioDuration: _audioDuration,
                        onAudioTap: _toggleAudio,
                        onZoomActiveChanged: (active) {
                          if (_lockDetailScroll == active) {
                            return;
                          }
                          setState(() => _lockDetailScroll = active);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 2),
                            _SellerAvatarIcon(
                              name: widget.itemData['seller_name'],
                              sellerId: widget.itemData['seller_uid'],
                              sellerPhone: widget.itemData['seller_phone'],
                              onOpenProfile: _stopDetailPlayback,
                            ),
                          ],
                        ),
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
                    _stopDetailPlayback();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShareListingPage(
                          itemId: widget.itemId,
                          itemData: widget.itemData,
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
    return '';
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

class _DetailMediaHeader extends StatefulWidget {
  const _DetailMediaHeader({
    required this.mediaItems,
    required this.preloadedVideoControllers,
    required this.preloadedVideoInitializers,
    required this.itemName,
    required this.price,
    required this.location,
    required this.isLiveItem,
    required this.audioUrl,
    required this.isAudioPlaying,
    required this.showAudioProgress,
    required this.audioPosition,
    required this.audioDuration,
    required this.onAudioTap,
    this.onZoomActiveChanged,
  });

  final List<MediaItem> mediaItems;
  final Map<String, VideoPlayerController> preloadedVideoControllers;
  final Map<String, Future<void>> preloadedVideoInitializers;
  final String itemName;
  final String price;
  final String location;
  final bool isLiveItem;
  final String audioUrl;
  final bool isAudioPlaying;
  final bool showAudioProgress;
  final Duration audioPosition;
  final Duration audioDuration;
  final VoidCallback onAudioTap;
  final ValueChanged<bool>? onZoomActiveChanged;

  @override
  State<_DetailMediaHeader> createState() => _DetailMediaHeaderState();
}

class _DetailMediaHeaderState extends State<_DetailMediaHeader> {
  final GlobalKey _mediaKey = GlobalKey();
  late final PageController _pageController;
  final ValueNotifier<int> _pauseSignal = ValueNotifier<int>(0);
  OverlayEntry? _zoomOverlay;
  Rect? _zoomRect;
  Offset _zoomStartFocal = Offset.zero;
  Offset _zoomCurrentFocal = Offset.zero;
  Offset _zoomLocalFocal = Offset.zero;
  MediaItem? _zoomReadyMedia;
  final Set<int> _mediaPointers = <int>{};
  double _zoomScale = 1;
  int _currentIndex = 0;
  bool _isPinchIntent = false;
  bool _isZooming = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _removeZoomOverlay();
    _pauseSignal.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int index) {
    _pauseSignal.value++;
    if (mounted) {
      setState(() => _currentIndex = index);
    } else {
      _currentIndex = index;
    }
  }

  void _handleMediaPointerDown(PointerDownEvent event) {
    _mediaPointers.add(event.pointer);
    if (_mediaPointers.length >= 2 && !_isPinchIntent) {
      setState(() => _isPinchIntent = true);
    }
  }

  void _handleMediaPointerUp(PointerEvent event) {
    _mediaPointers.remove(event.pointer);
    if (_mediaPointers.length < 2 && _isPinchIntent && !_isZooming) {
      setState(() => _isPinchIntent = false);
    }
  }

  void _handleScaleStart(MediaItem media, ScaleStartDetails details) {
    if (media.isVideo || _zoomImageUrl(media).isEmpty || _isZooming) {
      return;
    }
    _prepareZoom(media, details.focalPoint);
  }

  void _handleScaleUpdate(MediaItem media, ScaleUpdateDetails details) {
    if (_zoomReadyMedia?.url != media.url) {
      return;
    }
    _zoomCurrentFocal = details.focalPoint;
    _zoomScale = details.scale.clamp(1.0, 4.0);
    if (!_isZooming) {
      if (details.scale <= 1.01) {
        return;
      }
      _startZoom(media);
    }
    _zoomOverlay?.markNeedsBuild();
  }

  void _handleScaleEnd(MediaItem media) {
    if (_zoomReadyMedia?.url != media.url) {
      return;
    }
    _endZoomInteraction();
  }

  void _prepareZoom(MediaItem media, Offset focalPoint) {
    final context = _mediaKey.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    _zoomRect = topLeft & box.size;
    _zoomStartFocal = focalPoint;
    _zoomCurrentFocal = focalPoint;
    _zoomLocalFocal = focalPoint - topLeft;
    _zoomScale = 1;
    _zoomReadyMedia = media;
  }

  void _startZoom(MediaItem media) {
    if (_zoomRect == null) {
      return;
    }
    _isZooming = true;
    widget.onZoomActiveChanged?.call(true);
    setState(() {});
    _showZoomOverlay(media);
  }

  void _endZoomInteraction() {
    _removeZoomOverlay();
    _mediaPointers.clear();
    widget.onZoomActiveChanged?.call(false);
    if (mounted) {
      setState(() {
        _isZooming = false;
        _isPinchIntent = false;
        _zoomReadyMedia = null;
      });
    }
  }

  void _showZoomOverlay(MediaItem media) {
    _removeZoomOverlay();
    final overlay = Overlay.of(context);
    final imageUrl = _zoomImageUrl(media);
    if (imageUrl.isEmpty) {
      return;
    }
    _zoomOverlay = OverlayEntry(
      builder: (context) {
        final rect = _zoomRect;
        if (rect == null) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                Container(color: Colors.black.withValues(alpha: 0.18)),
                Positioned.fromRect(
                  rect: rect,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translate(
                        _zoomCurrentFocal.dx - _zoomStartFocal.dx,
                        _zoomCurrentFocal.dy - _zoomStartFocal.dy,
                      )
                      ..translate(_zoomLocalFocal.dx, _zoomLocalFocal.dy)
                      ..scale(_zoomScale)
                      ..translate(-_zoomLocalFocal.dx, -_zoomLocalFocal.dy),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: rect.width,
                      height: rect.height,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_zoomOverlay!);
  }

  String _zoomImageUrl(MediaItem media) {
    if (media.isVideo) {
      return media.thumbnailUrl?.trim() ?? '';
    }
    final url = media.url.trim();
    return url.isNotEmpty ? url : media.thumbnailUrl?.trim() ?? '';
  }

  void _removeZoomOverlay() {
    _zoomOverlay?.remove();
    _zoomOverlay = null;
  }

  Widget _buildDetailMediaPage(int index, double mediaHeight) {
    final media = widget.mediaItems[index];
    return _DetailMediaPage(
      media: media,
      height: mediaHeight,
      autoPlay: index == _currentIndex,
      pauseSignal: _pauseSignal,
      preloadedController: widget.preloadedVideoControllers[media.url],
      preloadFuture: widget.preloadedVideoInitializers[media.url],
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedLocation = widget.location.trim();
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.80;
    final imageCount = widget.mediaItems.where((media) => !media.isVideo).length;
    final videoCount = widget.mediaItems.where((media) => media.isVideo).length;
    final hideChrome = _isZooming;
    final lockMediaSwipe = hideChrome || _isPinchIntent;
    return SizedBox(
      height: mediaHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            key: _mediaKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handleMediaPointerDown,
            onPointerUp: _handleMediaPointerUp,
            onPointerCancel: _handleMediaPointerUp,
            child: SizedBox(
              child: widget.mediaItems.length == 1
                  ? _buildDetailMediaPage(0, mediaHeight)
                  : PageView.builder(
                      controller: _pageController,
                      clipBehavior: Clip.none,
                      physics: lockMediaSwipe
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      onPageChanged: _handlePageChanged,
                      itemCount: widget.mediaItems.length,
                      itemBuilder: (context, index) =>
                          _buildDetailMediaPage(index, mediaHeight),
                    ),
            ),
          ),
          if (!hideChrome && (imageCount > 0 || videoCount > 0))
            Positioned(
              left: 10,
              bottom: 16,
              child: Row(
                children: [
                  if (imageCount > 0)
                    _DetailMediaCountBadge(
                      icon: Icons.photo_camera,
                      count: imageCount,
                    ),
                  if (imageCount > 0 && videoCount > 0)
                    const SizedBox(width: 6),
                  if (videoCount > 0)
                    _DetailMediaCountBadge(
                      icon: Icons.videocam,
                      count: videoCount,
                    ),
                ],
              ),
            ),
          if (!hideChrome && widget.isLiveItem)
            const Positioned(
              top: 12,
              right: -72,
              child: IgnorePointer(
                child: _DetailLiveAnimation(),
              ),
            ),
          if (!hideChrome && widget.mediaItems.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: _DetailMediaDots(
                count: widget.mediaItems.length,
                activeIndex: _currentIndex,
              ),
            ),
          if (!hideChrome)
            Positioned(
            left: 14,
            right: 14,
            bottom: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.audioUrl.isNotEmpty) ...[
                  _DetailAudioIconChip(
                    isPlaying: widget.isAudioPlaying,
                    onTap: widget.onAudioTap,
                  ),
                  const SizedBox(height: 6),
                ],
                if (widget.itemName.isNotEmpty) ...[
                  IgnorePointer(
                    child: _DetailOverlayChip(
                      child: Text(
                        widget.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (trimmedLocation.isNotEmpty)
                  IgnorePointer(
                    child: _DetailOverlayChip(
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
                  ),
                if (widget.price.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  IgnorePointer(
                    child: _DetailOverlayChip(
                      child: PriceWithCurrency(
                        price: widget.price,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD00000),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.showAudioProgress && !hideChrome)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DetailAudioTimeline(
                position: widget.audioPosition,
                duration: widget.audioDuration,
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailMediaPage extends StatelessWidget {
  const _DetailMediaPage({
    required this.media,
    required this.height,
    required this.autoPlay,
    required this.pauseSignal,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    this.preloadedController,
    this.preloadFuture,
  });

  final MediaItem media;
  final double height;
  final bool autoPlay;
  final ValueNotifier<int> pauseSignal;
  final VideoPlayerController? preloadedController;
  final Future<void>? preloadFuture;
  final void Function(MediaItem media, ScaleStartDetails details) onScaleStart;
  final void Function(MediaItem media, ScaleUpdateDetails details) onScaleUpdate;
  final void Function(MediaItem media) onScaleEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: media.isVideo
          ? null
          : (details) => onScaleStart(media, details),
      onScaleUpdate: media.isVideo
          ? null
          : (details) => onScaleUpdate(media, details),
      onScaleEnd: media.isVideo ? null : (_) => onScaleEnd(media),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: media.isVideo
            ? VideoPreview(
                url: media.url,
                thumbnailUrl: media.thumbnailUrl,
                fit: BoxFit.cover,
                controller: preloadedController,
                initializeFuture: preloadFuture,
                autoPlay: autoPlay,
                pauseSignal: pauseSignal,
                showPlayButton: false,
                playIconSize: 72,
              )
            : CachedNetworkImage(
                imageUrl: media.url,
                width: double.infinity,
                height: height,
                memCacheWidth: 1200,
                maxWidthDiskCache: 1600,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 1),
                fadeOutDuration: const Duration(milliseconds: 1),
                placeholder: (context, url) => const MediaSkeletonPlaceholder(),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFFDCF8C6),
                  child: const Icon(
                    Icons.broken_image,
                    size: 50,
                    color: Color(0xFF075E54),
                  ),
                ),
              ),
      ),
    );
  }
}

class _DetailMediaCountBadge extends StatelessWidget {
  const _DetailMediaCountBadge({
    required this.icon,
    required this.count,
  });

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 3),
          Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLiveAnimation extends StatelessWidget {
  const _DetailLiveAnimation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 225,
      height: 108,
      child: Lottie.asset(
        'assets/lottie/live2.json',
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
      ),
    );
  }
}

class _DetailMediaDots extends StatelessWidget {
  const _DetailMediaDots({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _DetailAudioTimeline extends StatelessWidget {
  const _DetailAudioTimeline({
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final progress = (position.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      width: double.infinity,
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 4,
        backgroundColor: Colors.black.withValues(alpha: 0.16),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF7801)),
      ),
    );
  }
}

class _DetailAudioIconChip extends StatelessWidget {
  const _DetailAudioIconChip({
    required this.isPlaying,
    required this.onTap,
  });

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const iconSize = 24.0;
    const touchSize = iconSize * 2.5;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: SizedBox(
        width: touchSize,
        height: touchSize,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: IgnorePointer(
            child: _DetailOverlayChip(
              child: Icon(
                isPlaying ? Icons.pause : Icons.volume_up,
                color: const Color(0xFFFF7801),
                size: iconSize,
              ),
            ),
          ),
        ),
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
                        backgroundColor: const Color(0xFFFF7801),
                        foregroundColor: Colors.white,
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
        backgroundColor: const Color(0xFFFF7801),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        side: BorderSide.none,
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
    required this.onOpenProfile,
  });

  final Object? name;
  final Object? sellerId;
  final Object? sellerPhone;
  final VoidCallback onOpenProfile;

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
                    onOpenProfile();
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

class _ItemDetailWarmupSkeleton extends StatelessWidget {
  const _ItemDetailWarmupSkeleton();

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.80;
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF7),
      body: Column(
        children: [
          SizedBox(
            height: mediaHeight,
            child: Stack(
              children: [
                const Positioned.fill(child: MediaSkeletonPlaceholder()),
                Positioned(
                  top: topInset + 12,
                  left: 14,
                  child: const CircleAvatar(
                    radius: 21,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.arrow_back, color: Colors.black),
                  ),
                ),
                const Positioned(
                  left: 14,
                  right: 110,
                  bottom: 48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WarmupChip(width: 42),
                      SizedBox(height: 8),
                      _WarmupChip(width: 150),
                      SizedBox(height: 8),
                      _WarmupChip(width: 118),
                      SizedBox(height: 8),
                      _WarmupChip(width: 130),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 0),
            child: _WarmupChip(width: double.infinity, height: 42),
          ),
        ],
      ),
    );
  }
}

class _WarmupChip extends StatelessWidget {
  const _WarmupChip({required this.width, this.height = 30});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: const MediaSkeletonPlaceholder(),
      ),
    );
  }
}
