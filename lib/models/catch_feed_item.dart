import 'dart:typed_data';

import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';

class CatchFeedItem {
  const CatchFeedItem({
    required this.id,
    required this.scientificName,
    required this.notes,
    required this.weightKg,
    required this.lengthCm,
    required this.locationLabel,
    this.lat,
    this.lng,
    required this.occurredAt,
    this.imageBytes,
    required this.imageUrl,
    this.fromPublished = false,
    this.sourcePublishedId,
    this.reviewStatus = CatchReviewStatus.approved,
  });

  final String id;
  /// 与 `species_catalog.scientific_name` / 外键一致；展示中文名用 [displaySpeciesZh]。
  final String scientificName;
  final String notes;
  final double weightKg;
  final double lengthCm;
  final String locationLabel;
  final double? lat;
  final double? lng;
  final DateTime occurredAt;
  final Uint8List? imageBytes;
  final String imageUrl;
  final bool fromPublished;
  final String? sourcePublishedId;
  final CatchReviewStatus reviewStatus;

  String get displaySpeciesZh =>
      SpeciesCatalog.tryByScientificName(scientificName)?.speciesZh ?? scientificName;

  /// 首页等入口跳进信息流时使用的锚点 id（与列表项 id / sourcePublishedId 对齐）。
  String get timelineAnchorId {
    final s = sourcePublishedId?.trim();
    if (s != null && s.isNotEmpty) return s;
    return id;
  }

  /// [rawAnchor] 是否与本条记录为同一条（用于滚到点击的那张图）。
  bool matchesTimelineAnchor(String? rawAnchor) {
    final anchor = rawAnchor?.trim();
    if (anchor == null || anchor.isEmpty) return false;
    if (id == anchor) return true;
    final sp = sourcePublishedId?.trim();
    return sp != null && sp.isNotEmpty && sp == anchor;
  }
}
