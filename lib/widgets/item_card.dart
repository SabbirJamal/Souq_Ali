import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../item_detail_page.dart';
import 'media_carousel.dart';
import 'price_with_currency.dart';

class ItemCard extends StatefulWidget {
  const ItemCard({
    super.key,
    required this.docId,
    required this.item,
    this.isCompact = false,
  });

  final String docId;
  final Map<String, dynamic> item;
  final bool isCompact;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

final ValueNotifier<String?> _activeFeedAudioItemId = ValueNotifier(null);

class _ItemCardState extends State<ItemCard> with SingleTickerProviderStateMixin {
  late final AudioPlayer _audioPlayer;
  late final TransformationController _mediaZoomController;
  late final AnimationController _mediaZoomResetController;
  Animation<Matrix4>? _mediaZoomResetAnimation;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _isAudioPlaying = false;
  bool _showAudioProgress = false;
  bool _hasLoadedAudioSource = false;
  int _audioCompletionToken = 0;

  String get _audioUrl =>
      widget.item['audio_description_url']?.toString().trim() ?? '';

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _mediaZoomController = TransformationController();
    _mediaZoomResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _mediaZoomResetAnimation;
        if (animation != null) {
          _mediaZoomController.value = animation.value;
        }
      });
    _activeFeedAudioItemId.addListener(_pauseIfAnotherAudioStarts);
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
            _hasLoadedAudioSource = false;
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _activeFeedAudioItemId.removeListener(_pauseIfAnotherAudioStarts);
    _mediaZoomResetController.dispose();
    _mediaZoomController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pauseIfAnotherAudioStarts() async {
    if (_activeFeedAudioItemId.value == widget.docId || !_isAudioPlaying) {
      return;
    }
    await _audioPlayer.pause();
    if (mounted) {
      setState(() {
        _isAudioPlaying = false;
        _showAudioProgress = false;
      });
    }
  }

  void _resetMediaZoom() {
    _mediaZoomResetController.stop();
    _mediaZoomResetAnimation = Matrix4Tween(
      begin: _mediaZoomController.value,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(
        parent: _mediaZoomResetController,
        curve: Curves.easeOutCubic,
      ),
    );
    _mediaZoomResetController.forward(from: 0);
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
    _activeFeedAudioItemId.value = widget.docId;
    if (_hasLoadedAudioSource && _audioPosition > Duration.zero) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.play(UrlSource(_audioUrl));
      _hasLoadedAudioSource = true;
    }
    if (mounted) {
      setState(() {
        _isAudioPlaying = true;
        _showAudioProgress = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaItems = mediaItemsFromMap(widget.item);
    final uploadedAgo = _uploadedAgo(widget.item['created_at']);
    final imageCount = mediaItems.where((media) => !media.isVideo).length;
    final videoCount = mediaItems.where((media) => media.isVideo).length;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailPage(
                    itemData: widget.item,
                    itemId: widget.docId,
                  ),
                ),
              );
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardHeight = widget.isCompact
                    ? (constraints.maxWidth * 1.48).clamp(245.0, 310.0)
                    : (constraints.maxWidth * 1.36).clamp(445.0, 595.0);

                return Card(
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.18),
                  color: Colors.white,
                  margin: EdgeInsets.only(bottom: widget.isCompact ? 6 : 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    height: cardHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRect(
                            child: InteractiveViewer(
                              transformationController: _mediaZoomController,
                              minScale: 1,
                              maxScale: 3,
                              panEnabled: false,
                              clipBehavior: Clip.hardEdge,
                              onInteractionStart: (_) {
                                _mediaZoomResetController.stop();
                              },
                              onInteractionEnd: (_) => _resetMediaZoom(),
                              child: MediaPreview(
                                media: mediaItems.isEmpty
                                    ? null
                                    : mediaItems.first,
                                height: cardHeight,
                                borderRadius: 0,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: widget.isCompact ? 7 : 10,
                          left: widget.isCompact ? 7 : 10,
                          child: _MediaCountBadges(
                            imageCount: imageCount,
                            videoCount: videoCount,
                            isCompact: widget.isCompact,
                          ),
                        ),
                        Positioned(
                          top: widget.isCompact ? 7 : 10,
                          right: widget.isCompact ? 7 : 10,
                          child: _UploadedAgoBadge(
                            uploadedAgo: uploadedAgo,
                            isCompact: widget.isCompact,
                          ),
                        ),
                        Positioned(
                          left: widget.isCompact ? 8 : 14,
                          right: widget.isCompact ? 8 : 14,
                          bottom: widget.isCompact ? 10 : 18,
                          child: _ImageFilledDetails(
                            item: widget.item,
                            isCompact: widget.isCompact,
                            hasAudio: _audioUrl.isNotEmpty,
                            isAudioPlaying: _isAudioPlaying,
                            onAudioTap: _toggleAudio,
                          ),
                        ),
                        if (_showAudioProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _AudioTimeline(
                              position: _audioPosition,
                              duration: _audioDuration,
                              isCompact: widget.isCompact,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _uploadedAgo(Object? value) {
    DateTime? uploadedAt;
    if (value is Timestamp) {
      uploadedAt = value.toDate();
    } else if (value is DateTime) {
      uploadedAt = value;
    }

    if (uploadedAt == null) {
      return 'just now';
    }

    final difference = DateTime.now().difference(uploadedAt);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} hrs ago';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    }
    if (difference.inDays < 30) {
      return '${difference.inDays ~/ 7} weeks ago';
    }
    return '${difference.inDays ~/ 30} months ago';
  }
}

class ItemCardSkeleton extends StatelessWidget {
  const ItemCardSkeleton({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = isCompact
            ? (constraints.maxWidth * 1.48).clamp(245.0, 310.0)
            : (constraints.maxWidth * 1.36).clamp(445.0, 595.0);

        return RepaintBoundary(
          child: Card(
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            color: Colors.white,
            margin: EdgeInsets.only(bottom: isCompact ? 6 : 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: cardHeight,
              child: Stack(
                children: [
                  const Positioned.fill(child: MediaSkeletonPlaceholder()),
                  Positioned(
                    left: isCompact ? 8 : 14,
                    bottom: isCompact ? 10 : 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SkeletonChip(width: isCompact ? 76 : 118),
                        SizedBox(height: isCompact ? 5 : 8),
                        _SkeletonChip(width: isCompact ? 94 : 150),
                        SizedBox(height: isCompact ? 7 : 12),
                        _SkeletonChip(width: isCompact ? 64 : 110),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonChip extends StatelessWidget {
  const _SkeletonChip({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: 28,
        child: const MediaSkeletonPlaceholder(),
      ),
    );
  }
}

class _ImageFilledDetails extends StatelessWidget {
  const _ImageFilledDetails({
    required this.item,
    required this.isCompact,
    required this.hasAudio,
    required this.isAudioPlaying,
    required this.onAudioTap,
  });

  final Map<String, dynamic> item;
  final bool isCompact;
  final bool hasAudio;
  final bool isAudioPlaying;
  final VoidCallback onAudioTap;

  @override
  Widget build(BuildContext context) {
    final itemName = item['item_name']?.toString().trim() ?? '';

    return IntrinsicWidth(
      stepWidth: 1,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAudio) ...[
              _AudioIconChip(
                isPlaying: isAudioPlaying,
                isCompact: isCompact,
                onTap: onAudioTap,
              ),
              SizedBox(height: isCompact ? 5 : 8),
            ],
            _TextChip(
              child: _OverlayInfoRow(
                text: item['location']?.toString() ?? '',
                isCompact: isCompact,
              ),
              isCompact: isCompact,
            ),
            SizedBox(height: isCompact ? 5 : 8),
            _TextChip(
              child: PriceWithCurrency(
                price: _formatPrice(item['item_price']),
                style: TextStyle(
                  color: const Color(0xFFD00000),
                  fontSize: isCompact ? 13 : 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              isCompact: isCompact,
            ),
            if (itemName.isNotEmpty) ...[
              SizedBox(height: isCompact ? 5 : 8),
              _TextChip(
                child: Text(
                  itemName,
                  maxLines: isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: isCompact ? 14 : 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                isCompact: isCompact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AudioIconChip extends StatelessWidget {
  const _AudioIconChip({
    required this.isPlaying,
    required this.isCompact,
    required this.onTap,
  });

  final bool isPlaying;
  final bool isCompact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = isCompact ? 18.0 : 24.0;
    final touchSize = iconSize * 2.5;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: SizedBox(
      width: touchSize,
      height: touchSize,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: IgnorePointer(
            child: _TextChip(
                isCompact: isCompact,
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

class _AudioTimeline extends StatelessWidget {
  const _AudioTimeline({
    required this.position,
    required this.duration,
    required this.isCompact,
  });

  final Duration position;
  final Duration duration;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final progress = (position.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      width: double.infinity,
      child: LinearProgressIndicator(
        value: progress,
        minHeight: isCompact ? 3 : 4,
        backgroundColor: Colors.black.withValues(alpha: 0.16),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF7801)),
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

class _TextChip extends StatelessWidget {
  const _TextChip({required this.child, required this.isCompact});

  final Widget child;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 9,
        vertical: isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _OverlayInfoRow extends StatelessWidget {
  const _OverlayInfoRow({required this.text, required this.isCompact});

  final String text;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('📍', style: TextStyle(fontSize: isCompact ? 13 : 20)),
        SizedBox(width: isCompact ? 4 : 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.black,
              fontSize: isCompact ? 13 : 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaCountBadges extends StatelessWidget {
  const _MediaCountBadges({
    required this.imageCount,
    required this.videoCount,
    required this.isCompact,
  });

  final int imageCount;
  final int videoCount;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageCount > 0)
          _TopMediaBadge(
            icon: Icons.photo_camera,
            count: imageCount,
            isCompact: isCompact,
          ),
        if (imageCount > 0 && videoCount > 0) SizedBox(width: isCompact ? 4 : 8),
        if (videoCount > 0)
          _TopMediaBadge(
            icon: Icons.videocam,
            count: videoCount,
            isCompact: isCompact,
          ),
      ],
    );
  }
}

class _TopMediaBadge extends StatelessWidget {
  const _TopMediaBadge({
    required this.icon,
    required this.count,
    required this.isCompact,
  });

  final IconData icon;
  final int count;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 10,
        vertical: isCompact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: isCompact ? 13 : 20),
          SizedBox(width: isCompact ? 3 : 5),
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white,
              fontSize: isCompact ? 12 : 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadedAgoBadge extends StatelessWidget {
  const _UploadedAgoBadge({
    required this.uploadedAgo,
    required this.isCompact,
  });

  final String uploadedAgo;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        uploadedAgo,
        style: TextStyle(
          color: Colors.white,
          fontSize: isCompact ? 10 : 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
