import 'dart:io';
import 'dart:typed_data';

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
import '../story_repository.dart';
import '../widgets/price_with_currency.dart';

class SellerAddItemTab extends StatefulWidget {
  const SellerAddItemTab({super.key, this.onItemAddedDone});

  final VoidCallback? onItemAddedDone;

  @override
  SellerAddItemTabState createState() => SellerAddItemTabState();
}

class SellerAddItemTabState extends State<SellerAddItemTab> {
  static const _maxMediaCount = 9;
  static const _maxPriceValue = 1000000.0;

  final _nameController = TextEditingController();
  final _priceController = TextEditingController(text: '0');
  final _locationController = TextEditingController();
  final _priceFocusNode = FocusNode();

  final List<_SelectedMedia> _selectedMedia = [];
  final _priceUnits = ['/ kg', '/ box', '/ bag'];

  String _lastValidPriceText = '0';
  String _priceUnit = '/ kg';
  int _timePeriodHours = 18;
  bool _isUploading = false;
  bool _showLocationError = false;

  int get _totalTimePeriodHours => _timePeriodHours;

  @override
  void initState() {
    super.initState();
    _loadDefaultSellerLocation();
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
    if (!_canAddMedia()) {
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
      _selectedMedia.add(
        _SelectedMedia(file: captured.file, type: captured.type),
      );
      _sortSelectedMedia();
    });
  }

  Future<void> openMediaSheet() async {
    await _openMediaSheet();
  }

  Future<void> _openMediaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111614),
      shape: const RoundedRectangleBorder(),
      builder: (context) {
        return _MediaPickerSheet(
          selectedIds: _selectedMedia
              .map((media) => media.assetId)
              .whereType<String>()
              .toSet(),
          selectedCount: _selectedMedia.length,
          maxCount: _maxMediaCount,
          onCameraTap: () async {
            Navigator.pop(context);
            await _openCamera();
          },
          onAssetsDone: _addGalleryAssets,
        );
      },
    );
  }

  Future<void> _addGalleryAssets(List<AssetEntity> assets) async {
    if (assets.isEmpty) {
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

      newMedia.add(
        _SelectedMedia(
          file: file,
          type: asset.type == AssetType.video ? 'video' : 'image',
          assetId: asset.id,
        ),
      );
    }

    if (newMedia.isEmpty) {
      return;
    }

    setState(() {
      _selectedMedia.addAll(newMedia);
      _sortSelectedMedia();
    });
  }

  void _sortSelectedMedia() {
    _selectedMedia.sort((first, second) {
      if (first.isVideo == second.isVideo) {
        return 0;
      }
      return first.isVideo ? 1 : -1;
    });
  }

  bool _canAddMedia() {
    if (_selectedMedia.length >= _maxMediaCount) {
      _showMessage('Maximum $_maxMediaCount media files allowed');
      return false;
    }
    return true;
  }

  Future<List<_UploadedMedia>> _uploadMedia(String sellerUid) async {
    final uploaded = <_UploadedMedia>[];
    final orderedMedia = [..._selectedMedia]
      ..sort((first, second) {
        if (first.isVideo == second.isVideo) {
          return 0;
        }
        return first.isVideo ? 1 : -1;
      });

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

      final uploadSnapshot = await ref.putFile(
        compressed,
        SettableMetadata(contentType: contentType),
      );
      uploaded.add(
        _UploadedMedia(
          url: await uploadSnapshot.ref.getDownloadURL(),
          type: media.type,
        ),
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
    if (compressedPath == null || compressedPath.isEmpty) {
      return file;
    }

    return File(compressedPath);
  }

  Future<void> _addItem() async {
    final name = _nameController.text.trim();
    final priceNumber = _priceController.text.trim().isEmpty
        ? '0'
        : _priceController.text.trim();
    final location = _locationController.text.trim();

    if (_selectedMedia.isEmpty) {
      _showMessage('Please add atleast 1 image or video');
      return;
    }
    if (location.isEmpty) {
      setState(() => _showLocationError = true);
      return;
    }
    final normalizedPrice = _normalizePrice(priceNumber);
    if (normalizedPrice == null) {
      _showMessage('Invalid price');
      return;
    }
    setState(() => _isUploading = true);

    try {
      final session = await SellerSession.current();
      if (session == null) {
        _showMessage('Please login again');
        return;
      }

      final uploadedMedia = await _uploadMedia(session.sellerId);
      final imageUrls = uploadedMedia
          .where((media) => media.type == 'image')
          .map((media) => media.url)
          .toList();
      final formattedPrice = _formatPriceWithCommas(normalizedPrice);
      final price = 'OMR $formattedPrice $_priceUnit';
      final itemRef = FirebaseFirestore.instance.collection('items').doc();
      final timePeriodHours = _totalTimePeriodHours;
      final expiresAt = Timestamp.fromDate(
        DateTime.now().add(Duration(hours: timePeriodHours)),
      );

      await itemRef.set({
        'seller_uid': session.sellerId,
        'seller_name': session.name,
        'seller_phone': session.phoneNumber,
        'item_name': name,
        'item_price': price,
        'price_number': normalizedPrice,
        'price_unit': _priceUnit,
        'location': location,
        'image_urls': imageUrls,
        'media_files': uploadedMedia.map((media) => media.toMap()).toList(),
        'time_period_days': 0,
        'time_period_extra_hours': _timePeriodHours,
        'time_period_hours': timePeriodHours,
        'expires_at': expiresAt,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      await const StoryRepository().replaceItemVideos(
        itemId: itemRef.id,
        itemName: name,
        sellerId: session.sellerId,
        sellerName: session.name,
        sellerPhone: session.phoneNumber,
        itemPrice: price,
        videoUrls: uploadedMedia
            .where((media) => media.type == 'video')
            .map((media) => media.url)
            .toList(),
      );

      _clearForm();
      await _showItemAddedDialog();
    } on FirebaseException catch (error) {
      final message = error.code == 'object-not-found'
          ? 'Storage upload failed. Check Firebase Storage is enabled and rules allow uploads.'
          : error.message ?? error.code;
      _showMessage('Error: $message');
    } catch (error) {
      _showMessage('Error: $error');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _clearForm() {
    _nameController.clear();
    _priceController.text = '0';
    _lastValidPriceText = '0';
    setState(() {
      _selectedMedia.clear();
      _priceUnit = '/ kg';
      _timePeriodHours = 18;
      _showLocationError = false;
    });
    _loadDefaultSellerLocation();
  }

  Future<void> _showItemAddedDialog() async {
    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.teal, size: 56),
                SizedBox(height: 14),
                Text(
                  'Item added successfully',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
    widget.onItemAddedDone?.call();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMediaPicker(),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _nameController,
            label: 'Item Name',
            hint: 'Fresh Tomatoes',
            icon: Icons.shopping_bag,
            maxLength: 80,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _priceController,
                  label: 'Price',
                  hint: '2.500',
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
          const SizedBox(height: 16),
          _buildTimePeriodSelector(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isUploading ? null : _addItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
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
                : const Text('Add Item', style: TextStyle(fontSize: 16)),
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
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _selectedMedia.length + 1,
          itemBuilder: (context, index) {
            if (index == _selectedMedia.length) {
              return Center(child: _buildAddMediaCircle());
            }

            final media = _selectedMedia[index];
            return Stack(
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
                  right: 4,
                  child: GestureDetector(
                    onTap: _isUploading
                        ? null
                        : () => setState(() => _selectedMedia.removeAt(index)),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.red,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAddMediaCircle() {
    return InkWell(
      onTap: _isUploading ? null : _openMediaSheet,
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

  Widget _buildTimePeriodSelector() {
    const options = [6, 12, 18];
    return Opacity(
      opacity: _isUploading ? 0.45 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: options.map((hours) {
              final isSelected = _timePeriodHours == hours;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: hours == options.last ? 0 : 8,
                  ),
                  child: ChoiceChip(
                    label: Text('${hours} hrs'),
                    selected: isSelected,
                    onSelected: _isUploading
                        ? null
                        : (_) => setState(() => _timePeriodHours = hours),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    selectedColor: const Color(0xFFFF7801),
                    backgroundColor: Colors.white,
                    disabledColor: Colors.grey.shade100,
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFF7801)
                          : Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
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

class _MediaPickerSheet extends StatefulWidget {
  const _MediaPickerSheet({
    required this.selectedIds,
    required this.selectedCount,
    required this.maxCount,
    required this.onCameraTap,
    required this.onAssetsDone,
  });

  final Set<String> selectedIds;
  final int selectedCount;
  final int maxCount;
  final VoidCallback onCameraTap;
  final Future<void> Function(List<AssetEntity> assets) onAssetsDone;

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet> {
  static const _pageSize = 90;

  final Set<String> _selectedIds = {};
  final List<AssetEntity> _pendingAssets = [];
  List<AssetPathEntity> _albums = [];
  List<AssetEntity> _assets = [];
  AssetPathEntity? _selectedAlbum;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreAssets = true;
  bool _hasPermission = true;
  bool _hasLimitedPermission = false;
  int _currentPage = 0;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.selectedIds);
    _loadAssets();
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
    if (widget.selectedIds.contains(asset.id)) {
      return;
    }
    if (_selectedIds.contains(asset.id)) {
      setState(() {
        _selectedIds.remove(asset.id);
        _pendingAssets.removeWhere((pending) => pending.id == asset.id);
      });
      return;
    }

    if (_selectedIds.length >= widget.maxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only 9 media can be selected')),
      );
      return;
    }

    setState(() {
      _selectedIds.add(asset.id);
      _pendingAssets.add(asset);
    });
  }

  Future<void> _finishSelection() async {
    await widget.onAssetsDone(_pendingAssets);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 1,
        minChildSize: 0.25,
        maxChildSize: 1,
        builder: (context, scrollController) {
          return Stack(
            children: [
              CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context)),
                  if (_isLoading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!_hasPermission)
                    SliverFillRemaining(child: _buildPermissionDenied())
                  else
                    ...[
                      if (_hasLimitedPermission)
                        SliverToBoxAdapter(child: _buildLimitedAccessNotice()),
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
                            if (index == 0) {
                              return _CameraTile(
                                icon: Icons.camera_alt_outlined,
                                label: 'Camera',
                                onTap: widget.onCameraTap,
                              );
                            }
                            final asset = _assets[index - 1];
                            _maybeLoadMore(index - 1);
                            final selectedIndex = _selectedIds
                                .toList()
                                .indexOf(asset.id);
                            return _AssetTile(
                              asset: asset,
                              selectionNumber: selectedIndex == -1
                                  ? null
                                  : selectedIndex + 1,
                              onTap: () => _toggleAsset(asset),
                            );
                          }, childCount: _assets.length + 1),
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
                          return _SelectedAssetPreview(
                            asset: _pendingAssets[index],
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
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
              _selectedIds.isEmpty ? 'Done' : 'Done (${_selectedIds.length})',
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

class _CameraTile extends StatelessWidget {
  const _CameraTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Color(0xFF242928),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.selectionNumber,
    required this.onTap,
  });

  final AssetEntity asset;
  final int? selectionNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(
                const ThumbnailSize.square(240),
              ),
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
    );
  }
}

class _SelectedAssetPreview extends StatelessWidget {
  const _SelectedAssetPreview({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 42,
        height: 54,
        child: FutureBuilder<Uint8List?>(
          future: asset.thumbnailDataWithSize(const ThumbnailSize(90, 120)),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return Container(color: const Color(0xFF252A28));
            }
            return Image.memory(bytes, fit: BoxFit.cover);
          },
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
  const _UploadedMedia({required this.url, required this.type});

  final String url;
  final String type;

  Map<String, dynamic> toMap() {
    return {'url': url, 'type': type};
  }
}
