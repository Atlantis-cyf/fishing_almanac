import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/dto/user_me_dto.dart';

/// 与后端同步用户展示名（[UserProfile] 在已登录时调用；失败则保留本地缓存）。
class UserProfileRemote {
  UserProfileRemote({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Future<UserMeDto> fetchMe() async {
    final res = await _api.get<dynamic>(UserMeEndpoints.path);
    return UserMeDto.fromResponse(res.data);
  }

  /// 请求体使用 `display_name`；若响应体无展示名则回退为本次提交值。
  Future<UserMeDto> patchDisplayName(String displayName) async {
    final res = await _api.patch<dynamic>(
      UserMeEndpoints.path,
      data: <String, dynamic>{'display_name': displayName},
    );
    final parsed = UserMeDto.fromResponse(res.data);
    final resolved = parsed.displayName?.trim();
    if (resolved != null && resolved.isNotEmpty) {
      return parsed;
    }
    return UserMeDto(displayName: displayName);
  }
}
