/// 从登录/注册 JSON 中解析 token，兼容常见后端字段。
class AuthTokenPayload {
  const AuthTokenPayload({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;

  /// 若无法解析出 accessToken 则返回 null。
  static AuthTokenPayload? tryParse(dynamic data) {
    if (data == null) return null;
    if (data is! Map) return null;
    final root = Map<String, dynamic>.from(data);
    Map<String, dynamic> m = root;
    final inner = root['data'];
    if (inner is Map) {
      m = Map<String, dynamic>.from(inner);
    }
    final access = _firstNonEmpty([
      m['access_token'],
      m['accessToken'],
      m['token'],
      m['jwt'],
      m['id_token'],
      m['idToken'],
    ]);
    if (access == null) return null;
    final refresh = _firstNonEmpty([
      m['refresh_token'],
      m['refreshToken'],
    ]);
    return AuthTokenPayload(accessToken: access, refreshToken: refresh);
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c == null) continue;
      final s = c.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
