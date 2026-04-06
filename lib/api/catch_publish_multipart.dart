import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/models/published_catch.dart';

/// 构建鱼获发布 multipart 表单（snake_case 文本字段 + 可选 JPEG 文件）。
FormData buildCatchPublishFormData(
  PublishedCatch publishedCatch, {
  Uint8List? imageJpegBytes,
  String? speciesZh,
  String? taxonomyZh,
  bool? imageAuthorized,
}) {
  final map = <String, dynamic>{
    'scientific_name': publishedCatch.scientificName,
    'notes': publishedCatch.notes,
    'weight_kg': publishedCatch.weightKg.toString(),
    'length_cm': publishedCatch.lengthCm.toString(),
    'location_label': publishedCatch.locationLabel,
    'occurred_at': publishedCatch.occurredAt.toUtc().toIso8601String(),
  };
  if (publishedCatch.lat != null) {
    map['lat'] = publishedCatch.lat!.toString();
  }
  if (publishedCatch.lng != null) {
    map['lng'] = publishedCatch.lng!.toString();
  }
  if (speciesZh != null && speciesZh.isNotEmpty) {
    map['species_zh'] = speciesZh;
  }
  if (taxonomyZh != null && taxonomyZh.isNotEmpty) {
    map['taxonomy_zh'] = taxonomyZh;
  }
  if (imageAuthorized != null) {
    map['image_authorized'] = imageAuthorized.toString();
  }
  if (imageJpegBytes != null && imageJpegBytes.isNotEmpty) {
    map[CatchPublishEndpoints.imageField] = MultipartFile.fromBytes(
      imageJpegBytes,
      filename: 'catch.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
  }
  return FormData.fromMap(map);
}
