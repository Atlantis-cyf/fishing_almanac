import 'package:flutter/foundation.dart';

/// 供 [GoRouter] `refreshListenable` 与 redirect 使用的登录态（内存 + 与 [TokenStorage] 同步）。
class AuthSession extends ChangeNotifier {
  bool _ready = false;
  bool _loggedIn = false;

  /// 是否已完成冷启动时的 token 恢复（未完成前 redirect 不拦截，避免误踢）。
  bool get isReady => _ready;

  bool get isLoggedIn => _loggedIn;

  void markRestored({required bool loggedIn}) {
    _ready = true;
    _loggedIn = loggedIn;
    notifyListeners();
  }

  void setLoggedIn(bool value) {
    _ready = true;
    if (_loggedIn == value) return;
    _loggedIn = value;
    notifyListeners();
  }
}
