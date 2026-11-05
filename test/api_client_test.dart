import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/network/api_client.dart';
import 'package:green_clean_ops/core/config/app_env.dart';
import 'package:green_clean_ops/core/network/api_response.dart';

/// 用 Dio 拦截器捕获真实发出的 RequestOptions，验证拦截器链行为。
void main() {
  group('日志脱敏与环境配置', () {
    test('login 请求体里的密码/token 不会进 debug 日志', () {
      final Object? redacted = redactSensitive(<String, Object?>{
        'username': 'test2',
        'password': 'super-secret',
        'new_password1': 'another-secret',
        'token': 'abc123',
        'limit': 10,
      });
      expect(redacted, isA<Map>());
      final Map<Object?, Object?> map = redacted! as Map<Object?, Object?>;
      expect(map['password'], '***');
      expect(map['new_password1'], '***');
      expect(map['token'], '***');
      expect(map['username'], 'test2');
      expect(map['limit'], 10);
    });

    test('非 Map 数据原样返回', () {
      expect(redactSensitive('hello'), 'hello');
      expect(redactSensitive(null), isNull);
    });

    test('非生产环境不请求正式版本更新接口', () {
      expect(AppEnv.isProduction, isFalse);
      expect(AppEnv.versionCheckUrl, isNull);
    });
  });

  group('M0-02 拦截器链', () {
    test('token 以名为 token 的请求头注入（非 Bearer）', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/'));
      final ApiClient api = ApiClient(
        dio: dio,
        tokenReader: () => 'real-token-123',
        enableLog: false,
      );

      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                captured = options;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object?>{
                      'success': true,
                      'data': <Object?>[],
                    },
                  ),
                );
              },
        ),
      );

      final ApiResponse response = await api.getRaw('meta/basic');
      expect(response.success, isTrue);
      expect(captured, isNotNull);
      expect(captured!.headers['token'], 'real-token-123');
      expect(captured!.headers.containsKey('Authorization'), isFalse);
      expect(captured!.headers['X-Request-Id'], isNotEmpty);
      expect(captured!.headers['X-Client'], 'flutter');
    });

    test('后端返回 success=false 时抛业务异常并保留原文', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/'));
      final ApiClient api = ApiClient(dio: dio, enableLog: false);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object?>{
                      'success': false,
                      'error': 'FIELD_ERROR',
                      'message': '账户或密码不能为空',
                    },
                  ),
                );
              },
        ),
      );

      await expectLater(
        api.postRaw('login', data: const <String, Object?>{'username': ''}),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.userMessage,
            'message',
            '账户或密码不能为空',
          ),
        ),
      );
    });

    test('UNAUTHENTICATED 触发统一登出回调', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/'));
      final ApiClient api = ApiClient(dio: dio, enableLog: false);
      int logoutCalls = 0;
      api.onUnauthenticated = () => logoutCalls++;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object?>{
                      'success': false,
                      'error': 'UNAUTHENTICATED',
                      'message': '用户未认证或token过期',
                    },
                  ),
                );
              },
        ),
      );

      await expectLater(
        api.postRaw('task/timeline'),
        throwsA(isA<AppException>()),
      );
      expect(logoutCalls, 1);
    });
  });
}
