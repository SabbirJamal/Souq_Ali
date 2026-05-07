import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'story_repository.dart';
import 'widgets/media_carousel.dart';

class ItemEditPage extends StatefulWidget {
  const ItemEditPage({super.key, required this.docId, required this.itemData});

  final String docId;
  final Map<String, dynamic> itemData;

  @override
  State<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends State<ItemEditPage> {
  static const _maxMediaCount = 9;

  late final TextEditingController _nameController;
  late final TextEditingController _originController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;

  final _picker = ImagePicker();
  late final List<MediaItem> _existingMedia;
  final List<MediaItem> _removedMedia = [];
  final List<_SelectedMedia> _newMedia = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.itemData['item_name'] ?? '',
    );
    _originController = TextEditingController(
      text: widget.itemData['origin'] ?? '',
    );
    _quantityController = TextEditingController(
      text: widget.itemData['quantity_number'] ?? '',
    );
    _priceController = TextEditingController(
      text: widget.itemData['price_number'] ?? '',
    );
    _locationController = TextEditingController(
      text: widget.itemData['location'] ?? '',
    );
    _existingMedia = mediaItemsFromMap(widget.itemData);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _originController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    VideoCompress.cancelCompression();
    super.dispose();
  }

  Future<void> _pickMedia() async {
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
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final origin = _originController.text.trim();
    final quantity = _quantityController.text.trim();
    final price = _priceController.text.trim();
    final location = _locationController.text.trim();

    if (name.isEmpty ||
        origin.isEmpty ||
        quantity.isEmpty ||
        price.isEmpty ||
        location.isEmpty) {
      _showMessage('Please fill all fields');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final weightUnit = widget.itemData['weight_unit'] ?? 'kg';
      final priceUnit = widget.itemData['price_unit'] ?? 'per kg';
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
            'origin': origin,
            'quantity_number': quantity,
            'item_quantity': '$quantity $weightUnit',
            'price_number': price,
            'item_price': 'OMR $price $priceUnit',
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
        itemPrice: 'OMR $price $priceUnit',
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
    final compressed = List<File?>.filled(_newMedia.length, null);
    final imageJobs = <Future<void>>[];
    for (var i = 0; i < _newMedia.length; i++) {
      final media = _newMedia[i];
      if (media.isVideo) {
        compressed[i] = await _compressVideo(media.file);
      } else {
        final index = i;
        imageJobs.add(() async {
          compressed[index] = await _compressImage(media.file);
        }());
      }
    }
    await Future.wait(imageJobs);

    final uploadStartedAt = DateTime.now().millisecondsSinceEpoch;
    final uploads = <Future<MediaItem>>[];
    for (var i = 0; i < _newMedia.length; i++) {
      uploads.add(
        _uploadOne(sellerUid, _newMedia[i], compressed[i]!, i, uploadStartedAt),
      );
    }
    return Future.wait(uploads);
  }

  Future<MediaItem> _uploadOne(
    String sellerUid,
    _SelectedMedia media,
    File compressed,
    int index,
    int uploadStartedAt,
  ) async {
    final extension = media.isVideo ? 'mp4' : 'jpg';
    final contentType = media.isVideo ? 'video/mp4' : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref().child(
      'items/$sellerUid/${uploadStartedAt}_edit_$index.$extension',
    );

    final snapshot = await ref.putFile(
      compressed,
      SettableMetadata(contentType: contentType),
    );
    return MediaItem(url: await snapshot.ref.getDownloadURL(), type: media.type);
  }

  Future<File> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_${file.path.hashCode}.jpg';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_nameController, 'Item Name', Icons.shopping_bag),
          const SizedBox(height: 14),
          _field(_originController, 'Origin', Icons.place),
          const SizedBox(height: 14),
          _field(_quantityController, 'Quantity', Icons.scale),
          const SizedBox(height: 14),
          _field(_priceController, 'Price', Icons.monetization_on),
          const SizedBox(height: 14),
          _field(_locationController, 'Location', Icons.location_on),
          const SizedBox(height: 20),
          _buildMediaEditor(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(_isSaving ? 'Saving...' : 'Save Changes'),
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
                    _removedMedia.add(_existingMedia[index]);
                    _existingMedia.removeAt(index);
                  });
                },
              );
            }

            final newMediaIndex = index - _existingMedia.length;
            return _NewMediaTile(
              media: _newMedia[newMediaIndex],
              onRemove: () {
                setState(() => _newMedia.removeAt(newMediaIndex));
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAddMediaCircle() {
    return InkWell(
      onTap: _pickMedia,
      borderRadius: BorderRadius.circular(34),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.teal,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 34),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
