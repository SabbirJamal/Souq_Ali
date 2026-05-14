import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _isCollage = true;
  int _selectedImageIndex = 0;

  List<String> get _imageUrls => widget.mediaItems
      .where((media) => !media.isVideo)
      .map((media) => media.url)
      .toList(growable: false);

  String get _itemName => widget.itemData['item_name']?.toString() ?? 'Item';

  String get _itemPrice => widget.itemData['item_price']?.toString() ?? '';

  String get _shareLink => 'https://souqali.app/listing/${widget.itemId}';

  String get _shareText {
    final price = _itemPrice.trim();
    return price.isEmpty
        ? 'Check this listing: $_itemName\n$_shareLink'
        : 'Check this listing: $_itemName - $price\n$_shareLink';
  }

  Future<void> _shareToWhatsApp() async {
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _shareToSms() async {
    await launchUrl(Uri(scheme: 'sms', queryParameters: {'body': _shareText}));
  }

  Future<void> _shareToEmail() async {
    await launchUrl(
      Uri(
        scheme: 'mailto',
        queryParameters: {'subject': _itemName, 'body': _shareText},
      ),
    );
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareLink));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label sharing will be added next')));
  }

  @override
  Widget build(BuildContext context) {
    final imageUrls = _imageUrls;

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
            const SizedBox(height: 4),
            _ModeSelector(
              isCollage: _isCollage,
              onCollageTap: () => setState(() => _isCollage = true),
              onSingleTap: () => setState(() => _isCollage = false),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _isCollage
                          ? _CollagePreview(
                              key: const ValueKey('collage'),
                              imageUrls: imageUrls.take(5).toList(),
                              itemName: _itemName,
                              itemPrice: _itemPrice,
                            )
                          : _SinglePicturePreview(
                              key: const ValueKey('single'),
                              imageUrls: imageUrls,
                              itemName: _itemName,
                              itemPrice: _itemPrice,
                              selectedIndex: _selectedImageIndex,
                              onChanged: (index) {
                                setState(() => _selectedImageIndex = index);
                              },
                            ),
                    ),
                    const SizedBox(height: 26),
                    _ShareActions(
                      onWhatsApp: _shareToWhatsApp,
                      onInstagram: () => _showComingSoon('Instagram'),
                      onX: () => _showComingSoon('X'),
                      onFacebook: () => _showComingSoon('Facebook'),
                      onMessenger: () => _showComingSoon('Messenger'),
                      onTikTok: () => _showComingSoon('TikTok'),
                      onSms: _shareToSms,
                      onEmail: _shareToEmail,
                      onDownload: () => _showComingSoon('Download'),
                      onCopyLink: _copyLink,
                      onOthers: () => _showComingSoon('More'),
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

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.isCollage,
    required this.onCollageTap,
    required this.onSingleTap,
  });

  final bool isCollage;
  final VoidCallback onCollageTap;
  final VoidCallback onSingleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeButton(label: 'Collage', isSelected: isCollage, onTap: onCollageTap),
        const SizedBox(width: 8),
        _ModeButton(
          label: 'Single Picture',
          isSelected: !isCollage,
          onTap: onSingleTap,
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        side: BorderSide(
          color: isSelected ? const Color(0xFF0A84FF) : const Color(0xFFE2E2E2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

class _CollagePreview extends StatelessWidget {
  const _CollagePreview({
    super.key,
    required this.imageUrls,
    required this.itemName,
    required this.itemPrice,
  });

  final List<String> imageUrls;
  final String itemName;
  final String itemPrice;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E1E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 176,
            child: imageUrls.isEmpty
                ? const _EmptyPreview()
                : GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: imageUrls.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 1,
                          mainAxisSpacing: 1,
                        ),
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: imageUrls[index],
                        fit: BoxFit.cover,
                      );
                    },
                  ),
          ),
          _PreviewCaption(itemName: itemName, itemPrice: itemPrice),
        ],
      ),
    );
  }
}

