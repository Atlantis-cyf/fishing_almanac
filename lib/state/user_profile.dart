import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/api/dto/user_me_dto.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/services/user_profile_remote.dart';

/// 用户展示名：已登录时以服务端为准（`GET/PATCH /me`），本地 [SharedPreferences] 作缓存。
/// 密码等仍仅存本地（演示用）。
class UserProfile extends ChangeNotifier {
  UserProfile({
    UserProfileRemote? remote,
    AuthSession? authSession,
  })  : _remote = remote,
        _auth = authSession {
    _load();
  }

  final UserProfileRemote? _remote;
  final AuthSession? _auth;

  static const _keyDisplayName = 'user_display_name_v1';
  static const _keyEmail = 'user_email_v1';
  static const _keyPassword = 'user_password_v1';

  static const String defaultDisplayName = '深海观察者';

  String _displayName = defaultDisplayName;
  String? _email;
  String? _password;

  String get displayName => _displayName.trim().isEmpty ? defaultDisplayName : _displayName.trim();
  String get email => (_email == null || _email!.trim().isEmpty) ? '—' : _email!.trim();
  bool get hasPassword => _password != null && _password!.isNotEmpty;

  bool get _loggedIn => _auth?.isLoggedIn ?? false;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_keyDisplayName);
      _displayName = (raw == null || raw.trim().isEmpty) ? defaultDisplayName : raw.trim();
      _email = p.getString(_keyEmail);
      _password = p.getString(_keyPassword);
    } catch (e, st) {
      debugPrint('UserProfile._load failed: $e\n$st');
      _displayName = defaultDisplayName;
    }
    notifyListeners();
  }

  /// 已登录时请求 `GET /me` 并覆盖内存与缓存；失败则保留当前缓存。
  Future<void> syncFromServer() async {
    final remote = _remote;
    if (remote == null || !_loggedIn) return;
    try {
      final dto = await remote.fetchMe();
      final name = UserMeDto.resolveDisplayName(dto, defaultDisplayName);
      await _persistProfile(name: name, email: dto.email);
    } on ApiException catch (e) {
      debugPrint('UserProfile.syncFromServer ApiException: ${e.message}');
    } catch (e, st) {
      debugPrint('UserProfile.syncFromServer failed: $e\n$st');
    }
  }

  /// 登出后清空展示名缓存，避免账号切换串名。
  Future<void> onSessionEnded() async {
    _displayName = defaultDisplayName;
    _email = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_keyDisplayName);
      await p.remove(_keyEmail);
    } catch (e, st) {
      debugPrint('UserProfile.onSessionEnded remove displayName failed: $e\n$st');
    }
    notifyListeners();
  }

  /// 未登录或无私服客户端时仅写本地；已登录则 `PATCH /me` 后以服务端解析结果为准。
  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    final effective = trimmed.isEmpty ? defaultDisplayName : trimmed;

    final remote = _remote;
    if (remote != null && _loggedIn) {
      final dto = await remote.patchDisplayName(effective);
      final resolved = UserMeDto.resolveDisplayName(dto, effective);
      await _persistProfile(name: resolved, email: dto.email ?? _email);
      return;
    }

    await _persistProfile(name: effective, email: _email);
  }

  Future<void> _persistProfile({required String name, String? email}) async {
    try {
      _displayName = name;
      _email = email;
      final p = await SharedPreferences.getInstance();
      await p.setString(_keyDisplayName, _displayName);
      if (email != null && email.trim().isNotEmpty) {
        await p.setString(_keyEmail, email.trim());
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('UserProfile._persistProfile failed: $e\n$st');
      throw PersistenceException('无法保存昵称到本地', cause: e);
    }
  }

  /// 新密码与确认密码须一致；若本地已有密码则需先通过 [currentPassword]。
  Future<void> changePassword({
    required String newPassword,
    required String confirmPassword,
    String? currentPassword,
  }) async {
    if (hasPassword) {
      if (!verifyCurrentPassword(currentPassword ?? '')) {
        throw StateError('原密码不正确');
      }
    }
    if (newPassword != confirmPassword) {
      throw StateError('两次输入的密码不一致');
    }
    if (newPassword.length < 6) {
      throw StateError('密码至少 6 位');
    }
    _password = newPassword;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_keyPassword, newPassword);
      notifyListeners();
    } catch (e, st) {
      debugPrint('UserProfile.changePassword persist failed: $e\n$st');
      throw PersistenceException('无法保存密码到本地', cause: e);
    }
  }

  /// 修改密码时若已设置过密码，需校验原密码。
  bool verifyCurrentPassword(String input) {
    if (!hasPassword) return true;
    return input == _password;
  }
}
