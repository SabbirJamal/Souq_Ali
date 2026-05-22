import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'camera_capture_page.dart';
import 'story_repository.dart';
import 'widgets/media_carousel.dart';
import 'widgets/price_with_currency.dart';

class ItemEditPage extends StatefulWidget {
  const ItemEditPage({super.key, required this.docId, required this.itemData});

  final String docId;
  final Map<String, dynamic> itemData;

  @override
  State<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends State<ItemEditPage> {
  static const _maxMediaCount = 9;
  static const _maxPriceValue = 1000000.0;

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;
  final _priceFocusNode = FocusNode();

  final _picker = ImagePicker();
  late final List<MediaItem> _existingMedia;
  final List<MediaItem> _removedMedia = [];
  final List<_SelectedMedia> _newMedia = [];
  final _priceUnits = ['/ kg', '/ box', '/ bag'];

  String _lastValidPriceText = '';
  late String _priceUnit;
  bool _isSaving = false;
  bool _showLocationError = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.itemData['item_name'] ?? '',
    );
    _priceController = TextEditingController(
      text: _formatEditingPrice(widget.itemData['price_number']?.toString() ?? ''),
    );
    _lastValidPriceText = _priceController.text;
    _locationController = TextEditingController(
      text: widget.itemData['location'] ?? '',
    );
    _existingMedia = mediaItemsFromMap(widget.itemData);
    _priceUnit = _priceUnits.contains(widget.itemData['price_unit'])
        ? widget.itemData['price_unit'].toString()
        : '/ kg';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _priceFocusNode.dispose();
    _locationController.dispose();
    VideoCompress.cancelCompression();
    super.dispose();
  }

  Future<void> _openCamera() async {
    final remaining =
        _maxMediaCount - (_existingMedia.length + _newMedia.length);
    if (remaining <= 0) {
      _showMessage('Maximum $_maxMediaCount media files allowed');
      return;
    }

    final captured = await Navigator.push<CapturedMedia>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCapturePage()),
    );
    if (captured == null) {
      return;
    }

    setState(() {
      _newMedia.add(_SelectedMedia(file: captured.file, type: captured.type));
      _sortNewMedia();
    });
  }

  Future<void> _openMediaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111614),
      shape: const RoundedRectangleBorder(),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Row(
              children: [
                Expanded(
                  child: _MediaSheetButton(
                    icon: Icons.photo_camera,
                    label: 'Camera',
                    onTap: () async {
                      Navigator.pop(context);
                      await _openCamera();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MediaSheetButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickGalleryMedia();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickGalleryMedia() async {
    final remaining =
        _maxMediaCount - (_existingMedia.length + _newMedia.length);
    if (remaining <= 0) {
      _showMessage('Maximum $_maxMediaCount media files allowed');
      return;
    }

    final files = await _picker.pickMultipleMedia(
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
      limit: remaining,
    );
    if (files.isEmpty) {
      return;
    }

    setState(() {
      _newMedia.addAll(
        files.take(remaining).map((file) => _SelectedMedia.fromXFile(file)),
      );
      _sortNewMedia();
    });
  }

  void _sortNewMedia() {
    _newMedia.sort((first, second) {
      if (first.isVideo == second.isVideo) {
        return 0;
      }
      return first.isVideo ? 1 : -1;
    });
  }

  bool _canRemoveMedia() {
    if (_existingMedia.length + _newMedia.length <= 1) {
      _showMessage('Atleast 1 media is required');
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = _priceController.text.trim().isEmpty
        ? '0'
        : _priceController.text.trim();
    final location = _locationController.text.trim();

    if (location.isEmpty) {
      setState(() => _showLocationError = true);
      return;
    }
    final normalizedPrice = _normalizePrice(price);
    if (normalizedPrice == null) {
      _showMessage('Maximum price is 1,000,000.000');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final formattedPrice = _formatPriceWithCommas(normalizedPrice);
      final sellerUid = widget.itemData['seller_uid'];
      if (sellerUid == null || sellerUid.toString().isEmpty) {
        _showMessage('Please login again');
        return;
      }

      final uploadedMedia = await _uploadNewMedia(sellerUid.toString());
      final allMedia = [..._existingMedia, ...uploadedMedia];
      final imageUrls = allMedia
          .where((media) => !media.isVideo)
          .map((media) => media.url)
          .toList();
      final videoUrls = allMedia
          .where((media) => media.isVideo)
          .map((media) => media.url)
          .toList();

      await FirebaseFirestore.instance
          .collection('items')
          .doc(widget.docId)
          .update({
            'item_name': name,
            'origin': FieldValue.delete(),
            'quantity_number': FieldValue.delete(),
            'item_quantity': FieldValue.delete(),
            'weight_unit': FieldValue.delete(),
            'price_number': normalizedPrice,
            'price_unit': _priceUnit,
            'item_price': 'OMR $formattedPrice $_priceUnit',
            'location': location,
            'media_files': allMedia
                .map((media) => {'url': media.url, 'type': media.type})
                .toList(),
            'image_urls': imageUrls,
            'updated_at': FieldValue.serverTimestamp(),
          });

      await const StoryRepository().replaceItemVideos(
        sellerId: sellerUid.toString(),
        sellerName: widget.itemData['seller_name']?.toString() ?? 'Seller',
        sellerPhone: widget.itemData['seller_phone']?.toString() ?? '',
        itemId: widget.docId,
        itemName: name,
        itemPrice: 'OMR $formattedPrice $_priceUnit',
        videoUrls: videoUrls,
      );

      await _deleteRemovedStorageFiles();

      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      _showMessage('Item updated');
    } on FirebaseException catch (error) {
      _showMessage('Error: ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('Error: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<List<MediaItem>> _uploadNewMedia(String sellerUid) async {
    final uploaded = <MediaItem>[];
    for (var i = 0; i < _newMedia.length; i++) {
      final media = _newMedia[i];
      final compressed = media.isVideo
          ? await _compressVideo(media.file)
          : await _compressImage(media.file);
      final extension = media.isVideo ? 'mp4' : 'jpg';
      final contentType = media.isVideo ? 'video/mp4' : 'image/jpeg';
      final fileName = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'items/$sellerUid/${fileName}_edit_$i.$extension',
      );

      final snapshot = await ref.putFile(
        compressed,
        SettableMetadata(contentType: contentType),
      );
      uploaded.add(
        MediaItem(url: await snapshot.ref.getDownloadURL(), type: media.type),
      );
    }
    return uploaded;
  }

  Future<File> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      minWidth: 1280,
      minHeight: 1280,
      quality: 45,
      format: CompressFormat.jpeg,
    );
    return result == null ? file : File(result.path);
  }

  Future<File> _compressVideo(File file) async {
    final info = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.LowQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    final compressedPath = info?.path;
    return compressedPath == null || compressedPath.isEmpty
        ? file
        : File(compressedPath);
  }

  Future<void> _deleteRemovedStorageFiles() async {
    for (final media in _removedMedia) {
      try {
        await FirebaseStorage.instance.refFromURL(media.url).delete();
      } catch (_) {
        // The Firestore update is the source of truth; missing old files are safe.
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handlePriceChanged(String value) {
    final rawValue = value.trim().replaceAll(',', '');
    final dotCount = '.'.allMatches(rawValue).length;
    if (dotCount > 1) {
      _showMessage('Invalid price');
      _setPriceText(_lastValidPriceText);
      return;
    }

    var nextValue = rawValue;
    if (nextValue.startsWith('.')) {
      nextValue = '0$nextValue';
    }
    if (nextValue.length > 1 &&
        nextValue.startsWith('0') &&
        !nextValue.startsWith('0.')) {
      nextValue = nextValue.replaceFirst(RegExp(r'^0+'), '');
      if (nextValue.isEmpty || nextValue.startsWith('.')) {
        nextValue = '0$nextValue';
      }
    }

    if (nextValue.isEmpty || _isValidPriceInput(nextValue)) {
      final parsed = double.tryParse(nextValue);
      if (parsed != null && parsed > _maxPriceValue) {
        _showMessage('Maximum price is 1,000,000.000');
        _setPriceText(_lastValidPriceText);
        return;
      }
      final formatted = _formatEditingPrice(nextValue);
      _lastValidPriceText = formatted;
      if (formatted != value) {
        _setPriceText(formatted);
      }
    } else {
      _showMessage('Invalid price');
      _setPriceText(_lastValidPriceText);
    }
  }

  void _setPriceText(String value) {
    _priceController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _restoreDefaultPriceIfEmpty() {
    if (_priceController.text.trim().isEmpty) {
      _lastValidPriceText = '0';
      _setPriceText('0');
    }
  }

  bool _isValidPriceInput(String value) {
    return RegExp(r'^\d+\.?\d*$').hasMatch(value.replaceAll(',', ''));
  }

  String? _normalizePrice(String value) {
    final cleanValue = value.replaceAll(',', '');
    if (!_isValidPriceInput(cleanValue)) {
      return null;
    }
    final parsed = double.tryParse(cleanValue);
    if (parsed == null || parsed > _maxPriceValue) {
      return null;
    }
    return parsed.toStringAsFixed(3);
  }

  String _formatEditingPrice(String value) {
    final cleanValue = value.replaceAll(',', '');
    if (cleanValue.isEmpty) {
      return '';
    }
    final parts = cleanValue.split('.');
    final whole = _formatWholeNumber(parts.first);
    if (cleanValue.endsWith('.')) {
      return '$whole.';
    }
    if (parts.length == 2) {
      return '$whole.${parts.last}';
    }
    return whole;
  }

  String _formatPriceWithCommas(String value) {
    final parts = value.split('.');
    final whole = _formatWholeNumber(parts.first);
    return '$whole.${parts.length > 1 ? parts.last : '000'}';
  }

  String _formatWholeNumber(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return '0';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final reverseIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4FBF7),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          _buildMediaEditor(),
          const SizedBox(height: 20),
          _field(
            _nameController,
            'Item Name',
            Icons.shopping_bag,
            hint: 'Fresh Tomatoes',
            maxLength: 80,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _field(
                  _priceController,
                  'Price',
                  null,
                  hint: '2.500',
                  prefixIconWidget: const Padding(
                    padding: EdgeInsets.all(12),
                    child: RiyalCurrencyIcon(size: 22),
                  ),
                  focusNode: _priceFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onTap: () {
                    if (_priceController.text == '0') {
                      _setPriceText('');
                    }
                  },
                  onEditingComplete: _restoreDefaultPriceIfEmpty,
                  onTapOutside: (_) => _restoreDefaultPriceIfEmpty(),
                  onChanged: _handlePriceChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _buildDropdown(
                  value: _priceUnit,
                  items: _priceUnits,
                  onChanged: (value) => setState(() => _priceUnit = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _field(
            _locationController,
            'Location',
            null,
            hint: _showLocationError
                ? 'Please enter the location'
                : 'Muscat, Al Seeb',
            prefixIconWidget: const Center(
              widthFactor: 1,
              child: Text('📍', style: TextStyle(fontSize: 20)),
            ),
            maxLength: 30,
            errorText: _showLocationError ? 'Please enter the location' : null,
            onChanged: (_) {
              if (_showLocationError) {
                setState(() => _showLocationError = false);
              }
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Saving...',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : const Text('Save Changes', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaEditor() {
    final totalCount = _existingMedia.length + _newMedia.length;
    final canAddMore = totalCount < _maxMediaCount;

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: totalCount + (canAddMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (canAddMore && index == totalCount) {
              return Center(child: _buildAddMediaCircle());
            }

            if (index < _existingMedia.length) {
              return _ExistingMediaTile(
                media: _existingMedia[index],
                onRemove: () {
                  setState(() {
                    if (_canRemoveMedia()) {
                      _removedMedia.add(_existingMedia[index]);
                      _existingMedia.removeAt(index);
                    }
                  });
                },
              );
            }

            final newMediaIndex = index - _existingMedia.length;
            return _NewMediaTile(
              media: _newMedia[newMediaIndex],
              onRemove: () {
                if (_canRemoveMedia()) {
                  setState(() => _newMedia.removeAt(newMediaIndex));
                }
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAddMediaCircle() {
    return InkWell(
      onTap: _isSaving ? null : _openMediaSheet,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(Icons.add_a_photo, color: Color(0xFF111820), size: 38),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData? icon, {
    Widget? prefixIconWidget,
    String? hint,
    String? errorText,
    int? maxLength,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? onTap,
    VoidCallback? onEditingComplete,
    TapRegionCallback? onTapOutside,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: _isSaving,
      enabled: !_isSaving,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onTap: onTap,
      onEditingComplete: onEditingComplete,
      onTapOutside: onTapOutside,
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIconWidget ?? (icon == null ? null : Icon(icon)),
        errorText: errorText,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: _isSaving
          ? null
          : (value) {
              if (value != null) {
                onChanged(value);
              }
            },
    );
  }
}

class _ExistingMediaTile extends StatelessWidget {
  const _ExistingMediaTile({required this.media, required this.onRemove});

  final MediaItem media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _MediaTileFrame(
      onRemove: onRemove,
      child: media.isVideo
          ? const _VideoPlaceholder()
          : CachedNetworkImage(
              imageUrl: media.url,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: const Color(0xFFEFF4F1),
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFFDCF8C6),
                child: const Icon(Icons.broken_image),
              ),
            ),
    );
  }
}

class _NewMediaTile extends StatelessWidget {
  const _NewMediaTile({required this.media, required this.onRemove});

  final _SelectedMedia media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _MediaTileFrame(
      onRemove: onRemove,
      child: media.isVideo
          ? const _VideoPlaceholder()
          : Image.file(media.file, fit: BoxFit.cover),
    );
  }
}

class _MediaTileFrame extends StatelessWidget {
  const _MediaTileFrame({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.red,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 42),
    );
  }
}

class _MediaSheetButton extends StatelessWidget {
  const _MediaSheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF202523),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF25D366), size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _SelectedMedia {
  const _SelectedMedia({required this.file, required this.type});

  factory _SelectedMedia.fromXFile(XFile file) {
    final type =
        _isVideoPath(file.path) || file.mimeType?.startsWith('video/') == true
        ? 'video'
        : 'image';
    return _SelectedMedia(file: File(file.path), type: type);
  }

  final File file;
  final String type;

  bool get isVideo => type == 'video';

  static bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }
}
