import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:green_clean_ops/app.dart';
import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/retry_policy.dart';
import 'package:green_clean_ops/features/auth/data/models/app_user.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';

/// 测试用登录用户（与 MockAuthRepository 的演示账号一致）。
AppUser get demoTestUser => AppUser.fromJson(<String, Object?>{
  'id': '1001',
  'token': 'test-token',
  'nickname': '张伟',
  'username': 'admin',
  'title': '运维工程师',
  'op': true,
  'opsManager': true,
});

/// 跳过真实登录流程，直接注入已登录状态。
class FakeAuthenticatedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      AuthState(status: AuthStatus.authenticated, user: demoTestUser);
}

/// 构建带 ProviderScope 的 App；[authenticated] 为 false 时走真实鉴权流程，
/// [demoData] 把数据源固定为演示数据（产品默认已改为真实后端）。
Widget buildTestApp({bool authenticated = true, bool demoData = true}) =>
    ProviderScope(
      retry: noAutoRetry,
      overrides: [
        if (demoData) useMockProvider.overrideWithValue(true),
        if (authenticated)
          authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
      ],
      child: const GreenCleanOpsApp(),
    );
