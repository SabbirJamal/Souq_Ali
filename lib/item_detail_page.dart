import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final videoFutures = _preloadedVideoInitializers.values;
    final audioFuture = _prepareAudioSource();
    final warmupFuture = Future.wait<void>([
      ...imageFutures,
      ...videoFutures,
      audioFuture,
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
    final videos = mediaItemsFromMap(
      widget.itemData,
    ).where((media) => media.isVideo);
    for (final media in videos) {
      if (_preloadedVideoControllers.containsKey(media.url)) {
        continue;
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(media.url));
      _preloadedVideoControllers[media.url] = controller;
      _preloadedVideoInitializers[media.url] = controller.initialize().catchError(
        (_) {},
      );
    }
  }

  void _stopDetailPlayback({bool updateUi = true}) {
    _audioCompletionToken++;
    _audioPlayer.stop();
    if (updateUi && mounted) {
      setState(() {
        _isAudioPlaying = false;
        _showAudioProgress = false;
        _audioPosition = Duration.zero;
      });
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

  void _openFullscreen(
    BuildContext context,
    List<MediaItem> mediaItems,
    int initialIndex,
    String sellerPhone,
  ) {
    _stopDetailPlayback();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SingleMediaPage(
          mediaItems: mediaItems,
          initialIndex: initialIndex,
          sellerPhone: sellerPhone,
          preloadedVideoControllers: _preloadedVideoControllers,
          preloadedVideoInitializers: _preloadedVideoInitializers,
        ),
      ),
    );
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
                    children: [
                      _DetailMediaHeader(
                        mediaItems: mediaItems,
                        itemName: itemName,
                        price: _formatPrice(widget.itemData['item_price']),
                        location: widget.itemData['location']?.toString() ?? '',
                        audioUrl: _audioUrl,
                        isAudioPlaying: _isAudioPlaying,
                        showAudioProgress: _showAudioProgress,
                        audioPosition: _audioPosition,
                        audioDuration: _audioDuration,
                        onAudioTap: _toggleAudio,
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

class _DetailMediaHeader extends StatelessWidget {
  const _DetailMediaHeader({
    required this.mediaItems,
    required this.itemName,
    required this.price,
    required this.location,
    required this.audioUrl,
    required this.isAudioPlaying,
    required this.showAudioProgress,
    required this.audioPosition,
    required this.audioDuration,
    required this.onAudioTap,
    required this.onMediaTap,
  });

  final List<MediaItem> mediaItems;
  final String itemName;
  final String price;
  final String location;
  final String audioUrl;
  final bool isAudioPlaying;
  final bool showAudioProgress;
  final Duration audioPosition;
  final Duration audioDuration;
  final VoidCallback onAudioTap;
  final void Function(MediaItem media, int index) onMediaTap;

  @override
  Widget build(BuildContext context) {
    final trimmedLocation = location.trim();
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.80;
    return SizedBox(
      height: mediaHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaCarousel(
            mediaItems: mediaItems,
            height: mediaHeight,
            borderRadius: 0,
            fit: BoxFit.cover,
            showCountBadge: true,
            showPageDots: true,
            onMediaTap: onMediaTap,
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (audioUrl.isNotEmpty) ...[
                  _DetailOverlayChip(
                    child: GestureDetector(
                      onTap: onAudioTap,
                      child: Icon(
                        isAudioPlaying ? Icons.pause : Icons.volume_up,
                        color: const Color(0xFFFF7801),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (itemName.isNotEmpty) ...[
                  _DetailOverlayChip(
                    child: Text(
                      itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (trimmedLocation.isNotEmpty)
                  _DetailOverlayChip(
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
                if (price.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _DetailOverlayChip(
                    child: PriceWithCurrency(
                      price: price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD00000),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showAudioProgress)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DetailAudioTimeline(
                position: audioPosition,
                duration: audioDuration,
              ),
            ),
        ],
      ),
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

class _SingleMediaPage extends StatefulWidget {
  const _SingleMediaPage({
    required this.mediaItems,
    required this.initialIndex,
    required this.sellerPhone,
    required this.preloadedVideoControllers,
    required this.preloadedVideoInitializers,
  });

  final List<MediaItem> mediaItems;
  final int initialIndex;
  final String sellerPhone;
  final Map<String, VideoPlayerController> preloadedVideoControllers;
  final Map<String, Future<void>> preloadedVideoInitializers;

  @override
  State<_SingleMediaPage> createState() => _SingleMediaPageState();
}

class _SingleMediaPageState extends State<_SingleMediaPage> {
  late final PageController _pageController;
  final ValueNotifier<int> _pauseSignal = ValueNotifier<int>(0);
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
    _pauseActiveVideo();
    _pauseSignal.dispose();
    _pageController.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _pauseActiveVideo() {
    _pauseSignal.value++;
  }

  void _close() {
    _pauseActiveVideo();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mediaTopPadding = MediaQuery.paddingOf(context).top + 74;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _pauseActiveVideo(),
      child: Scaffold(
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
                          _pauseActiveVideo();
                          setState(() => _currentIndex = index);
                        },
                        itemCount: widget.mediaItems.length,
                        itemBuilder: (context, index) {
                          return _FullscreenMediaView(
                            media: widget.mediaItems[index],
                            allowZoom: true,
                            fit: BoxFit.contain,
                            pauseSignal: _pauseSignal,
                            preloadedController:
                                widget.preloadedVideoControllers[
                                  widget.mediaItems[index].url
                                ],
                            preloadFuture: widget.preloadedVideoInitializers[
                              widget.mediaItems[index].url
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                _FullscreenContactBar(sellerPhone: widget.sellerPhone),
              ],
            ),
            _FullscreenHeader(onBack: _close),
            _MediaPositionCounter(
              currentIndex: _currentIndex,
              totalCount: widget.mediaItems.length,
            ),
          ],
        ),
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
    required this.pauseSignal,
    required this.preloadedController,
    required this.preloadFuture,
    this.fit = BoxFit.contain,
  });

  final MediaItem media;
  final bool allowZoom;
  final ValueListenable<int> pauseSignal;
  final VideoPlayerController? preloadedController;
  final Future<void>? preloadFuture;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return SizedBox.expand(
        child: VideoPreview(
          url: media.url,
          thumbnailUrl: media.thumbnailUrl,
          fit: fit,
          pauseSignal: pauseSignal,
          controller: preloadedController,
          initializeFuture: preloadFuture,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final image = CachedNetworkImage(
          imageUrl: media.url,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          memCacheWidth: 1400,
          maxWidthDiskCache: 1800,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 1),
          fadeOutDuration: const Duration(milliseconds: 1),
          placeholder: (context, url) => const MediaSkeletonPlaceholder(
            baseColor: Color(0xFF202421),
            highlightColor: Color(0xFF333A35),
          ),
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
                  onPressed: sellerPhone.isEmpty
                      ? null
                      : () => _launchWhatsApp(sellerPhone),
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
                  onPressed: () {},
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
                      color: Colors.white,
                    ),
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
