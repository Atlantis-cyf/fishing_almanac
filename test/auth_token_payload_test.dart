import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/auth/auth_token_payload.dart';

void main() {
  test('tryParse snake_case root', () {
    final p = AuthTokenPayload.tryParse({
      'access_token': 'a1',
      'refresh_token': 'r1',
    });
    expect(p?.accessToken, 'a1');
    expect(p?.refreshToken, 'r1');
  });

  test('tryParse camelCase in data', () {
    final p = AuthTokenPayload.tryParse({
      'data': {'accessToken': 'x', 'refreshToken': 'y'},
    });
    expect(p?.accessToken, 'x');
    expect(p?.refreshToken, 'y');
  });

  test('tryParse token alias', () {
    final p = AuthTokenPayload.tryParse({'token': 'jwt'});
    expect(p?.accessToken, 'jwt');
  });

  test('tryParse returns null without access', () {
    expect(AuthTokenPayload.tryParse({'refresh_token': 'only'}), isNull);
  });
}
