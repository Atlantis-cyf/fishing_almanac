import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';

Future<void> showPhotoAdjustDialog(
  BuildContext context, {
  Uint8List? memoryBytes,
  String? networkUrlFallback,
  String title = '调整照片展示',
}) async {
  if ((memoryBytes == null || memoryBytes.isEmpty) &&
      (networkUrlFallback == null || networkUrlFallback.isEmpty)) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            AspectRatio(
              aspectRatio: CatchUi.photoAspectWidthOverHeight,
              child: Container(
                color: Colors.black,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: CatchImageDisplay(
                    memoryBytes: memoryBytes,
                    networkUrlFallback: networkUrlFallback,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('双指缩放，拖动可移动位置', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    },
  );
}

