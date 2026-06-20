import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'utils/formatters.dart';
import 'widgets/app_toast.dart';
import 'widgets/media_carousel.dart';
import 'widgets/price_with_currency.dart';

class ShareListingPage extends StatefulWidget {
  const ShareListingPage({
    super.key,
    required this.itemId,
    required this.itemData,
    required this.mediaItems,
  });

  final String itemId;
  final Map<String, dynamic> itemData;
  final List<MediaItem> mediaItems;

  @override
  State<ShareListingPage> createState() => _ShareListingPageState();
}

class _ShareListingPageState extends State<ShareListingPage> {
  static const _directShareChannel = MethodChannel('com.bizsooq.app/direct_share');
  static const _whatsAppPackage = 'com.whatsapp';
  static const _whatsAppBusinessPackage = 'com.whatsapp.w4b';

  final GlobalKey _previewKey = GlobalKey();
  bool _isSharing = false;

  String get _itemName => widget.itemData['item_name']?.toString() ?? 'Item';

  String get _itemPrice => widget.itemData['item_price']?.toString() ?? '';

  String get _shareLink => 'https://souqali.app/listing/${widget.itemId}';

  String get _shareText {
    final price = _itemPrice.trim();
    return price.isEmpty
        ? 'Check this listing: $_itemName\n$_shareLink'
        : 'Check this listing: $_itemName - $price\n$_shareLink';
  }

  String get _previewImageUrl {
    if (widget.mediaItems.isEmpty) return '';
    final media = widget.mediaItems.first;
    if (media.isVideo) {
      return media.thumbnailUrl?.trim() ?? '';
    }
    return media.url.trim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final url = _previewImageUrl;
    if (url.isNotEmpty) {
      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  Future<File?> _capturePreviewFile() async {
    final url = _previewImageUrl;
    if (url.isNotEmpty) {
      await precacheImage(CachedNetworkImageProvider(url), context);
    }
    await WidgetsBinding.instance.endOfFrame;
    final previewContext = _previewKey.currentContext;
    final renderObject = previewContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final image = await renderObject.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bizsooq_${widget.itemId}_share.png');
    return file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  Future<void> _sharePreviewImage({
    String? androidPackage,
    required String appName,
  }) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final file = await _capturePreviewFile();
      if (file == null) {
        if (mounted) AppToast.show(context, 'Unable to prepare image');
        return;
      }
      if (Platform.isAndroid && androidPackage != null) {
        await _directShareChannel.invokeMethod<bool>('shareImageToPackage', {
          'filePath': file.path,
          'packageName': androidPackage,
          'text': _shareText,
        });
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: _shareText,
            files: [XFile(file.path, mimeType: 'image/png')],
          ),
        );
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'not_installed') {
        AppToast.show(context, '$appName is not installed');
      } else {
        AppToast.show(context, 'Unable to share image');
      }
    } catch (_) {
      if (mounted) AppToast.show(context, 'Unable to share image');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareLink));
    if (!mounted) return;
    AppToast.show(context, 'Link copied');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    'Share this listing',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    RepaintBoundary(
                      key: _previewKey,
                      child: _ShareItemCardPreview(
                        item: widget.itemData,
                        mediaItems: widget.mediaItems,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _ShareActions(
                      isSharing: _isSharing,
                      onShareWhatsApp: () => _sharePreviewImage(
                        androidPackage: _whatsAppPackage,
                        appName: 'WhatsApp',
                      ),
                      onShareWhatsAppBusiness: () => _sharePreviewImage(
                        androidPackage: _whatsAppBusinessPackage,
                        appName: 'WhatsApp Business',
                      ),
                      onCopyLink: _copyLink,
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareItemCardPreview extends StatelessWidget {
  const _ShareItemCardPreview({
    required this.item,
    required this.mediaItems,
  });

  final Map<String, dynamic> item;
  final List<MediaItem> mediaItems;

  @override
  Widget build(BuildContext context) {
    const width = 260.0;
    const height = 390.0;
    final firstMedia = mediaItems.isEmpty ? null : mediaItems.first;
    final imageCount = mediaItems.where((media) => !media.isVideo).length;
    final videoCount = mediaItems.where((media) => media.isVideo).length;
    final isLiveItem = item['status']?.toString() == 'live';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Positioned.fill(child: _ShareMediaBackground(media: firstMedia)),
              Positioned(
                top: 10,
                left: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShareMediaCountBadges(
                      imageCount: imageCount,
                      videoCount: videoCount,
                    ),
                    if (isLiveItem) ...[
                      const SizedBox(height: 7),
                      const _ShareLiveBadge(),
                    ],
                  ],
                ),
              ),
              if (!isLiveItem)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _ShareUploadedAgoBadge(
                    uploadedAgo: _uploadedAgo(item['created_at']),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: _ShareCardDetails(item: item),
              ),
            ],
          ),
        ),
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

    if (uploadedAt == null) return 'just now';
    final difference = DateTime.now().difference(uploadedAt);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hrs ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    if (difference.inDays < 30) return '${difference.inDays ~/ 7} weeks ago';
    return '${difference.inDays ~/ 30} months ago';
  }
}

