import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 数据看板壳：底部导航 + 子路由 [child] 作为正文区域。
class AdminDashboardShell extends StatelessWidget {
  const AdminDashboardShell({super.key, required this.child});

  final Widget child;

  static int indexForPath(String path) {
    if (path.contains('upload-funnel')) return 1;
    if (path.contains('ai-identify')) return 2;
    if (path.contains('collection-growth')) return 3;
    return 0;
  }

  static const List<_DashDest> _dests = [
    _DashDest('/admin-dashboard/overview', '概览', Icons.dashboard_outlined),
    _DashDest('/admin-dashboard/upload-funnel', '上传', Icons.cloud_upload_outlined),
    _DashDest('/admin-dashboard/ai-identify', 'AI', Icons.psychology_outlined),
    _DashDest('/admin-dashboard/collection-growth', '图鉴', Icons.collections_bookmark_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final idx = indexForPath(path);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background.withValues(alpha: 0.9),
        title: Text(
          '数据看板',
          style: AppFont.manrope(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin-species'),
          tooltip: '返回物种管理',
        ),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(_dests[i].path),
        destinations: [
          for (final d in _dests)
            NavigationDestination(
              icon: Icon(d.icon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _DashDest {
  const _DashDest(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}
