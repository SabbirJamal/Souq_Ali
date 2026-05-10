import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'item_detail_page.dart';

class StoryVideo {
  const StoryVideo({
    required this.url,
    required this.itemId,
    required this.itemName,
    required this.itemPrice,
    required this.sellerName,
    required this.sellerPhone,
    this.itemData,
  });

  final String url;
  final String itemId;
  final String itemName;
  final String itemPrice;
  final String sellerName;
  final String sellerPhone;
  final Map<String, dynamic>? itemData;

  StoryVideo copyWith({String? itemName, String? itemPrice}) {
    return StoryVideo(
      url: url,
      itemId: itemId,
      itemName: itemName ?? this.itemName,
      itemPrice: itemPrice ?? this.itemPrice,
      sellerName: sellerName,
      sellerPhone: sellerPhone,
      itemData: itemData,
    );
  }
}

class StorySeller {
  const StorySeller({required this.sellerName, required this.videos});

  final String sellerName;
  final List<StoryVideo> videos;
}

class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.stories,
    required this.initialStoryIndex,
    this.showCloseButton = true,
    this.popOnComplete = true,
  });

  final List<StorySeller> stories;
  final int initialStoryIndex;
  final bool showCloseButton;
  final bool popOnComplete;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  late final PageController _pageController;
  late int _currentStoryIndex;

  @override
  void initState() {
    super.initState();
    _currentStoryIndex = widget.initialStoryIndex;
    _pageController = PageController(initialPage: widget.initialStoryIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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

  void _goNext() {
    if (_currentStoryIndex >= widget.stories.length - 1) {
      if (widget.popOnComplete && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.stories.length,
        onPageChanged: (index) => setState(() => _currentStoryIndex = index),
        itemBuilder: (context, index) {
          final sellerStory = widget.stories[index];
          return _SellerStoryPage(
            key: ValueKey(sellerStory.sellerName),
            videos: sellerStory.videos,
            onFinished: _goNext,
            onCall: (phone) => _launchPhone(phone),
            onWhatsApp: (phone) => _launchWhatsApp(phone),
            showCloseButton: widget.showCloseButton,
          );
        },
      ),
    );
  }
}

class _SellerStoryPage extends StatefulWidget {
  const _SellerStoryPage({
    super.key,
    required this.videos,
    required this.onFinished,
    required this.onCall,
    required this.onWhatsApp,
    required this.showCloseButton,
  });

  final List<StoryVideo> videos;
  final VoidCallback onFinished;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onWhatsApp;
  final bool showCloseButton;

  @override
  State<_SellerStoryPage> createState() => _SellerStoryPageState();
}

class _SellerStoryPageState extends State<_SellerStoryPage> {
  late final PageController _videoController;
  int _currentVideoIndex = 0;

  @override
  void initState() {
    super.initState();
    _videoController = PageController();
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  void _goNextVideo() {
    if (_currentVideoIndex >= widget.videos.length - 1) {
      widget.onFinished();
      return;
    }
    _videoController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _videoController,
      itemCount: widget.videos.length,
      onPageChanged: (index) => setState(() => _currentVideoIndex = index),
      itemBuilder: (context, index) {
        final story = widget.videos[index];
        return _StoryVideoPage(
          key: ValueKey(story.url),
          story: story,
          onFinished: _goNextVideo,
          onCall: () => widget.onCall(story.sellerPhone),
          onWhatsApp: () => widget.onWhatsApp(story.sellerPhone),
          showCloseButton: widget.showCloseButton,
        );
      },
    );
  }
}

class _StoryVideoPage extends StatefulWidget {
  const _StoryVideoPage({
    super.key,
    required this.story,
    required this.onFinished,
    required this.onCall,
    required this.onWhatsApp,
    required this.showCloseButton,
  });

  final StoryVideo story;
  final VoidCallback onFinished;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final bool showCloseButton;

  @override
  State<_StoryVideoPage> createState() => _StoryVideoPageState();
}

class _StoryVideoPageState extends State<_StoryVideoPage> {
  late final VideoPlayerController _controller;
  bool _isReady = false;
  bool _hasError = false;
  bool _didFinish = false;
  bool _isPressPaused = false;
  bool _isTapPaused = false;
  bool _showPauseIcon = false;
  DateTime? _pressStartedAt;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.story.url))
      ..initialize()
          .then((_) {
            if (!mounted) {
              return;
            }
            setState(() => _isReady = true);
            _controller.play();
          })
          .catchError((_) {
            if (!mounted) {
              return;
            }
            setState(() => _hasError = true);
          });
    _controller.addListener(_handleProgress);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleProgress);
    _controller.dispose();
    super.dispose();
  }

  void _handleProgress() {
    if (!_controller.value.isInitialized || _didFinish) {
      return;
    }

    final position = _controller.value.position;
    final duration = _controller.value.duration;
    if (duration.inMilliseconds > 0) {
      final nextProgress =
          position.inMilliseconds / duration.inMilliseconds;
      if ((nextProgress - _progress).abs() >= 0.01 && mounted) {
        setState(() => _progress = nextProgress.clamp(0, 1));
      }
    }

    if (duration.inMilliseconds > 0 &&
        position >= duration - const Duration(milliseconds: 250)) {
      _didFinish = true;
      if (mounted) {
        setState(() => _progress = 1);
      }
      widget.onFinished();
    }
  }

  void _handlePointerDown() {
    if (!_controller.value.isInitialized || _didFinish) {
      return;
    }
    _pressStartedAt = DateTime.now();
    if (_controller.value.isPlaying) {
      _isPressPaused = true;
      _controller.pause();
      if (mounted) {
        setState(() => _showPauseIcon = true);
      }
    }
  }

  void _handlePointerUp() {
    if (!_controller.value.isInitialized || _didFinish) {
      _clearPressState();
      return;
    }

    final startedAt = _pressStartedAt;
    final pressDuration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    final isTap = pressDuration < const Duration(milliseconds: 280);

    if (isTap) {
      _isTapPaused = !_isTapPaused;
      _isPressPaused = false;
      if (_isTapPaused) {
        _controller.pause();
        setState(() => _showPauseIcon = true);
      } else {
        _controller.play();
        setState(() => _showPauseIcon = false);
      }
      _pressStartedAt = null;
      return;
    }

    if (_isPressPaused && !_isTapPaused) {
      _controller.play();
      if (mounted) {
        setState(() => _showPauseIcon = false);
      }
    }
    _clearPressState();
  }

  void _handlePointerCancel() {
    if (_isPressPaused &&
        !_isTapPaused &&
        _controller.value.isInitialized &&
        !_didFinish) {
      _controller.play();
      if (mounted) {
        setState(() => _showPauseIcon = false);
      }
    }
    _clearPressState();
  }

  void _clearPressState() {
    _isPressPaused = false;
    _pressStartedAt = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handlePointerDown(),
      onPointerUp: (_) => _handlePointerUp(),
      onPointerCancel: (_) => _handlePointerCancel(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_hasError)
            _UnavailableStory(onNext: widget.onFinished)
          else if (_isReady)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 14,
            right: 14,
            top: 8,
            child: SafeArea(
              child: _StoryProgressBar(progress: _progress),
            ),
          ),
          if (_showPauseIcon && _isReady && !_hasError)
            Center(
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pause,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          if (widget.showCloseButton)
            Positioned(
              left: 8,
              top: 8,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.24),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 84,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StoryActionButton(
                    icon:
                        const Icon(Icons.phone, color: Colors.white, size: 27),
                    backgroundColor: const Color(0xFF0A84FF),
                    onTap: widget.onCall,
                  ),
                  const SizedBox(height: 14),
                  _StoryActionButton(
                    icon: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Colors.white,
                      size: 27,
                    ),
                    backgroundColor: const Color(0xFF25D366),
                    onTap: widget.onWhatsApp,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 94,
            child: SafeArea(
              child: _StoryItemInfo(
                story: widget.story,
                onBeforeOpen: () => _controller.pause(),
                onAfterReturn: () {
                  if (mounted &&
                      _controller.value.isInitialized &&
                      !_didFinish) {
                    _controller.play();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryItemInfo extends StatelessWidget {
  const _StoryItemInfo({
    required this.story,
    required this.onBeforeOpen,
    required this.onAfterReturn,
  });

  final StoryVideo story;
  final VoidCallback onBeforeOpen;
  final VoidCallback onAfterReturn;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: story.itemData == null || story.itemId.isEmpty
          ? null
          : () async {
              onBeforeOpen();
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailPage(
                    itemData: story.itemData!,
                    itemId: story.itemId,
                  ),
                ),
              );
              onAfterReturn();
            },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              story.itemName,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (story.itemPrice.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                story.itemPrice,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFD8D8),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoryProgressBar extends StatelessWidget {
  const _StoryProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 2.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.white.withValues(alpha: 0.35)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0, 1),
              child: Container(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableStory extends StatelessWidget {
  const _UnavailableStory({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, color: Colors.white70, size: 52),
          const SizedBox(height: 12),
          const Text(
            'Video unavailable',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onNext,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _StoryActionButton extends StatelessWidget {
  const _StoryActionButton({
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
  });

  final Widget icon;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      elevation: 5,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: icon),
        ),
      ),
    );
  }
}
