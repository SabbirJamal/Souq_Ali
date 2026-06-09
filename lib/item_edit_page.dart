import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'camera_capture_page.dart';
import 'seller_session_guard.dart';
import 'utils/formatters.dart';
import 'widgets/item_edit/edit_widgets.dart';
import 'widgets/item_add/selected_media_preview_dialog.dart';
import 'widgets/app_toast.dart';
import 'widgets/media_carousel.dart';
import 'widgets/price_with_currency.dart';

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
  static const _maxPriceValue = 1000000.0;

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;
  final _priceFocusNode = FocusNode();

  final _picker = ImagePicker();
  final List<EditableMedia> _media = [];
  final List<MediaItem> _removedMedia = [];
  final _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];

  String _lastValidPriceText = '';
  late String _priceUnit;
  String _sellerDefaultLocation = '';
  bool _isSaving = false;
  bool _showLocationError = false;
  bool _showPriceError = false;
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
    final result = await Navigator.push<Object?>(context, _cameraCaptureRoute());
    if (result == CameraCaptureAction.openGallery) {
      await _pickGalleryMedia();
      return;
    }
    if (result is! CapturedMedia) return;
    if (!_canAddMedia()) return;
    if (result.isVideo && !await _isVideoWithinLimit(result.file)) {
      _showMessage('Video cannot be more than 1 minute');
      return;
    }

    setState(() {
      _media.add(EditableMedia.newMedia(SelectedMedia(file: result.file, type: result.type)));
    });
  }

  Future<void> _openMediaSheet() async {
    await _openCamera();
  }

  Route<Object?> _cameraCaptureRoute() => PageRouteBuilder<Object?>(
    pageBuilder: (context, animation, secondaryAnimation) => const CameraCapturePage(),
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );

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
    if (files.isEmpty) return;

    final selected = <EditableMedia>[];
    for (final file in files.take(remaining)) {
      final media = SelectedMedia.fromXFile(file);
      if (media.isVideo && !await _isVideoWithinLimit(media.file)) {
        _showMessage('Video cannot be more than 1 minute');
        continue;
      }
      selected.add(EditableMedia.newMedia(media));
    }

    if (selected.isEmpty) return;
    setState(() => _media.addAll(selected));
  }

  bool _canAddMedia() => _media.length < _maxMediaCount;

  Future<bool> _isVideoWithinLimit(File file) async {
    final info = await VideoCompress.getMediaInfo(file.path);
    return (info.duration ?? 0) <= 60000;
  }

  bool _canRemoveMedia() => _media.length > 1;

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
    final isLiveItem = _isLiveItem;
    final isTransitPost = !isLiveItem && _isTransitPost;
    final name = _nameController.text.trim();
    final price = _priceController.text.trim();
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

    setState(() => _isSaving = true);
    try {
      final sellerUid = widget.itemData['seller_uid']?.toString();
      if (sellerUid == null || sellerUid.isEmpty) {
        _showMessage('Please login again');
        return;
      }
      if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;

      final newEntries = _media.where((m) => !m.isExisting).toList();
      final uploadedMedia = await _uploadNewMedia(sellerUid, newEntries);
      final allMedia = _media.map((m) => m.isExisting ? m.existing! : uploadedMedia[m]!).toList();
      
      final imageUrls = allMedia.where((m) => !m.isVideo).map((m) => m.url).toList();
      final mediaFileMaps = allMedia.map((m) => {
        'url': m.url,
        'type': m.type,
        if (m.thumbnailUrl != null) 'thumbnail_url': m.thumbnailUrl,
      }).toList();

      final priceUnit = isLiveItem ? _priceUnit : '';
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

      await FirebaseFirestore.instance.collection('items').doc(widget.docId).update(updateData);
      await _deleteRemovedStorageFiles();

      if (mounted) {
        Navigator.pop(context);
        _showMessage('Item updated');
      }
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Map<EditableMedia, MediaItem>> _uploadNewMedia(String sellerUid, List<EditableMedia> entries) async {
    final uploaded = <EditableMedia, MediaItem>{};
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

  Future<void> _deleteRemovedStorageFiles() async {
    for (final m in _removedMedia) {
      try {
        if (m.thumbnailUrl?.isNotEmpty == true) await FirebaseStorage.instance.refFromURL(m.thumbnailUrl!).delete();
        await FirebaseStorage.instance.refFromURL(m.url).delete();
      } catch (_) {}
    }
  }

  void _showMessage(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  void _handlePriceChanged(String val) {
    final raw = val.replaceAll(',', '');
    if ('.'.allMatches(raw).length > 1) { _setPriceText(_lastValidPriceText); return; }
    var next = raw.startsWith('.') ? '0$raw' : raw;
    if (next.isNotEmpty && !RegExp(r'^\d+\.?\d*$').hasMatch(next)) { _setPriceText(_lastValidPriceText); return; }
    if (double.tryParse(next) != null && double.parse(next) > _maxPriceValue) { _setPriceText(_lastValidPriceText); return; }
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
    final clean = val.replaceAll(',', '');
    final p = double.tryParse(clean);
    return (p == null || p > _maxPriceValue) ? null : p.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final pageColor = _isLiveItem ? const Color(0xFFFFE9EC) : const Color(0xFFF4FBF7);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.black, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: pageColor,
        body: Column(
          children: [
            Container(height: MediaQuery.paddingOf(context).top, color: Colors.black),
            Container(height: kToolbarHeight, color: pageColor, alignment: Alignment.centerLeft, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildMediaEditor(),
                  const SizedBox(height: 15),
                  if (!_isLiveItem) ...[_buildTransitToggle(), const SizedBox(height: 14)],
                  _field(_nameController, 'Item Name', maxLength: 80),
                  const SizedBox(height: 14),
                  if (_isLiveItem) ...[
                    Row(
                      children: [
                        Expanded(flex: 3, child: _field(_priceController, _showPriceError ? 'PRICE REQUIRED' : 'Price', prefixIconWidget: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), focusNode: _priceFocusNode, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onTap: () { if (_priceController.text == '0') _setPriceText(''); if (_showPriceError) setState(() => _showPriceError = false); }, onChanged: _handlePriceChanged, hasErrorBorder: _showPriceError)),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: SizedBox(
                          height: 56,
                          child: DropdownButtonFormField<String>(
                            initialValue: _priceUnit,
                            isExpanded: true,
                            items: _priceUnits.map((u) => DropdownMenuItem(value: u, child: Text(u.replaceFirst('/ ', '')))).toList(),
                            onChanged: _isSaving ? null : (v) => setState(() => _priceUnit = v!),
                            decoration: InputDecoration(filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
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
                        child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)) : const Text('Update', style: TextStyle(fontSize: 16)),
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
    if (_isTransitPost) return 76;
    return 20;
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
                    child: EditableMediaTile(media: _media[i], sequenceNumber: i + 1, isDropTarget: cand.isNotEmpty, onRemove: () { if (_canRemoveMedia()) setState(() { final r = _media.removeAt(i); if (r.isExisting) _removedMedia.add(r.existing!); }); }),
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
      height: 40,
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