class _SinglePicturePreview extends StatelessWidget {
  const _SinglePicturePreview({
    super.key,
    required this.imageUrls,
    required this.itemName,
    required this.itemPrice,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> imageUrls;
  final String itemName;
  final String itemPrice;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox(width: 210, height: 260, child: _EmptyPreview());
    }

    return SizedBox(
      height: 290,
      child: PageView.builder(
        controller: PageController(
          viewportFraction: 0.58,
          initialPage: selectedIndex.clamp(0, imageUrls.length - 1),
        ),
        itemCount: imageUrls.length,
        onPageChanged: onChanged,
        itemBuilder: (context, index) {
          final isSelected = selectedIndex == index;
          return AnimatedScale(
            scale: isSelected ? 1 : 0.92,
            duration: const Duration(milliseconds: 180),
            child: Opacity(
              opacity: isSelected ? 1 : 0.48,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE1E1E1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        child: CachedNetworkImage(
                          imageUrl: imageUrls[index],
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    _PreviewCaption(itemName: itemName, itemPrice: itemPrice),
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

class _PreviewCaption extends StatelessWidget {
  const _PreviewCaption({required this.itemName, required this.itemPrice});

  final String itemName;
  final String itemPrice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            itemName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (itemPrice.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            PriceWithCurrency(
              price: itemPrice,
              style: const TextStyle(
                color: Color(0xFFD00000),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F4F4),
      child: const Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey, size: 42),
      ),
    );
  }
}

class _ShareActions extends StatelessWidget {
  const _ShareActions({
    required this.onWhatsApp,
    required this.onInstagram,
    required this.onX,
    required this.onFacebook,
    required this.onMessenger,
    required this.onTikTok,
    required this.onSms,
    required this.onEmail,
    required this.onDownload,
    required this.onCopyLink,
    required this.onOthers,
  });

  final VoidCallback onWhatsApp;
  final VoidCallback onInstagram;
  final VoidCallback onX;
  final VoidCallback onFacebook;
  final VoidCallback onMessenger;
  final VoidCallback onTikTok;
  final VoidCallback onSms;
  final VoidCallback onEmail;
  final VoidCallback onDownload;
  final VoidCallback onCopyLink;
  final VoidCallback onOthers;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ShareActionData(
        label: 'Whatsapp',
        icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white),
        color: const Color(0xFF5DD95D),
        onTap: onWhatsApp,
      ),
      _ShareActionData(
        label: 'WhatsAp...',
        icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white),
        color: const Color(0xFF5DD95D),
        onTap: onWhatsApp,
      ),
      _ShareActionData(
        label: 'Instagram',
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        color: const Color(0xFFE4405F),
        onTap: onInstagram,
      ),
      _ShareActionData(
        label: 'X',
        icon: const FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white),
        color: Colors.black,
        onTap: onX,
      ),
      _ShareActionData(
        label: 'Facebook',
        icon: const FaIcon(FontAwesomeIcons.facebookF, color: Colors.white),
        color: const Color(0xFF4267B2),
        onTap: onFacebook,
      ),
      _ShareActionData(
        label: 'Messenger',
        icon: const Icon(Icons.messenger, color: Colors.white),
        color: const Color(0xFF8C5CF6),
        onTap: onMessenger,
      ),
      _ShareActionData(
        label: 'TikTok',
        icon: const FaIcon(FontAwesomeIcons.tiktok, color: Colors.white),
        color: Colors.black,
        onTap: onTikTok,
      ),
      _ShareActionData(
        label: 'SMS',
        icon: const Icon(Icons.sms, color: Colors.white),
        color: const Color(0xFF4D86C8),
        onTap: onSms,
      ),
      _ShareActionData(
        label: 'Email',
        icon: const Icon(Icons.email, color: Colors.white),
        color: const Color(0xFF8B20B8),
        onTap: onEmail,
      ),
      _ShareActionData(
        label: 'Download',
        icon: const Icon(Icons.file_download_outlined, color: Colors.black),
        color: Colors.white,
        hasBorder: true,
        onTap: onDownload,
      ),
      _ShareActionData(
        label: 'Copy link',
        icon: const Icon(Icons.copy, color: Colors.black),
        color: Colors.white,
        hasBorder: true,
        onTap: onCopyLink,
      ),
      _ShareActionData(
        label: 'Others',
        icon: const Icon(Icons.more_vert, color: Colors.black),
        color: Colors.white,
        hasBorder: true,
        onTap: onOthers,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (context, index) => _ShareAction(action: actions[index]),
      ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
