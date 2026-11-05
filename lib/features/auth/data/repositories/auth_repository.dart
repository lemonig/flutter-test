import '../../../../core/config/app_env.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';

/// 版本更新信息（M1-06）。
class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.downloadUrl,
    this.force = false,
    this.notes = '',
  });

  final String version;
  final String downloadUrl;
  final bool force;
  final String notes;
}

abstract class AuthRepository {
  Future<AppUser> login({required String username, required String password});

  /// 静默续期 / 刷新用户资料（原工程 `meta/auth`）。
  Future<AppUser> fetchProfile({required String fallbackToken});

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<void> logout();

  Future<AppVersionInfo?> checkVersion();
}

/// 真实后端实现，接口见 `docs/接口契约.md`。
class RemoteAuthRepository implements AuthRepository {
  const RemoteAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<AppUser> login({required String username, required String password}) =>
      _api.postMapped<AppUser>(
        'login',
        data: <String, Object?>{'username': username, 'password': password},
        map: (ApiResponse response) => AppUser.fromJson(response.mapData),
      );

  @override
  Future<AppUser> fetchProfile({required String fallbackToken}) =>
      _api.getMapped<AppUser>(
        'meta/auth',
        map: (ApiResponse response) {
          final Map<String, Object?> data = response.mapData;
          // 原工程：meta/auth 不返回 token，需用本地旧 token 回填。
          return AppUser.fromJson(<String, Object?>{
            ...data,
            'token': data['token'] ?? fallbackToken,
          });
        },
      );

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) => _api.postMapped<void>(
    'user/update_pwd',
    data: <String, Object?>{
      'old_password': oldPassword,
      'new_password1': newPassword,
      'new_password2': newPassword,
    },
    map: (ApiResponse _) {},
  );

  @override
  Future<void> logout() async {
    try {
      await _api.postRaw('logout');
    } on Object {
      // 原工程 logout 超时仅 3 秒，失败不阻塞本地清理。
    }
  }

  @override
  Future<AppVersionInfo?> checkVersion() async {
    final String? versionUrl = AppEnv.versionCheckUrl;
    if (versionUrl == null) return null;
    try {
      // 版本检查是绝对地址，单独起一个 Dio 请求绕过 baseUrl。
      final dynamic response = await _api.raw.get<dynamic>(
        versionUrl,
        queryParameters: <String, Object?>{'key': AppEnv.versionKey},
      );
      final ApiResponse parsed = ApiResponse.parse(response.data);
      if (!parsed.success || parsed.data is! Map) return null;
      final Map<Object?, Object?> map = Map<Object?, Object?>.from(
        parsed.data! as Map,
      );
      final String version = map['version']?.toString() ?? '';
      if (version.isEmpty) return null;
      return AppVersionInfo(
        version: version,
        downloadUrl:
            map['url']?.toString() ?? map['downloadUrl']?.toString() ?? '',
        force: map['force'] == true || map['force'] == 1,
        notes: map['notes']?.toString() ?? map['description']?.toString() ?? '',
      );
    } on Object {
      return null;
    }
  }
}

/// 演示数据源（默认启用）：`admin / 123456`。
class MockAuthRepository implements AuthRepository {
  const MockAuthRepository({this.delay = const Duration(milliseconds: 500)});

  final Duration delay;

  static const String demoUsername = 'admin';
  static const String demoPassword = '123456';

  @override
  Future<AppUser> login({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(delay);
    if (password != demoPassword || username.trim().isEmpty) {
      throw const AppException(
        '账号或密码错误，请重新输入',
        kind: ApiErrorKind.business,
        code: 'BAD_CREDENTIALS',
      );
    }
    return _demoUser(username.trim());
  }

  @override
  Future<AppUser> fetchProfile({required String fallbackToken}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _demoUser(demoUsername, token: fallbackToken);
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await Future<void>.delayed(delay);
    if (oldPassword != demoPassword) {
      throw const AppException(
        '原密码不正确',
        kind: ApiErrorKind.business,
        code: 'BAD_OLD_PASSWORD',
      );
    }
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AppVersionInfo?> checkVersion() async => null;

  static AppUser _demoUser(String username, {String? token}) =>
      AppUser.fromJson(<String, Object?>{
        'id': '1001',
        'token': token ?? 'mock-token-${username.hashCode}',
        'nickname': '张伟',
        'username': username,
        'title': '运维工程师',
        'mobile': '138****6621',
        'op': true,
        'opsManager': true,
      });
}

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return const MockAuthRepository();
      return RemoteAuthRepository(ref.watch(apiClientProvider));
    });
