import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class MediaCompressionService {
  const MediaCompressionService._();

  static const int imageMainSize = 1080;
  static const int imageMainQuality = 42;
  static const int videoShortSide = 480;
  static const int videoCrf = 28;

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
    final temp = await getTemporaryDirectory();
    final output =
        '${temp.path}/${DateTime.now().microsecondsSinceEpoch}_ffmpeg.mp4';
    final scaleFilter =
        "scale=w='if(gt(iw,ih),-2,min($videoShortSide,trunc(iw/2)*2))':"
        "h='if(gt(iw,ih),min($videoShortSide,trunc(ih/2)*2),-2)'";

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      file.path,
      '-vf',
      scaleFilter,
      '-c:v',
      'libx264',
      '-crf',
      '$videoCrf',
      '-preset',
      'veryfast',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      output,
    ]);

    final returnCode = await session.getReturnCode();
    final compressed = File(output);
    if (ReturnCode.isSuccess(returnCode) && await compressed.exists()) {
      final compressedSize = await compressed.length();
      final originalSize = await file.length();
      if (compressedSize > 0 && compressedSize < originalSize) {
        return compressed;
      }
    }
    return file;
  }
}
