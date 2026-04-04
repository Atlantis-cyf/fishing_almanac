import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';

/// 单页时间线结果（远程分页 + 本地单页）。
class CatchFeedPage {
  const CatchFeedPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<CatchFeedItem> items;
  final CatchTimelineCursor? nextCursor;
  final bool hasMore;
}
