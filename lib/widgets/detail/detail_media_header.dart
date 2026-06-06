import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';

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
    required this.audioUrl,
    required this.isAudioPlaying,
    required this.showAudioProgress,
    required this.audioPositionNotifier,
    required this.audioDurationNotifier,
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
  final ValueNotifier<Duration> audioPositionNotifier;
  final ValueNotifier<Duration> audioDurationNotifier;
  final VoidCallback onAudioTap;
  final ValueChanged<bool>? onZoomActiveChanged;

  @override
  State<DetailMediaHeader> createState() => _DetailMediaHeaderState();
}

class _DetailMediaHeaderState extends State<DetailMediaHeader> {
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
      widget.onZoomActiveChanged?.call(true);
    }
  }

  void _handleMediaPointerUp(PointerEvent event) {
    _mediaPointers.remove(event.pointer);
    if (_mediaPointers.length < 2 && _isPinchIntent && !_isZooming) {
      setState(() => _isPinchIntent = false);
      widget.onZoomActiveChanged?.call(false);
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
      if (details.pointerCount < 2 || details.scale <= 1.002) {
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
    // Use screen percentage for media header height
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.72;
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
              child: ValueListenableBuilder<Duration>(
                valueListenable: widget.audioPositionNotifier,
                builder: (context, position, _) {
                  return ValueListenableBuilder<Duration>(
                    valueListenable: widget.audioDurationNotifier,
                    builder: (context, duration, _) {
                      return _DetailAudioTimeline(
                        position: position,
                        duration: duration,
                      );
                    },
                  );
                },
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
