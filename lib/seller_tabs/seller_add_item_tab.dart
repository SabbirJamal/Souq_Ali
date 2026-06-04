import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'
    as device_permissions;
import 'package:photo_manager/photo_manager.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';

import '../camera_capture_page.dart';
import '../seller_session.dart';
import '../upload_status_manager.dart';
import '../widgets/price_with_currency.dart';

class SellerAddItemTab extends StatefulWidget {
  const SellerAddItemTab({
    super.key,
    this.onItemAddedDone,
    this.onLiveModeChanged,
    this.isLive = false,
  });

  final ValueChanged<bool>? onItemAddedDone;
  final ValueChanged<bool>? onLiveModeChanged;
  final bool isLive;
  @override
  SellerAddItemTabState createState() => SellerAddItemTabState();
}

class SellerAddItemTabState extends State<SellerAddItemTab> {
  static const _maxMediaCount = 9;
  static const _maxPriceValue = 1000000.0;

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _priceFocusNode = FocusNode();

  final List<_SelectedMedia> _selectedMedia = [];
  final _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];
  String? _audioDescriptionPath;
  Duration _audioDescriptionDuration = Duration.zero;

  String _lastValidPriceText = '';
  String _priceUnit = '/ kg';
  int _timePeriodHours = 720;
  int _audioResetToken = 0;
  bool _isUploading = false;
  bool _showLocationError = false;
  bool _showPriceError = false;
  bool _isLiveItem = false;
  bool _isTransitPost = false;

  int get _totalTimePeriodHours => _isLiveItem ? 2 : _timePeriodHours;

  @override
  void initState() {
    super.initState();
    _isLiveItem = widget.isLive;
    _loadDefaultSellerLocation();
  }

  @override
  void didUpdateWidget(covariant SellerAddItemTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLive != widget.isLive) {
      _isLiveItem = widget.isLive;
    }
  }

  Future<void> _loadDefaultSellerLocation() async {
    final session = await SellerSession.current();
    if (session == null) {
      return;
    }
    final sellerDoc = await FirebaseFirestore.instance
        .collection('sellers')
        .doc(session.sellerId)
        .get();
    final defaultLocation = sellerDoc.data()?['location']?.toString().trim() ?? '';
    if (!mounted || defaultLocation.isEmpty || _locationController.text.isNotEmpty) {
      return;
    }
    _locationController.text = defaultLocation;
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
      await _openGallerySheet();
      return;
    }
    if (result is! CapturedMedia) {
      return;
    }
    final captured = result;
    if (!_canAddMedia()) {
      return;
    }
    if (captured.isVideo && !await _isVideoWithinLimit(captured.file)) {
      _showMessage('Video cannot be more than 1 minute');
      return;
    }

    setState(() {
      _selectedMedia.add(
        _SelectedMedia(file: captured.file, type: captured.type),
      );
    });
  }

  Future<bool> _ensureMediaPermissions() async {
    final cameraAndAudio = await [
      device_permissions.Permission.camera,
      device_permissions.Permission.microphone,
    ].request();
    final gallery = await PhotoManager.requestPermissionExtend();

    final hasCamera =
        cameraAndAudio[device_permissions.Permission.camera]?.isGranted ??
        false;
    final hasMicrophone =
        cameraAndAudio[device_permissions.Permission.microphone]?.isGranted ??
        false;

    if (hasCamera && hasMicrophone && gallery.hasAccess) {
      return true;
    }

    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Camera, microphone and gallery access are needed'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: device_permissions.openAppSettings,
        ),
      ),
    );
    return false;
  }

  Future<void> openMediaSheet() async {
    await _openCamera();
  }

  Future<void> _openGallerySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111614),
      shape: const RoundedRectangleBorder(),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: _MediaPickerSheet(
            selectedIds: _selectedMedia
                .map((media) => media.assetId)
                .whereType<String>()
                .toSet(),
            selectedCount: _selectedMedia.length,
            maxCount: _maxMediaCount,
            onAssetsDone: _addGalleryAssets,
          ),
        );
      },
    );
  }

  Future<void> _addGalleryAssets(
    List<AssetEntity> assets,
    Set<String> selectedAssetIds,
  ) async {
    if (assets.isEmpty) {
      if (mounted) {
        setState(() {
          _selectedMedia.removeWhere((media) {
            final assetId = media.assetId;
            return assetId != null && !selectedAssetIds.contains(assetId);
          });
        });
      }
      return;
    }

    final newMedia = <_SelectedMedia>[];
    for (final asset in assets) {
      if (_selectedMedia.any((media) => media.assetId == asset.id)) {
        continue;
      }

      final file = await asset.fileWithSubtype ?? await asset.file;
      if (file == null) {
        _showMessage('Could not open selected file');
        continue;
      }
      if (asset.type == AssetType.video && asset.duration > 60) {
        _showMessage('Video cannot be more than 1 minute');
        continue;
      }

      newMedia.add(
        _SelectedMedia(
          file: file,
          type: asset.type == AssetType.video ? 'video' : 'image',
          assetId: asset.id,
        ),
      );
    }

    setState(() {
      _selectedMedia.removeWhere((media) {
        final assetId = media.assetId;
        return assetId != null && !selectedAssetIds.contains(assetId);
      });
      _selectedMedia.addAll(newMedia);
    });
  }

  bool _canAddMedia() {
    if (_selectedMedia.length >= _maxMediaCount) {
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

  Future<List<_UploadedMedia>> _uploadMedia(
    String sellerUid, [
    List<_SelectedMedia>? mediaToUpload,
  ]) async {
    final uploaded = <_UploadedMedia>[];
    final orderedMedia = [...(mediaToUpload ?? _selectedMedia)];

    for (var i = 0; i < orderedMedia.length; i++) {
      final media = orderedMedia[i];
      final compressed = media.isVideo
          ? await _compressVideo(media.file)
          : await _compressImage(media.file);
      final extension = media.isVideo ? 'mp4' : 'jpg';
      final contentType = media.isVideo ? 'video/mp4' : 'image/jpeg';
      final fileName = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'items/$sellerUid/${fileName}_$i.$extension',
      );

      final uploadFuture = ref.putFile(
        compressed,
        SettableMetadata(contentType: contentType),
      );
      final thumbnailFuture = media.isVideo
          ? _uploadVideoThumbnail(
              videoFile: compressed,
              sellerUid: sellerUid,
              fileName: fileName,
              index: i,
            )
          : _uploadImageThumbnail(
              imageFile: compressed,
              sellerUid: sellerUid,
              fileName: fileName,
              index: i,
            );
      final uploadSnapshot = await uploadFuture;
      final thumbnailUrl = await thumbnailFuture;
      uploaded.add(
        _UploadedMedia(
          url: await uploadSnapshot.ref.getDownloadURL(),
          type: media.type,
          thumbnailUrl: thumbnailUrl,
        ),
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
        'items/$sellerUid/${fileName}_${index}_thumb.jpg',
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
        'items/$sellerUid/${fileName}_${index}_feed.jpg',
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
    if (compressedPath == null || compressedPath.isEmpty) {
      return file;
    }

    return File(compressedPath);
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
      'items/$sellerUid/audio_description_$fileName.m4a',
    );
    final snapshot = await ref.putFile(
      audioFile,
      SettableMetadata(contentType: 'audio/mp4'),
    );
    return snapshot.ref.getDownloadURL();
  }

  Future<void> _addItem() async {
    final isLiveItem = _isLiveItem;
    final isTransitPost = !isLiveItem && _isTransitPost;
    final name = _nameController.text.trim();
    final priceNumber = isLiveItem
        ? (_priceController.text.trim().isEmpty
              ? '0'
              : _priceController.text.trim())
        : '';
    final location = isTransitPost ? 'TRANSIT' : _locationController.text.trim();

    if (_selectedMedia.isEmpty) {
      _showMessage('Please add atleast 1 image or video');
      return;
    }
    if (!isTransitPost && location.isEmpty) {
      setState(() => _showLocationError = true);
      return;
    }
    final normalizedPrice = isLiveItem ? _normalizePrice(priceNumber) : '';
    if (isLiveItem) {
      if (normalizedPrice == null) {
        _showMessage('Invalid price');
        return;
      }
      if (double.parse(normalizedPrice) <= 0) {
        setState(() => _showPriceError = true);
        _priceFocusNode.requestFocus();
        return;
      }
    }
    setState(() => _isUploading = true);

    try {
      final session = await SellerSession.current();
      if (session == null) {
        _showMessage('Please login again');
        return;
      }

      final mediaToUpload = List<_SelectedMedia>.from(_selectedMedia);
      final priceUnit = isLiveItem ? _priceUnit : '';
      final timePeriodHours = _totalTimePeriodHours;
      final selectedTimePeriodHours = _timePeriodHours;

      UploadStatusManager.uploading();
      widget.onItemAddedDone?.call(isLiveItem);

      final uploadedMedia = await _uploadMedia(session.sellerId, mediaToUpload);
      final audioDescriptionUrl = isLiveItem
          ? null
          : await _uploadAudioDescription(session.sellerId);
      final imageUrls = uploadedMedia
          .where((media) => media.type == 'image')
          .map((media) => media.url)
          .toList();
      final price = isLiveItem
          ? 'OMR ${_formatPriceWithCommas(normalizedPrice!)} $priceUnit'
          : '';
      final itemRef = FirebaseFirestore.instance.collection('items').doc();
      final mediaFileMaps = uploadedMedia.map((media) => media.toMap()).toList();
      final expiresAt = Timestamp.fromDate(
        DateTime.now().add(Duration(hours: timePeriodHours)),
      );

      await itemRef.set({
        'seller_uid': session.sellerId,
        'seller_name': session.name,
        'seller_phone': session.phoneNumber,
        'status': isLiveItem ? 'live' : 'post',
        'is_transit': isTransitPost,
        'item_name': name,
        'item_price': price,
        'price_number': normalizedPrice,
        'price_unit': priceUnit,
        'location': location,
        'image_urls': imageUrls,
        'media_files': mediaFileMaps,
        if (audioDescriptionUrl != null) ...{
          'audio_description_url': audioDescriptionUrl,
          'audio_description_duration_seconds':
              _audioDescriptionDuration.inSeconds,
        },
        'time_period_days': 0,
        'time_period_extra_hours': selectedTimePeriodHours,
        'time_period_hours': timePeriodHours,
        'expires_at': expiresAt,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      UploadStatusManager.success();
      if (mounted) {
        _clearForm();
      }
    } on FirebaseException catch (error) {
      final message = error.code == 'object-not-found'
          ? 'Storage upload failed. Check Firebase Storage is enabled and rules allow uploads.'
          : error.message ?? error.code;
      UploadStatusManager.error('Upload failed: $message');
    } catch (error) {
      UploadStatusManager.error('Upload failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _clearForm() {
    _nameController.clear();
    _priceController.clear();
    _lastValidPriceText = '';
    setState(() {
      _selectedMedia.clear();
      _priceUnit = '/ kg';
      _timePeriodHours = 720;
      _isTransitPost = false;
      if (!_isLiveItem) {
        _audioDescriptionPath = null;
        _audioDescriptionDuration = Duration.zero;
        _audioResetToken++;
      }
      _showLocationError = false;
      _showPriceError = false;
    });
    _loadDefaultSellerLocation();
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
    if (_showPriceError) {
      setState(() => _showPriceError = false);
    }
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
    if (nextValue.length > 1 && nextValue.startsWith('0') && !nextValue.startsWith('0.')) {
      nextValue = nextValue.replaceFirst(RegExp(r'^0+'), '');
      if (nextValue.isEmpty || nextValue.startsWith('.')) {
        nextValue = '0$nextValue';
      }
      final formatted = _formatEditingPrice(nextValue);
      _lastValidPriceText = formatted;
      _setPriceText(formatted);
      return;
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
    final cleanValue = _priceController.text.trim().replaceAll(',', '');
    if (cleanValue.isEmpty || double.tryParse(cleanValue) == 0) {
      _lastValidPriceText = '';
      _setPriceText('');
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
    if (parsed == null) {
      return null;
    }
    if (parsed > _maxPriceValue) {
      return null;
    }
    return parsed.toStringAsFixed(3);
  }

  String _formatEditingPrice(String value) {
    if (value.isEmpty) {
      return '';
    }
    final parts = value.split('.');
    final whole = _formatWholeNumber(parts.first);
    if (value.endsWith('.')) {
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
    return SizedBox.expand(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: _isLiveItem ? const Color(0xFFFFE9EC) : const Color(0xFFF4FBF7),
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLiveSwitch(),
          const SizedBox(height: 16),
          _buildMediaPicker(),
          const SizedBox(height: 20),
          if (!_isLiveItem) ...[
            _buildTransitToggle(),
            const SizedBox(height: 14),
          ],
          _buildTextField(
            controller: _nameController,
            label: 'Item Name',
            hint: '',
            maxLength: 80,
          ),
          const SizedBox(height: 14),
          if (!_isLiveItem) ...[
            AudioDescriptionField(
              isDisabled: _isUploading,
              resetToken: _audioResetToken,
              onChanged: (path, duration) {
                _audioDescriptionPath = path;
                _audioDescriptionDuration = duration;
              },
            ),
            const SizedBox(height: 8),
          ],
          if (_isLiveItem) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    controller: _priceController,
                    label: _showPriceError ? 'PRICE REQUIRED' : 'Price',
                    hint: 'Price',
                    icon: null,
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
                      if (_showPriceError) {
                        setState(() => _showPriceError = false);
                      }
                    },
                    onEditingComplete: _restoreDefaultPriceIfEmpty,
                    onTapOutside: (_) => _restoreDefaultPriceIfEmpty(),
                    onChanged: _handlePriceChanged,
                    errorText: _showPriceError ? '' : null,
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
          ],
          if (_isLiveItem || !_isTransitPost)
            _buildTextField(
            controller: _locationController,
            label: 'Location',
            hint: _showLocationError ? 'Please enter the location' : 'Muscat, Al Seeb',
            icon: null,
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
            onPressed: _isUploading ? null : _addItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isLiveItem
                  ? const Color(0xFF25D366)
                  : const Color(0xFFFF7801),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isUploading
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
                          'Uploading...',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _isLiveItem ? 'Go Live - 2 Hrs' : 'Post - 18 Hrs',
                    style: const TextStyle(fontSize: 20),
                  ),
          ),
        ],
        ),
        ),
      ),
    );
  }

  Widget _buildLiveSwitch() {
    final liveAnimation = Transform.scale(
      scale: 2.6,
      child: Lottie.asset(
        'assets/lottie/live2.json',
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
      ),
    );

    return Center(
      child: GestureDetector(
        onTap: _isUploading ? null : () => _setLiveMode(!_isLiveItem),
        child: AnimatedScale(
          scale: _isLiveItem ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 150,
            height: 60,
            child: ClipRect(
              child: _isLiveItem
                  ? liveAnimation
                  : ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: liveAnimation,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _setLiveMode(bool isLive) {
    if (_isLiveItem == isLive) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isLiveItem = isLive;
      if (isLive) {
        _isTransitPost = false;
        _showLocationError = false;
        _audioDescriptionPath = null;
        _audioDescriptionDuration = Duration.zero;
        _audioResetToken++;
      } else {
        _showPriceError = false;
        _priceController.clear();
        _lastValidPriceText = '';
      }
    });
    widget.onLiveModeChanged?.call(isLive);
  }

  Widget _buildTransitToggle() {
    void setTransitMode(bool isTransit) {
      if (_isTransitPost == isTransit || _isUploading) {
        return;
      }
      setState(() {
        _isTransitPost = isTransit;
        if (isTransit) {
          _showLocationError = false;
        }
      });
    }

    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TransitStatusButton(
              text: 'IN STOCK',
              isSelected: !_isTransitPost,
              onTap: () => setTransitMode(false),
            ),
          ),
          Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
          Expanded(
            child: _TransitStatusButton(
              text: 'TRANSIT',
              isSelected: _isTransitPost,
              onTap: () => setTransitMode(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPicker() {
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _selectedMedia.length + 1,
          itemBuilder: (context, index) {
            if (index == _selectedMedia.length) {
              return Align(
                alignment: Alignment.topCenter,
                child: _buildMediaActionCircle(
                  onTap: _openCamera,
                ),
              );
            }

            final media = _selectedMedia[index];
            return DragTarget<int>(
              onWillAcceptWithDetails: (details) =>
                  !_isUploading && details.data != index,
              onAcceptWithDetails: (details) {
                _moveSelectedMedia(details.data, index);
              },
              builder: (context, candidateData, rejectedData) {
                final tile = _SelectedMediaTile(
                  media: media,
                  sequenceNumber: index + 1,
                  isDropTarget: candidateData.isNotEmpty,
                  onRemove: _isUploading
                      ? null
                      : () => setState(() => _selectedMedia.removeAt(index)),
                );

                if (_isUploading) {
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

  void _moveSelectedMedia(int fromIndex, int toIndex) {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= _selectedMedia.length ||
        toIndex >= _selectedMedia.length) {
      return;
    }

    setState(() {
      final media = _selectedMedia.removeAt(fromIndex);
      _selectedMedia.insert(toIndex, media);
    });
  }

  Widget _buildMediaActionCircle({
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isUploading ? null : onTap,
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
        child: const Icon(
          Icons.add_a_photo,
          color: Color(0xFF111820),
          size: 38,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    Widget? prefixIconWidget,
    TextInputType? keyboardType,
    String? prefixText,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? onTap,
    VoidCallback? onEditingComplete,
    TapRegionCallback? onTapOutside,
    ValueChanged<String>? onChanged,
    String? errorText,
    int? maxLength,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: _isUploading,
      enabled: !_isUploading,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      onTap: onTap,
      onEditingComplete: onEditingComplete,
      onTapOutside: onTapOutside,
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
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
      onChanged: _isUploading
          ? null
          : (value) {
              if (value != null) {
                onChanged(value);
              }
            },
    );
  }
}

class _TransitStatusButton extends StatelessWidget {
  const _TransitStatusButton({
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFFF7801) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class AudioDescriptionField extends StatefulWidget {
  const AudioDescriptionField({
    super.key,
    required this.isDisabled,
    required this.resetToken,
    required this.onChanged,
    this.label = 'Voice Note',
  });

  final bool isDisabled;
  final int resetToken;
  final void Function(String? path, Duration duration) onChanged;
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
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _completeSubscription;
  String? _audioPath;
  List<double> _waveSamples = const [];
  Duration _recordElapsed = Duration.zero;
  Duration _recordedDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  bool _isRecording = false;
  bool _isCancelArmed = false;
  bool _showCancelFeedback = false;
  bool _isPlaying = false;
  double _recordDragOffset = 0;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() => _playbackPosition = position);
      }
    });
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackPosition = Duration.zero;
        });
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
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    if (_isRecording) {
      unawaited(_recorder.stop().catchError((_) => null));
    }
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _deleteLocalFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // The temp file may already be gone.
    }
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
      await _deleteLocalFile(oldPath);
    }
    widget.onChanged(null, Duration.zero);
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/audio_description_${DateTime.now().microsecondsSinceEpoch}.m4a';

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
      _waveSamples = const [];
      _recordElapsed = Duration.zero;
      _recordedDuration = Duration.zero;
      _playbackPosition = Duration.zero;
      _isRecording = true;
      _isCancelArmed = false;
      _showCancelFeedback = false;
      _isPlaying = false;
      _recordDragOffset = 0;
    });

    _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) async {
      if (!mounted) {
        return;
      }
      final waveSamples = List<double>.from(_waveSamples);
      waveSamples.add(await _readWaveSample(waveSamples.length));
      if (waveSamples.length > 42) {
        waveSamples.removeAt(0);
      }
      final nextElapsed = _recordElapsed + const Duration(milliseconds: 200);
      if (nextElapsed >= _maxDuration) {
        _finishRecording(cancel: false);
        return;
      }
      setState(() {
        _recordElapsed = nextElapsed;
        _waveSamples = waveSamples;
      });
    });
  }

  Future<double> _readWaveSample(int index) async {
    try {
      final amplitude = await _recorder.getAmplitude();
      final current = amplitude.current;
      if (current.isFinite) {
        return ((current + 45) / 45).clamp(0.08, 1.0);
      }
    } catch (_) {}
    return (0.25 + (math.sin(index * 1.7).abs() * 0.75)).clamp(0.08, 1.0);
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
        await _deleteLocalFile(path);
      }
      setState(() {
        _isRecording = false;
        _isCancelArmed = false;
        _showCancelFeedback = true;
        _recordElapsed = Duration.zero;
        _recordedDuration = Duration.zero;
        _playbackPosition = Duration.zero;
        _audioPath = null;
        _waveSamples = const [];
        _recordDragOffset = 0;
      });
      Future<void>.delayed(const Duration(milliseconds: 820), () {
        if (mounted) {
          setState(() => _showCancelFeedback = false);
        }
      });
      return;
    }

    setState(() {
      _isRecording = false;
      _isCancelArmed = false;
      _showCancelFeedback = false;
      _recordedDuration = elapsed > _maxDuration ? _maxDuration : elapsed;
      _playbackPosition = Duration.zero;
      _recordElapsed = Duration.zero;
      _audioPath = path;
      _waveSamples = _waveSamples.isEmpty ? _fallbackWaveSamples() : _waveSamples;
      _recordDragOffset = 0;
    });
    widget.onChanged(path, _recordedDuration);
  }

  List<double> _fallbackWaveSamples() {
    return List<double>.generate(
      34,
      (index) => (0.22 + math.sin(index * 0.82).abs() * 0.78).clamp(0.08, 1.0),
    );
  }

  Future<void> _togglePlayback() async {
    final path = _audioPath;
    if (path == null || widget.isDisabled) {
      return;
    }
    if (_isPlaying) {
      await _player.pause();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    await _player.play(DeviceFileSource(path));
    if (mounted) {
      setState(() {
        _isPlaying = true;
        _playbackPosition = Duration.zero;
      });
    }
  }

  Future<void> _discardAudio({bool notifyParent = true}) async {
    final path = _audioPath;
    await _player.stop();
    if (path != null) {
      await _deleteLocalFile(path);
    }
    if (mounted) {
      setState(() {
        _audioPath = null;
        _waveSamples = const [];
        _recordedDuration = Duration.zero;
        _playbackPosition = Duration.zero;
        _isPlaying = false;
      });
    }
    if (notifyParent) {
      widget.onChanged(null, Duration.zero);
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 30);
    return '0:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = _audioPath != null;
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
        isEmpty: !hasAudio && !_isRecording && !_showCancelFeedback,
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
            else if (hasAudio)
              Container(
                width: 52,
                height: 40,
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: _togglePlayback,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFFF7801),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 22,
                    ),
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
                      : hasAudio
                          ? Row(
                              key: const ValueKey('waveform'),
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 34,
                                    child: _AudioWaveform(
                                      samples: _waveSamples,
                                      progress: _recordedDuration.inMilliseconds ==
                                              0
                                          ? 0
                                          : (_playbackPosition.inMilliseconds /
                                                _recordedDuration.inMilliseconds)
                                              .clamp(0.0, 1.0),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDuration(_recordedDuration),
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
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
                              fontWeight: hasAudio || _isRecording
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ),
            if (hasAudio)
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

class _AudioWaveform extends StatelessWidget {
  const _AudioWaveform({required this.samples, required this.progress});

  final List<double> samples;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AudioWaveformPainter(samples, progress),
      size: Size.infinite,
    );
  }
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter(this.samples, this.progress);

  final List<double> samples;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final barCount = (size.width / 4).floor().clamp(22, 44).toInt();
    final centerY = size.height / 2;
    final usableHeight = size.height - 4;
    final playedBars = (barCount * progress.clamp(0.0, 1.0)).round();

    for (var index = 0; index < barCount; index++) {
      paint.color = index < playedBars
          ? const Color(0xFFFF7801)
          : const Color(0xFF111820);
      final sample = samples.isEmpty
          ? (0.25 + math.sin(index * 0.82).abs() * 0.75)
          : samples[(index * samples.length / barCount).floor()];
      final barHeight = (4 + (usableHeight * sample))
          .clamp(5.0, usableHeight)
          .toDouble();
      final x = (index / (barCount - 1)) * size.width;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.progress != progress;
  }
}

