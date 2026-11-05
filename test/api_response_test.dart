import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/core/network/server_time.dart';

void main() {
  group('M0-01 ApiResponse 解包', () {
    test('success=true 时正确取出 data 数组', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': <Object?>[
          <String, Object?>{'id': 1},
          <String, Object?>{'id': 2},
        ],
      });
      expect(response.success, isTrue);
      expect(response.failure, isNull);
      expect(response.listData, hasLength(2));
    });

    test('data 为对象时可用 mapData', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': <String, Object?>{'token': 'abc', 'nickname': '张伟'},
      });
      expect(response.mapData['token'], 'abc');
    });

    test('业务失败透传后端原文', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': false,
        'error': 'BAD_CREDENTIALS',
        'message': '账号或密码错误',
      });
      final AppException? failure = response.failure;
      expect(failure, isNotNull);
      expect(failure!.kind, ApiErrorKind.business);
      expect(failure.userMessage, '账号或密码错误');
    });

    test('UNAUTHENTICATED 映射为登录过期', () {
      final AppException? failure = ApiResponse.parse(<String, Object?>{
        'success': false,
        'error': 'UNAUTHENTICATED',
      }).failure;
      expect(failure!.isUnauthenticated, isTrue);
      expect(failure.userMessage, contains('登录已过期'));
    });

    test('裸数据响应视为成功', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'id': 1,
        'name': 'test',
      });
      expect(response.success, isTrue);
      expect(response.mapData['name'], 'test');
    });

    test('data 类型不符时抛解析异常', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': 'not-a-list',
      });
      expect(() => response.listData, throwsA(isA<AppException>()));
    });
  });

  group('M0-01 Dio 异常 → 领域异常', () {
    DioException dio(DioExceptionType type, {int? status}) => DioException(
      type: type,
      requestOptions: RequestOptions(path: '/x'),
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
            ),
    );

    test('连接失败 → 网络错误且可重试', () {
      final AppException error = AppException.fromDio(
        dio(DioExceptionType.connectionError),
      );
      expect(error.kind, ApiErrorKind.network);
      expect(error.isRetryable, isTrue);
      expect(error.userMessage, contains('网络'));
    });

    test('超时 → 超时错误且可重试', () {
      final AppException error = AppException.fromDio(
        dio(DioExceptionType.receiveTimeout),
      );
      expect(error.kind, ApiErrorKind.timeout);
      expect(error.isRetryable, isTrue);
    });

    test('401 → 登录过期且不重试', () {
      final AppException error = AppException.fromDio(
        dio(DioExceptionType.badResponse, status: 401),
      );
      expect(error.isUnauthenticated, isTrue);
      expect(error.isRetryable, isFalse);
    });

    test('取消请求不可重试', () {
      final AppException error = AppException.fromDio(
        dio(DioExceptionType.cancel),
      );
      expect(error.kind, ApiErrorKind.cancelled);
      expect(error.isRetryable, isFalse);
    });
  });

  group('M0-08 服务端时间校准', () {
    test('HTTP Date 头可解析并产生偏移', () {
      final ServerTime time = ServerTime()
        ..calibrateFromHttpDate('Wed, 04 Nov 2026 11:30:00 GMT');
      expect(time.isCalibrated, isTrue);
      expect(time.offset.inDays.abs(), lessThan(3650));
      expect(
        time.now().difference(DateTime.now()).inSeconds.abs(),
        lessThanOrEqualTo(time.offset.inSeconds.abs() + 2),
      );
    });

    test('非法 Date 头不会污染状态', () {
      final ServerTime time = ServerTime()..calibrateFromHttpDate('garbage');
      expect(time.isCalibrated, isFalse);
      expect(time.offset, Duration.zero);
    });

    test('reset 清空校准', () {
      final ServerTime time = ServerTime()..calibrate(DateTime.now().toUtc());
      expect(time.isCalibrated, isTrue);
      time.reset();
      expect(time.isCalibrated, isFalse);
    });
  });
}
