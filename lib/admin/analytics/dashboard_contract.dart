/// Dashboard KPI contract version shared by admin frontend.
///
/// Keep this value aligned with backend/admin/contracts/analyticsDashboardContract.js
/// so API and UI always reference the same contract version.
class AdminDashboardContract {
  const AdminDashboardContract._();

  /// 中文说明：前端用于校验/展示合同版本的单一来源，
  /// 变更时需与后端 CONTRACT_VERSION 同步更新。
  static const String contractVersion = '2026-04-mvp-v1';
}
