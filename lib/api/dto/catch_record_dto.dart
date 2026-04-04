import '../../data/species_catalog.dart';
import '../../models/catch_review_status.dart';

/// 鱼获记录 API 契约（与后端 JSON 字段名一致，snake_case）。
///
/// **时间字段 `occurred_at`**
/// - 线上 JSON 使用 **ISO-8601** 字符串。
/// - [CatchRecordDto.toJson] 输出为 **UTC**（`DateTime.toUtc().toIso8601String()`，带 `Z`），便于后端统一按 UTC 存库。
/// - [CatchRecordDto.fromJson] 接受任意 [DateTime.tryParse] 可解析的 ISO 字符串（含 `Z`、`+08:00` 等），内存中为解析结果（与字符串时区一致）。
/// - 若同时存在数值毫秒字段 `occurred_at_ms`，**优先**采用毫秒（与历史/分页游标约定一致时再收紧）。
///
/// **物种**：主字段 `scientific_name`（与 `species_catalog.scientific_name` 外键一致）；仍可读旧字段 `species_zh` 并尝试映射到学名。
class CatchRecordDto {
  const CatchRecordDto({
    required this.id,
    this.imageBase64,
    this.imageUrl,
    required this.scientificName,
    required this.notes,
    required this.weightKg,
    required this.lengthCm,
    required this.locationLabel,
    this.lat,
    this.lng,
    required this.occurredAt,
    this.reviewStatus,
  });

  final String id;
  final String? imageBase64;
  final String? imageUrl;
  final String scientificName;
  final String notes;
  final double weightKg;
  final double lengthCm;
  final String locationLabel;
  final double? lat;
  final double? lng;
  final DateTime occurredAt;

  /// 缺省由 [publishedCatchFromDto] 等按场景补为 approved / pending。
  final CatchReviewStatus? reviewStatus;

  /// 后端 wire：snake_case。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'image_base64': imageBase64,
        'image_url': imageUrl,
        'scientific_name': scientificName,
        'notes': notes,
        'weight_kg': weightKg,
        'length_cm': lengthCm,
        'location_label': locationLabel,
        'lat': lat,
        'lng': lng,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        if (reviewStatus != null) 'review_status': reviewStatus!.wireValue,
      };

  factory CatchRecordDto.fromJson(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from(json);
    final rs = m['review_status'] ?? m['reviewStatus'] ?? m['status'];
    return CatchRecordDto(
      id: _jsonIdToString(m['id']),
      imageBase64: m['image_base64'] as String?,
      imageUrl: m['image_url'] as String?,
      scientificName: _scientificNameFromWire(m),
      notes: m['notes'] as String? ?? '',
      weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
      lengthCm: (m['length_cm'] as num?)?.toDouble() ?? 0,
      locationLabel: m['location_label'] as String? ?? '',
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      occurredAt: _parseOccurredAt(m),
      reviewStatus: rs != null ? parseCatchReviewStatusApi(rs) : null,
    );
  }

  static String _scientificNameFromWire(Map<String, dynamic> m) {
    final sn = (m['scientific_name'] as String?)?.trim() ?? '';
    if (sn.isNotEmpty) return sn;
    final legacy = (m['species_zh'] as String?)?.trim() ?? '';
    if (legacy.isEmpty) return '';
    final hit = SpeciesCatalog.tryBySpeciesZh(legacy);
    return hit?.scientificName ?? legacy;
  }

  static String _jsonIdToString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static DateTime _parseOccurredAt(Map<String, dynamic> m) {
    final ms = m['occurred_at_ms'];
    if (ms is num) {
      return DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true);
    }
    final s = (m['occurred_at'] as String?)?.trim() ?? '';
    if (s.isNotEmpty) {
      final d = DateTime.tryParse(s);
      if (d != null) return d;
    }
    return DateTime.now().toUtc();
  }
}
