import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/admin/router/admin_auth_redirect.dart';
import 'package:fishing_almanac/admin/screens/admin_login_screen.dart';
import 'package:fishing_almanac/admin/screens/admin_species_screen.dart';
import 'package:fishing_almanac/admin/screens/dashboard/admin_dashboard_shell.dart';
import 'package:fishing_almanac/admin/screens/dashboard/admin_dashboard_ai_identify_screen.dart';
import 'package:fishing_almanac/admin/screens/dashboard/admin_dashboard_collection_growth_screen.dart';
import 'package:fishing_almanac/admin/screens/dashboard/admin_dashboard_overview_screen.dart';
import 'package:fishing_almanac/admin/screens/dashboard/admin_dashboard_upload_funnel_screen.dart';

final GlobalKey<NavigatorState> adminNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAdminRouter({required AuthSession authSession}) {
  return GoRouter(
    navigatorKey: adminNavigatorKey,
    initialLocation: '/admin-login',
    refreshListenable: authSession,
    redirect: (context, state) => adminAuthRedirect(authSession, state),
    routes: [
      GoRoute(path: '/', builder: (c, s) => const AdminLoginScreen()),
      GoRoute(path: '/admin-login', builder: (c, s) => const AdminLoginScreen()),
      GoRoute(path: '/admin-species', builder: (c, s) => const AdminSpeciesScreen()),
      // 中文注释：不用嵌套 ShellRoute，避免父级仅有 redirect/routes 时在部分版本下匹配异常；每条完整路径单独 builder。
      GoRoute(
        path: '/admin-dashboard/overview',
        builder: (context, state) => const AdminDashboardShell(
          child: AdminDashboardOverviewScreen(),
        ),
      ),
      GoRoute(
        path: '/admin-dashboard/upload-funnel',
        builder: (context, state) => const AdminDashboardShell(
          child: AdminDashboardUploadFunnelScreen(),
        ),
      ),
      GoRoute(
        path: '/admin-dashboard/ai-identify',
        builder: (context, state) => const AdminDashboardShell(
          child: AdminDashboardAiIdentifyScreen(),
        ),
      ),
      GoRoute(
        path: '/admin-dashboard/collection-growth',
        builder: (context, state) => const AdminDashboardShell(
          child: AdminDashboardCollectionGrowthScreen(),
        ),
      ),
    ],
  );
}
