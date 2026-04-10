import 'package:flutter/material.dart';

import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_analytics_tab_body.dart';
import 'package:fishing_almanac/api/api_config.dart';

/// 数据看板 — 图鉴增长 Tab（整窗 UV 见 summary，勿对 daily UV 求和）。
class AdminDashboardCollectionGrowthScreen extends StatelessWidget {
  const AdminDashboardCollectionGrowthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAnalyticsTabBody(
      endpoint: AdminAnalyticsEndpoints.collectionGrowth,
      showEntryPosition: false,
    );
  }
}
