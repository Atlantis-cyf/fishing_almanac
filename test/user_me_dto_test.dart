import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/api/dto/user_me_dto.dart';
import 'package:fishing_almanac/state/user_profile.dart';

void main() {
  group('UserMeDto.fromResponse', () {
    test('root display_name', () {
      final d = UserMeDto.fromResponse({'display_name': ' 海王 '});
      expect(UserMeDto.resolveDisplayName(d, UserProfile.defaultDisplayName), '海王');
    });

    test('unwraps data', () {
      final d = UserMeDto.fromResponse({
        'data': {'displayName': 'Neo'},
      });
      expect(UserMeDto.resolveDisplayName(d, UserProfile.defaultDisplayName), 'Neo');
    });

    test('nested user', () {
      final d = UserMeDto.fromResponse({
        'user': {'nickname': '潮汐'},
      });
      expect(UserMeDto.resolveDisplayName(d, UserProfile.defaultDisplayName), '潮汐');
    });

    test('fallback when empty', () {
      final d = UserMeDto.fromResponse({'display_name': ''});
      expect(UserMeDto.resolveDisplayName(d, UserProfile.defaultDisplayName), UserProfile.defaultDisplayName);
    });
  });
}
