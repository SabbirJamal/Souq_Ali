import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaItem {
  const MediaItem({required this.url, required this.type, this.thumbnailUrl});

  final String url;
  final String type;
  final String? thumbnailUrl;

  bool get isVideo => type == 'video';
}

List<MediaItem> mediaItemsFromMap(Map<String, dynamic> item) {
  final mediaFiles = item['media_files'];
  if (mediaFiles is List && mediaFiles.isNotEmpty) {
    return mediaFiles
        .whereType<Map>()
        .map((media) {
          final data = Map<String, dynamic>.from(media);
          return MediaItem(
            url: data['url']?.toString() ?? '',
            type: data['type']?.toString() ?? 'image',
            thumbnailUrl: data['thumbnail_url']?.toString(),
          );
        })
        .where((media) => media.url.isNotEmpty)
        .toList();
  }

  final imageUrls = List<String>.from(item['image_urls'] ?? []);
  return imageUrls
      .map((url) => MediaItem(url: url, type: 'image'))
      .where((media) => media.url.isNotEmpty)
      .toList();
}

class MediaCarousel extends StatefulWidget {
  const MediaCarousel({
    super.key,
    required this.mediaItems,
    this.height = 280,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
    this.showCountBadge = true,
    this.showPageDots = false,
    this.peekSideItems = false,
    this.onMediaTap,
  });

  final List<MediaItem> mediaItems;
  final double height;
  final double borderRadius;
  final BoxFit fit;
  final bool showCountBadge;
  final bool showPageDots;
  final bool peekSideItems;
  final void Function(MediaItem media, int index)? onMediaTap;

  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class MediaPreview extends StatelessWidget {
  const MediaPreview({
    super.key,
    required this.media,
    required this.height,
    this.borderRadius = 0,
    this.fit = BoxFit.cover,
  });

  final MediaItem? media;
  final double height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final currentMedia = media;
    if (currentMedia == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: double.infinity,
          height: height,
          color: const Color(0xFFDCF8C6),
          child: const Icon(Icons.image, size: 50, color: Color(0xFF075E54)),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: currentMedia.isVideo
            ? _VideoThumbnailPreview(
                thumbnailUrl: currentMedia.thumbnailUrl,
                height: height,
                fit: fit,
              )
            : CachedNetworkImage(
                imageUrl: currentMedia.url,
                width: double.infinity,
                height: height,
                memCacheWidth: 720,
                maxWidthDiskCache: 1080,
                fit: fit,
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (context, url) => const _MediaLoadingPlaceholder(),
                errorWidget: (context, url, error) =>
                    const _MediaErrorPlaceholder(),
              ),
      ),
    );
  }
}

class _VideoThumbnailPreview extends StatelessWidget {
  const _VideoThumbnailPreview({
    required this.thumbnailUrl,
    required this.height,
    required this.fit,
  });

