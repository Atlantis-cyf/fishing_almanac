import 'package:flutter/material.dart';

import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_analytics_tab_body.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_layouts.dart';
import 'package:fishing_almanac/api/api_config.dart';

/// 数据看板 — 上传漏斗 Tab（支持 entry_position）。
class AdminDashboardUploadFunnelScreen extends StatelessWidget {
  const AdminDashboardUploadFunnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAnalyticsTabBody(
      endpoint: AdminAnalyticsEndpoints.uploadFunnel,
      showEntryPosition: true,
      mode: AnalyticsDashboardMode.uploadFunnel,
    );
  }
}
