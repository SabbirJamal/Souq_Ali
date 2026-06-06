import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_compress/video_compress.dart';

import '../camera_capture_page.dart';
import '../seller_session.dart';
import '../upload_status_manager.dart';
import '../widgets/audio_description_field.dart';
import '../widgets/item_add/media_picker_sheet.dart';
import '../widgets/item_edit/edit_widgets.dart';
import '../widgets/price_with_currency.dart';

class SellerAddItemTab extends StatefulWidget {
  const SellerAddItemTab({
    super.key,
    this.onItemAddedDone,
    this.onItemUploadSuccess,
    this.onLiveModeChanged,
    this.isLive = false,
  });
  final ValueChanged<bool>? onItemAddedDone;
  final ValueChanged<bool>? onItemUploadSuccess;
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
  final List<SelectedMedia> _selectedMedia = [];
  final _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];
  String? _audioDescriptionPath;
  Duration _audioDescriptionDuration = Duration.zero;
  String _lastValidPriceText = '';
  String _priceUnit = '/ kg';
  int _audioResetToken = 0;
  bool _isUploading = false;
  bool _showLocationError = false;
  bool _showPriceError = false;
  bool _isLiveItem = false;
  bool _isTransitPost = false;

  @override
  void initState() {
    super.initState();
    _isLiveItem = widget.isLive;
    _loadDefaultSellerLocation();
    unawaited(CameraCapturePage.preloadCameras());
  }

  Future<void> _loadDefaultSellerLocation() async {
    final s = await SellerSession.current();
    if (s == null) return;
    final doc = await FirebaseFirestore.instance.collection('sellers').doc(s.sellerId).get();
    final loc = doc.data()?['location']?.toString().trim() ?? '';
    if (mounted && loc.isNotEmpty && _locationController.text.isEmpty) setState(() => _locationController.text = loc);
  }

  @override
  void dispose() {
    _nameController.dispose(); _priceController.dispose(); _priceFocusNode.dispose(); _locationController.dispose();
    VideoCompress.cancelCompression(); super.dispose();
  }

  Future<void> _openCamera() async {
    final res = await Navigator.push<Object?>(context, MaterialPageRoute(builder: (_) => const CameraCapturePage()));
    if (res == CameraCaptureAction.openGallery) { _openGallerySheet(); return; }
    if (res is! CapturedMedia) return;
    if (_selectedMedia.length >= _maxMediaCount) return;
    setState(() => _selectedMedia.add(SelectedMedia(file: res.file, type: res.type)));
  }

  Future<void> _openGallerySheet() async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF111614),
      builder: (ctx) => FractionallySizedBox(heightFactor: 0.85, child: MediaPickerSheet(
        selectedIds: _selectedMedia.map((m) => m.assetId).whereType<String>().toSet(),
        selectedCount: _selectedMedia.length, maxCount: _maxMediaCount, onAssetsDone: _addGalleryAssets,
      )),
    );
  }

  Future<void> _addGalleryAssets(List<AssetEntity> assets, Set<String> ids) async {
    final newMedia = <SelectedMedia>[];
    for (final a in assets) {
      if (_selectedMedia.any((m) => m.assetId == a.id)) continue;
      final f = await a.fileWithSubtype ?? await a.file;
      if (f != null) newMedia.add(SelectedMedia(file: f, type: a.type == AssetType.video ? 'video' : 'image', assetId: a.id));
    }
    setState(() {
      _selectedMedia.removeWhere((m) => m.assetId != null && !ids.contains(m.assetId));
      _selectedMedia.addAll(newMedia);
    });
  }

  Future<void> openMediaSheet() async {
    await _openCamera();
  }

  Future<void> _addItem() async {
    if (_selectedMedia.isEmpty) { _showMessage('Add at least 1 media'); return; }
    final name = _nameController.text.trim();
    final loc = _isTransitPost ? '🚚 Transit' : _locationController.text.trim();
    if (loc.isEmpty) { setState(() => _showLocationError = true); return; }
    final normPrice = _isLiveItem ? _normalizePrice(_priceController.text) : '';
    if (_isLiveItem && (normPrice == null || double.parse(normPrice) <= 0)) { setState(() => _showPriceError = true); _priceFocusNode.requestFocus(); return; }

    setState(() => _isUploading = true);
    try {
      final s = await SellerSession.current();
      if (s == null) return;
      UploadStatusManager.uploading();
      widget.onItemAddedDone?.call(_isLiveItem);

      final uploaded = await _uploadMedia(s.sellerId);
      final audioUrl = _isLiveItem ? null : await _uploadAudioDescription(s.sellerId);
      final price = _isLiveItem ? 'OMR ${_formatPriceWithCommas(normPrice!)} $_priceUnit' : '';
      
      await FirebaseFirestore.instance.collection('items').add({
        'seller_uid': s.sellerId, 'seller_name': s.name, 'seller_phone': s.phoneNumber,
        'status': _isLiveItem ? 'live' : 'post', 'is_transit': _isTransitPost, 'item_name': name,
        'item_price': price, 'price_number': normPrice, 'price_unit': _isLiveItem ? _priceUnit : '',
        'location': loc, 'image_urls': uploaded.where((m) => m.type == 'image').map((m) => m.url).toList(),
        'media_files': uploaded.map((m) => m.toMap()).toList(),
        if (audioUrl != null) 'audio_description_url': audioUrl,
        if (audioUrl != null) 'audio_description_duration_seconds': _audioDescriptionDuration.inSeconds,
        'created_at': FieldValue.serverTimestamp(), 'expires_at': Timestamp.fromDate(DateTime.now().add(Duration(hours: _isLiveItem ? 2 : 720))),
      });
      widget.onItemUploadSuccess?.call(_isLiveItem);
      UploadStatusManager.success();
      if (mounted) _clearForm();
    } catch (e) { UploadStatusManager.error('Upload failed: $e'); }
    finally { if (mounted) setState(() => _isUploading = false); }
  }

  Future<List<_UploadedMedia>> _uploadMedia(String uid) async {
    final res = <_UploadedMedia>[];
    for (var i = 0; i < _selectedMedia.length; i++) {
      final m = _selectedMedia[i];
      final comp = m.isVideo ? await _compressVideo(m.file) : await _compressImage(m.file);
      final name = '${DateTime.now().millisecondsSinceEpoch}_$i';
      final ref = FirebaseStorage.instance.ref().child('items/$uid/$name.${m.isVideo ? 'mp4' : 'jpg'}');
      final snap = await ref.putFile(comp, SettableMetadata(contentType: m.isVideo ? 'video/mp4' : 'image/jpeg'));
      final thumb = m.isVideo ? await _uploadThumb(comp, uid, name, i, true) : await _uploadThumb(comp, uid, name, i, false);
      res.add(_UploadedMedia(url: await snap.ref.getDownloadURL(), type: m.type, thumbnailUrl: thumb));
    }
    return res;
  }

  Future<String?> _uploadThumb(File f, String uid, String name, int i, bool isVid) async {
    try {
      final File thumb;
      if (isVid) thumb = await VideoCompress.getFileThumbnail(f.path, quality: 45);
      else {
        final path = '${(await getTemporaryDirectory()).path}/${DateTime.now().microsecondsSinceEpoch}_t.jpg';
        final res = await FlutterImageCompress.compressAndGetFile(f.path, path, minWidth: 720, minHeight: 720, quality: 36);
        if (res == null) return null;
        thumb = File(res.path);
      }
      final ref = FirebaseStorage.instance.ref().child('items/$uid/${name}_t.jpg');
      return await (await ref.putFile(thumb, SettableMetadata(contentType: 'image/jpeg'))).ref.getDownloadURL();
    } catch (_) { return null; }
  }

  Future<String?> _uploadAudioDescription(String uid) async {
    if (_audioDescriptionPath == null) return null;
    final f = File(_audioDescriptionPath!);
    if (!await f.exists()) return null;
    final ref = FirebaseStorage.instance.ref().child('items/$uid/audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
    return await (await ref.putFile(f, SettableMetadata(contentType: 'audio/mp4'))).ref.getDownloadURL();
  }

  Future<File> _compressImage(File f) async {
    final path = '${(await getTemporaryDirectory()).path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final res = await FlutterImageCompress.compressAndGetFile(f.path, path, minWidth: 1080, minHeight: 1080, quality: 42);
    return res == null ? f : File(res.path);
  }

  Future<File> _compressVideo(File f) async {
    final info = await VideoCompress.compressVideo(f.path, quality: VideoQuality.LowQuality, deleteOrigin: false, includeAudio: true);
    return info?.path != null ? File(info!.path!) : f;
  }

  void _clearForm() {
    _nameController.clear(); _priceController.clear(); _lastValidPriceText = '';
    setState(() { _selectedMedia.clear(); _priceUnit = '/ kg'; _isTransitPost = false; _audioDescriptionPath = null; _audioResetToken++; });
    _loadDefaultSellerLocation();
  }

  void _showMessage(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _handlePriceChanged(String v) {
    final raw = v.replaceAll(',', '');
    if ('.'.allMatches(raw).length > 1) { _setPriceText(_lastValidPriceText); return; }
    final next = raw.startsWith('.') ? '0$raw' : raw;
    if (next.isNotEmpty && !RegExp(r'^\d+\.?\d*$').hasMatch(next)) { _setPriceText(_lastValidPriceText); return; }
    if (double.tryParse(next) != null && double.parse(next) > _maxPriceValue) { _setPriceText(_lastValidPriceText); return; }
    final fmt = _formatEditingPrice(next); _lastValidPriceText = fmt; if (fmt != v) _setPriceText(fmt);
  }

  void _setPriceText(String v) => _priceController.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));

  String _formatEditingPrice(String v) {
    if (v.isEmpty) return '';
    final parts = v.replaceAll(',', '').split('.');
    final whole = _formatWholeNumber(parts.first);
    return v.endsWith('.') ? '$whole.' : (parts.length == 2 ? '$whole.${parts.last}' : whole);
  }

  String _formatWholeNumber(String v) {
    final d = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '0';
    final buf = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      final rev = d.length - i; buf.write(d[i]);
      if (rev > 1 && rev % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  String _formatPriceWithCommas(String v) {
    final parts = v.split('.');
    return '${_formatWholeNumber(parts.first)}.${parts.length > 1 ? parts.last : '000'}';
  }

  String? _normalizePrice(String v) {
    final p = double.tryParse(v.replaceAll(',', ''));
    return (p == null || p > _maxPriceValue) ? null : p.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final color = _isLiveItem ? const Color(0xFFFFE9EC) : const Color(0xFFF4FBF7);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180), color: color,
      child: LayoutBuilder(builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight && constraints.maxHeight > 20 ? constraints.maxHeight - 20 : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildPostTypeSelector(), const SizedBox(height: 16), _buildMediaEditor(), const SizedBox(height: 20),
          if (!_isLiveItem) ...[_buildTransitToggle(), const SizedBox(height: 14)],
          _field(_nameController, 'Item Name', maxLength: 80), const SizedBox(height: 14),
          if (!_isLiveItem) ...[
            AudioDescriptionField(isDisabled: _isUploading, resetToken: _audioResetToken, onChanged: (p, d, _) { _audioDescriptionPath = p; _audioDescriptionDuration = d; }),
            const SizedBox(height: 8),
          ],
          if (_isLiveItem) ...[
            Row(children: [
              Expanded(flex: 3, child: _field(_priceController, _showPriceError ? 'PRICE REQUIRED' : 'Price', prefix: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), focus: _priceFocusNode, keyboard: const TextInputType.numberWithOptions(decimal: true), input: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onTap: () { if (_priceController.text == '0') _setPriceText(''); if (_showPriceError) setState(() => _showPriceError = false); }, onChanged: _handlePriceChanged, error: _showPriceError ? '' : null)),
              const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _priceUnit,
                    items: _priceUnits
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(u.replaceFirst('/ ', '')),
                          ),
                        )
                        .toList(),
                    onChanged: _isUploading ? null : (v) => setState(() => _priceUnit = v!),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
          ],
          if (_isLiveItem || !_isTransitPost)
            _field(_locationController, 'Location', prefix: const Center(widthFactor: 1, child: Text('📍', style: TextStyle(fontSize: 20))), maxLength: 30, error: _showLocationError ? 'Required' : null, onChanged: (v) => _showLocationError ? setState(() => _showLocationError = false) : null),
          const SizedBox(height: 24),
          FractionallySizedBox(
            widthFactor: 0.75,
            child: ElevatedButton(
              onPressed: _isUploading ? null : _addItem,
              style: ElevatedButton.styleFrom(backgroundColor: _isLiveItem ? const Color(0xFFE92808) : const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : Text(_isLiveItem ? 'Go Live - 2 Hrs' : 'Post - 18 Hrs', style: const TextStyle(fontSize: 20)),
            ),
          ),
            ])),
          );
      }),
    );
  }

  Widget _buildPostTypeSelector() => _AddItemSegmentedSelector(
    leftText: 'POST',
    rightText: 'LIVE',
    isRightSelected: _isLiveItem,
    leftSelectedColor: const Color(0xFF001341),
    rightSelectedColor: const Color(0xFFFF7801),
    onLeftTap: _isUploading ? null : () {
      if (!_isLiveItem) return;
      setState(() => _isLiveItem = false);
      widget.onLiveModeChanged?.call(false);
    },
    onRightTap: _isUploading ? null : () {
      if (_isLiveItem) return;
      setState(() {
        _isLiveItem = true;
        _isTransitPost = false;
        _audioDescriptionPath = null;
        _audioResetToken++;
      });
      widget.onLiveModeChanged?.call(true);
    },
  );

  Widget _buildTransitToggle() => _AddItemSegmentedSelector(
    leftText: 'IN SITE',
    rightText: '🚚 TRANSIT',
    isRightSelected: _isTransitPost,
    leftSelectedColor: const Color(0xFF001341),
    rightSelectedColor: const Color(0xFFFF7801),
    onLeftTap: _isUploading ? null : () => setState(() => _isTransitPost = false),
    onRightTap: _isUploading ? null : () => setState(() {
      _isTransitPost = true;
      _showLocationError = false;
    }),
  );

  Widget _buildMediaEditor() {
    final count = _selectedMedia.length;
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: count + 1,
      itemBuilder: (ctx, i) {
        if (i == count) return Center(child: IconButton.filled(onPressed: _openCamera, icon: const Icon(Icons.add_a_photo, size: 32), style: IconButton.styleFrom(fixedSize: const Size(76, 76), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), backgroundColor: Colors.white, foregroundColor: Colors.black)));
        return DragTarget<int>(
          onAcceptWithDetails: (d) => setState(() { final m = _selectedMedia.removeAt(d.data); _selectedMedia.insert(i, m); }),
          builder: (ctx, cand, _) => LongPressDraggable<int>(
            data: i, feedback: SizedBox(width: 100, height: 100, child: Opacity(opacity: 0.8, child: _tile(i, false))),
            child: _tile(i, cand.isNotEmpty),
          ),
        );
      },
    );
  }

  Widget _tile(int i, bool drop) => Container(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: drop ? Border.all(color: const Color(0xFF25D366), width: 3) : null),
    child: Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: _selectedMedia[i].isVideo ? Container(color: Colors.black87, child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 42)) : Image.file(_selectedMedia[i].file, fit: BoxFit.cover)),
      Positioned(top: 4, left: 4, child: CircleAvatar(radius: 12, backgroundColor: const Color(0xFF25D366), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)))),
      Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => setState(() => _selectedMedia.removeAt(i)), child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)))),
    ]),
  );

  Widget _field(TextEditingController ctrl, String label, {Widget? prefix, int? maxLength, String? error, TextInputType? keyboard, List<TextInputFormatter>? input, VoidCallback? onTap, ValueChanged<String>? onChanged, FocusNode? focus}) => TextField(
    controller: ctrl, focusNode: focus, readOnly: _isUploading, maxLength: maxLength, keyboardType: keyboard, inputFormatters: input, onTap: onTap, onChanged: onChanged,
    decoration: InputDecoration(filled: true, fillColor: Colors.white, labelText: label, prefixIcon: prefix, errorText: error, counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
  );
}

class _AddItemSegmentedSelector extends StatelessWidget {
  const _AddItemSegmentedSelector({
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
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AddItemSegmentButton(
              text: leftText,
              isSelected: !isRightSelected,
              selectedColor: leftSelectedColor,
              onTap: onLeftTap,
            ),
          ),
          Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
          Expanded(
            child: _AddItemSegmentButton(
              text: rightText,
              isSelected: isRightSelected,
              selectedColor: rightSelectedColor,
              onTap: onRightTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddItemSegmentButton extends StatelessWidget {
  const _AddItemSegmentButton({
    required this.text,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  final String text;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? selectedColor : Colors.transparent,
      child: InkWell(
        onTap: onTap,
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

class _UploadedMedia {
  const _UploadedMedia({required this.url, required this.type, this.thumbnailUrl});
  final String url, type; final String? thumbnailUrl;
  Map<String, dynamic> toMap() => {'url': url, 'type': type, if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl};
}
