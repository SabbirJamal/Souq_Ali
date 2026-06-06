import 'dart:async';
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
import 'utils/formatters.dart';
import 'widgets/audio_description_field.dart';
import 'widgets/item_edit/edit_widgets.dart';
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
  final List<EditableMedia> _media = [];
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
  late final bool _isLiveItem;
  bool _isTransitPost = false;

  @override
  void initState() {
    super.initState();
    _isLiveItem = widget.itemData['status']?.toString().toLowerCase() == 'live';
    _isTransitPost = !_isLiveItem && widget.itemData['is_transit'] == true;
    _nameController = TextEditingController(text: widget.itemData['item_name'] ?? '');
    final existingPrice = widget.itemData['price_number']?.toString() ?? '';
    _priceController = TextEditingController(
      text: isZeroPrice(existingPrice) ? '' : _formatEditingPrice(existingPrice),
    );
    _lastValidPriceText = _priceController.text;
    _locationController = TextEditingController(text: widget.itemData['location'] ?? '');
    _media.addAll(mediaItemsFromMap(widget.itemData).map(EditableMedia.existing));
    _existingAudioUrl = widget.itemData['audio_description_url']?.toString().trim();
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
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCapturePage()),
    );
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111614),
      shape: const RoundedRectangleBorder(),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Row(
            children: [
              Expanded(
                child: MediaSheetButton(
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
                child: MediaSheetButton(
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
      ),
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

  Future<void> _save() async {
    final isLiveItem = _isLiveItem;
    final isTransitPost = !isLiveItem && _isTransitPost;
    final name = _nameController.text.trim();
    final price = isLiveItem && _priceController.text.trim().isEmpty ? '0' : _priceController.text.trim();
    final location = isTransitPost ? 'TRANSIT' : _locationController.text.trim();

    if (!isTransitPost && location.isEmpty) {
      setState(() => _showLocationError = true);
      return;
    }
    final normalizedPrice = isLiveItem ? _normalizePrice(price) : '';
    if (isLiveItem && (normalizedPrice == null || double.parse(normalizedPrice) <= 0)) {
      _showMessage('Valid price is required for live items');
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

      final newEntries = _media.where((m) => !m.isExisting).toList();
      final uploadedMedia = await _uploadNewMedia(sellerUid, newEntries);
      final allMedia = _media.map((m) => m.isExisting ? m.existing! : uploadedMedia[m]!).toList();
      
      final imageUrls = allMedia.where((m) => !m.isVideo).map((m) => m.url).toList();
      final mediaFileMaps = allMedia.map((m) => {
        'url': m.url,
        'type': m.type,
        if (m.thumbnailUrl != null) 'thumbnail_url': m.thumbnailUrl,
      }).toList();

      final audioUrl = isLiveItem ? null : await _uploadAudioDescription(sellerUid);
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

      if (isLiveItem || _removeExistingAudio) {
        updateData['audio_description_url'] = FieldValue.delete();
        updateData['audio_description_duration_seconds'] = FieldValue.delete();
      }
      if (audioUrl != null) {
        updateData['audio_description_url'] = audioUrl;
        updateData['audio_description_duration_seconds'] = _audioDescriptionDuration.inSeconds;
      }

      await FirebaseFirestore.instance.collection('items').doc(widget.docId).update(updateData);
      await _deleteRemovedStorageFiles();
      if (audioUrl != null || isLiveItem) await _deleteRemovedAudioIfNeeded(true);

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

  Future<String?> _uploadAudioDescription(String sellerUid) async {
    if (_audioDescriptionPath == null) return null;
    final file = File(_audioDescriptionPath!);
    if (!await file.exists()) return null;
    final ref = FirebaseStorage.instance.ref().child('items/$sellerUid/audio_description_edit_${DateTime.now().millisecondsSinceEpoch}.m4a');
    final snap = await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
    return snap.ref.getDownloadURL();
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

  Future<void> _deleteRemovedAudioIfNeeded(bool replaced) async {
    if (_existingAudioUrl != null && (_removeExistingAudio || replaced)) {
      try { await FirebaseStorage.instance.refFromURL(_existingAudioUrl!).delete(); } catch (_) {}
    }
  }

  void _showMessage(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                  const SizedBox(height: 20),
                  if (!_isLiveItem) ...[_buildTransitToggle(), const SizedBox(height: 14)],
                  _field(_nameController, 'Item Name', maxLength: 80),
                  const SizedBox(height: 14),
                  if (!_isLiveItem) ...[
                    AudioDescriptionField(
                      isDisabled: _isSaving,
                      resetToken: _audioResetToken,
                      initialUrl: _existingAudioUrl,
                      initialDuration: Duration(seconds: (widget.itemData['audio_description_duration_seconds'] as num?)?.toInt() ?? 0),
                      onChanged: (path, dur, rem) { _audioDescriptionPath = path; _audioDescriptionDuration = dur; _removeExistingAudio = rem; },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_isLiveItem) ...[
                    Row(
                      children: [
                        Expanded(flex: 3, child: _field(_priceController, 'Price', prefixIconWidget: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), focusNode: _priceFocusNode, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onTap: () => _priceController.text == '0' ? _setPriceText('') : null, onChanged: _handlePriceChanged)),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: DropdownButtonFormField<String>(
                          value: _priceUnit,
                          items: _priceUnits.map((u) => DropdownMenuItem(value: u, child: Text(u.replaceFirst('/ ', '')))).toList(),
                          onChanged: _isSaving ? null : (v) => setState(() => _priceUnit = v!),
                          decoration: InputDecoration(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        )),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_isLiveItem || !_isTransitPost)
                    _field(_locationController, 'Location', prefixIconWidget: const Center(widthFactor: 1, child: Text('📍', style: TextStyle(fontSize: 20))), maxLength: 30, errorText: _showLocationError ? 'Required' : null, onChanged: (_) => _showLocationError ? setState(() => _showLocationError = false) : null),
                  const SizedBox(height: 24),
                  FractionallySizedBox(
                    widthFactor: 0.75,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: _isLiveItem ? const Color(0xFFE92808) : const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Update', style: TextStyle(fontSize: 16)),
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

  Widget _buildTransitToggle() => Container(
    height: 58,
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Expanded(child: TransitStatusButton(text: 'IN STOCK', isSelected: !_isTransitPost, onTap: () => setState(() { _isTransitPost = false; _locationController.clear(); }))),
      const VerticalDivider(width: 1),
      Expanded(child: TransitStatusButton(text: 'TRANSIT', isSelected: _isTransitPost, onTap: () => setState(() { _isTransitPost = true; _locationController.text = 'TRANSIT'; })))
    ]),
  );

  Widget _buildMediaEditor() {
    final count = _media.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: count < _maxMediaCount ? count + 1 : count,
      itemBuilder: (ctx, i) {
        if (i == count) return Center(child: IconButton.filled(onPressed: _openMediaSheet, icon: const Icon(Icons.add_a_photo, size: 32), style: IconButton.styleFrom(fixedSize: const Size(76, 76), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), backgroundColor: Colors.white, foregroundColor: Colors.black)));
        return DragTarget<int>(
          onAcceptWithDetails: (d) => _moveMedia(d.data, i),
          builder: (ctx, cand, _) => LongPressDraggable<int>(
            data: i,
            feedback: SizedBox(width: 100, height: 100, child: EditableMediaTile(media: _media[i], sequenceNumber: i + 1, isDropTarget: false, onRemove: null)),
            child: EditableMediaTile(media: _media[i], sequenceNumber: i + 1, isDropTarget: cand.isNotEmpty, onRemove: () { if (_canRemoveMedia()) setState(() { final r = _media.removeAt(i); if (r.isExisting) _removedMedia.add(r.existing!); }); }),
          ),
        );
      },
    );
  }

  Widget _field(TextEditingController ctrl, String label, {Widget? prefixIconWidget, int? maxLength, String? errorText, TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters, VoidCallback? onTap, ValueChanged<String>? onChanged, FocusNode? focusNode}) => TextField(
    controller: ctrl, focusNode: focusNode, readOnly: _isSaving, maxLength: maxLength, keyboardType: keyboardType, inputFormatters: inputFormatters, onTap: onTap, onChanged: onChanged,
    decoration: InputDecoration(filled: true, fillColor: Colors.white, labelText: label, prefixIcon: prefixIconWidget, errorText: errorText, counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
  );
}
