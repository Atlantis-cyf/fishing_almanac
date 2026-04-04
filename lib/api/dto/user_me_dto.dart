/// 解析 `GET /me`、`PATCH /me` 等响应中的展示名（根级、`data` 或 `user` 嵌套）。
class UserMeDto {
  const UserMeDto({this.displayName, this.email});

  final String? displayName;
  final String? email;

  static const _nameKeys = [
    'display_name',
    'displayName',
    'nickname',
    'username',
    'name',
    'user_name',
    'userName',
  ];

  factory UserMeDto.fromResponse(dynamic data) {
    if (data == null) return const UserMeDto(displayName: null, email: null);
    final m = _unwrapMap(data);
    if (m == null) {
      if (data is String && data.trim().isNotEmpty) {
        return UserMeDto(displayName: data.trim(), email: null);
      }
      return const UserMeDto(displayName: null, email: null);
    }
    final directEmail = _firstString(m, const ['email', 'mail', 'user_email', 'userEmail']);
    final direct = _firstString(m, _nameKeys);
    if (direct != null) return UserMeDto(displayName: direct, email: directEmail);
    final user = m['user'];
    if (user is Map) {
      final u = Map<String, dynamic>.from(user);
      final nested = _firstString(u, _nameKeys);
      final nestedEmail = _firstString(u, const ['email', 'mail']);
      if (nested != null) return UserMeDto(displayName: nested, email: nestedEmail ?? directEmail);
      if (nestedEmail != null) return UserMeDto(displayName: null, email: nestedEmail);
    }
    return UserMeDto(displayName: null, email: directEmail);
  }

  /// 无字段时用 [fallback]（例如本地默认「深海观察者」）。
  static String resolveDisplayName(UserMeDto dto, String fallback) {
    final s = dto.displayName?.trim();
    if (s == null || s.isEmpty) return fallback;
    return s;
  }

  static Map<String, dynamic>? _unwrapMap(dynamic data) {
    if (data is! Map) return null;
    final root = Map<String, dynamic>.from(data);
    final inner = root['data'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner);
    }
    return root;
  }

  static String? _firstString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