class _ShareMediaBackground extends StatelessWidget {
  const _ShareMediaBackground({required this.media});

  final MediaItem? media;

  @override
  Widget build(BuildContext context) {
    final media = this.media;
    final imageUrl = media?.isVideo == true
        ? (media?.thumbnailUrl?.trim().isNotEmpty == true
            ? media!.thumbnailUrl!.trim()
            : '')
        : media?.url.trim() ?? '';

    if (imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFFECECEC),
        child: const Center(
          child: Icon(Icons.image_not_supported, color: Colors.grey, size: 46),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 800,
      maxWidthDiskCache: 1000,
      placeholder: (_, _) => Container(color: const Color(0xFFECECEC)),
      errorWidget: (_, _, _) => Container(
        color: const Color(0xFFECECEC),
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.grey, size: 46),
        ),
      ),
    );
  }
}

class _ShareCardDetails extends StatelessWidget {
  const _ShareCardDetails({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final itemName = item['item_name']?.toString().trim() ?? '';
    final isTransit = item['is_transit'] == true;
    final rawLocation = item['location']?.toString().trim() ?? '';
    final location = _displayLocation(rawLocation, isTransit);
    final price = isTransit ? '' : formatPrice(item['item_price']);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (location.isNotEmpty)
          _ShareTextChip(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isTransit ? '🚚' : '📍', style: const TextStyle(fontSize: 17)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (price.isNotEmpty) ...[
          const SizedBox(height: 7),
          _ShareTextChip(
            child: PriceWithCurrency(
              price: price,
              style: const TextStyle(
                color: Color(0xFFD00000),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        if (itemName.isNotEmpty) ...[
          const SizedBox(height: 7),
          _ShareTextChip(
            child: Text(
              itemName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _displayLocation(String location, bool isTransit) {
    if (!isTransit) return location;
    final text = location.replaceFirst(RegExp(r'^[🚚📍\s]+'), '').trim();
    return text.isEmpty ? 'Transit' : text;
  }
}

class _ShareTextChip extends StatelessWidget {
  const _ShareTextChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _ShareMediaCountBadges extends StatelessWidget {
  const _ShareMediaCountBadges({
    required this.imageCount,
    required this.videoCount,
  });

  final int imageCount;
  final int videoCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageCount > 0)
          _ShareTopBadge(icon: Icons.photo_camera, count: imageCount),
        if (imageCount > 0 && videoCount > 0) const SizedBox(width: 5),
        if (videoCount > 0)
          _ShareTopBadge(icon: Icons.videocam, count: videoCount),
      ],
    );
  }
}

class _ShareTopBadge extends StatelessWidget {
  const _ShareTopBadge({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareLiveBadge extends StatelessWidget {
  const _ShareLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 27,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFE92808),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors, color: Colors.white, size: 16),
          SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareUploadedAgoBadge extends StatelessWidget {
  const _ShareUploadedAgoBadge({required this.uploadedAgo});

  final String uploadedAgo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        uploadedAgo,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ShareActions extends StatelessWidget {
  const _ShareActions({
    required this.isSharing,
    required this.onShareWhatsApp,
    required this.onShareWhatsAppBusiness,
    required this.onCopyLink,
  });

  final bool isSharing;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onShareWhatsAppBusiness;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ShareActionData(
        label: 'WhatsApp',
        icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white),
        color: const Color(0xFF5DD95D),
        onTap: onShareWhatsApp,
      ),
      _ShareActionData(
        label: 'WhatsApp Business',
        icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white),
        color: const Color(0xFF25D366),
        onTap: onShareWhatsAppBusiness,
      ),
      _ShareActionData(
        label: 'Copy link',
        icon: const Icon(Icons.copy, color: Colors.black),
        color: Colors.white,
        hasBorder: true,
        onTap: onCopyLink,
      ),
    ];

    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                SizedBox(width: 82, child: _ShareAction(action: actions[i])),
                if (i != actions.length - 1) const SizedBox(width: 18),
              ],
            ],
          ),
        ),
        if (isSharing)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ),
      ],
    );
  }
}

class _ShareActionData {
  const _ShareActionData({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.hasBorder = false,
  });

  final String label;
  final Widget icon;
  final Color color;
  final VoidCallback onTap;
  final bool hasBorder;
}

class _ShareAction extends StatelessWidget {
  const _ShareAction({required this.action});

  final _ShareActionData action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: action.color,
              shape: BoxShape.circle,
              border: action.hasBorder
                  ? Border.all(color: const Color(0xFFE0E0E0))
                  : null,
            ),
            child: Center(child: action.icon),
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, height: 1.1),
          ),
        ],
      ),
    );
  }
}
