import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/published_catch.dart';
import 'package:fishing_almanac/repositories/catch_feed_page.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';

/// 鱼获数据源抽象。UI 只依赖本类型，不直接访问 [SharedPreferences] 或 `jsonDecode`。
abstract class CatchRepository extends ChangeNotifier {
  CatchRepository();

  /// 本地加载或 [upsertLocal] 后递增，用于触发界面重新拉取 [Future] 列表。
  int get dataGeneration;

  /// 时间线是否来自远端 HTTP（未登录时可走演示 fallback）。
  bool get usesRemoteTimeline => false;

  /// 本地存储层向用户展示的最近一次提示（若有）；调用 [consumePersistenceHint] 后清空。
  String? get persistenceHint => null;

  /// 取出并清空 [persistenceHint]，避免重复 SnackBar。
  String? consumePersistenceHint() => null;

  Future<CatchFeedPage> timelineHome({CatchTimelineCursor? cursor});

  Future<CatchFeedPage> timelineForSpecies(
    String speciesScientificName, {
    CatchTimelineCursor? cursor,
  });

  /// 仅用户已发布（无演示数据），用于物种详情网格。
  Future<List<CatchFeedItem>> userPhotosForSpecies(String speciesScientificName);

  Future<PublishedCatch?> getById(String id);

  Future<void> upsertLocal(PublishedCatch publishedCatch);

  /// 发布鱼获：本地实现等价于 [upsertLocal]；远程为 multipart 创建/更新。
  Future<void> publish(
    PublishedCatch publishedCatch, {
    Uint8List? imageBytes,
    bool updating = false,
    String? updateId,
  });

  /// 永久删除已发布鱼获（本地从列表移除；远程 `DELETE /v1/catches/:id`）。
  Future<void> deletePublished(String id);
}
