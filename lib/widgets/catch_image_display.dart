import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:fishing_almanac/theme/app_colors.dart';

/// 优先内存字节，其次网络占位（编辑/演示共用）。
class CatchImageDisplay extends StatelessWidget {
  const CatchImageDisplay({
    super.key,
    this.memoryBytes,
    this.networkUrlFallback,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.width,
    this.height,
  });

  final Uint8List? memoryBytes;
  final String? networkUrlFallback;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (memoryBytes != null && memoryBytes!.isNotEmpty) {
      child = Image.memory(
        memoryBytes!,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
      );
    } else if (networkUrlFallback != null && networkUrlFallback!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: networkUrlFallback!,
        fit: fit,
        width: width,
        height: height,
        placeholder: (_, __) => Container(
          width: width,
          height: height,
          color: AppColors.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => Container(
          width: width,
          height: height,
          color: AppColors.surfaceContainerHighest,
        ),
      );
    } else {
      child = Container(
        width: width,
        height: height ?? width,
        color: AppColors.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.image_not_supported_outlined, color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
      );
    }
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
