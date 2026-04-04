import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/auth/auth_token_payload.dart';
import 'package:fishing_almanac/auth/token_storage.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
    AuthSession? authSession,
  })  : _api = apiClient,
        _storage = tokenStorage,
        _session = authSession;

  final ApiClient _api;
  final TokenStorage _storage;
  final AuthSession? _session;

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.post<dynamic>(
      AuthEndpoints.login,
      data: <String, dynamic>{
        'email': email.trim(),
        'password': password,
      },
    );
    final payload = AuthTokenPayload.tryParse(res.data);
    if (payload == null) {
      throw ApiException(
        message: '登录响应缺少 access token，请检查 AUTH_LOGIN_PATH 与后端契约',
        statusCode: res.statusCode,
        rawBody: res.data,
      );
    }
    await _storage.writeTokens(
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken,
    );
    _api.setAccessToken(payload.accessToken);
    _session?.setLoggedIn(true);
  }

  /// 返回 `true` 表示响应内已带 token 并已完成登录；`false` 表示需跳转登录页手动登录。
  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _api.post<dynamic>(
      AuthEndpoints.register,
      data: <String, dynamic>{
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
      },
    );
    final payload = AuthTokenPayload.tryParse(res.data);
    if (payload == null) {
      return false;
    }
    await _storage.writeTokens(
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken,
    );
    _api.setAccessToken(payload.accessToken);
    _session?.setLoggedIn(true);
    return true;
  }

  Future<void> logout() async {
    try {
      await _storage.clear();
    } catch (e, st) {
      debugPrint('AuthRepository.logout clear tokens failed: $e\n$st');
    }
    _api.setAccessToken(null);
    _session?.setLoggedIn(false);
  }
}
