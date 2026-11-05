import 'dart:io' show SocketException;

import 'package:dio/dio.dart';

/// 后端响应信封类型（M0-01）。
///
/// 原 iOS 工程 `NetworkTool.request` 以 `JSON(res.value)["success"].bool`
/// 判定成败，失败读 `json["error"]`。本类做等价解包并兼容 `code` / `message`。
class ApiResponse {
  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.message,
    this.code,
    this.raw,
  });

  final bool success;
  final Object? data;
  final String? error;
  final String? message;
  final int? code;
  final Object? raw;

  factory ApiResponse.parse(Object? json) {
    if (json is! Map) {
      // 少数接口直接返回裸数据，视为成功。
      return ApiResponse(success: true, data: json, raw: json);
    }

    final Map<Object?, Object?> map = json;
    final bool hasEnvelope =
        map.containsKey('success') ||
        map.containsKey('error') ||
        map.containsKey('data');

    if (!hasEnvelope) {
      return ApiResponse(success: true, data: json, raw: json);
    }

    final Object? rawSuccess = map['success'];
    final Object? rawCode = map['code'];
    final bool success =
        rawSuccess == true ||
        rawSuccess == 1 ||
        rawSuccess == 'true' ||
        (rawSuccess == null && rawCode == 0) ||
        (rawSuccess == null &&
            rawCode == null &&
            map['error'] == null &&
            map.containsKey('data'));

    final Object? rawError = map['error'];
    final Object? rawMessage = map['message'] ?? map['msg'];
    final Object? data = map.containsKey('data') ? map['data'] : null;

    return ApiResponse(
      success: success,
      data: data,
      error: rawError?.toString(),
      message: rawMessage?.toString(),
      code: rawCode is int ? rawCode : int.tryParse('$rawCode'),
      raw: json,
    );
  }

  /// 业务失败时转成领域异常；成功返回 null。
  AppException? get failure {
    if (success) return null;
    if (error?.toUpperCase() == 'UNAUTHENTICATED') {
      return const AppException(
        '登录已过期，请重新登录',
        kind: ApiErrorKind.unauthenticated,
        code: 'UNAUTHENTICATED',
      );
    }
    final String? text = message ?? error;
    return AppException(
      text == null || text.isEmpty ? '请求失败，请稍后重试' : text,
      kind: ApiErrorKind.business,
      code: error,
      statusCode: code,
    );
  }

  /// 后端 `ApiResponse.additional_data`：分页对象 PaginationVO。
  Object? get additionalData =>
      raw is Map ? (raw! as Map)['additional_data'] : null;

  /// `more_items_in_collection`：是否还有下一页。
  bool? get hasMoreItems {
    final Object? extra = additionalData;
    if (extra is! Map) return null;
    final Object? flag = extra['more_items_in_collection'];
    return flag is bool ? flag : null;
  }

  /// 取列表数据；非 List 时抛解析异常。
  List<Object?> get listData {
    final Object? value = data;
    if (value is List) return value;
    if (value == null) return const <Object?>[];
    throw const AppException(
      '数据格式异常',
      kind: ApiErrorKind.parse,
      code: 'DATA_NOT_LIST',
    );
  }

  /// 取对象数据；非 Map 时抛解析异常。
  Map<String, Object?> get mapData {
    final Object? value = data;
    if (value is Map) return Map<String, Object?>.from(value);
    throw const AppException(
      '数据格式异常',
      kind: ApiErrorKind.parse,
      code: 'DATA_NOT_MAP',
    );
  }
}

enum ApiErrorKind {
  network,
  timeout,
  server,
  business,
  unauthenticated,
  parse,
  cancelled,
  unknown,
}

/// 领域异常：UI 只依赖 [kind] 与 [userMessage]，不接触 Dio 细节。
class AppException implements Exception {
  const AppException(
    this.message, {
    this.kind = ApiErrorKind.unknown,
    this.code,
    this.statusCode,
    this.original,
  });

  final String message;
  final ApiErrorKind kind;
  final String? code;
  final int? statusCode;
  final Object? original;

  bool get isUnauthenticated => kind == ApiErrorKind.unauthenticated;

  /// 可安全自动重试（幂等请求限定，由调用方决定是否真的重试）。
  bool get isRetryable =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      (kind == ApiErrorKind.server && (statusCode ?? 500) >= 500);

  String get userMessage => switch (kind) {
    ApiErrorKind.network => '网络连接不可用，请检查网络后重试',
    ApiErrorKind.timeout => '请求超时，请稍后重试',
    ApiErrorKind.server => '服务暂时不可用（${statusCode ?? '未知状态'}）',
    ApiErrorKind.unauthenticated => '登录已过期，请重新登录',
    ApiErrorKind.parse => '数据解析失败，请稍后重试',
    ApiErrorKind.cancelled => '请求已取消',
    ApiErrorKind.business || ApiErrorKind.unknown => message,
  };

  factory AppException.fromDio(DioException error) {
    final Object? original = error.error;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => AppException(
        '请求超时',
        kind: ApiErrorKind.timeout,
        statusCode: error.response?.statusCode,
        original: error,
      ),
      DioExceptionType.connectionError => AppException(
        original is SocketException ? '无法连接服务器' : '网络连接失败',
        kind: ApiErrorKind.network,
        original: error,
      ),
      DioExceptionType.cancel => const AppException(
        '请求已取消',
        kind: ApiErrorKind.cancelled,
      ),
      DioExceptionType.badCertificate => const AppException(
        '证书校验失败，请检查网络环境',
        kind: ApiErrorKind.network,
      ),
      DioExceptionType.badResponse => _fromBadResponse(error),
      DioExceptionType.unknown => AppException(
        error.message ?? '未知网络错误',
        kind: ApiErrorKind.unknown,
        original: error,
      ),
    };
  }

  static AppException _fromBadResponse(DioException error) {
    final int? status = error.response?.statusCode;
    if (status == 401) {
      return AppException(
        '登录已过期，请重新登录',
        kind: ApiErrorKind.unauthenticated,
        statusCode: status,
        original: error,
      );
    }
    final ApiResponse parsed = ApiResponse.parse(error.response?.data);
    final AppException? business = parsed.failure;
    if (business != null && business.kind == ApiErrorKind.business) {
      return AppException(
        business.message,
        kind: ApiErrorKind.business,
        code: business.code,
        statusCode: status,
        original: error,
      );
    }
    return AppException(
      'HTTP $status',
      kind: ApiErrorKind.server,
      statusCode: status,
      original: error,
    );
  }

  @override
  String toString() => 'AppException(${kind.name}, $code): $message';
}
