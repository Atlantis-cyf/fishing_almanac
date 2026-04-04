import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';

/// 全局 HTTP 客户端。业务层只通过此类发请求，不在 Screen 中 new [Dio]。
class ApiClient {
  ApiClient({
    String? baseUrl,
    this.onUnauthorized,
  }) : _dio = Dio(_baseOptions(baseUrl ?? ApiConfig.baseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final t = accessToken;
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
      ),
    );
    if (kDebugMode) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          compact: true,
          maxWidth: 96,
        ),
      );
    }
  }

  final Dio _dio;

  /// 响应 401 时回调（清会话、跳转登录等），由应用层注入。
  final void Function()? onUnauthorized;

  /// 供 PR-2 鉴权注入；为 null 时不带 [Authorization]。
  String? accessToken;

  Dio get dio => _dio;

  static BaseOptions _baseOptions(String baseUrl) {
    return BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: <String, dynamic>{
        Headers.acceptHeader: 'application/json',
        Headers.contentTypeHeader: Headers.jsonContentType,
      },
    );
  }

  void setAccessToken(String? token) {
    accessToken = token;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _guard(() => _dio.get<T>(path, queryParameters: queryParameters, options: options, cancelToken: cancelToken));

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) =>
      _guard(
        () => _dio.post<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
        ),
      );

  /// `multipart/form-data` 上传（由 Dio 自动带 boundary）。
  Future<Response<T>> postMultipart<T>(
    String path, {
    required FormData data,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) =>
      _guard(
        () => _dio.post<T>(
          path,
          data: data,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
        ),
      );

  Future<Response<T>> putMultipart<T>(
    String path, {
    required FormData data,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) =>
      _guard(
        () => _dio.put<T>(
          path,
          data: data,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
        ),
      );

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _guard(
        () => _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken),
      );

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _guard(
        () =>
            _dio.patch<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken),
      );

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _guard(
        () => _dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken),
      );

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        try {
          onUnauthorized?.call();
        } catch (_) {
          // 避免回调异常掩盖原始 401
        }
      }
      throw ApiException.fromDio(e);
    }
  }
}
