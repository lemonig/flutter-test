import 'package:dio/dio.dart';

import 'app_env.dart';

/// 后端连通性探测结果。
enum ProbeStatus { reachable, unreachable, timeout, serverError }

/// 一次探测的结论。
///
/// 只关心「HTTP 层是否通」，不参与业务鉴权流程 —— 这样即使 token 失效，
/// 也能把「网络/服务不通」和「登录态过期」区分开，避免用户把两者混为一谈。
class EnvProbeResult {
  const EnvProbeResult({
    required this.status,
    required this.elapsedMs,
    this.statusCode,
    this.message,
    this.detail,
    this.unauthenticated = false,
    this.hasToken = false,
  });

  final ProbeStatus status;
  final int elapsedMs;
  final int? statusCode;

  /// 后端返回的 `message`（未登录时会拿到「用户未认证或token过期」）。
  final String? message;
  final String? detail;

  /// 后端明确回了 `UNAUTHENTICATED`：服务本身是通的，只是当前 token 不可用。
  final bool unauthenticated;

  /// 本次探测是否带了 token，决定「未认证」该算正常还是异常。
  final bool hasToken;

  bool get isHealthy => status == ProbeStatus.reachable;

  String get label => switch (status) {
    ProbeStatus.reachable => (unauthenticated && hasToken) ? '登录态已失效' : '后端可达',
    ProbeStatus.unreachable => '无法连接',
    ProbeStatus.timeout => '连接超时',
    ProbeStatus.serverError => '服务异常',
  };

  /// 一句话说明，给诊断面板做副标题。
  String get summary {
    if (!isHealthy) {
      return detail ??
          (status == ProbeStatus.timeout ? '连接超时，请检查网络或服务是否启动' : '请求失败，请检查地址与网络');
    }
    final String tail = !hasToken
        ? '服务可达（当前未登录）'
        : (unauthenticated ? '登录态已过期，重新登录即可' : '服务与登录态正常');
    return 'HTTP ${statusCode ?? 200} · ${elapsedMs}ms · $tail';
  }
}

/// 环境探测：请求 `{baseUrl}version`，端到端确认「这个包连的是哪台机器、通不通」。
class EnvProbe {
  const EnvProbe._();

  static Future<EnvProbeResult> run({
    String? token,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        // 业务上 401 / 缺参数也会返回 200，这里只判断传输与状态码。
        validateStatus: (int? _) => true,
        headers: <String, Object?>{'token': ?token},
      ),
    );
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Response<Object?> response = await dio.get<Object?>(
        '${AppEnv.baseUrl}meta/auth',
      );
      watch.stop();
      final int code = response.statusCode ?? 0;
      final Object? body = response.data;
      final Map<String, Object?>? map = body is Map
          ? body.cast<String, Object?>()
          : null;
      return EnvProbeResult(
        status: code >= 200 && code < 500
            ? ProbeStatus.reachable
            : ProbeStatus.serverError,
        statusCode: code,
        elapsedMs: watch.elapsedMilliseconds,
        hasToken: token != null,
        message: map?['message'] as String?,
        unauthenticated: map?['error'] == 'UNAUTHENTICATED',
      );
    } on DioException catch (error) {
      watch.stop();
      final bool timeout =
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
      return EnvProbeResult(
        status: timeout ? ProbeStatus.timeout : ProbeStatus.unreachable,
        elapsedMs: watch.elapsedMilliseconds,
        detail: _friendly(error),
      );
    } catch (error) {
      watch.stop();
      return EnvProbeResult(
        status: ProbeStatus.unreachable,
        elapsedMs: watch.elapsedMilliseconds,
        detail: '$error',
      );
    } finally {
      dio.close(force: true);
    }
  }

  static String _friendly(DioException error) {
    final String raw = error.message ?? '${error.type}';
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => '连接超时（>${error.requestOptions.connectTimeout?.inSeconds ?? 6}s）',
      DioExceptionType.connectionError => '建立连接失败：$raw',
      DioExceptionType.badCertificate => '证书校验失败：$raw',
      DioExceptionType.cancel => '请求被取消',
      _ => raw,
    };
  }
}
