import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/auth_bridge.dart';
import '../../../core/storage/app_storage.dart';
import '../data/models/app_user.dart';
import '../data/repositories/auth_repository.dart';

enum AuthStatus { initializing, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.user, this.message});

  final AuthStatus status;
  final AppUser? user;
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  static const AuthState unauthenticated = AuthState(
    status: AuthStatus.unauthenticated,
  );

  AuthState copyWith({AuthStatus? status, AppUser? user, String? message}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        message: message,
      );
}

/// 登录按钮 loading 态。刻意不复用 `authProvider` 的 AsyncLoading，
/// 否则路由守卫会把登录过程误判为「启动中」而闪一次启动页。
final NotifierProvider<AuthBusyNotifier, bool> authBusyProvider =
    NotifierProvider<AuthBusyNotifier, bool>(AuthBusyNotifier.new);

class AuthBusyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final AsyncNotifierProvider<AuthNotifier, AuthState> authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthState> {
  bool _handlingUnauthorized = false;

  AuthRepository get _repository => ref.read(authRepositoryProvider);
  AppStorage get _storage => ref.read(appStorageProvider);

  @override
  Future<AuthState> build() async {
    // 把 401 / UNAUTHENTICATED 回调接到登出，解耦网络层与鉴权层。
    final ApiClient api = ref.read(apiClientProvider);
    api.onUnauthenticated = _handleUnauthorized;
    ref.onDispose(() {
      if (api.onUnauthenticated == _handleUnauthorized) {
        api.onUnauthenticated = null;
      }
    });

    final StoredSession? session = await _storage.readSession();
    if (session == null || session.token.isEmpty) {
      return AuthState.unauthenticated;
    }

    final AppUser? cached = AppUser.tryFromJsonString(session.userJson);
    if (cached == null) {
      await _storage.clearSession();
      return AuthState.unauthenticated;
    }

    // 环境切换后旧会话失效，避免出现「测试环境账号打到生产」。
    if (session.baseUrl.isNotEmpty && session.baseUrl != AppEnv.baseUrl) {
      await _storage.clearSession();
      return const AuthState(
        status: AuthStatus.unauthenticated,
        message: '运行环境已切换，请重新登录',
      );
    }

    ref.read(tokenHolderProvider).token = cached.token;

    // 静默续期：刷新用户资料；网络异常时保留本地会话，401 则强制登出。
    try {
      final AppUser fresh = await _repository.fetchProfile(
        fallbackToken: cached.token,
      );
      await _persist(fresh);
      return AuthState(status: AuthStatus.authenticated, user: fresh);
    } on AppException catch (error) {
      if (error.isUnauthenticated) {
        await _clearLocal();
        return const AuthState(
          status: AuthStatus.unauthenticated,
          message: '登录已过期，请重新登录',
        );
      }
      return AuthState(status: AuthStatus.authenticated, user: cached);
    } on Object {
      return AuthState(status: AuthStatus.authenticated, user: cached);
    }
  }

  Future<void> login({
    required String username,
    required String password,
    required bool remember,
    required bool agreementAccepted,
  }) async {
    if (!agreementAccepted) {
      throw const AppException('请先阅读并同意用户协议与隐私政策', kind: ApiErrorKind.business);
    }
    ref.read(authBusyProvider.notifier).set(true);
    try {
      final AppUser user = await _repository.login(
        username: username.trim(),
        password: password,
      );
      ref.read(tokenHolderProvider).token = user.token;
      await _persist(user);
      await _storage.saveRememberedUser(username.trim(), enabled: remember);
      await _storage.setAgreementAccepted(true);
      state = AsyncData<AuthState>(
        AuthState(status: AuthStatus.authenticated, user: user),
      );
    } finally {
      ref.read(authBusyProvider.notifier).set(false);
    }
  }

  /// M1-05：清理会话、token、未读角标相关缓存。
  Future<void> logout({String? reason}) async {
    try {
      await _repository.logout();
    } on Object {
      // 退出接口失败不阻塞本地清理。
    }
    await _clearLocal();
    state = AsyncData<AuthState>(
      AuthState(status: AuthStatus.unauthenticated, message: reason),
    );
  }

  Future<void> refreshProfile() async {
    final AppUser? current = state.value?.user;
    if (current == null) return;
    try {
      final AppUser fresh = await _repository.fetchProfile(
        fallbackToken: current.token,
      );
      await _persist(fresh);
      state = AsyncData<AuthState>(
        AuthState(status: AuthStatus.authenticated, user: fresh),
      );
    } on Object {
      // 刷新失败不改变当前登录态。
    }
  }

  /// M1-04：改密成功后强制重新登录。
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _repository.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    await logout(reason: '密码已修改，请重新登录');
  }

  Future<void> _persist(AppUser user) => _storage.saveSession(
    StoredSession(
      token: user.token,
      userJson: user.rawJson,
      baseUrl: AppEnv.baseUrl,
      savedAt: DateTime.now(),
    ),
  );

  Future<void> _clearLocal() async {
    ref.read(tokenHolderProvider).token = null;
    await _storage.clearSession();
  }

  void _handleUnauthorized() {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    Future<void>.microtask(() async {
      try {
        await logout(reason: '登录已过期，请重新登录');
      } finally {
        _handlingUnauthorized = false;
      }
    });
  }
}

/// M1-06：登录后检查版本；无新版本返回 null。
final FutureProvider<AppVersionInfo?> appVersionProvider =
    FutureProvider<AppVersionInfo?>((Ref ref) async {
      final AuthState auth = await ref.watch(authProvider.future);
      if (!auth.isAuthenticated) return null;
      return ref.watch(authRepositoryProvider).checkVersion();
    });
