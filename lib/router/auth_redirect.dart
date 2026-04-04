import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/auth/auth_session.dart';
/// 白名单：欢迎页、登录、注册。其余路径需已登录。
String? authRedirect(AuthSession auth, GoRouterState state) {
  if (!auth.isReady) return null;

  final loc = state.matchedLocation;
  final isPublic = loc == '/' || loc == '/login' || loc == '/register';

  if (!auth.isLoggedIn && !isPublic) {
    final path = state.uri.path;
    if (path.startsWith('/') &&
        !path.startsWith('//') &&
        !path.contains('..') &&
        path != '/login' &&
        path != '/register' &&
        path != '/') {
      final full = state.uri.hasQuery ? '$path?${state.uri.query}' : path;
      return Uri(path: '/login', queryParameters: {'redirect': full}).toString();
    }
    return '/login';
  }
  if (auth.isLoggedIn && (loc == '/login' || loc == '/register')) {
    return '/home';
  }
  return null;
}