  final String? thumbnailUrl;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = thumbnailUrl?.trim() ?? '';
    final Widget preview = url.isEmpty
        ? Container(
            color: Colors.black,
            child: const Icon(
              Icons.videocam,
              color: Colors.white,
              size: 50,
            ),
          )
        : CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            height: height,
            memCacheWidth: 720,
            maxWidthDiskCache: 1080,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (context, url) => const _MediaLoadingPlaceholder(),
            errorWidget: (context, url, error) => Container(
              color: Colors.black,
              child: const Icon(
                Icons.videocam,
                color: Colors.white,
                size: 50,
              ),
            ),
          );

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaCarouselState extends State<MediaCarousel> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.peekSideItems ? 0.985 : 1,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.mediaItems.where((media) => !media.isVideo).length;
    final videoCount = widget.mediaItems.where((media) => media.isVideo).length;

    if (widget.mediaItems.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Container(
          width: double.infinity,
          height: widget.height,
          color: const Color(0xFFDCF8C6),
          child: const Icon(Icons.image, size: 50, color: Color(0xFF075E54)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: widget.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  clipBehavior: widget.peekSideItems ? Clip.none : Clip.hardEdge,
                  padEnds: false,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemCount: widget.mediaItems.length,
                  itemBuilder: (context, index) {
                    final media = widget.mediaItems[index];
                    final isFirst = index == 0;
                    final isLast = index == widget.mediaItems.length - 1;
                    final edgePadding = widget.peekSideItems
                        ? EdgeInsets.only(
                            left: isFirst ? 0 : 3,
                            right: isLast ? 0 : 3,
                          )
                        : EdgeInsets.zero;
                    return RepaintBoundary(
                      child: Padding(
                        padding: edgePadding,
                        child: GestureDetector(
                          onTap: widget.onMediaTap == null
                              ? null
                              : () => widget.onMediaTap!(media, index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              widget.borderRadius,
                            ),
                            child: media.isVideo
                                ? VideoPreview(url: media.url, fit: widget.fit)
                                : CachedNetworkImage(
                                    imageUrl: media.url,
                                    width: double.infinity,
                                    height: widget.height,
                                    memCacheWidth: 1200,
                                    maxWidthDiskCache: 1600,
                                    fit: widget.fit,
                                    fadeInDuration: const Duration(
                                      milliseconds: 120,
                                    ),
                                    placeholder: (context, url) =>
                                        const _MediaLoadingPlaceholder(),
                                    errorWidget: (context, url, error) =>
                                        const _MediaErrorPlaceholder(),
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.showCountBadge && (imageCount > 0 || videoCount > 0))
                Positioned(
                  left: widget.peekSideItems ? 28 : 10,
                  bottom: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (imageCount > 0)
                        _MediaCountBadge(
                          icon: Icons.photo_camera,
                          count: imageCount,
                        ),
                      if (imageCount > 0 && videoCount > 0)
                        const SizedBox(width: 6),
                      if (videoCount > 0)
                        _MediaCountBadge(icon: Icons.videocam, count: videoCount),
                    ],
                  ),
                ),
              if (widget.showPageDots && widget.mediaItems.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: _MediaPageDots(
                    count: widget.mediaItems.length,
                    currentIndex: _currentIndex,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MediaPageDots extends StatelessWidget {
  const _MediaPageDots({required this.count, required this.currentIndex});

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (index) {
            final isActive = index == currentIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: isActive ? 14 : 7,
              height: isActive ? 14 : 7,
              margin: EdgeInsets.symmetric(horizontal: isActive ? 3 : 5),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.42),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _MediaCountBadge extends StatelessWidget {
  const _MediaCountBadge({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaLoadingPlaceholder extends StatelessWidget {
  const _MediaLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const MediaSkeletonPlaceholder();
  }
}

class _MediaErrorPlaceholder extends StatelessWidget {
  const _MediaErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFDCF8C6),
      child: const Icon(Icons.broken_image, size: 50, color: Color(0xFF075E54)),
    );
  }
}

class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late final VideoPlayerController _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() => _isReady = true);
      });
  }

  @override
  void deactivate() {
    _controller.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const MediaSkeletonPlaceholder(baseColor: Color(0xFF202421));
    }

    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            color: Colors.black,
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          ),
          IconButton.filled(
            onPressed: () {
              setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              });
            },
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
          ),
        ],
      ),
    );
  }
}

class MediaSkeletonPlaceholder extends StatefulWidget {
  const MediaSkeletonPlaceholder({
    super.key,
    this.baseColor = const Color(0xFFE9EFEB),
    this.highlightColor = const Color(0xFFF8FBF9),
  });

  final Color baseColor;
  final Color highlightColor;

  @override
  State<MediaSkeletonPlaceholder> createState() =>
      _MediaSkeletonPlaceholderState();
}

class _MediaSkeletonPlaceholderState extends State<MediaSkeletonPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.0 + value * 2.4, -0.8),
                end: Alignment(-0.2 + value * 2.4, 0.8),
                colors: [
                  widget.baseColor,
                  widget.highlightColor,
                  widget.baseColor,
                ],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          ),
        );
      },
    );
  }
}
