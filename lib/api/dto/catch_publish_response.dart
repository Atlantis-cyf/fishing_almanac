import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/api/dto/catch_record_dto.dart';
import 'package:fishing_almanac/api/mappers/catch_record_mapper.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/published_catch.dart';

/// 解析创建/更新接口返回的单个鱼获对象（支持根级或 `data` 包裹）。
PublishedCatch? tryParsePublishedCatchResponse(dynamic data) {
  if (data == null) return null;
  try {
    Map<String, dynamic> root;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final inner = m['data'];
      if (inner is Map) {
        root = Map<String, dynamic>.from(inner);
      } else {
        root = m;
      }
    } else {
      return null;
    }
    final dto = CatchRecordDto.fromJson(root);
    return publishedCatchFromDto(
      dto,
      reviewStatusWhenNull: CatchReviewStatus.pendingReview,
    );
  } catch (e, st) {
    debugPrint('tryParsePublishedCatchResponse: $e\n$st');
    return null;
  }
}