class _SelectedMediaTile extends StatelessWidget {
  const _SelectedMediaTile({
    required this.media,
    required this.sequenceNumber,
    required this.isDropTarget,
    required this.onRemove,
  });

  final _SelectedMedia media;
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
                ? Container(
                    color: Colors.black87,
                    child: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 42,
                    ),
                  )
                : Image.file(media.file, fit: BoxFit.cover),
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

class _PickerLimitMessage extends StatelessWidget {
  const _PickerLimitMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Only 9 media can be selected',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPickerSheet extends StatefulWidget {
  const _MediaPickerSheet({
    required this.selectedIds,
    required this.selectedCount,
    required this.maxCount,
    required this.onAssetsDone,
  });

  final Set<String> selectedIds;
  final int selectedCount;
  final int maxCount;
  final Future<void> Function(List<AssetEntity> assets, Set<String> selectedIds)
  onAssetsDone;

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet> {
  static const _pageSize = 90;

  final Set<String> _selectedIds = {};
  final Map<String, int> _selectedOrder = {};
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  final List<AssetEntity> _pendingAssets = [];
  List<AssetPathEntity> _albums = [];
  List<AssetEntity> _assets = [];
  AssetPathEntity? _selectedAlbum;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreAssets = true;
  bool _hasPermission = true;
  bool _hasLimitedPermission = false;
  bool _maxSelectionMessageShown = false;
  bool _isMaxSelectionMessageVisible = false;
  int _currentPage = 0;
  int _loadToken = 0;
  Timer? _maxSelectionMessageTimer;

  int get _currentTotalSelectionCount =>
      widget.selectedCount - widget.selectedIds.length + _selectedIds.length;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.selectedIds);
    _rebuildSelectedOrder();
    _loadAssets();
  }

  @override
  void dispose() {
    _maxSelectionMessageTimer?.cancel();
    super.dispose();
  }

  void _rebuildSelectedOrder() {
    _selectedOrder
      ..clear()
      ..addEntries(
        _selectedIds.toList().asMap().entries.map(
              (entry) => MapEntry(entry.value, entry.key + 1),
            ),
      );
  }

  Future<Uint8List?> _thumbnailFor(AssetEntity asset, ThumbnailSize size) {
    return _thumbnailFutures.putIfAbsent(
      '${asset.id}-${size.width}-${size.height}',
      () => asset.thumbnailDataWithSize(size),
    );
  }

  Future<void> _loadAssets() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
      return;
    }

    final hasLimitedPermission = permission == PermissionState.limited;
    final albums = await _loadMediaAlbums();
    if (albums.isEmpty) {
      setState(() {
        _hasLimitedPermission = hasLimitedPermission;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _albums = albums;
      _selectedAlbum = albums.first;
      _hasLimitedPermission = hasLimitedPermission;
      _isLoading = false;
    });
    await _loadFirstAlbumPage();
  }

  Future<List<AssetPathEntity>> _loadMediaAlbums() async {
    final albumsById = <String, AssetPathEntity>{};
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    for (final album in albums) {
      albumsById[album.id] = album;
    }
    final sortedAlbums = albumsById.values.toList();
    sortedAlbums.sort((first, second) {
      if (first.isAll != second.isAll) {
        return first.isAll ? -1 : 1;
      }
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    return sortedAlbums;
  }

  Future<void> _changeAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) {
      return;
    }
    setState(() {
      _selectedAlbum = album;
      _assets = [];
      _currentPage = 0;
      _hasMoreAssets = true;
      _isLoadingMore = false;
    });
    await _loadFirstAlbumPage();
  }

  Future<void> _loadFirstAlbumPage() async {
    final token = ++_loadToken;
    setState(() {
      _assets = [];
      _currentPage = 0;
      _hasMoreAssets = true;
      _isLoadingMore = true;
    });
    await _loadMoreAssets(token: token);
  }

  Future<void> _loadMoreAssets({int? token}) async {
    final album = _selectedAlbum;
    if (album == null || _isLoadingMore && token == null || !_hasMoreAssets) {
      return;
    }

    final activeToken = token ?? _loadToken;
    if (token == null) {
      setState(() => _isLoadingMore = true);
    }

    final nextAssets = await album.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );
    if (!mounted || activeToken != _loadToken) {
      return;
    }

    final visibleAssets = nextAssets
        .where(
          (asset) => asset.type == AssetType.image || asset.type == AssetType.video,
        )
        .toList();

    setState(() {
      _assets.addAll(visibleAssets);
      _currentPage += 1;
      _hasMoreAssets = nextAssets.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  void _maybeLoadMore(int index) {
    if (index >= _assets.length - 18 && _hasMoreAssets && !_isLoadingMore) {
      _loadMoreAssets();
    }
  }

  Future<void> _toggleAsset(AssetEntity asset) async {
    if (_selectedIds.contains(asset.id)) {
      setState(() {
        _selectedIds.remove(asset.id);
        _pendingAssets.removeWhere((pending) => pending.id == asset.id);
        if (_currentTotalSelectionCount < widget.maxCount) {
          _maxSelectionMessageShown = false;
        }
        _rebuildSelectedOrder();
      });
      return;
    }

    if (_currentTotalSelectionCount >= widget.maxCount) {
      _showMaxSelectionMessage();
      return;
    }
    if (asset.type == AssetType.video && asset.duration > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video cannot be more than 1 minute')),
      );
      return;
    }

    setState(() {
      _selectedIds.add(asset.id);
      _pendingAssets.add(asset);
      if (_currentTotalSelectionCount < widget.maxCount) {
        _maxSelectionMessageShown = false;
      }
      _rebuildSelectedOrder();
    });
  }

  void _showMaxSelectionMessage() {
    if (_maxSelectionMessageShown) {
      return;
    }
    _maxSelectionMessageShown = true;
    _maxSelectionMessageTimer?.cancel();
    setState(() => _isMaxSelectionMessageVisible = true);
    _maxSelectionMessageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isMaxSelectionMessageVisible = false);
      }
    });
  }

  Future<void> _finishSelection() async {
    await widget.onAssetsDone(_pendingAssets, Set<String>.from(_selectedIds));
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    if (_isLoading)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!_hasPermission)
                      SliverFillRemaining(child: _buildPermissionDenied())
                    else
                      ...[
                        if (_hasLimitedPermission)
                          SliverToBoxAdapter(
                            child: _buildLimitedAccessNotice(),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 92),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final asset = _assets[index];
                              _maybeLoadMore(index);
                              return _AssetTile(
                                asset: asset,
                                thumbnailFuture: _thumbnailFor(
                                  asset,
                                  const ThumbnailSize.square(240),
                                ),
                                selectionNumber: _selectedOrder[asset.id],
                                onTap: () => _toggleAsset(asset),
                              );
                            }, childCount: _assets.length),
                          ),
                        ),
                        if (_isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 96),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                  ],
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: SafeArea(
                    child: FloatingActionButton(
                      heroTag: 'media_done',
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.black,
                      onPressed: _finishSelection,
                      child: const Icon(Icons.check),
                    ),
                  ),
                ),
                if (_pendingAssets.isNotEmpty)
                  Positioned(
                    left: 8,
                    right: 86,
                    bottom: 18,
                    child: SafeArea(
                      child: SizedBox(
                        height: 54,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _pendingAssets.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final asset = _pendingAssets[index];
                            return _SelectedAssetPreview(
                              asset: asset,
                              thumbnailFuture: _thumbnailFor(
                                asset,
                                const ThumbnailSize(90, 120),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: _pendingAssets.isEmpty ? 92 : 84,
                  child: SafeArea(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _isMaxSelectionMessageVisible
                          ? const _PickerLimitMessage()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2D2F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedAlbum?.id,
                    dropdownColor: const Color(0xFF2A2D2F),
                    iconEnabledColor: Colors.white,
                    isExpanded: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    items: _albums
                        .map(
                          (album) => DropdownMenuItem<String>(
                            value: album.id,
                            child: Text(
                              album.isAll ? 'Recent' : album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (albumId) {
                      if (albumId == null) {
                        return;
                      }
                      final album = _albums.firstWhere(
                        (album) => album.id == albumId,
                        orElse: () => _albums.first,
                      );
                      _changeAlbum(album);
                    },
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _finishSelection,
            child: Text(
              _currentTotalSelectionCount == 0
                  ? 'Done'
                  : 'Done ($_currentTotalSelectionCount)',
              style: const TextStyle(color: Color(0xFF25D366)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library, color: Colors.white70, size: 44),
            const SizedBox(height: 12),
            const Text(
              'Allow photo access to choose item media.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitedAccessNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF252A28),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Only selected media is visible. Allow full gallery access in settings.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}


class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.thumbnailFuture,
    required this.selectionNumber,
    required this.onTap,
  });

  final AssetEntity asset;
  final Future<Uint8List?> thumbnailFuture;
  final int? selectionNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FutureBuilder<Uint8List?>(
                future: thumbnailFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return Container(color: const Color(0xFF252A28));
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
            ),
            if (asset.type == AssetType.video)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(Icons.play_circle_fill, color: Colors.white),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: selectionNumber != null
                    ? const Color(0xFF25D366)
                    : Colors.black54,
                child: Text(
                  selectionNumber?.toString() ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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

class _SelectedAssetPreview extends StatelessWidget {
  const _SelectedAssetPreview({
    required this.asset,
    required this.thumbnailFuture,
  });

  final AssetEntity asset;
  final Future<Uint8List?> thumbnailFuture;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 42,
          height: 54,
          child: FutureBuilder<Uint8List?>(
            future: thumbnailFuture,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(color: const Color(0xFF252A28));
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
        ),
      ),
    );
  }
}

class _SelectedMedia {
  const _SelectedMedia({required this.file, required this.type, this.assetId});

  final File file;
  final String type;
  final String? assetId;

  bool get isVideo => type == 'video';
}

class _UploadedMedia {
  const _UploadedMedia({
    required this.url,
    required this.type,
    this.thumbnailUrl,
  });

  final String url;
  final String type;
  final String? thumbnailUrl;

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type,
      if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
        'thumbnail_url': thumbnailUrl,
    };
  }
}
