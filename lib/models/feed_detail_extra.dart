class FeedDetailExtra {
  const FeedDetailExtra({
    this.initialIndex = 0,
    this.speciesScientificName,
    this.anchorCatchId,
  });

  final int initialIndex;
  /// 与 `species_catalog.scientific_name` / 列表筛选一致。
  final String? speciesScientificName;

  /// 与 [CatchFeedItem.id] 或 [CatchFeedItem.sourcePublishedId] 对齐，用于打开信息流后滚到对应卡片。
  final String? anchorCatchId;
}
