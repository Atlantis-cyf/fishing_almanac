import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/api/api_exception.dart';

void main() {
  group('ApiError.fromResponseData', () {
    test('parses message and code from map', () {
      final e = ApiError.fromResponseData(
        {'message': '用户不存在', 'code': 'USER_NOT_FOUND'},
        statusCode: 404,
      );
      expect(e.message, '用户不存在');
      expect(e.code, 'USER_NOT_FOUND');
    });

    test('parses error field', () {
      final e = ApiError.fromResponseData({'error': 'Invalid token'});
      expect(e.message, 'Invalid token');
    });

    test('parses detail field', () {
      final e = ApiError.fromResponseData({'detail': 'Not found'});
      expect(e.message, 'Not found');
    });
  });

  group('ApiException.fromDio', () {
    test('badResponse maps body', () {
      final ex = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 422,
            data: {'message': '校验失败', 'code': 'VALIDATION'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(ex.statusCode, 422);
      expect(ex.message, '校验失败');
      expect(ex.code, 'VALIDATION');
    });
  });
}
