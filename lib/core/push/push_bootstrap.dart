import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/models/app_user.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'push_service.dart';

/// 推送别名同步（M6-04）。
///
/// 职责只有三件：SDK 初始化、登录后绑别名、登出后解绑。
/// 放在 App 最外层而不是登录页，是因为**冷启动时 token 已恢复**，
/// 此时并没有「登录动作」，只能靠登录态变化来补绑定。
///
/// 别名规则与后端 `AppPushService.PREFIX` 对齐：`LJYW + userId`。
class PushBootstrap extends ConsumerStatefulWidget {
  const PushBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushBootstrap> createState() => _PushBootstrapState();
}

class _PushBootstrapState extends ConsumerState<PushBootstrap> {
  /// 当前已绑定的别名，避免重复绑/误解绑。
  String? _boundAlias;

  /// 防止并发：绑定是异步的，登录态快速切换时可能同时进来两次。
  bool _syncing = false;

  /// 通知权限每次启动最多问一次，避免反复弹窗骚扰。
  bool _permissionAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final PushService push = ref.read(pushServiceProvider);
      // 先初始化 SDK：不等登录，否则未登录期间的推送全部收不到
      await push.init();
      await _sync(ref.read(authProvider).value);
    });
  }

  Future<void> _sync(AuthState? auth) async {
    final PushService push = ref.read(pushServiceProvider);
    if (!push.isSupported) return;

    final AppUser? user = auth?.user;
    final String? desired = (auth?.isAuthenticated ?? false) && user != null
        ? pushAliasFor(user.id)
        : null;

    if (desired == _boundAlias || _syncing) return;

    _syncing = true;
    try {
      if (_boundAlias != null) {
        await push.unbindAlias(_boundAlias!);
        _boundAlias = null;
      }
      if (desired != null) {
        final bool ok = await push.bindAlias(desired);
        if (ok) {
          _boundAlias = desired;
          await _ensureNotificationPermission(push);
        }
      }
    } finally {
      _syncing = false;
    }
  }

  /// Android 13+ 不申请 POST_NOTIFICATIONS，通知会被系统静默丢弃。
  ///
  /// 时机选在「登录并绑定别名之后」：此时用户是真实使用者，
  /// 在启动页或登录前弹窗只会被随手拒绝。
  Future<void> _ensureNotificationPermission(PushService push) async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    if (await push.isNotificationPermissionGranted()) return;
    await push.requestNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    // 登录态变化时同步别名：登录 → 绑定，登出 → 解绑
    ref.listen<AsyncValue<AuthState>>(authProvider, (
      AsyncValue<AuthState>? previous,
      AsyncValue<AuthState> next,
    ) {
      _sync(next.value);
    });

    return widget.child;
  }
}
