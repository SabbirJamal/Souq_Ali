import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class MediaCompressionService {
  const MediaCompressionService._();

  static const int imageMainSize = 1080;
  static const int imageMainQuality = 42;

  static Future<File> compressImage(File file) async {
    final temp = await getTemporaryDirectory();
    final path =
        '${temp.path}/${DateTime.now().microsecondsSinceEpoch}_main.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      path,
      minWidth: imageMainSize,
      minHeight: imageMainSize,
      quality: imageMainQuality,
    );
    return result == null ? file : File(result.path);
  }

  static Future<File> compressVideo(File file) async {
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final compressedPath = info?.path;
      if (compressedPath == null || compressedPath.isEmpty) return file;

      final compressed = File(compressedPath);
      if (!await compressed.exists()) return file;

      final compressedSize = await compressed.length();
      final originalSize = await file.length();
      if (compressedSize > 0 && compressedSize < originalSize) {
        return compressed;
      }
    } catch (_) {
      return file;
    }
    return file;
  }
}
