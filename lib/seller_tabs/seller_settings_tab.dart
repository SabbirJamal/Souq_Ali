import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../seller_home_page.dart';
import '../seller_session.dart';
import '../widgets/profile_image.dart';

class SellerSettingsTab extends StatefulWidget {
  const SellerSettingsTab({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<SellerSettingsTab> createState() => _SellerSettingsTabState();
}

class _SellerSettingsTabState extends State<SellerSettingsTab> {
  final _picker = ImagePicker();
  bool _isUploadingProfile = false;

  Future<void> _logout(BuildContext context) async {
    await SellerSession.clear();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SellerHomePage(isSellerMode: false)),
      (route) => false,
    );
  }

  Future<void> _openProfileImageSheet(SellerSession session) async {
    if (_isUploadingProfile) {
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF111614),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Row(
              children: [
                Expanded(
                  child: _ProfileMediaButton(
                    icon: Icons.photo_camera,
                    label: 'Camera',
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProfileMediaButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) {
      return;
    }
    await _pickCropAndUploadProfileImage(session, source);
  }

  Future<void> _pickCropAndUploadProfileImage(
    SellerSession session,
    ImageSource source,
  ) async {
    try {
      final pickedImage = await _picker.pickImage(
        source: source,
        imageQuality: 92,
      );
      if (pickedImage == null) {
        return;
      }

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedImage.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 88,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Picture',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFFFF7801),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Profile Picture',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
            ],
          ),
        ],
      );

      if (croppedFile == null || !mounted) {
        return;
      }

      setState(() => _isUploadingProfile = true);
      final imageBytes = await FlutterImageCompress.compressWithFile(
        croppedFile.path,
        minWidth: 360,
        minHeight: 360,
        quality: 72,
        format: CompressFormat.jpeg,
      );
      if (imageBytes == null) {
        _showMessage('Error: Could not prepare profile picture');
        return;
      }
      final imageData = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';

      await FirebaseFirestore.instance
          .collection('sellers')
          .doc(session.sellerId)
          .set({
            'profile_image_url': imageData,
            'profile_image_data': imageData,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      _showMessage('Profile picture updated');
      setState(() {});
    } on FirebaseException catch (error) {
      _showMessage('Error: ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('Error: $error');
    } finally {
      if (mounted) {
        setState(() => _isUploadingProfile = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: SellerSession.current(),
      builder: (context, sessionSnapshot) {
        final session = sessionSnapshot.data;
        if (sessionSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (session == null) {
          return const Center(child: Text('Please login again'));
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('sellers')
              .doc(session.sellerId)
              .snapshots(),
          builder: (context, sellerSnapshot) {
            final seller = sellerSnapshot.data?.data() ?? {};
            final profileImageUrl =
                seller['profile_image_url']?.toString() ?? '';
            final sellerName = seller['name']?.toString() ?? session.name;
            final crNumber =
                seller['cr_number']?.toString().trim().isNotEmpty == true
                ? seller['cr_number'].toString()
                : seller['crNumber']?.toString() ?? '';
            final sellerLocation = seller['location']?.toString() ?? '';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onBack,
                        child: const SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(Icons.arrow_back, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: _ProfileAvatar(
                      imageUrl: profileImageUrl,
                      isUploading: _isUploadingProfile,
                      onCameraTap: () => _openProfileImageSheet(session),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    sellerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.phoneNumber,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 22),
                  _CrNumberField(
                    sellerId: session.sellerId,
                    initialValue: crNumber,
                  ),
                  const SizedBox(height: 12),
                  _SellerInfoField(
                    sellerId: session.sellerId,
                    fieldKey: 'location',
                    label: 'Location',
                    hint: 'Location',
                    initialValue: sellerLocation,
                    prefix: const Text('📍', style: TextStyle(fontSize: 18)),
                    keyboardType: TextInputType.text,
                    inputFormatters: const [],
                    savedMessage: 'Location saved',
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => _logout(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageUrl,
    required this.isUploading,
    required this.onCameraTap,
  });

  final String imageUrl;
  final bool isUploading;
  final VoidCallback onCameraTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CircleAvatar(
              backgroundColor: const Color(0xFFFFE5D1),
              child: ProfileImage(imageValue: imageUrl, size: 104),
            ),
          ),
          if (isUploading)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x66000000),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          Positioned(
            left: -2,
            bottom: 2,
            child: Material(
              color: const Color(0xFFFF7801),
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                onTap: isUploading ? null : onCameraTap,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(Icons.photo_camera, color: Colors.white, size: 19),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrNumberField extends StatefulWidget {
  const _CrNumberField({required this.sellerId, required this.initialValue});

  final String sellerId;
  final String initialValue;

  @override
  State<_CrNumberField> createState() => _CrNumberFieldState();
}

class _CrNumberFieldState extends State<_CrNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _CrNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _saveCrNumber() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('sellers')
          .doc(widget.sellerId)
          .set({
            'cr_number': _controller.text.trim(),
            'crNumber': _controller.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CR number saved')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error.message ?? error.code}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'CR number',
              hintText: 'Optional',
              prefixIcon: const Icon(Icons.badge_outlined),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveCrNumber,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7801),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class _SellerInfoField extends StatefulWidget {
  const _SellerInfoField({
    required this.sellerId,
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.prefix,
    required this.keyboardType,
    required this.inputFormatters,
    required this.savedMessage,
  });

  final String sellerId;
  final String fieldKey;
  final String label;
  final String hint;
  final String initialValue;
  final Widget prefix;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final String savedMessage;

  @override
  State<_SellerInfoField> createState() => _SellerInfoFieldState();
}

class _SellerInfoFieldState extends State<_SellerInfoField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SellerInfoField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('sellers')
          .doc(widget.sellerId)
          .set({
            widget.fieldKey: _controller.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.savedMessage)),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error.message ?? error.code}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_isSaving,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              prefixIcon: Center(widthFactor: 1, child: widget.prefix),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7801),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class _ProfileMediaButton extends StatelessWidget {
  const _ProfileMediaButton({
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
            Icon(icon, color: const Color(0xFFFF7801), size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
