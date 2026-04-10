import 'package:flutter/material.dart';

import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_analytics_tab_body.dart';
import 'package:fishing_almanac/api/api_config.dart';

/// 数据看板 — 概览 Tab。
class AdminDashboardOverviewScreen extends StatelessWidget {
  const AdminDashboardOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAnalyticsTabBody(
      endpoint: AdminAnalyticsEndpoints.overview,
      showEntryPosition: false,
    );
  }
}
