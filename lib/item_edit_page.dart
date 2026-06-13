import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_compress/video_compress.dart';

import 'camera_capture_page.dart';
import 'seller_home_page.dart';
import 'seller_session_guard.dart';
import 'upload_status_manager.dart';
import 'utils/formatters.dart';
import 'utils/price_input.dart';
import 'widgets/item_edit/edit_widgets.dart';
import 'widgets/item_add/selected_media_preview_dialog.dart';
import 'widgets/app_status_bar.dart';
import 'widgets/app_toast.dart';
import 'widgets/media_carousel.dart';
import 'widgets/price_with_currency.dart';
import 'widgets/seller_bottom_nav_bar.dart';

Route<void> _instantSellerTabRoute(int index) {
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) =>
        SellerHomePage(initialTabIndex: index),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

Route<void> _instantListingsRoute(String status) {
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) => SellerHomePage(
      initialTabIndex: 3,
      initialListingsStatus: status,
    ),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

class ItemEditPage extends StatefulWidget {
  const ItemEditPage({super.key, required this.docId, required this.itemData, this.onSessionInvalid});

  final String docId;
  final Map<String, dynamic> itemData;
  final VoidCallback? onSessionInvalid;

  @override
  State<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends State<ItemEditPage> {
  static const _maxMediaCount = 8;
  static const _maxMediaMessage =
      '8 Media selected, please delete media to select new media';

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;
  final _priceFocusNode = FocusNode();

  final List<EditableMedia> _media = [];
  final List<MediaItem> _removedMedia = [];
  final _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];

  String _lastValidPriceText = '';
  late String _priceUnit;
  String _sellerDefaultLocation = '';
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _showLocationError = false;
  bool _showPriceError = false;
  bool _showEmbeddedCamera = false;
  late final bool _isLiveItem;
  bool _isTransitPost = false;

  @override
  void initState() {
    super.initState();
    _isLiveItem = widget.itemData['status']?.toString().toLowerCase() == 'live';
    final existingLocation = widget.itemData['location']?.toString().trim() ?? '';
    _isTransitPost =
        !_isLiveItem &&
        (widget.itemData['is_transit'] == true ||
            existingLocation.toLowerCase().contains('transit'));
    _nameController = TextEditingController(text: widget.itemData['item_name'] ?? '');
    final existingPrice = widget.itemData['price_number']?.toString() ?? '';
    _priceController = TextEditingController(
      text: isZeroPrice(existingPrice) ? '' : _formatEditingPrice(existingPrice),
    );
    _lastValidPriceText = _priceController.text;
    _locationController = TextEditingController(text: existingLocation);
    _media.addAll(mediaItemsFromMap(widget.itemData).map(EditableMedia.existing));
    _priceUnit = _priceUnits.contains(widget.itemData['price_unit'])
        ? widget.itemData['price_unit'].toString()
        : '/ kg';
    _loadSellerDefaultLocation();
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
    if (!_canAddMedia()) {
      _showMessage(_maxMediaMessage);
      return;
    }
    setState(() => _showEmbeddedCamera = true);
  }

  Future<void> _handleEmbeddedGallery() async {
    setState(() => _showEmbeddedCamera = false);
    await _openGallerySheet();
  }

  Future<void> _handleEmbeddedCapture(CapturedMedia result) async {
    if (!_canAddMedia()) {
      setState(() => _showEmbeddedCamera = false);
      return;
    }
    if (result.isVideo && !await _isVideoWithinLimit(result.file)) {
      setState(() => _showEmbeddedCamera = false);
      _showMessage('Video cannot be more than 1 minute');
      return;
    }

    setState(() {
      _media.add(EditableMedia.newMedia(SelectedMedia(file: result.file, type: result.type)));
      _showEmbeddedCamera = false;
    });
  }

