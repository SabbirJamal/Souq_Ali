import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'detail_video_player.dart';
import '../media_carousel.dart';
import '../price_with_currency.dart';

class DetailMediaHeader extends StatefulWidget {
  const DetailMediaHeader({
    super.key,
    required this.mediaItems,
    required this.preloadedVideoControllers,
    required this.preloadedVideoInitializers,
    required this.itemName,
    required this.price,
    required this.location,
    required this.isLiveItem,
    required this.isTransitItem,
    this.onZoomActiveChanged,
  });

  final List<MediaItem> mediaItems;
  final Map<String, VideoPlayerController> preloadedVideoControllers;
  final Map<String, Future<void>> preloadedVideoInitializers;
  final String itemName;
  final String price;
  final String location;
  final bool isLiveItem;
  final bool isTransitItem;
  final ValueChanged<bool>? onZoomActiveChanged;

  @override
  State<DetailMediaHeader> createState() => _DetailMediaHeaderState();
}

class _DetailMediaHeaderState extends State<DetailMediaHeader> {
  final GlobalKey _mediaKey = GlobalKey();
  late final PageController _pageController;
  final ValueNotifier<int> _pauseSignal = ValueNotifier<int>(0);
  final Map<String, Size> _imageSizes = {};
  final Set<String> _pendingImageSizeUrls = <String>{};
  OverlayEntry? _zoomOverlay;
  Rect? _zoomRect;
  Offset _zoomStartFocal = Offset.zero;
  Offset _zoomCurrentFocal = Offset.zero;
  Offset _zoomLocalFocal = Offset.zero;
  MediaItem? _zoomReadyMedia;
  final Set<int> _mediaPointers = <int>{};
  final Set<String> _pausedVideoUrls = <String>{};
  Offset? _mediaSwipeStart;
  Offset _mediaSwipeDelta = Offset.zero;
  double _zoomScale = 1;
  double _inlineVideoScale = 1;
  int _mediaSwipeStartIndex = 0;
  int _currentIndex = 0;
  bool _isPinchIntent = false;
  bool _isHoldingMedia = false;
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
    if (_mediaPointers.length == 1 && widget.mediaItems.length > 1) {
      _mediaSwipeStart = event.position;
      _mediaSwipeDelta = Offset.zero;
      _mediaSwipeStartIndex = _currentIndex;
    }
    if (_mediaPointers.length >= 2 && !_isPinchIntent) {
      setState(() => _isPinchIntent = true);
      widget.onZoomActiveChanged?.call(true);
    }
  }

  void _handleMediaPointerMove(PointerMoveEvent event) {
    final start = _mediaSwipeStart;
    if (start == null || _mediaPointers.length != 1) return;
    _mediaSwipeDelta = event.position - start;
  }

  void _handleMediaPointerUp(PointerEvent event) {
    _handleLooseHorizontalSwipe();
    _mediaPointers.remove(event.pointer);
    if (_mediaPointers.isEmpty) {
      _mediaSwipeStart = null;
      _mediaSwipeDelta = Offset.zero;
    }
    if (_mediaPointers.length < 2 && _isPinchIntent && !_isZooming) {
      setState(() => _isPinchIntent = false);
      if (!_isHoldingMedia) widget.onZoomActiveChanged?.call(false);
    }
  }

  void _handleLooseHorizontalSwipe() {
    if (widget.mediaItems.length < 2 ||
        _isZooming ||
        _isPinchIntent ||
        _isHoldingMedia ||
        _currentIndex != _mediaSwipeStartIndex ||
        !_pageController.hasClients) {
      return;
    }
    final dx = _mediaSwipeDelta.dx;
    final dy = _mediaSwipeDelta.dy.abs();
    if (dx.abs() < 42 || dx.abs() < dy * 0.45) return;

    final page = _pageController.page;
    if (page != null && (page - _currentIndex).abs() > 0.08) return;

    final nextIndex = dx < 0 ? _currentIndex + 1 : _currentIndex - 1;
    if (nextIndex < 0 || nextIndex >= widget.mediaItems.length) return;
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScaleStart(MediaItem media, ScaleStartDetails details) {
    if (_isZooming) {
      return;
    }
    if (media.isVideo) {
      if (!_isPinchIntent) {
        setState(() => _isPinchIntent = true);
        widget.onZoomActiveChanged?.call(true);
      }
      return;
    }
    if (_zoomImageUrl(media).isEmpty) return;
    _prepareZoom(media, details.focalPoint);
  }

  void _handleScaleUpdate(MediaItem media, ScaleUpdateDetails details) {
    if (media.isVideo) {
      final nextScale = details.scale.clamp(1.0, 4.0);
      if (details.pointerCount < 2 && nextScale <= 1.002) return;
      if (!_isPinchIntent) widget.onZoomActiveChanged?.call(true);
      if (mounted) {
        setState(() {
          _isPinchIntent = true;
          _inlineVideoScale = nextScale;
        });
      }
      return;
    }
    if (_zoomReadyMedia?.url != media.url) {
      return;
    }
    _zoomCurrentFocal = details.focalPoint;
    _zoomScale = details.scale.clamp(1.0, 4.0);
    if (!_isZooming) {
      if (details.pointerCount < 2 || details.scale <= 1.002) {
        return;
      }
      _startZoom(media);
    }
    _zoomOverlay?.markNeedsBuild();
  }

  void _handleScaleEnd(MediaItem media) {
    if (media.isVideo) {
      if (!_isHoldingMedia) widget.onZoomActiveChanged?.call(false);
      if (mounted) {
        setState(() {
          _isPinchIntent = false;
          _inlineVideoScale = 1;
        });
      }
      return;
    }
    if (_zoomReadyMedia?.url != media.url) {
      return;
    }
    _endZoomInteraction();
  }

  void _handleMediaHoldStart() {
    if (_isHoldingMedia) return;
    setState(() => _isHoldingMedia = true);
    widget.onZoomActiveChanged?.call(true);
  }

  void _handleMediaHoldEnd() {
    if (!_isHoldingMedia) return;
    setState(() => _isHoldingMedia = false);
    if (!_isZooming && !_isPinchIntent) widget.onZoomActiveChanged?.call(false);
  }

  void _handleVideoTap(MediaItem media) {
    if (!media.isVideo) return;
    final controller = widget.preloadedVideoControllers[media.url];
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _pausedVideoUrls.add(media.url);
      } else {
        controller.setVolume(1);
        controller.play();
        _pausedVideoUrls.remove(media.url);
      }
    });
  }

  void _prepareZoom(MediaItem media, Offset focalPoint) {
    final context = _mediaKey.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    final displayRect = _containedDisplayRect(media, topLeft, box.size);
    _zoomRect = displayRect;
    _zoomStartFocal = focalPoint;
    _zoomCurrentFocal = focalPoint;
    _zoomLocalFocal = focalPoint - displayRect.topLeft;
    _zoomScale = 1;
    _zoomReadyMedia = media;
  }

  Rect _containedDisplayRect(MediaItem media, Offset topLeft, Size frameSize) {
    final sourceSize = _sourceSizeFor(media);
    if (sourceSize == null || sourceSize.isEmpty || frameSize.isEmpty) {
      return topLeft & frameSize;
    }

    final fitted = applyBoxFit(BoxFit.contain, sourceSize, frameSize);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & frameSize,
    );
    return destination.shift(topLeft);
  }

  Size? _sourceSizeFor(MediaItem media) {
    if (media.isVideo) {
      final controller = widget.preloadedVideoControllers[media.url];
      final size = controller?.value.size;
      return size == null || size.isEmpty ? null : size;
    }
    return _imageSizes[media.url];
  }

  void _rememberImageSize(String url, ImageProvider provider) {
    if (_imageSizes.containsKey(url) || !_pendingImageSizeUrls.add(url)) return;
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      _imageSizes[url] = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
    }, onError: (_, _) {
      stream.removeListener(listener);
      _pendingImageSizeUrls.remove(url);
    });
    stream.addListener(listener);
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
                      fit: BoxFit.contain,
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
    if (!media.isVideo) {
      final provider = CachedNetworkImageProvider(media.url);
      _rememberImageSize(media.url, provider);
    }
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
      onHoldStart: _handleMediaHoldStart,
      onHoldEnd: _handleMediaHoldEnd,
      onVideoTap: _handleVideoTap,
      videoScale: media.isVideo && index == _currentIndex ? _inlineVideoScale : 1,
      showVideoPauseIcon: media.isVideo && _pausedVideoUrls.contains(media.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedLocation = _displayLocation(widget.location.trim());
    // Use screen percentage for media header height
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.8;
    final imageCount = widget.mediaItems.where((media) => !media.isVideo).length;
    final videoCount = widget.mediaItems.where((media) => media.isVideo).length;
    final hideChrome = _isZooming || _isPinchIntent || _isHoldingMedia;
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
            onPointerMove: _handleMediaPointerMove,
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
              right: 14,
              child: IgnorePointer(
                child: _DetailLiveBadge(),
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
                if (trimmedLocation.isNotEmpty) ...[
                  IgnorePointer(
                    child: _DetailOverlayChip(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Text(widget.isTransitItem ? '🚚' : '📍', style: const TextStyle(fontSize: 15)),
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
                  if (widget.price.isNotEmpty || widget.itemName.isNotEmpty)
                    const SizedBox(height: 6),
                ],
                if (widget.price.isNotEmpty) ...[
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
                  if (widget.itemName.isNotEmpty) const SizedBox(height: 6),
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
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayLocation(String location) {
    if (!widget.isTransitItem) return location;
    final text = location.replaceFirst(RegExp(r'^[🚚📍\s]+'), '').trim();
    return text.isEmpty ? 'Transit' : text;
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
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onVideoTap,
    required this.videoScale,
    required this.showVideoPauseIcon,
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
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final void Function(MediaItem media) onVideoTap;
  final double videoScale;
  final bool showVideoPauseIcon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: media.isVideo ? () => onVideoTap(media) : null,
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldEnd,
      onScaleStart: (details) => onScaleStart(media, details),
      onScaleUpdate: (details) => onScaleUpdate(media, details),
      onScaleEnd: (_) => onScaleEnd(media),
      child: ColoredBox(
        color: Colors.black,
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              media.isVideo
                  ? DetailVideoPlayer(
                      url: media.url,
                      videoScale: videoScale,
                      autoPlay: autoPlay,
                      pauseSignal: pauseSignal,
                      showPauseIcon: showVideoPauseIcon,
                      controller: preloadedController,
                      initializeFuture: preloadFuture,
                    )
                  : CachedNetworkImage(
                      imageUrl: media.url,
                      width: double.infinity,
                      height: height,
                      memCacheWidth: 1200,
                      maxWidthDiskCache: 1600,
                      fit: BoxFit.contain,
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
            ],
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

class _DetailLiveBadge extends StatelessWidget {
  const _DetailLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE92808),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors, color: Colors.white, size: 21),
          SizedBox(width: 7),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
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
