import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/auth/auth_session.dart';

String? adminAuthRedirect(AuthSession auth, GoRouterState state) {
  if (!auth.isReady) return null;
  final loc = state.matchedLocation;
  final isPublic = loc == '/' || loc == '/admin-login';

  if (!auth.isLoggedIn && !isPublic) {
    final path = state.uri.path;
    if (path.startsWith('/') && !path.startsWith('//') && !path.contains('..') && path != '/admin-login') {
      final full = state.uri.hasQuery ? '$path?${state.uri.query}' : path;
      return Uri(path: '/admin-login', queryParameters: {'redirect': full}).toString();
    }
    return '/admin-login';
  }

  // 中文注释：/admin-dashboard 无子路径时统一到 overview（与 ShellRoute 拆分方案等价，避免单独挂 redirect 路由）。
  if (auth.isLoggedIn) {
    final p = state.uri.path;
    if (p == '/admin-dashboard' || p == '/admin-dashboard/') {
      return '/admin-dashboard/overview';
    }
  }

  if (auth.isLoggedIn && (loc == '/' || loc == '/admin-login')) {
    return '/admin-species';
  }
  return null;
}