  void _handleEmbeddedCaptureAndContinue(CapturedMedia result) {
    if (!_canAddMedia()) {
      return;
    }
    setState(() {
      _media.add(EditableMedia.newMedia(SelectedMedia(file: result.file, type: result.type)));
      _showEmbeddedCamera = _media.length < _maxMediaCount;
    });
  }

  Future<void> _openMediaSheet() async {
    await _openCamera();
  }

  Future<void> _openGallerySheet() async {
    final selection = await CameraCapturePage.openGalleryPicker(
      context,
      selectedIds: _media
          .where((media) => !media.isExisting)
          .map((media) => media.selected?.assetId)
          .whereType<String>()
          .toSet(),
      selectedCount: _media.length,
      maxCount: _maxMediaCount,
      maxSelectionMessage: _maxMediaMessage,
    );
    if (selection == null) return;
    await _addGalleryAssets(selection.assets, selection.selectedIds);
  }

  Future<void> _addGalleryAssets(List<AssetEntity> assets, Set<String> selectedIds) async {
    final newMedia = <EditableMedia>[];
    for (final asset in assets) {
      if (_media.any((media) => media.selected?.assetId == asset.id)) continue;
      final file = await asset.fileWithSubtype ?? await asset.file;
      if (file == null) continue;
      newMedia.add(
        EditableMedia.newMedia(
          SelectedMedia(
            file: file,
            type: asset.type == AssetType.video ? 'video' : 'image',
            assetId: asset.id,
          ),
        ),
      );
    }
    setState(() {
      _media.removeWhere((media) {
        final assetId = media.selected?.assetId;
        return assetId != null && !selectedIds.contains(assetId);
      });
      _media.addAll(newMedia);
    });
  }

  bool _canAddMedia() => _media.length < _maxMediaCount;

  Future<bool> _isVideoWithinLimit(File file) async {
    final info = await VideoCompress.getMediaInfo(file.path);
    return (info.duration ?? 0) <= 60000;
  }

  void _moveMedia(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    setState(() {
      final item = _media.removeAt(fromIndex);
      _media.insert(toIndex, item);
    });
  }

