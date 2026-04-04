import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/published_catch.dart';

/// 鱼获时间线仅来自用户发布数据（本地 [PublishedCatch] 或远端列表），不合并演示数据。
abstract final class CatchFeedData {
  static bool speciesMatches(String itemScientific, String filterScientific) {
    final a = SpeciesCatalog.normalizeScientificNameKey(itemScientific);
    final b = SpeciesCatalog.normalizeScientificNameKey(filterScientific);
    if (b.isEmpty) return true;
    return a == b;
  }

  /// 首页：仅已发布记录，按 occurredAt 新→旧。
  static List<CatchFeedItem> timelineHomeFromPublished(List<PublishedCatch> published) {
    final publishedItems = published.map((e) => e.toFeedItem()).toList();
    publishedItems.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return publishedItems;
  }

  /// 图鉴进入：仅该鱼种（学名键）。
  static List<CatchFeedItem> timelineForSpeciesFromPublished(
    List<PublishedCatch> published,
    String speciesScientificName,
  ) {
    final all = timelineHomeFromPublished(published);
    return all.where((e) => speciesMatches(e.scientificName, speciesScientificName)).toList();
  }

  static List<CatchFeedItem> userPhotosForSpeciesFromPublished(
    List<PublishedCatch> published,
    String speciesScientificName,
  ) {
    return published
        .where((p) => speciesMatches(p.scientificName, speciesScientificName))
        .map((e) => e.toFeedItem())
        .toList();
  }
}
