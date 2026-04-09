import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/auth/auth_repository.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/auth/token_storage.dart';
import 'package:fishing_almanac/admin/router/admin_router.dart';
import 'package:fishing_almanac/theme/app_theme.dart';

class FishingAlmanacAdminApp extends StatefulWidget {
  const FishingAlmanacAdminApp({super.key});

  @override
  State<FishingAlmanacAdminApp> createState() => _FishingAlmanacAdminAppState();
}

class _FishingAlmanacAdminAppState extends State<FishingAlmanacAdminApp> {
  late final AuthSession _authSession = AuthSession();
  late final TokenStorage _tokenStorage = TokenStorage();
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(onUnauthorized: _handleUnauthorized);
    _authRepository = AuthRepository(
      apiClient: _apiClient,
      tokenStorage: _tokenStorage,
      authSession: _authSession,
    );
    _router = createAdminRouter(authSession: _authSession);
    unawaited(_restoreAccessToken());
  }

  Future<void> _restoreAccessToken() async {
    final access = await _tokenStorage.readAccessToken();
    final has = access != null && access.isNotEmpty;
    if (has) _apiClient.setAccessToken(access);
    _authSession.markRestored(loggedIn: has);
  }

  void _handleUnauthorized() {
    unawaited(_authRepository.logout());
    _authSession.markRestored(loggedIn: false);
    final ctx = adminNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      GoRouter.of(ctx).go('/admin-login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthSession>.value(value: _authSession),
        Provider<ApiClient>.value(value: _apiClient),
        Provider<TokenStorage>.value(value: _tokenStorage),
        Provider<AuthRepository>.value(value: _authRepository),
      ],
      child: MaterialApp.router(
        title: '海钓图鉴管理台',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}

