import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'
    as device_permissions;
import 'package:record/record.dart';
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
  final List<_EditableMedia> _media = [];
  final List<MediaItem> _removedMedia = [];
  final _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];

  String? _existingAudioUrl;
  String? _audioDescriptionPath;
  Duration _audioDescriptionDuration = Duration.zero;
  String _lastValidPriceText = '';
  late String _priceUnit;
  int _audioResetToken = 0;
  bool _removeExistingAudio = false;
  bool _isSaving = false;
  bool _showLocationError = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.itemData['item_name'] ?? '',
    );
    final existingPrice = widget.itemData['price_number']?.toString() ?? '';
    _priceController = TextEditingController(
      text: _isZeroPrice(existingPrice) ? '' : _formatEditingPrice(existingPrice),
    );
    _lastValidPriceText = _priceController.text;
    _locationController = TextEditingController(
      text: widget.itemData['location'] ?? '',
    );
    _media.addAll(
      mediaItemsFromMap(widget.itemData).map(_EditableMedia.existing),
    );
    _existingAudioUrl =
        widget.itemData['audio_description_url']?.toString().trim();
    if (_existingAudioUrl?.isEmpty == true) {
      _existingAudioUrl = null;
    }
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
    if (!await _ensureMediaPermissions()) {
      return;
    }

    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCapturePage()),
    );
    if (result == CameraCaptureAction.openGallery) {
      await _pickGalleryMedia();
      return;
    }
    if (result is! CapturedMedia) {
      return;
    }
    if (!_canAddMedia()) {
      return;
    }
    if (result.isVideo && !await _isVideoWithinLimit(result.file)) {
      _showMessage('Video cannot be more than 1 minute');
      return;
    }

    setState(() {
      _media.add(
        _EditableMedia.newMedia(
          _SelectedMedia(file: result.file, type: result.type),
        ),
      );
    });
  }

  Future<bool> _ensureMediaPermissions() async {
    final cameraAndAudio = await [
      device_permissions.Permission.camera,
      device_permissions.Permission.microphone,
    ].request();
    final hasCamera =
        cameraAndAudio[device_permissions.Permission.camera]?.isGranted ??
        false;
    final hasMicrophone =
        cameraAndAudio[device_permissions.Permission.microphone]?.isGranted ??
        false;

    if (hasCamera && hasMicrophone) {
      return true;
    }

    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Camera and microphone access are needed'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: device_permissions.openAppSettings,
        ),
      ),
    );
    return false;
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
    final remaining = _maxMediaCount - _media.length;
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

    final selected = <_EditableMedia>[];
    for (final file in files.take(remaining)) {
      final media = _SelectedMedia.fromXFile(file);
      if (media.isVideo && !await _isVideoWithinLimit(media.file)) {
        _showMessage('Video cannot be more than 1 minute');
        continue;
      }
      selected.add(_EditableMedia.newMedia(media));
    }

    if (selected.isEmpty) {
      return;
    }
    setState(() => _media.addAll(selected));
  }

  bool _canAddMedia() {
    if (_media.length >= _maxMediaCount) {
      _showMessage('Maximum $_maxMediaCount media files allowed');
      return false;
    }
    return true;
  }

  Future<bool> _isVideoWithinLimit(File file) async {
    final info = await VideoCompress.getMediaInfo(file.path);
    final duration = info.duration;
    if (duration == null) {
      return true;
    }
    return duration <= const Duration(seconds: 60).inMilliseconds;
  }

  bool _canRemoveMedia() {
    if (_media.length <= 1) {
      _showMessage('Atleast 1 media is required');
      return false;
    }
    return true;
  }

  void _moveMedia(int fromIndex, int toIndex) {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= _media.length ||
        toIndex >= _media.length) {
      return;
    }

    setState(() {
      final media = _media.removeAt(fromIndex);
      _media.insert(toIndex, media);
    });
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

      final newEntries = _media.where((media) => !media.isExisting).toList();
      final uploadedMedia = await _uploadNewMedia(
        sellerUid.toString(),
        newEntries,
      );
      final allMedia = _media.map((media) {
        if (media.isExisting) {
          return media.existing!;
        }
        return uploadedMedia[media]!;
      }).toList();
      final imageUrls = allMedia
          .where((media) => !media.isVideo)
          .map((media) => media.url)
          .toList();
      final videoUrls = allMedia
          .where((media) => media.isVideo)
          .map((media) => media.url)
          .toList();
      final mediaFileMaps = allMedia
          .map(
            (media) => {
              'url': media.url,
              'type': media.type,
              if (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty)
                'thumbnail_url': media.thumbnailUrl,
            },
          )
          .toList();
      final expiresAt = widget.itemData['expires_at'] is Timestamp
          ? widget.itemData['expires_at'] as Timestamp
          : Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)));
      final audioDescriptionUrl = await _uploadAudioDescription(
        sellerUid.toString(),
      );
      final updateData = <String, dynamic>{
        'item_name': name,
        'origin': FieldValue.delete(),
        'quantity_number': FieldValue.delete(),
        'item_quantity': FieldValue.delete(),
        'weight_unit': FieldValue.delete(),
        'price_number': normalizedPrice,
        'price_unit': _priceUnit,
        'item_price': 'OMR $formattedPrice $_priceUnit',
        'location': location,
        'media_files': mediaFileMaps,
        'image_urls': imageUrls,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (audioDescriptionUrl != null) {
        updateData['audio_description_url'] = audioDescriptionUrl;
        updateData['audio_description_duration_seconds'] =
            _audioDescriptionDuration.inSeconds;
      } else if (_removeExistingAudio) {
        updateData['audio_description_url'] = FieldValue.delete();
        updateData['audio_description_duration_seconds'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('items')
          .doc(widget.docId)
          .update(updateData);

      await const StoryRepository().replaceItemVideos(
        sellerId: sellerUid.toString(),
        sellerName: widget.itemData['seller_name']?.toString() ?? 'Seller',
        sellerPhone: widget.itemData['seller_phone']?.toString() ?? '',
        itemId: widget.docId,
        itemName: name,
        itemPrice: 'OMR $formattedPrice $_priceUnit',
        location: location,
        expiresAt: expiresAt,
        mediaFiles: mediaFileMaps,
        videoUrls: videoUrls,
      );

      await _deleteRemovedStorageFiles();
      await _deleteRemovedAudioIfNeeded(audioDescriptionUrl != null);

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

  Future<Map<_EditableMedia, MediaItem>> _uploadNewMedia(
    String sellerUid,
    List<_EditableMedia> entries,
  ) async {
    final uploaded = <_EditableMedia, MediaItem>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final selected = entry.selected!;
      final compressed = selected.isVideo
          ? await _compressVideo(selected.file)
          : await _compressImage(selected.file);
      final extension = selected.isVideo ? 'mp4' : 'jpg';
      final contentType = selected.isVideo ? 'video/mp4' : 'image/jpeg';
      final fileName = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'items/$sellerUid/${fileName}_edit_$i.$extension',
      );

      final snapshot = await ref.putFile(
        compressed,
        SettableMetadata(contentType: contentType),
      );
      final thumbnailUrl = selected.isVideo
          ? await _uploadVideoThumbnail(
              videoFile: compressed,
              sellerUid: sellerUid,
              fileName: fileName,
              index: i,
            )
          : await _uploadImageThumbnail(
              imageFile: compressed,
              sellerUid: sellerUid,
              fileName: fileName,
              index: i,
            );
      uploaded[entry] = MediaItem(
        url: await snapshot.ref.getDownloadURL(),
        type: selected.type,
        thumbnailUrl: thumbnailUrl,
      );
    }
    return uploaded;
  }

  Future<String?> _uploadVideoThumbnail({
    required File videoFile,
    required String sellerUid,
    required int fileName,
    required int index,
  }) async {
    try {
      final thumbnail = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 45,
        position: -1,
      );
      final ref = FirebaseStorage.instance.ref().child(
        'items/$sellerUid/${fileName}_edit_${index}_thumb.jpg',
      );
      final snapshot = await ref.putFile(
        thumbnail,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return snapshot.ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _uploadImageThumbnail({
    required File imageFile,
    required String sellerUid,
    required int fileName,
    required int index,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_feed.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        targetPath,
        minWidth: 720,
        minHeight: 720,
        quality: 36,
        format: CompressFormat.jpeg,
      );
      if (result == null) {
        return null;
      }
      final ref = FirebaseStorage.instance.ref().child(
        'items/$sellerUid/${fileName}_edit_${index}_feed.jpg',
      );
      final snapshot = await ref.putFile(
        File(result.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return snapshot.ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _uploadAudioDescription(String sellerUid) async {
    final path = _audioDescriptionPath;
    if (path == null || path.isEmpty) {
      return null;
    }

    final audioFile = File(path);
    if (!await audioFile.exists()) {
      return null;
    }

    final fileName = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref().child(
      'items/$sellerUid/audio_description_edit_$fileName.m4a',
    );
    final snapshot = await ref.putFile(
      audioFile,
      SettableMetadata(contentType: 'audio/mp4'),
    );
    return snapshot.ref.getDownloadURL();
  }

  Future<File> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      minWidth: 1080,
      minHeight: 1080,
      quality: 42,
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
        final thumbnailUrl = media.thumbnailUrl?.trim() ?? '';
        if (thumbnailUrl.isNotEmpty) {
          await FirebaseStorage.instance.refFromURL(thumbnailUrl).delete();
        }
        await FirebaseStorage.instance.refFromURL(media.url).delete();
      } catch (_) {
        // The Firestore update is the source of truth; missing old files are safe.
      }
    }
  }

  Future<void> _deleteRemovedAudioIfNeeded(bool replacedAudio) async {
    final audioUrl = _existingAudioUrl;
    if (audioUrl == null || (!_removeExistingAudio && !replacedAudio)) {
      return;
    }

    try {
      await FirebaseStorage.instance.refFromURL(audioUrl).delete();
    } catch (_) {
      // Firestore update already removed/replaced the reference.
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

  bool _isZeroPrice(String value) {
    final cleanValue = value.replaceAll(',', '').trim();
    if (cleanValue.isEmpty) {
      return false;
    }
    return double.tryParse(cleanValue) == 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4FBF7),
        body: Column(
          children: [
            Container(
              height: MediaQuery.paddingOf(context).top,
              color: Colors.black,
            ),
            Container(
              height: kToolbarHeight,
              color: const Color(0xFFF4FBF7),
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.black),
              ),
            ),
            Expanded(
              child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            _buildMediaEditor(),
            const SizedBox(height: 20),
            _field(
              _nameController,
              'Item Name',
              null,
              hint: 'Fresh Tomatoes',
              maxLength: 80,
            ),
            const SizedBox(height: 14),
            AudioDescriptionField(
              isDisabled: _isSaving,
              resetToken: _audioResetToken,
              initialUrl: _existingAudioUrl,
              initialDuration: Duration(
                seconds:
                    (widget.itemData['audio_description_duration_seconds'] as num?)
                            ?.toInt() ??
                        0,
              ),
              onChanged: (path, duration, removeExisting) {
                _audioDescriptionPath = path;
                _audioDescriptionDuration = duration;
                _removeExistingAudio = removeExisting;
              },
            ),
            const SizedBox(height: 8),
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
                backgroundColor: const Color(0xFFFF7801),
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
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildMediaEditor() {
    final totalCount = _media.length;
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

            return DragTarget<int>(
              onWillAcceptWithDetails: (details) =>
                  !_isSaving && details.data != index,
              onAcceptWithDetails: (details) {
                _moveMedia(details.data, index);
              },
              builder: (context, candidateData, rejectedData) {
                final tile = _EditableMediaTile(
                  media: _media[index],
                  sequenceNumber: index + 1,
                  isDropTarget: candidateData.isNotEmpty,
                  onRemove: _isSaving
                      ? null
                      : () {
                          if (!_canRemoveMedia()) {
                            return;
                          }
                          setState(() {
                            final removed = _media.removeAt(index);
                            if (removed.isExisting) {
                              _removedMedia.add(removed.existing!);
                            }
                          });
                        },
                );

                if (_isSaving) {
                  return tile;
                }

                return LongPressDraggable<int>(
                  data: index,
                  feedback: SizedBox(
                    width: 110,
                    height: 110,
                    child: Material(
                      color: Colors.transparent,
                      child: Opacity(opacity: 0.88, child: tile),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: tile),
                  child: tile,
                );
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
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item.replaceFirst('/ ', '')),
            ),
          )
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

class AudioDescriptionField extends StatefulWidget {
  const AudioDescriptionField({
    super.key,
    required this.isDisabled,
    required this.resetToken,
    required this.onChanged,
    this.initialUrl,
    this.initialDuration = Duration.zero,
    this.label = 'Voice Note',
  });

  final bool isDisabled;
  final int resetToken;
  final String? initialUrl;
  final Duration initialDuration;
  final void Function(String? path, Duration duration, bool removeExisting)
  onChanged;
  final String label;

  @override
  State<AudioDescriptionField> createState() => _AudioDescriptionFieldState();
}

class _AudioDescriptionFieldState extends State<AudioDescriptionField> {
  static const _maxDuration = Duration(seconds: 30);
  static const _cancelSlideDistance = -80.0;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _recordTimer;
  String? _audioPath;
  String? _existingUrl;
  late Duration _recordedDuration;
  Duration _recordElapsed = Duration.zero;
  bool _isRecording = false;
  bool _isCancelArmed = false;
  bool _showCancelFeedback = false;
  bool _isPlaying = false;
  bool _removeExisting = false;
  double _recordDragOffset = 0;

  bool get _hasAudio => _audioPath != null || _existingUrl != null;

  @override
  void initState() {
    super.initState();
    _existingUrl = widget.initialUrl;
    _recordedDuration = widget.initialDuration;
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AudioDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _discardAudio(notifyParent: false);
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording(PointerDownEvent event) async {
    if (widget.isDisabled || _isRecording) {
      return;
    }

    final permission = await device_permissions.Permission.microphone.request();
    if (!permission.isGranted || !await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone access is needed')),
        );
      }
      return;
    }

    await _player.stop();
    final oldPath = _audioPath;
    if (oldPath != null) {
      await File(oldPath).delete().catchError((_) {});
    }
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/audio_description_edit_${DateTime.now().microsecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _recordTimer?.cancel();
    setState(() {
      _audioPath = null;
      _recordElapsed = Duration.zero;
      _recordedDuration = Duration.zero;
      _isRecording = true;
      _isCancelArmed = false;
      _showCancelFeedback = false;
      _isPlaying = false;
      _removeExisting = false;
      _recordDragOffset = 0;
    });

    _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) {
        return;
      }
      final nextElapsed = _recordElapsed + const Duration(milliseconds: 200);
      if (nextElapsed >= _maxDuration) {
        _finishRecording(cancel: false);
        return;
      }
      setState(() => _recordElapsed = nextElapsed);
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isRecording) {
      return;
    }
    final dragOffset = event.localPosition.dx.clamp(_cancelSlideDistance, 0.0);
    final shouldCancel = dragOffset <= _cancelSlideDistance;
    setState(() {
      _recordDragOffset = dragOffset;
      _isCancelArmed = shouldCancel;
    });
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    if (_isRecording) {
      await _finishRecording(cancel: _isCancelArmed);
    }
  }

  Future<void> _finishRecording({required bool cancel}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final elapsed = _recordElapsed;
    final path = await _recorder.stop();
    if (!mounted) {
      return;
    }

    if (cancel || path == null || elapsed < const Duration(milliseconds: 500)) {
      if (path != null) {
        await File(path).delete().catchError((_) {});
      }
      setState(() {
        _isRecording = false;
        _isCancelArmed = false;
        _showCancelFeedback = true;
        _recordElapsed = Duration.zero;
        _recordedDuration = Duration.zero;
        _audioPath = null;
        _recordDragOffset = 0;
      });
      Future<void>.delayed(const Duration(milliseconds: 820), () {
        if (mounted) {
          setState(() => _showCancelFeedback = false);
        }
      });
      widget.onChanged(null, Duration.zero, false);
      return;
    }

    final shouldRemoveExisting = _existingUrl != null;
    setState(() {
      _isRecording = false;
      _isCancelArmed = false;
      _showCancelFeedback = false;
      _recordedDuration = elapsed > _maxDuration ? _maxDuration : elapsed;
      _recordElapsed = Duration.zero;
      _audioPath = path;
      _existingUrl = null;
      _removeExisting = shouldRemoveExisting;
      _recordDragOffset = 0;
    });
    widget.onChanged(path, _recordedDuration, shouldRemoveExisting);
  }

  Future<void> _togglePlayback() async {
    if (widget.isDisabled) {
      return;
    }
    if (_isPlaying) {
      await _player.pause();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    final path = _audioPath;
    if (path != null) {
      await _player.play(DeviceFileSource(path));
    } else {
      final url = _existingUrl;
      if (url == null) {
        return;
      }
      await _player.play(UrlSource(url));
    }
    if (mounted) {
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _discardAudio({bool notifyParent = true}) async {
    final path = _audioPath;
    await _player.stop();
    if (path != null) {
      await File(path).delete().catchError((_) {});
    }
    final shouldRemoveExisting = _existingUrl != null || _removeExisting;
    if (mounted) {
      setState(() {
        _audioPath = null;
        _existingUrl = null;
        _recordedDuration = Duration.zero;
        _isPlaying = false;
        _removeExisting = shouldRemoveExisting;
      });
    }
    if (notifyParent) {
      widget.onChanged(null, Duration.zero, shouldRemoveExisting);
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 30);
    return '0:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cancelProgress = (_recordDragOffset.abs() /
            _cancelSlideDistance.abs())
        .clamp(0.0, 1.0);
    final cancelHintOffset = -0.28 * cancelProgress;
    final cancelHintOpacity =
        _isRecording ? (1 - (cancelProgress * 0.75)).clamp(0.25, 1.0) : 1.0;

    return SizedBox(
      height: 70,
      child: InputDecorator(
        isFocused: _isRecording || _showCancelFeedback,
        isEmpty: !_hasAudio && !_isRecording && !_showCancelFeedback,
        decoration: InputDecoration(
          filled: true,
          fillColor: widget.isDisabled ? Colors.grey.shade100 : Colors.white,
          labelText: widget.label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          constraints: const BoxConstraints(minHeight: 70, maxHeight: 70),
        ),
        child: Row(
          children: [
            if (_isRecording)
              Text(
                '${_formatDuration(_recordElapsed)} / ${_formatDuration(_maxDuration)}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (_hasAudio)
              Container(
                width: 52,
                height: 40,
                alignment: Alignment.center,
                child: IconButton(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle : Icons.play_circle_fill,
                    color: const Color(0xFFFF7801),
                    size: 36,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              )
            else
              const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: _isRecording ? 24 : 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _showCancelFeedback
                      ? TweenAnimationBuilder<double>(
                          key: const ValueKey('cancel-feedback'),
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 720),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            final lift = value < 0.45
                                ? -44 * (value / 0.45)
                                : -44 + (52 * ((value - 0.45) / 0.55));
                            final fade = value < 0.72
                                ? 1.0
                                : (1 - ((value - 0.72) / 0.28))
                                      .clamp(0.0, 1.0);
                            final micScale = value < 0.45
                                ? 1.0
                                : (1 - (0.25 * ((value - 0.45) / 0.55)));

                            return Opacity(
                              opacity: fade,
                              child: SizedBox(
                                height: 40,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 42,
                                    height: 40,
                                    child: OverflowBox(
                                      maxHeight: 92,
                                      alignment: Alignment.bottomLeft,
                                      child: SizedBox(
                                        width: 42,
                                        height: 72,
                                        child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                        const Positioned(
                                          bottom: 2,
                                          child: Icon(
                                            Icons.delete,
                                            color: Color(0xFF606060),
                                            size: 22,
                                          ),
                                        ),
                                        Transform.translate(
                                          offset: Offset(0, lift),
                                          child: Transform.scale(
                                            scale: micScale,
                                            child: const CircleAvatar(
                                              radius: 10,
                                              backgroundColor: Colors.red,
                                              child: Icon(
                                                Icons.mic,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : AnimatedSlide(
                          key: ValueKey(_isRecording ? 'recording' : 'idle'),
                          offset: Offset(cancelHintOffset, 0),
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          child: AnimatedOpacity(
                            opacity: cancelHintOpacity,
                            duration: const Duration(milliseconds: 90),
                            child: Text(
                              _isRecording
                                  ? (_isCancelArmed
                                        ? 'Release to cancel'
                                        : '<<< Slide to Cancel')
                                  : _hasAudio
                                  ? 'Audio description ${_formatDuration(_recordedDuration)}'
                                  : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: _isRecording
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: TextStyle(
                                color: _isRecording && _isCancelArmed
                                    ? Colors.red
                                    : Colors.grey.shade700,
                                fontSize: 15,
                                fontWeight: _hasAudio || _isRecording
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            if (_hasAudio)
              GestureDetector(
                onTap: widget.isDisabled ? null : _discardAudio,
                child: Container(
                  width: 52,
                  height: 40,
                  alignment: Alignment.center,
                  child: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.red,
                    child: Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              )
            else
              Listener(
                onPointerDown: _startRecording,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: (_) {
                  if (_isRecording) {
                    _finishRecording(cancel: true);
                  }
                },
                child: Transform.translate(
                  offset: const Offset(8, 0),
                  child: Container(
                    width: 52,
                    height: 40,
                    alignment: Alignment.center,
                    child: OverflowBox(
                      maxWidth: 88,
                      maxHeight: 88,
                      child: CircleAvatar(
                        radius: _isRecording ? 44 : 18,
                        backgroundColor: _isRecording
                            ? Colors.red
                            : const Color(0xFFFF7801),
                        child: Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: _isRecording ? 40 : 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditableMediaTile extends StatelessWidget {
  const _EditableMediaTile({
    required this.media,
    required this.sequenceNumber,
    required this.isDropTarget,
    required this.onRemove,
  });

  final _EditableMedia media;
  final int sequenceNumber;
  final bool isDropTarget;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: isDropTarget
            ? Border.all(color: const Color(0xFF25D366), width: 3)
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: media.isVideo
                ? const _VideoPlaceholder()
                : media.isExisting
                    ? CachedNetworkImage(
                        imageUrl: media.existing!.url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: const Color(0xFFEFF4F1),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFFDCF8C6),
                          child: const Icon(Icons.broken_image),
                        ),
                      )
                    : Image.file(media.selected!.file, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF25D366),
              child: Text(
                '$sequenceNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
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
      ),
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

class _EditableMedia {
  const _EditableMedia.existing(this.existing) : selected = null;

  const _EditableMedia.newMedia(this.selected) : existing = null;

  final MediaItem? existing;
  final _SelectedMedia? selected;

  bool get isExisting => existing != null;

  bool get isVideo => isExisting ? existing!.isVideo : selected!.isVideo;
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

