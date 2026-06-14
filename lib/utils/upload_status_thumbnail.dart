import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../widgets/item_edit/edit_widgets.dart';

Future<File?> localUploadStatusThumbnail(SelectedMedia? media) async {
  if (media == null) return null;
  if (!media.isVideo) return media.file;
  try {
    return await VideoCompress.getFileThumbnail(media.file.path, quality: 45);
  } catch (_) {
    return null;
  }
}
