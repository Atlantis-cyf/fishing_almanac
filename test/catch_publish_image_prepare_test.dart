import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/api/catch_publish_image_prepare.dart';
import 'package:image/image.dart' as img;

void main() {
  test('toUploadJpeg returns jpeg bytes for tiny image', () {
    final pic = img.Image(width: 4, height: 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        pic.setPixel(x, y, img.ColorRgb8(10, 20, 30));
      }
    }
    final png = Uint8List.fromList(img.encodePng(pic));
    final out = CatchPublishImagePrepare.toUploadJpeg(png);
    expect(out.length, greaterThan(8));
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
  });
}
