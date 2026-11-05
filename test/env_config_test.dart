import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/config/app_env.dart';
import 'package:green_clean_ops/core/config/env_probe.dart';
import 'package:green_clean_ops/shared/widgets/env_badge.dart';

/// 环境可见性回归：装错包、连错地址是这一轮最贵的沟通成本，
/// 所以「默认连真实后端」「徽标文案」「诊断文案」都要有测试盯着。
void main() {
  group('AppEnv 默认值', () {
    test('默认不走演示数据', () {
      expect(
        AppEnv.useMock,
        isFalse,
        reason: '产品默认必须连真实后端，否则装完包看不到数据会被误判成接口故障',
      );
    });

    test('默认环境是开发环境且地址以 /api/ 结尾', () {
      expect(AppEnv.flavor, AppFlavor.dev);
      expect(AppEnv.baseUrl, 'http://192.168.188.66:1601/api/');
      expect(AppEnv.baseUrl.endsWith('/'), isTrue);
    });

    test('非生产环境不做版本检查', () {
      expect(AppEnv.isProduction, isFalse);
      expect(AppEnv.versionCheckUrl, isNull);
    });
  });

  group('EnvDescriptor', () {
    test('演示包显示演示徽标', () {
      final EnvDescriptor env = EnvDescriptor.of(demo: true);
      expect(env.badge, '演示');
      expect(env.title, '演示模式');
      expect(env.dataSource, contains('不发起任何网络请求'));
    });

    test('非演示包按 flavor 显示开发徽标', () {
      final EnvDescriptor env = EnvDescriptor.of(demo: false);
      expect(env.badge, '开发');
      expect(env.title, '开发环境');
      expect(env.dataSource, contains('局域网'));
    });
  });

  group('EnvProbeResult 文案', () {
    test('可达且带有效 token 时提示服务与登录态正常', () {
      const EnvProbeResult result = EnvProbeResult(
        status: ProbeStatus.reachable,
        elapsedMs: 42,
        statusCode: 200,
        hasToken: true,
      );
      expect(result.label, '后端可达');
      expect(result.summary, contains('42ms'));
      expect(result.summary, contains('服务与登录态正常'));
    });

    test('带 token 但后端回未认证时提示登录态过期', () {
      const EnvProbeResult result = EnvProbeResult(
        status: ProbeStatus.reachable,
        elapsedMs: 80,
        statusCode: 200,
        hasToken: true,
        unauthenticated: true,
      );
      expect(result.label, '登录态已失效');
      expect(result.summary, contains('重新登录'));
    });

    test('未登录探测只说明服务可达', () {
      const EnvProbeResult result = EnvProbeResult(
        status: ProbeStatus.reachable,
        elapsedMs: 30,
        statusCode: 200,
        unauthenticated: true,
      );
      expect(result.label, '后端可达');
      expect(result.summary, contains('当前未登录'));
    });

    test('超时给出可操作提示', () {
      const EnvProbeResult result = EnvProbeResult(
        status: ProbeStatus.timeout,
        elapsedMs: 6000,
      );
      expect(result.isHealthy, isFalse);
      expect(result.summary, contains('连接超时'));
    });
  });
}
