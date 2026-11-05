import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 网络层与鉴权层之间的解耦桥。
///
/// `ApiClient` 不能反向依赖 `authProvider`（会形成 Provider 循环），
/// 因此 token 通过一个同步可读的持有者传递；鉴权模块在登录/登出时更新它。
class TokenHolder {
  String? token;
}

final Provider<TokenHolder> tokenHolderProvider = Provider<TokenHolder>(
  (Ref ref) => TokenHolder(),
);
