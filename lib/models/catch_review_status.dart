/// 与后端 `review_status`（或兼容 `status`）枚举对齐。
enum CatchReviewStatus {
  /// `pending_review`
  pendingReview,

  /// `rejected`
  rejected,

  /// `approved`
  approved,
}

extension CatchReviewStatusWire on CatchReviewStatus {
  String get wireValue => switch (this) {
        CatchReviewStatus.pendingReview => 'pending_review',
        CatchReviewStatus.rejected => 'rejected',
        CatchReviewStatus.approved => 'approved',
      };

  /// 列表角标 / 详情文案（approved 不展示角标时可返回空）。
  String get listLabel => switch (this) {
        CatchReviewStatus.pendingReview => '审核中',
        CatchReviewStatus.rejected => '未通过',
        CatchReviewStatus.approved => '',
      };

  /// 详情/编辑提示长文案。
  String get detailHint => switch (this) {
        CatchReviewStatus.pendingReview => '照片审核中，审核完成后即可编辑',
        CatchReviewStatus.rejected => '审核未通过，可修改后重新提交',
        CatchReviewStatus.approved => '',
      };

  /// `pending_review` 时禁止编辑（与自检「照片审核中」一致）。
  bool get blocksEditingWhilePending => this == CatchReviewStatus.pendingReview;
}

/// 本地 JSON / 宽松解析：缺省为 [CatchReviewStatus.approved]（兼容旧数据）。
CatchReviewStatus parseCatchReviewStatusLocal(dynamic v) {
  if (v == null) return CatchReviewStatus.approved;
  final s = v.toString().trim().toLowerCase().replaceAll('-', '_');
  if (s == 'pending_review' || s == 'pendingreview') return CatchReviewStatus.pendingReview;
  if (s == 'rejected' || s == 'reject') return CatchReviewStatus.rejected;
  if (s == 'approved' || s == 'approve') return CatchReviewStatus.approved;
  return CatchReviewStatus.approved;
}

/// 接口解析：未知字符串保守为 [CatchReviewStatus.pendingReview]。
CatchReviewStatus parseCatchReviewStatusApi(dynamic v) {
  if (v == null) return CatchReviewStatus.approved;
  final s = v.toString().trim().toLowerCase().replaceAll('-', '_');
  if (s == 'pending_review' || s == 'pendingreview') return CatchReviewStatus.pendingReview;
  if (s == 'rejected' || s == 'reject') return CatchReviewStatus.rejected;
  if (s == 'approved' || s == 'approve') return CatchReviewStatus.approved;
  return CatchReviewStatus.pendingReview;
}
