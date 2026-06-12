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
import '../seller_session_guard.dart';
import '../upload_status_manager.dart';
import '../widgets/app_toast.dart';
import '../widgets/item_add/selected_media_preview_dialog.dart';
import '../widgets/item_edit/edit_widgets.dart';
import '../widgets/price_with_currency.dart';

class SellerAddItemTab extends StatefulWidget {
  const SellerAddItemTab({
    super.key,
    this.onItemAddedDone,
    this.onItemUploadSuccess,
    this.onLiveModeChanged,
    this.onSessionInvalid,
    this.isLive = false,
  });
  final ValueChanged<bool>? onItemAddedDone;
  final ValueChanged<bool>? onItemUploadSuccess;
  final ValueChanged<bool>? onLiveModeChanged;
  final VoidCallback? onSessionInvalid;
  final bool isLive;
  @override
  SellerAddItemTabState createState() => SellerAddItemTabState();
}

class SellerAddItemTabState extends State<SellerAddItemTab> {
  static const _maxMediaCount = 8;
  static const _maxPriceValue = 1000000.0;
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _priceFocusNode = FocusNode();
  final List<SelectedMedia> _selectedMedia = [];
  final _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];
  String _lastValidPriceText = '';
  String _priceUnit = '/ kg';
  bool _isUploading = false;
  bool _showLocationError = false;
  bool _showPriceError = false;
  bool _isLiveItem = false;
  bool _isTransitPost = false;
  bool _showEmbeddedCamera = false;

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
    if (_selectedMedia.length >= _maxMediaCount) {
      _showMessage('8 Media selected, please delete media to select new media');
      return;
    }
    setState(() => _showEmbeddedCamera = true);
  }

  Future<void> _openGallerySheet() async {
    final selection = await CameraCapturePage.openGalleryPicker(
      context,
      selectedIds: _selectedMedia.map((m) => m.assetId).whereType<String>().toSet(),
      selectedCount: _selectedMedia.length,
      maxCount: _maxMediaCount,
    );
    if (selection == null) return;
    await _addGalleryAssets(selection.assets, selection.selectedIds);
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

  Future<void> openMediaFromBottomNav() async {
    await _openCamera();
  }

  void closeEmbeddedCamera() {
    if (_showEmbeddedCamera) setState(() => _showEmbeddedCamera = false);
  }

  Future<void> _handleEmbeddedGallery() async {
    setState(() => _showEmbeddedCamera = false);
    await _openGallerySheet();
  }

  void _handleEmbeddedCapture(CapturedMedia media) {
    if (_selectedMedia.length >= _maxMediaCount) {
      setState(() => _showEmbeddedCamera = false);
      _showMessage('8 Media selected, please delete media to select new media');
      return;
    }
    setState(() {
      _selectedMedia.add(SelectedMedia(file: media.file, type: media.type));
      _showEmbeddedCamera = false;
    });
  }

  Future<void> _openSelectedMediaPreview(int index) async {
    if (index < 0 || index >= _selectedMedia.length) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SelectedMediaPreviewDialog(
        initialIndex: index,
        items: _selectedMedia
            .map(
              (media) => SelectedMediaPreviewItem.file(
                file: media.file,
                isVideo: media.isVideo,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _addItem() async {
    if (_selectedMedia.isEmpty) { _showMessage('Minimum 1 media required'); return; }
    final name = _nameController.text.trim();
    final loc = _isTransitPost ? '🚚 Transit' : _locationController.text.trim();
    if (loc.isEmpty) { setState(() => _showLocationError = true); return; }
    final normPrice = _isLiveItem ? _normalizePrice(_priceController.text) : '';
    if (_isLiveItem && (normPrice == null || double.parse(normPrice) <= 0)) { setState(() => _showPriceError = true); _priceFocusNode.requestFocus(); return; }

    setState(() => _isUploading = true);
    try {
      final s = await SellerSession.current();
      if (s == null) return;
      if (!mounted) return;
      if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
      UploadStatusManager.uploading(thumbnail: _selectedMedia.first.file);
      widget.onItemAddedDone?.call(_isLiveItem);

      final uploaded = await _uploadMedia(s.sellerId);
      final price = _isLiveItem ? 'OMR ${_formatPriceWithCommas(normPrice!)} $_priceUnit' : '';
      UploadStatusManager.progress(0.96);
      
      await FirebaseFirestore.instance.collection('items').add({
        'seller_uid': s.sellerId, 'seller_name': s.name, 'seller_phone': s.phoneNumber,
        'status': _isLiveItem ? 'live' : 'post', 'is_transit': _isTransitPost, 'item_name': name,
        'item_price': price, 'price_number': normPrice, 'price_unit': _isLiveItem ? _priceUnit : '',
        'location': loc, 'image_urls': uploaded.where((m) => m.type == 'image').map((m) => m.url).toList(),
        'media_files': uploaded.map((m) => m.toMap()).toList(),
        'created_at': FieldValue.serverTimestamp(), 'expires_at': Timestamp.fromDate(DateTime.now().add(Duration(hours: _isLiveItem ? 2 : 18))),
      });
      widget.onItemUploadSuccess?.call(_isLiveItem);
      UploadStatusManager.success();
      if (mounted) _clearForm();
    } catch (e) { UploadStatusManager.error('Upload failed: $e'); }
    finally { if (mounted) setState(() => _isUploading = false); }
  }

  Future<List<_UploadedMedia>> _uploadMedia(String uid) async {
    final res = <_UploadedMedia>[];
    final total = _selectedMedia.length;
    for (var i = 0; i < _selectedMedia.length; i++) {
      final m = _selectedMedia[i];
      final comp = m.isVideo ? await _compressVideo(m.file) : await _compressImage(m.file);
      final name = '${DateTime.now().millisecondsSinceEpoch}_$i';
      final ref = FirebaseStorage.instance.ref().child('items/$uid/$name.${m.isVideo ? 'mp4' : 'jpg'}');
      final snap = await _uploadFileWithProgress(
        ref,
        comp,
        SettableMetadata(contentType: m.isVideo ? 'video/mp4' : 'image/jpeg'),
        start: (i / total) * 0.86,
        span: 0.74 / total,
      );
      final thumb = m.isVideo ? await _uploadThumb(comp, uid, name, i, true) : await _uploadThumb(comp, uid, name, i, false);
      UploadStatusManager.progress(((i + 1) / total) * 0.86);
      res.add(_UploadedMedia(url: await snap.ref.getDownloadURL(), type: m.type, thumbnailUrl: thumb));
    }
    return res;
  }

  Future<TaskSnapshot> _uploadFileWithProgress(
    Reference ref,
    File file,
    SettableMetadata metadata, {
    required double start,
    required double span,
  }) async {
    var lastPercent = -1;
    final task = ref.putFile(file, metadata);
    final sub = task.snapshotEvents.listen((snapshot) {
      final totalBytes = snapshot.totalBytes;
      if (totalBytes <= 0) return;
      final uploaded = snapshot.bytesTransferred / totalBytes;
      final percent = ((start + (uploaded * span)) * 100).floor();
      if (percent == lastPercent) return;
      lastPercent = percent;
      UploadStatusManager.progress(start + (uploaded * span));
    });
    try {
      return await task;
    } finally {
      await sub.cancel();
    }
  }

  Future<String?> _uploadThumb(File f, String uid, String name, int i, bool isVid) async {
    try {
      final File thumb;
      if (isVid) {
        thumb = await VideoCompress.getFileThumbnail(f.path, quality: 45);
      } else {
        final path = '${(await getTemporaryDirectory()).path}/${DateTime.now().microsecondsSinceEpoch}_t.jpg';
        final res = await FlutterImageCompress.compressAndGetFile(f.path, path, minWidth: 720, minHeight: 720, quality: 36);
        if (res == null) return null;
        thumb = File(res.path);
      }
      final ref = FirebaseStorage.instance.ref().child('items/$uid/${name}_t.jpg');
      return await (await ref.putFile(thumb, SettableMetadata(contentType: 'image/jpeg'))).ref.getDownloadURL();
    } catch (_) { return null; }
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
    setState(() { _selectedMedia.clear(); _priceUnit = '/ kg'; _isTransitPost = false; });
    _loadDefaultSellerLocation();
  }

  void _showMessage(String m) => AppToast.show(context, m);

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
    const livePriceFieldHeight = 56.0;
    if (_showEmbeddedCamera) {
      return CameraCapturePage(
        embedded: true,
        selectedCount: _selectedMedia.length,
        maxCount: _maxMediaCount,
        onClose: () => setState(() => _showEmbeddedCamera = false),
        onOpenGallery: _handleEmbeddedGallery,
        onCaptured: _handleEmbeddedCapture,
      );
    }

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
          _buildPostTypeSelector(), const SizedBox(height: 16), _buildMediaEditor(), const SizedBox(height: 15),
          if (!_isLiveItem) ...[_buildTransitToggle(), const SizedBox(height: 14)],
          _field(_nameController, 'Item Name', maxLength: 80), const SizedBox(height: 14),
          if (_isLiveItem) ...[
            Builder(builder: (context) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: SizedBox(height: livePriceFieldHeight, child: _field(_priceController, _showPriceError ? 'PRICE REQUIRED' : 'Price', prefix: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), focus: _priceFocusNode, keyboard: const TextInputType.numberWithOptions(decimal: true), input: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onTap: () { if (_priceController.text == '0') _setPriceText(''); if (_showPriceError) setState(() => _showPriceError = false); }, onChanged: _handlePriceChanged, hasErrorBorder: _showPriceError))),
                  const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: livePriceFieldHeight,
                        child: DropdownButtonFormField<String>(
                        initialValue: _priceUnit,
                        isExpanded: true,
                        isDense: false,
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
                          constraints: const BoxConstraints.tightFor(height: livePriceFieldHeight),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      ),
                    ),
                ]);
            }),
            const SizedBox(height: 14),
          ],
          if (_isLiveItem || !_isTransitPost)
            _field(_locationController, _showLocationError ? 'Location Required' : 'Location', prefix: const Center(widthFactor: 1, child: Text('📍', style: TextStyle(fontSize: 20))), maxLength: 30, hasErrorBorder: _showLocationError, onChanged: (v) => _showLocationError ? setState(() => _showLocationError = false) : null),
          SizedBox(height: _buttonAlignmentSpacerHeight),
          const SizedBox(height: 24),
          FractionallySizedBox(
            widthFactor: 0.75,
            child: SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _addItem,
                style: ElevatedButton.styleFrom(backgroundColor: _isLiveItem ? const Color(0xFFE92808) : const Color(0xFF25D366), foregroundColor: Colors.white, padding: EdgeInsets.zero, minimumSize: const Size.fromHeight(40), tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)) : Text(_isLiveItem ? 'Go Live - 2 Hrs' : 'Post - 18 Hrs', style: const TextStyle(fontSize: 20)),
              ),
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
      });
      widget.onLiveModeChanged?.call(true);
    },
  );

  double get _buttonAlignmentSpacerHeight {
    if (_isLiveItem) return 4;
    if (_isTransitPost) return 76;
    return 20;
  }

  Widget _buildTransitToggle() => _AddItemSegmentedSelector(
    leftText: 'IN STOCK',
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
                onAcceptWithDetails: (d) => setState(() { final m = _selectedMedia.removeAt(d.data); _selectedMedia.insert(i, m); }),
                builder: (ctx, cand, _) => LongPressDraggable<int>(
                  data: i,
                  feedback: SizedBox(width: tileSize, height: tileSize, child: Opacity(opacity: 0.8, child: _tile(i, false))),
                  child: GestureDetector(
                    onTap: () => _openSelectedMediaPreview(i),
                    child: _tile(i, cand.isNotEmpty),
                  ),
                ),
              ),
            ),
          _cameraAddButton(_openCamera, size: tileSize),
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

  Widget _tile(int i, bool drop) => Container(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: drop ? Border.all(color: const Color(0xFF25D366), width: 3) : null),
    child: Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: _selectedMedia[i].isVideo ? Container(color: Colors.black87, child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 42)) : Image.file(_selectedMedia[i].file, fit: BoxFit.cover)),
      Positioned(top: 4, left: 4, child: CircleAvatar(radius: 12, backgroundColor: const Color(0xFF25D366), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)))),
      Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => setState(() => _selectedMedia.removeAt(i)), child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)))),
    ]),
  );

  Widget _field(TextEditingController ctrl, String label, {Widget? prefix, int? maxLength, bool hasErrorBorder = false, TextInputType? keyboard, List<TextInputFormatter>? input, VoidCallback? onTap, ValueChanged<String>? onChanged, FocusNode? focus}) => TextField(
    controller: ctrl, focusNode: focus, readOnly: _isUploading, maxLength: maxLength, keyboardType: keyboard, inputFormatters: input, onTap: onTap, onChanged: onChanged,
    decoration: InputDecoration(filled: true, fillColor: Colors.white, labelText: label, floatingLabelBehavior: hasErrorBorder ? FloatingLabelBehavior.always : null, prefixIcon: prefix, counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: hasErrorBorder ? OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)) : null, focusedBorder: hasErrorBorder ? OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)) : null),
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
            child: _AddItemSegmentButton(
              text: leftText,
              isSelected: !isRightSelected,
              selectedColor: leftSelectedColor,
              onTap: onLeftTap,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
            ),
          ),
          Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
          Expanded(
            child: _AddItemSegmentButton(
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

class _AddItemSegmentButton extends StatelessWidget {
  const _AddItemSegmentButton({
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

class _UploadedMedia {
  const _UploadedMedia({required this.url, required this.type, this.thumbnailUrl});
  final String url, type; final String? thumbnailUrl;
  Map<String, dynamic> toMap() => {'url': url, 'type': type, if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl};
}
