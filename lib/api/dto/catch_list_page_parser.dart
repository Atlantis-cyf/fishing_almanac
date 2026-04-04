import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/api/dto/catch_record_dto.dart';
import 'package:fishing_almanac/api/mappers/catch_record_mapper.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/repositories/catch_feed_page.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';

/// 解析列表 GET 响应为 [CatchFeedPage]。
///
/// 约定（可按后端调整）：
/// - 根对象或 `data` 内：`items` / `records` / `results` 为对象数组（[CatchRecordDto]）。
/// - `has_more` / `hasMore`：是否还有下一页。
/// - `next_cursor`：`{ "occurred_at_ms": int, "id": string }` 或 `{ "page": int }`。
abstract final class CatchListPageParser {
  static CatchFeedPage parse(dynamic data, {required int limit}) {
    final root = _unwrapRoot(data);
    final rawList = root['items'] ?? root['records'] ?? root['results'];
    final List<dynamic> list;
    if (rawList is List) {
      list = rawList;
    } else if (rawList == null) {
      list = [];
    } else {
      throw ApiException(message: '列表字段 items/records/results 类型无效', rawBody: data);
    }

    final items = <CatchFeedItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final dto = CatchRecordDto.fromJson(Map<String, dynamic>.from(e));
      items.add(catchFeedItemFromDto(dto));
    }

    final next = _parseNextCursor(root);
    final bool hasMore;
    if (root['has_more'] == true || root['hasMore'] == true) {
      hasMore = true;
    } else if (root['has_more'] == false || root['hasMore'] == false) {
      hasMore = false;
    } else {
      hasMore = next != null || items.length >= limit;
    }

    return CatchFeedPage(items: items, nextCursor: next, hasMore: hasMore);
  }

  static Map<String, dynamic> _unwrapRoot(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final inner = m['data'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return m;
    }
    throw ApiException(message: '列表响应应为 JSON 对象', rawBody: data);
  }

  static CatchTimelineCursor? _parseNextCursor(Map<String, dynamic> root) {
    final c = root['next_cursor'] ?? root['nextCursor'];
    if (c is Map) {
      final mm = Map<String, dynamic>.from(c);
      final ms = mm['occurred_at_ms'] ?? mm['occurredAtMs'];
      final id = mm['id'] ?? mm['after_id'];
      final page = mm['page'] ?? mm['next_page'];
      return CatchTimelineCursor(
        occurredAtMs: ms is num ? ms.toInt() : null,
        id: id?.toString(),
        page: page is num ? page.toInt() : null,
      );
    }
    final np = root['next_page'] ?? root['nextPage'];
    if (np is num) {
      return CatchTimelineCursor(page: np.toInt());
    }
    return null;
  }
}
