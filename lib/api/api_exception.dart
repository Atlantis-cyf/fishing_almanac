import 'package:dio/dio.dart';

/// 与后端约定对齐的错误载荷（常见字段兼容解析）。
class ApiError {
  const ApiError({
    required this.message,
    this.code,
    this.rawBody,
  });

  final String message;
  final String? code;
  final dynamic rawBody;

  /// 尝试从 JSON Map 解析（支持 `message` / `error` / `detail` / `code` 等）。
  factory ApiError.fromResponseData(dynamic data, {int? statusCode}) {
    if (data == null) {
      return ApiError(
        message: statusCode != null ? '请求失败 ($statusCode)' : '请求失败',
        rawBody: data,
      );
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final msg = _firstNonEmptyString(map, [
            'message',
            'msg',
            'error',
            'error_message',
            'detail',
            'description',
          ]) ??
          (statusCode != null ? '请求失败 ($statusCode)' : '请求失败');
      final code = _stringOf(map['code'] ?? map['error_code']);
      return ApiError(message: msg, code: code, rawBody: data);
    }
    if (data is String) {
      return ApiError(message: data.isNotEmpty ? data : '请求失败', rawBody: data);
    }
    return ApiError(message: data.toString(), rawBody: data);
  }

  static String? _firstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static String? _stringOf(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// 非 2xx 或网络层失败时抛出，供 Repository 统一捕获。
class ApiException implements Exception {
  ApiException({
    required String message,
    this.statusCode,
    String? code,
    this.rawBody,
    this.dioType,
    this.cause,
  }) : error = ApiError(message: message, code: code, rawBody: rawBody);

  final ApiError error;

  String get message => error.message;
  String? get code => error.code;
  final int? statusCode;
  final dynamic rawBody;
  final DioExceptionType? dioType;
  final Object? cause;

  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    final status = res?.statusCode;
    final data = res?.data;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: '连接超时，请检查网络',
          statusCode: status,
          dioType: e.type,
          cause: e,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          message: '网络不可用，请稍后重试',
          statusCode: status,
          dioType: e.type,
          cause: e,
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          message: '证书校验失败',
          statusCode: status,
          dioType: e.type,
          cause: e,
        );
      case DioExceptionType.cancel:
        return ApiException(
          message: '请求已取消',
          statusCode: status,
          dioType: e.type,
          cause: e,
        );
      case DioExceptionType.badResponse:
        final parsed = ApiError.fromResponseData(data, statusCode: status);
        return ApiException(
          message: parsed.message,
          statusCode: status,
          code: parsed.code,
          rawBody: parsed.rawBody,
          dioType: e.type,
          cause: e,
        );
      case DioExceptionType.unknown:
        final parsed = data != null ? ApiError.fromResponseData(data, statusCode: status) : null;
        return ApiException(
          message: parsed?.message ?? (e.message ?? '未知错误'),
          statusCode: status,
          code: parsed?.code,
          rawBody: parsed?.rawBody ?? data,
          dioType: e.type,
          cause: e,
        );
    }
  }

  @override
  String toString() => 'ApiException($statusCode, ${error.code}, $message)';
}
