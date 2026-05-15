import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ProfileImage extends StatelessWidget {
  const ProfileImage({
    super.key,
    required this.imageValue,
    required this.size,
    this.fallbackColor = const Color(0xFFFF7801),
  });

  final String imageValue;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final trimmed = imageValue.trim();
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: trimmed.isEmpty
            ? _fallback()
            : _isInlineImage(trimmed)
            ? Image.memory(
                _decodeInlineImage(trimmed),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : CachedNetworkImage(
                imageUrl: trimmed,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (context, url, error) => _fallback(),
              ),
      ),
    );
  }

  bool _isInlineImage(String value) {
    return value.startsWith('data:image/') || !value.startsWith('http');
  }

  Uint8List _decodeInlineImage(String value) {
    final payload = value.contains(',') ? value.split(',').last : value;
    return base64Decode(payload);
  }

  Widget _fallback() {
    return Icon(Icons.account_circle, size: size * 0.92, color: fallbackColor);
  }
}
