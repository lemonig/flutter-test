import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/router/app_router.dart';
import 'package:green_clean_ops/features/auth/data/models/app_user.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';

void main() {
  final AuthState loggedIn = AuthState(
    status: AuthStatus.authenticated,
    user: AppUser.fromJson(<String, Object?>{
      'id': '1',
      'token': 't',
      'nickname': '张伟',
      'op': true,
    }),
  );

  String? guard(AsyncValue<AuthState> auth, String location, {String? query}) =>
      authGuardFor(
        auth: auth,
        matchedLocation: location,
        uri: Uri.parse('$location${query == null ? '' : '?$query'}'),
      );

  group('M0-09 鉴权 redirect', () {
    test('鉴权初始化时经过启动页并保留原目标', () {
      final String? redirect = guard(const AsyncLoading<AuthState>(), '/home');
      expect(redirect, startsWith('/splash?from='));
      expect(Uri.parse(redirect!).queryParameters['from'], '/home');
      expect(guard(const AsyncLoading<AuthState>(), '/splash'), isNull);
    });

    test('深链直达：初始化 → 启动页 → 登录后回到原详情页', () {
      final String? step1 = guard(
        const AsyncLoading<AuthState>(),
        '/task/ab-1001',
      );
      expect(Uri.parse(step1!).queryParameters['from'], '/task/ab-1001');

      final String? step2 = guard(
        AsyncData<AuthState>(loggedIn),
        '/splash',
        query: step1.split('?').last,
      );
      expect(step2, '/task/ab-1001');
    });

    test('未登录时启动页携带的深链会继续传到登录页', () {
      final String? redirect = guard(
        const AsyncData<AuthState>(AuthState.unauthenticated),
        '/splash',
        query: 'from=%2Ftask%2Fab-1001',
      );
      expect(redirect, isNotNull);
      expect(Uri.parse(redirect!).queryParameters['from'], '/task/ab-1001');
    });

    test('未登录访问业务页 → 登录页并保留原地址', () {
      final String? redirect = guard(
        const AsyncData<AuthState>(AuthState.unauthenticated),
        '/task/ab-1001',
      );
      expect(redirect, isNotNull);
      expect(redirect, startsWith('/login?from='));
      expect(Uri.parse(redirect!).queryParameters['from'], '/task/ab-1001');
    });

    test('未登录访问启动页 → 登录页，不带回跳参数', () {
      expect(
        guard(const AsyncData<AuthState>(AuthState.unauthenticated), '/splash'),
        '/login',
      );
    });

    test('未登录停留在登录页不产生循环', () {
      expect(
        guard(const AsyncData<AuthState>(AuthState.unauthenticated), '/login'),
        isNull,
      );
    });

    test('登录后回跳到深链原页面', () {
      expect(
        guard(
          AsyncData<AuthState>(loggedIn),
          '/login',
          query: 'from=%2Ftask%2Fab-1001',
        ),
        '/task/ab-1001',
      );
    });

    test('已登录访问启动页 / 登录页 → 首页', () {
      expect(guard(AsyncData<AuthState>(loggedIn), '/splash'), '/home');
      expect(guard(AsyncData<AuthState>(loggedIn), '/login'), '/home');
    });

    test('已登录访问业务页不重定向', () {
      expect(guard(AsyncData<AuthState>(loggedIn), '/home'), isNull);
      expect(guard(AsyncData<AuthState>(loggedIn), '/task/ab-1'), isNull);
    });
  });

  group('M2-05 详情页路由', () {
    test('三类任务映射到各自的详情路径', () {
      expect(detailPathFor(TaskCategory.abnormal, 'ab-1'), '/task/ab-1');
      expect(
        detailPathFor(TaskCategory.inspection, 'in-2'),
        '/inspection/in-2',
      );
      expect(detailPathFor(TaskCategory.signIn, 'si-3'), '/attend/si-3');
    });
  });
}
