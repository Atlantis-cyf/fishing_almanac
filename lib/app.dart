import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/auth/auth_repository.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/auth/token_storage.dart';
import 'package:fishing_almanac/router/app_router.dart';
import 'package:fishing_almanac/services/remote_species_identification.dart';
import 'package:fishing_almanac/services/species_identification.dart';
import 'package:fishing_almanac/services/user_profile_remote.dart';
import 'package:fishing_almanac/repositories/local_catch_repository.dart';
import 'package:fishing_almanac/repositories/remote_catch_repository.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/state/user_profile.dart';
import 'package:fishing_almanac/theme/app_theme.dart';

class FishingAlmanacApp extends StatefulWidget {
  const FishingAlmanacApp({
    super.key,
    this.useRemoteCatchRepository,
    this.useRemoteSpeciesIdentification,
  });

  /// 为 null 时使用 `--dart-define=USE_REMOTE_CATCH_REPOSITORY=true`（默认 false）。
  final bool? useRemoteCatchRepository;

  /// 为 null 时使用 `--dart-define=USE_REMOTE_SPECIES_IDENTIFICATION=true`（默认 false）。
  final bool? useRemoteSpeciesIdentification;

  @override
  State<FishingAlmanacApp> createState() => _FishingAlmanacAppState();
}

class _FishingAlmanacAppState extends State<FishingAlmanacApp> {
  late CatchRepository _catchRepository;
  late final CatchDraft _catchDraft = CatchDraft();
  late final UserProfile _userProfile;
  late final AuthSession _authSession = AuthSession();
  late final TokenStorage _tokenStorage = TokenStorage();
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final AnalyticsClient _analytics;
  late final GoRouter _router;
  late final SpeciesIdentificationService _speciesIdentificationService;

  CatchRepository _createCatchRepository() {
    final useRemote = widget.useRemoteCatchRepository ??
        const bool.fromEnvironment('USE_REMOTE_CATCH_REPOSITORY', defaultValue: false);
    if (useRemote) {
      return RemoteCatchRepository(api: _apiClient, authSession: _authSession);
    }
    return LocalCatchRepository();
  }

  SpeciesIdentificationService _createSpeciesIdentificationService() {
    final useRemote = widget.useRemoteSpeciesIdentification ??
        const bool.fromEnvironment('USE_REMOTE_SPECIES_IDENTIFICATION', defaultValue: false);
    if (useRemote) {
      return RemoteSpeciesIdentificationService(api: _apiClient);
    }
    return const StubSpeciesIdentificationService();
  }

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(onUnauthorized: _handleUnauthorized);
    _analytics = AnalyticsClient(api: _apiClient);
    unawaited(_analytics.init());
    _authRepository = AuthRepository(
      apiClient: _apiClient,
      tokenStorage: _tokenStorage,
      authSession: _authSession,
    );
    _userProfile = UserProfile(
      remote: UserProfileRemote(api: _apiClient),
      authSession: _authSession,
    );
    _catchRepository = _createCatchRepository();
    _speciesIdentificationService = _createSpeciesIdentificationService();
    _router = createAppRouter(authSession: _authSession);
    unawaited(_restoreAccessToken());
    _analytics.trackFireAndForget('app_open');
  }

  void _handleUnauthorized() {
    unawaited(_handleUnauthorizedAsync());
  }

  Future<void> _handleUnauthorizedAsync() async {
    await _authRepository.logout();
    await _userProfile.onSessionEnded();
    if (!mounted) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      GoRouter.of(ctx).go('/login');
    }
  }

  Future<void> _restoreAccessToken() async {
    final access = await _tokenStorage.readAccessToken();
    final has = access != null && access.isNotEmpty;
    if (has) {
      _apiClient.setAccessToken(access);
    }
    _authSession.markRestored(loggedIn: has);
    if (has) {
      unawaited(_userProfile.syncFromServer());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatchRepository>.value(value: _catchRepository),
        ChangeNotifierProvider<CatchDraft>.value(value: _catchDraft),
        ChangeNotifierProvider<UserProfile>.value(value: _userProfile),
        ChangeNotifierProvider<AuthSession>.value(value: _authSession),
        Provider<ApiClient>.value(value: _apiClient),
        Provider<TokenStorage>.value(value: _tokenStorage),
        Provider<AuthRepository>.value(value: _authRepository),
        Provider<AnalyticsClient>.value(value: _analytics),
        Provider<SpeciesIdentificationService>.value(value: _speciesIdentificationService),
      ],
      child: MaterialApp.router(
        title: '海钓图鉴',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
