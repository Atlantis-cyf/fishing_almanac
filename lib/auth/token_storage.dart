import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_almanac/repositories/persistence_exception.dart';

/// Access / Refresh 存于 [SharedPreferences]（联调够用；生产可换 secure_storage）。
class TokenStorage {
  static const _kAccess = 'auth_access_token_v1';
  static const _kRefresh = 'auth_refresh_token_v1';

  Future<String?> readAccessToken() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kAccess);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<String?> readRefreshToken() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kRefresh);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> writeTokens({required String accessToken, String? refreshToken}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kAccess, accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await p.setString(_kRefresh, refreshToken);
      }
    } catch (e, st) {
      debugPrint('TokenStorage.writeTokens failed: $e\n$st');
      throw PersistenceException('无法保存登录凭证', cause: e);
    }
  }

  Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kAccess);
      await p.remove(_kRefresh);
    } catch (e, st) {
      debugPrint('TokenStorage.clear failed: $e\n$st');
      throw PersistenceException('无法清除登录凭证', cause: e);
    }
  }
}
