import 'dart:convert';
import 'dart:typed_data';

import 'package:fishing_almanac/api/dto/catch_record_dto.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/published_catch.dart';

/// [PublishedCatch]（应用层 camelCase + 本地存储）与 [CatchRecordDto]（API snake_case）互转。

CatchRecordDto publishedCatchToDto(PublishedCatch p) {
  return CatchRecordDto(
    id: p.id,
    imageBase64: p.imageBase64,
    imageUrl: p.imageUrlFallback,
    scientificName: p.scientificName,
    notes: p.notes,
    weightKg: p.weightKg,
    lengthCm: p.lengthCm,
    locationLabel: p.locationLabel,
    lat: p.lat,
    lng: p.lng,
    occurredAt: p.occurredAt,
    reviewStatus: p.reviewStatus,
  );
}

/// [reviewStatusWhenNull]：列表缺字段视为已上线数据 [CatchReviewStatus.approved]；
/// 发布接口响应体缺字段时与 PR-7 衔接，默认 [CatchReviewStatus.pendingReview]。
PublishedCatch publishedCatchFromDto(
  CatchRecordDto d, {
  CatchReviewStatus reviewStatusWhenNull = CatchReviewStatus.approved,
}) {
  return PublishedCatch(
    id: d.id,
    imageBase64: d.imageBase64,
    imageUrlFallback: d.imageUrl,
    scientificName: d.scientificName,
    notes: d.notes,
    weightKg: d.weightKg,
    lengthCm: d.lengthCm,
    locationLabel: d.locationLabel,
    lat: d.lat,
    lng: d.lng,
    occurredAt: d.occurredAt,
    reviewStatus: d.reviewStatus ?? reviewStatusWhenNull,
  );
}

/// 将 API 记录转为信息流展示模型（可选 Base64 → 内存图）。
CatchFeedItem catchFeedItemFromDto(
  CatchRecordDto d, {
  bool fromPublished = true,
}) {
  Uint8List? bytes;
  final b64 = d.imageBase64;
  if (b64 != null && b64.isNotEmpty) {
    try {
      bytes = base64Decode(b64);
    } catch (_) {}
  }
  return CatchFeedItem(
    id: d.id,
    sourcePublishedId: d.id,
    imageBytes: bytes,
    imageUrl: d.imageUrl ?? '',
    scientificName: d.scientificName,
    notes: d.notes,
    weightKg: d.weightKg,
    lengthCm: d.lengthCm,
    locationLabel: d.locationLabel,
    lat: d.lat,
    lng: d.lng,
    occurredAt: d.occurredAt,
    fromPublished: fromPublished,
    reviewStatus: d.reviewStatus ?? CatchReviewStatus.approved,
  );
}

/// 草稿/列表 → API DTO（有字节则出 `image_base64`，否则仅 `image_url`）。
CatchRecordDto catchFeedItemToDto(CatchFeedItem item) {
  String? b64;
  if (item.imageBytes != null && item.imageBytes!.isNotEmpty) {
    b64 = base64Encode(item.imageBytes!);
  }
  final id = (item.sourcePublishedId != null && item.sourcePublishedId!.isNotEmpty)
      ? item.sourcePublishedId!
      : item.id;
  return CatchRecordDto(
    id: id,
    imageBase64: b64,
    imageUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
    scientificName: item.scientificName,
    notes: item.notes,
    weightKg: item.weightKg,
    lengthCm: item.lengthCm,
    locationLabel: item.locationLabel,
    lat: item.lat,
    lng: item.lng,
    occurredAt: item.occurredAt,
    reviewStatus: item.reviewStatus,
  );
}