  Future<void> _openSelectedMediaPreview(int index) async {
    if (index < 0 || index >= _media.length) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SelectedMediaPreviewDialog(
        initialIndex: index,
        items: _media
            .map(
              (media) => media.isExisting
                  ? SelectedMediaPreviewItem.network(
                      url: media.existing!.url,
                      thumbnailUrl: media.existing!.thumbnailUrl,
                      isVideo: media.isVideo,
                    )
                  : SelectedMediaPreviewItem.file(
                      file: media.selected!.file,
                      isVideo: media.isVideo,
                    ),
            )
            .toList(growable: false),
        onDelete: (deleteIndex) {
          if (!mounted ||
              deleteIndex < 0 ||
              deleteIndex >= _media.length) {
            return;
          }
          setState(() {
            final removed = _media.removeAt(deleteIndex);
            if (removed.isExisting) _removedMedia.add(removed.existing!);
          });
        },
      ),
    );
  }

  Future<void> _loadSellerDefaultLocation() async {
    final sellerUid = widget.itemData['seller_uid']?.toString();
    if (sellerUid == null || sellerUid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('sellers').doc(sellerUid).get();
      final location = doc.data()?['location']?.toString().trim() ?? '';
      if (!mounted || location.isEmpty) return;
      _sellerDefaultLocation = location;
      if (!_isTransitPost && _locationController.text.trim().isEmpty) {
        setState(() => _locationController.text = location);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_media.isEmpty) {
      _showMessage('Minimum 1 media required');
      return;
    }
    final isLiveItem = _isLiveItem;
    final isTransitPost = !isLiveItem && _isTransitPost;
    final name = _nameController.text.trim();
    final price = _priceController.text.trim();
    final selectedPriceUnit = _priceUnit;
    final location = isTransitPost ? '🚚 Transit' : _locationController.text.trim();

    if (!isTransitPost && location.isEmpty) {
      setState(() => _showLocationError = true);
      return;
    }
    final normalizedPrice = isLiveItem ? _normalizePrice(price) : '';
    if (isLiveItem && (normalizedPrice == null || double.parse(normalizedPrice) <= 0)) {
      setState(() => _showPriceError = true);
      _priceFocusNode.requestFocus();
      return;
    }

    final sellerUid = widget.itemData['seller_uid']?.toString();
    if (sellerUid == null || sellerUid.isEmpty) {
      _showMessage('Please login again');
      return;
    }
    if (!await SellerSessionGuard.ensureActive(
      context,
      onInvalid: widget.onSessionInvalid ?? () {},
    )) {
      return;
    }
    if (!mounted) return;

    setState(() => _isSaving = true);
    final mediaSnapshot = List<EditableMedia>.of(_media);
    final removedSnapshot = List<MediaItem>.of(_removedMedia);
    final firstMedia = mediaSnapshot.isNotEmpty ? mediaSnapshot.first : null;
    final uploadId = UploadStatusManager.uploading(
      target: UploadStatusTarget.listings,
      thumbnail: firstMedia?.selected?.file,
      thumbnailUrl: firstMedia?.existing?.thumbnailUrl?.trim().isNotEmpty == true
          ? firstMedia!.existing!.thumbnailUrl!.trim()
          : firstMedia?.existing?.url,
    );
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        _instantListingsRoute(isLiveItem ? 'live' : 'post'),
        (_) => false,
      );
    }

    try {
      final newEntries = mediaSnapshot.where((m) => !m.isExisting).toList();
      final uploadedMedia = await _uploadNewMedia(sellerUid, newEntries, uploadId);
      final allMedia = mediaSnapshot.map((m) => m.isExisting ? m.existing! : uploadedMedia[m]!).toList();
      
      final imageUrls = allMedia.where((m) => !m.isVideo).map((m) => m.url).toList();
      final mediaFileMaps = allMedia.map((m) => {
        'url': m.url,
        'type': m.type,
        if (m.thumbnailUrl != null) 'thumbnail_url': m.thumbnailUrl,
      }).toList();

      final priceUnit = isLiveItem ? selectedPriceUnit : '';
      final itemPrice = isLiveItem ? 'OMR ${_formatPriceWithCommas(normalizedPrice!)} $priceUnit' : '';

      final updateData = <String, dynamic>{
        'status': isLiveItem ? 'live' : 'post',
        'is_transit': isTransitPost,
        'item_name': name,
        'price_number': normalizedPrice,
        'price_unit': priceUnit,
        'item_price': itemPrice,
        'location': location,
        'media_files': mediaFileMaps,
        'image_urls': imageUrls,
        'updated_at': FieldValue.serverTimestamp(),
      };

      UploadStatusManager.progress(uploadId, 0.96);
      await FirebaseFirestore.instance.collection('items').doc(widget.docId).update(updateData);
      await _deleteStorageFiles(removedSnapshot);
      UploadStatusManager.success(uploadId);
      refreshLatestListingsPage();
    } catch (e) {
      UploadStatusManager.error(uploadId, 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Map<EditableMedia, MediaItem>> _uploadNewMedia(String sellerUid, List<EditableMedia> entries, String uploadId) async {
    final uploaded = <EditableMedia, MediaItem>{};
    final total = entries.isEmpty ? 1 : entries.length;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final sel = entry.selected!;
      final compressed = sel.isVideo ? await _compressVideo(sel.file) : await _compressImage(sel.file);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_edit_$i';
      final ref = FirebaseStorage.instance.ref().child('items/$sellerUid/$fileName.${sel.isVideo ? 'mp4' : 'jpg'}');
      
      final snap = await ref.putFile(compressed, SettableMetadata(contentType: sel.isVideo ? 'video/mp4' : 'image/jpeg'));
      final thumb = sel.isVideo 
          ? await _uploadVideoThumbnail(videoFile: compressed, sellerUid: sellerUid, fileName: int.parse(fileName.split('_').first), index: i)
          : await _uploadImageThumbnail(imageFile: compressed, sellerUid: sellerUid, fileName: int.parse(fileName.split('_').first), index: i);
      
      uploaded[entry] = MediaItem(url: await snap.ref.getDownloadURL(), type: sel.type, thumbnailUrl: thumb);
      UploadStatusManager.progress(uploadId, ((i + 1) / total) * 0.86);
    }
    return uploaded;
  }

  Future<String?> _uploadVideoThumbnail({required File videoFile, required String sellerUid, required int fileName, required int index}) async {
    try {
      final thumb = await VideoCompress.getFileThumbnail(videoFile.path, quality: 45);
      final ref = FirebaseStorage.instance.ref().child('items/$sellerUid/${fileName}_edit_${index}_thumb.jpg');
      final snap = await ref.putFile(thumb, SettableMetadata(contentType: 'image/jpeg'));
      return snap.ref.getDownloadURL();
    } catch (_) { return null; }
  }

  Future<String?> _uploadImageThumbnail({required File imageFile, required String sellerUid, required int fileName, required int index}) async {
    try {
      final temp = await getTemporaryDirectory();
      final path = '${temp.path}/${DateTime.now().microsecondsSinceEpoch}_feed.jpg';
      final res = await FlutterImageCompress.compressAndGetFile(imageFile.absolute.path, path, minWidth: 720, minHeight: 720, quality: 36);
      if (res == null) return null;
      final ref = FirebaseStorage.instance.ref().child('items/$sellerUid/${fileName}_edit_${index}_feed.jpg');
      final snap = await ref.putFile(File(res.path), SettableMetadata(contentType: 'image/jpeg'));
      return snap.ref.getDownloadURL();
    } catch (_) { return null; }
  }

  Future<File> _compressImage(File file) async {
    final temp = await getTemporaryDirectory();
    final path = '${temp.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final res = await FlutterImageCompress.compressAndGetFile(file.absolute.path, path, minWidth: 1080, minHeight: 1080, quality: 42);
    return res == null ? file : File(res.path);
  }

  Future<File> _compressVideo(File file) async {
    final info = await VideoCompress.compressVideo(file.path, quality: VideoQuality.LowQuality, deleteOrigin: false, includeAudio: true);
    return info?.path != null ? File(info!.path!) : file;
  }

  Future<void> _deleteStorageFiles(List<MediaItem> media) async {
    for (final m in media) {
      try {
        if (m.thumbnailUrl?.isNotEmpty == true) await FirebaseStorage.instance.refFromURL(m.thumbnailUrl!).delete();
        await FirebaseStorage.instance.refFromURL(m.url).delete();
      } catch (_) {}
    }
  }

  Future<void> _confirmDeleteItem() async {
    if (_isSaving || _isDeleting) return;
    if (!await SellerSessionGuard.ensureActive(
      context,
      onInvalid: widget.onSessionInvalid ?? () {},
    )) {
      return;
    }
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'Delete !',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'No',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'Yes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    await _deleteItem();
  }

  Future<void> _deleteItem() async {
    setState(() => _isDeleting = true);
    try {
      await _deleteItemStorageFiles();
      await _deleteSeenRecord();
      await FirebaseFirestore.instance.collection('items').doc(widget.docId).delete();
      if (!mounted) return;
      AppToast.show(context, 'Item deleted');
      Navigator.of(context).pushAndRemoveUntil(
        _instantListingsRoute(_isLiveItem ? 'live' : 'post'),
        (_) => false,
      );
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _deleteItemStorageFiles() async {
    final urls = <String>{};
    final imageUrls = widget.itemData['image_urls'];
    if (imageUrls is List) {
      for (final url in imageUrls) {
        final text = url?.toString().trim() ?? '';
        if (text.isNotEmpty) urls.add(text);
      }
    }

    final mediaFiles = widget.itemData['media_files'];
    if (mediaFiles is List) {
      for (final media in mediaFiles) {
        if (media is! Map) continue;
        final url = media['url']?.toString().trim() ?? '';
        final thumbnailUrl = media['thumbnail_url']?.toString().trim() ?? '';
        if (url.isNotEmpty) urls.add(url);
        if (thumbnailUrl.isNotEmpty) urls.add(thumbnailUrl);
      }
    }

    final legacyAudioUrl =
        widget.itemData['audio_description_url']?.toString().trim() ?? '';
    if (legacyAudioUrl.isNotEmpty) urls.add(legacyAudioUrl);

    await Future.wait(urls.map((url) async {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }));
  }

  Future<void> _deleteSeenRecord() async {
    try {
      final seenRef =
          FirebaseFirestore.instance.collection('item_seen').doc(widget.docId);
      final viewers = await seenRef.collection('viewers').limit(100).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final viewer in viewers.docs) {
        batch.delete(viewer.reference);
        batch.delete(
          FirebaseFirestore.instance
              .collection('viewer_seen')
              .doc(viewer.id)
              .collection('items')
              .doc(widget.docId),
        );
      }
      batch.delete(seenRef);
      await batch.commit();
    } catch (_) {}
  }

  void _showMessage(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  void _handlePriceChanged(String val) {
    final raw = val.replaceAll(',', '');
    if ('.'.allMatches(raw).length > 1) { _setPriceText(_lastValidPriceText); return; }
    var next = raw.startsWith('.') ? '0$raw' : raw;
    if (next.isNotEmpty && !RegExp(r'^\d+\.?\d*$').hasMatch(next)) { _setPriceText(_lastValidPriceText); return; }
    if (double.tryParse(next) != null && double.parse(next) > maxAllowedPrice) { _setPriceText(_lastValidPriceText); return; }
    final fmt = _formatEditingPrice(next);
    _lastValidPriceText = fmt;
    if (fmt != val) _setPriceText(fmt);
  }

  void _setPriceText(String val) {
    _priceController.value = TextEditingValue(text: val, selection: TextSelection.collapsed(offset: val.length));
  }

  String _formatEditingPrice(String val) {
    final clean = val.replaceAll(',', '');
    if (clean.isEmpty) return '';
    final parts = clean.split('.');
    final whole = _formatWholeNumber(parts.first);
    return clean.endsWith('.') ? '$whole.' : (parts.length == 2 ? '$whole.${parts.last}' : whole);
  }

  String _formatPriceWithCommas(String val) {
    final parts = val.split('.');
    return '${_formatWholeNumber(parts.first)}.${parts.length > 1 ? parts.last : '000'}';
  }

  String _formatWholeNumber(String val) {
    final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '0';
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final rev = digits.length - i;
      buf.write(digits[i]);
      if (rev > 1 && rev % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  String? _normalizePrice(String val) {
    return normalizePriceInput(val);
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = AppStatusBar.heightOf(context);
    if (_showEmbeddedCamera) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Column(
                children: [
                  SizedBox(height: statusBarHeight),
                  Expanded(
                    child: CameraCapturePage(
                      embedded: true,
                      selectedCount: _media.length,
                      maxCount: _maxMediaCount,
                      maxSelectionMessage: _maxMediaMessage,
                      onClose: () => setState(() => _showEmbeddedCamera = false),
                      onOpenGallery: _handleEmbeddedGallery,
                      onCaptured: _handleEmbeddedCapture,
                      onCapturedAndContinue: _handleEmbeddedCaptureAndContinue,
                    ),
                  ),
                ],
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppStatusBar(),
              ),
            ],
          ),
          bottomNavigationBar: SellerBottomNavBar(
            currentIndex: 2,
            onTap: _handleBottomNavTap,
            backgroundColor: const Color(0xFFF4FBF7),
          ),
        ),
      );
    }

    final pageColor = _isLiveItem ? const Color(0xFFFFE9EC) : const Color(0xFFF4FBF7);
    final contentDecoration = BoxDecoration(
      color: _isLiveItem ? null : const Color(0xFFF4FBF7),
      gradient: _isLiveItem
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFE9EC), Color(0xFFF4FBF7)],
            )
          : null,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.black, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: pageColor,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(height: statusBarHeight),
                Container(
                  height: kToolbarHeight,
                  color: pageColor,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _EditDeletePill(
                          isDeleting: _isDeleting,
                          onTap: _isDeleting ? null : _confirmDeleteItem,
                        ),
                      ),
                    ],
                  ),
                ),
            Expanded(
              child: DecoratedBox(
                decoration: contentDecoration,
                child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildMediaEditor(),
                  const SizedBox(height: 15),
                  _field(_nameController, 'Item Name', maxLength: 80),
                  const SizedBox(height: 14),
                  if (!_isLiveItem) ...[
                    _buildTransitToggle(),
                    const SizedBox(height: 14),
                  ],
                  if (_isLiveItem) ...[
                    Row(
                      children: [
                          Expanded(flex: 3, child: SizedBox(height: 56, child: _field(_priceController, _showPriceError ? 'PRICE REQUIRED' : 'Price', prefixIconWidget: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), focusNode: _priceFocusNode, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: const [PriceInputFormatter()], onTap: () { if (_priceController.text == '0') _setPriceText(''); if (_showPriceError) setState(() => _showPriceError = false); }, onChanged: _handlePriceChanged, hasErrorBorder: _showPriceError))),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: SizedBox(
                          height: 56,
                          child: DropdownButtonFormField<String>(
                            initialValue: _priceUnit,
                            isExpanded: true,
                            isDense: false,
                            items: _priceUnits.map((u) => DropdownMenuItem(value: u, child: Text(u.replaceFirst('/ ', '')))).toList(),
                            onChanged: _isSaving ? null : (v) => setState(() => _priceUnit = v!),
                            decoration: InputDecoration(filled: true, fillColor: Colors.white, constraints: const BoxConstraints.tightFor(height: 56), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                        )),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_isLiveItem || !_isTransitPost)
                    _field(_locationController, _showLocationError ? 'Location Required' : 'Location', prefixIconWidget: const Center(widthFactor: 1, child: Text('📍', style: TextStyle(fontSize: 20))), maxLength: 30, hasErrorBorder: _showLocationError, onChanged: (_) => _showLocationError ? setState(() => _showLocationError = false) : null),
                  SizedBox(height: _buttonAlignmentSpacerHeight),
                  const SizedBox(height: 24),
                  FractionallySizedBox(
                    widthFactor: 0.75,
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(backgroundColor: _isLiveItem ? const Color(0xFFE92808) : const Color(0xFF25D366), foregroundColor: Colors.white, padding: EdgeInsets.zero, minimumSize: const Size.fromHeight(40), tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)) : const Text('Update', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
              ],
            ),
            const Positioned(top: 0, left: 0, right: 0, child: AppStatusBar()),
          ],
        ),
        bottomNavigationBar: SellerBottomNavBar(
          currentIndex: 3,
          onTap: _handleBottomNavTap,
          backgroundColor: const Color(0xFFF4FBF7),
        ),
      ),
    );
  }

  void _handleBottomNavTap(int index) {
    if (index == 3) {
      Navigator.pop(context);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      _instantSellerTabRoute(index),
      (_) => false,
    );
  }

  Widget _buildTransitToggle() => _EditSegmentedSelector(
    leftText: 'IN STOCK',
    rightText: '🚚 TRANSIT',
    isRightSelected: _isTransitPost,
    leftSelectedColor: const Color(0xFF001341),
    rightSelectedColor: const Color(0xFFFF7801),
    onLeftTap: _isSaving ? null : () => setState(() {
      _isTransitPost = false;
      _locationController.text = _sellerDefaultLocation;
    }),
    onRightTap: _isSaving ? null : () => setState(() {
      _isTransitPost = true;
      _showLocationError = false;
    }),
  );

  double get _buttonAlignmentSpacerHeight {
    if (_isLiveItem) return 4;
    if (_isTransitPost) return 60;
    return 4;
  }

  Widget _buildMediaEditor() {
    final count = _media.length;
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 8.0;
      final tileSize = (constraints.maxWidth - (spacing * 2)) / 3;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: DragTarget<int>(
                onAcceptWithDetails: (d) => _moveMedia(d.data, i),
                builder: (ctx, cand, _) => LongPressDraggable<int>(
                  data: i,
                  feedback: SizedBox(width: tileSize, height: tileSize, child: EditableMediaTile(media: _media[i], sequenceNumber: i + 1, isDropTarget: false, onRemove: null)),
                  child: GestureDetector(
                    onTap: () => _openSelectedMediaPreview(i),
                    child: EditableMediaTile(media: _media[i], sequenceNumber: i + 1, isDropTarget: cand.isNotEmpty, onRemove: () => setState(() { final r = _media.removeAt(i); if (r.isExisting) _removedMedia.add(r.existing!); })),
                  ),
                ),
              ),
            ),
          _cameraAddButton(_openMediaSheet, size: tileSize),
        ],
      );
    });
  }

  Widget _cameraAddButton(VoidCallback onPressed, {double size = 76}) => IconButton.filled(
    onPressed: onPressed,
    icon: Icon(Icons.add_a_photo, size: size * 0.42),
    style: IconButton.styleFrom(
      fixedSize: Size.square(size),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
  );

  Widget _field(TextEditingController ctrl, String label, {Widget? prefixIconWidget, int? maxLength, String? errorText, bool hasErrorBorder = false, TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters, VoidCallback? onTap, ValueChanged<String>? onChanged, FocusNode? focusNode}) => TextField(
    controller: ctrl, focusNode: focusNode, readOnly: _isSaving, maxLength: maxLength, keyboardType: keyboardType, inputFormatters: inputFormatters, onTap: onTap, onChanged: onChanged,
    decoration: InputDecoration(filled: true, fillColor: Colors.white, labelText: label, floatingLabelBehavior: hasErrorBorder ? FloatingLabelBehavior.always : null, prefixIcon: prefixIconWidget, errorText: errorText, counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: hasErrorBorder ? OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)) : null, focusedBorder: hasErrorBorder ? OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)) : null),
  );
}

class _EditSegmentedSelector extends StatelessWidget {
  const _EditSegmentedSelector({
    required this.leftText,
    required this.rightText,
    required this.isRightSelected,
    required this.leftSelectedColor,
    required this.rightSelectedColor,
    required this.onLeftTap,
    required this.onRightTap,
  });

  final String leftText;
  final String rightText;
  final bool isRightSelected;
  final Color leftSelectedColor;
  final Color rightSelectedColor;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _EditSegmentButton(
              text: leftText,
              isSelected: !isRightSelected,
              selectedColor: leftSelectedColor,
              onTap: onLeftTap,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
            ),
          ),
          Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
          Expanded(
            child: _EditSegmentButton(
              text: rightText,
              isSelected: isRightSelected,
              selectedColor: rightSelectedColor,
              onTap: onRightTap,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _EditDeletePill extends StatelessWidget {
  const _EditDeletePill({required this.isDeleting, required this.onTap});

  final bool isDeleting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red,
            border: Border.all(color: Colors.black, width: 1.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isDeleting
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

class _EditSegmentButton extends StatelessWidget {
  const _EditSegmentButton({
    required this.text,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
    required this.borderRadius,
  });

  final String text;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? selectedColor : Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
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
