import 'package:flutter/material.dart';

import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_analytics_tab_body.dart';
import 'package:fishing_almanac/api/api_config.dart';

/// 数据看板 — AI 识别 Tab（整窗 dedup 见 summary.dedup_request_count）。
class AdminDashboardAiIdentifyScreen extends StatelessWidget {
  const AdminDashboardAiIdentifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAnalyticsTabBody(
      endpoint: AdminAnalyticsEndpoints.aiIdentify,
      showEntryPosition: false,
    );
  }
}
