/// 时间线分页游标（远程实现时使用；本地首版可忽略）。
class CatchTimelineCursor {
  const CatchTimelineCursor({this.occurredAtMs, this.id, this.page});

  /// 与后端 `occurred_at_ms` 对齐的毫秒时间戳（用于 keyset）。
  final int? occurredAtMs;

  /// 同时间点并列时的 tie-breaker（通常为记录 id）。
  final String? id;

  /// 页码模式（1-based），与 `after_*` 二选一，由 `--dart-define=CATCH_LIST_USE_PAGE_PARAM` 控制。
  final int? page;
}
