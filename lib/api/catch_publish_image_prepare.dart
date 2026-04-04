import 'dart:typed_data';

import 'package:fishing_almanac/api/api_config.dart';
import 'package:image/image.dart' as img;

/// 发布前将照片压成 JPEG（可配置长边与质量）；失败时回退原始字节。
abstract final class CatchPublishImagePrepare {
  static Uint8List toUploadJpeg(Uint8List raw) {
    if (CatchPublishImageConfig.skipReencode) {
      return raw;
    }
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      return raw;
    }
    var work = decoded;
    final max = CatchPublishImageConfig.maxEdge.clamp(256, 8192);
    if (work.width > max || work.height > max) {
      if (work.width >= work.height) {
        work = img.copyResize(work, width: max);
      } else {
        work = img.copyResize(work, height: max);
      }
    }
    final q = CatchPublishImageConfig.jpegQuality.clamp(1, 100);
    return Uint8List.fromList(img.encodeJpg(work, quality: q));
  }
}
