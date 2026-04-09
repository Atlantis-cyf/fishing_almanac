import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/admin/router/admin_auth_redirect.dart';
import 'package:fishing_almanac/admin/screens/admin_login_screen.dart';
import 'package:fishing_almanac/admin/screens/admin_species_screen.dart';

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
    ],
  );
}

