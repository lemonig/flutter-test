import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_env.dart';
import 'api_client.dart';
import 'auth_bridge.dart';
import 'server_time.dart';

/// 数据源开关（M0-03）。
///
/// 编译期默认值来自 `--dart-define=USE_MOCK`，但提升成 Provider 后，
/// 测试可以覆盖成演示数据而不必依赖构建参数 —— 产品默认连真实后端，
/// 单测仍然零网络。
final Provider<bool> useMockProvider = Provider<bool>(
  (Ref ref) => AppEnv.useMock,
);

/// 全局唯一的 ApiClient。token 通过 [TokenHolder] 同步读取，
/// 因此登录/登出无需重建网络层，也不会形成 Provider 循环依赖。
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final TokenHolder holder = ref.watch(tokenHolderProvider);
  final ServerTime serverTime = ref.watch(serverTimeProvider);
  return ApiClient(tokenReader: () => holder.token, serverTime: serverTime);
});
