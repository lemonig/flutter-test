import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import 'api_response.dart';
import 'server_time.dart';

typedef TokenReader = String? Function();

const String _kRetryCount = 'retry_count';
const String _kRequestId = 'request_id';
const String _kStartTime = 'start_time';

/// 日志脱敏：debug 日志会进 logcat / 崩溃上报，绝不能把密码、token 明文打出去。
/// 真机联调时曾发现 `[API] → POST /login data={username: ..., password: ...}` 泄漏。
Object? redactSensitive(Object? data) {
  if (data is! Map) return data;
  const Set<String> sensitive = <String>{
    'password',
    'old_password',
    'new_password1',
    'new_password2',
    'code',
    'token',
    'wxUserId',
    'mobile',
  };
  return data.map<Object?, Object?>(
    (Object? key, Object? value) => MapEntry<Object?, Object?>(
      key,
      sensitive.contains('$key') ? '***' : value,
    ),
  );
}

/// 统一网络客户端（M0-01 / M0-02）。
///
/// 与原 iOS 工程 `NetworkTool` 对齐：
/// - 鉴权头是 `token`，不是 `Authorization: Bearer`
/// - 业务成败以响应体 `success` 为准，`UNAUTHENTICATED` 触发统一登出
/// - 所有业务错误统一转成 [AppException]
class ApiClient {
  ApiClient({
    Dio? dio,
    TokenReader? tokenReader,
    ServerTime? serverTime,
    bool? enableLog,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppEnv.baseUrl,
               connectTimeout: AppEnv.connectTimeout,
               receiveTimeout: AppEnv.receiveTimeout,
               headers: const <String, Object>{'Accept': 'application/json'},
               contentType: Headers.jsonContentType,
             ),
           ),
       // 显式赋值而非 `this._x`：私有 initializing formal 会让跨库调用方
       // 无法传 tokenReader，导致真实后端 401。
       // ignore: prefer_initializing_formals
       _tokenReader = tokenReader,
       // ignore: prefer_initializing_formals
       _serverTime = serverTime,
       _enableLog = enableLog ?? (kDebugMode && AppEnv.verboseLog) {
    _dio.interceptors.addAll(<Interceptor>[
      _RequestIdInterceptor(),
      _AuthInterceptor(_tokenReader),
      _ServerTimeInterceptor(_serverTime),
      _LogInterceptor(_enableLog),
      _RetryInterceptor(_dio),
    ]);
  }

  final Dio _dio;
  final TokenReader? _tokenReader;
  final ServerTime? _serverTime;
  final bool _enableLog;

  /// 由鉴权模块在 `build()` 里绑定，避免 Provider 循环依赖。
  VoidCallback? onUnauthenticated;

  Dio get raw => _dio;

  String get baseUrl => _dio.options.baseUrl;

  bool get isLoggingEnabled => _enableLog;

  /// GET 并解包。
  Future<ApiResponse> getRaw(
    String path, {
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) => _execute('GET', path, query: query, cancelToken: cancelToken);

  /// POST 并解包（业务列表接口统一走 POST）。
  Future<ApiResponse> postRaw(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) => _execute(
    'POST',
    path,
    data: data,
    query: query,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
  );

  Future<ApiResponse> putRaw(String path, {Object? data}) =>
      _execute('PUT', path, data: data);

  Future<ApiResponse> deleteRaw(String path, {Object? data}) =>
      _execute('DELETE', path, data: data);

  Future<T> getMapped<T>(
    String path, {
    required T Function(ApiResponse response) map,
    Map<String, Object?>? query,
  }) async => map(await getRaw(path, query: query));

  Future<T> postMapped<T>(
    String path, {
    required T Function(ApiResponse response) map,
    Object? data,
  }) async => map(await postRaw(path, data: data));

  Future<ApiResponse> _execute(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final Response<Object?> response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        options: Options(method: method),
      );
      final ApiResponse parsed = ApiResponse.parse(response.data);
      final AppException? failure = parsed.failure;
      if (failure != null) {
        if (failure.isUnauthenticated) onUnauthenticated?.call();
        throw failure;
      }
      return parsed;
    } on DioException catch (error) {
      final AppException exception = AppException.fromDio(error);
      if (exception.isUnauthenticated) onUnauthenticated?.call();
      throw exception;
    }
  }
}

/// 注入 `token` 头；登录接口无需携带。
class _AuthInterceptor extends Interceptor {
  const _AuthInterceptor(this._readToken);

  final TokenReader? _readToken;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? token = _readToken?.call();
    if (token != null && token.isNotEmpty) {
      options.headers['token'] = token;
    }
    handler.next(options);
  }
}

/// 请求 ID + 客户端标识 + 计时，便于日志串联与后端排查。
class _RequestIdInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final int millis = DateTime.now().millisecondsSinceEpoch;
    final int random = Random().nextInt(0xFFFFFF);
    final String id = '${millis.toRadixString(16)}-${random.toRadixString(16)}';
    options.extra[_kRequestId] = id;
    options.extra[_kStartTime] = DateTime.now();
    options.headers['X-Request-Id'] = id;
    options.headers['X-Client'] = 'flutter';
    handler.next(options);
  }
}

/// 从 HTTP `Date` 头校准服务端时间（M0-08）。
class _ServerTimeInterceptor extends Interceptor {
  const _ServerTimeInterceptor(this._serverTime);

  final ServerTime? _serverTime;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _serverTime?.calibrateFromHttpDate(response.headers.value('date'));
    handler.next(response);
  }
}

class _LogInterceptor extends Interceptor {
  const _LogInterceptor(this._enabled);

  final bool _enabled;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_enabled) {
      debugPrint(
        '[API] → ${options.method} ${options.uri} '
        'id=${options.extra[_kRequestId]} data=${redactSensitive(options.data)}',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_enabled) {
      final DateTime? start =
          response.requestOptions.extra[_kStartTime] as DateTime?;
      final int ms = start == null
          ? 0
          : DateTime.now().difference(start).inMilliseconds;
      debugPrint(
        '[API] ← ${response.statusCode} '
        '${response.requestOptions.uri} ${ms}ms '
        'id=${response.requestOptions.extra[_kRequestId]}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_enabled) {
      debugPrint(
        '[API] ✗ ${err.type.name} ${err.requestOptions.uri} '
        'id=${err.requestOptions.extra[_kRequestId]} → ${err.message}',
      );
    }
    handler.next(err);
  }
}

/// 断网/超时/5xx 自动重试 1 次（M0-02）。
/// 401 与手动取消不重试，避免重复触发登出。
class _RetryInterceptor extends Interceptor {
  const _RetryInterceptor(this._dio);

  final Dio _dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int retried = (err.requestOptions.extra[_kRetryCount] as int?) ?? 0;
    final AppException exception = AppException.fromDio(err);
    if (retried >= 1 || !exception.isRetryable || exception.isUnauthenticated) {
      handler.next(err);
      return;
    }
    final RequestOptions options = err.requestOptions;
    options.extra[_kRetryCount] = retried + 1;
    try {
      final Response<dynamic> response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
