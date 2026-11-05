import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/network/auth_bridge.dart';
import 'package:green_clean_ops/core/storage/app_storage.dart';
import 'package:green_clean_ops/features/auth/data/repositories/auth_repository.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';

void main() {
  late InMemoryKeyValueStore store;

  ProviderContainer createContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        appStorageProvider.overrideWith((Ref ref) => AppStorage(store)),
        authRepositoryProvider.overrideWith(
          (Ref ref) => const MockAuthRepository(delay: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<AuthState> loggedIn(ProviderContainer container) =>
      container.read(authProvider.future);

  setUp(() => store = InMemoryKeyValueStore());

  group('M1-02 登录与会话', () {
    test('冷启动无会话 → 未登录', () async {
      final ProviderContainer container = createContainer();
      expect((await loggedIn(container)).isAuthenticated, isFalse);
    });

    test('正确账号密码登录成功，token 与会话持久化', () async {
      final ProviderContainer container = createContainer();
      await loggedIn(container);

      await container
          .read(authProvider.notifier)
          .login(
            username: MockAuthRepository.demoUsername,
            password: MockAuthRepository.demoPassword,
            remember: true,
            agreementAccepted: true,
          );

      final AuthState state = await loggedIn(container);
      expect(state.isAuthenticated, isTrue);
      expect(state.user!.displayName, '张伟');
      expect(container.read(tokenHolderProvider).token, isNotEmpty);
      final StoredSession? session = await AppStorage(store).readSession();
      expect(session, isNotNull);
      expect(session!.token, isNotEmpty);
    });

    test('错误密码抛出业务异常且提示后端原文', () async {
      final ProviderContainer container = createContainer();
      await loggedIn(container);

      await expectLater(
        container
            .read(authProvider.notifier)
            .login(
              username: 'admin',
              password: 'wrong',
              remember: false,
              agreementAccepted: true,
            ),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('账号或密码错误'),
          ),
        ),
      );
      expect((await loggedIn(container)).isAuthenticated, isFalse);
    });

    test('未勾选协议时拒绝登录', () async {
      final ProviderContainer container = createContainer();
      await loggedIn(container);

      await expectLater(
        container
            .read(authProvider.notifier)
            .login(
              username: 'admin',
              password: MockAuthRepository.demoPassword,
              remember: false,
              agreementAccepted: false,
            ),
        throwsA(isA<Exception>()),
      );
      expect(container.read(authBusyProvider), isFalse);
    });

    test('退出登录清理 token 与本地会话', () async {
      final ProviderContainer container = createContainer();
      await loggedIn(container);
      await container
          .read(authProvider.notifier)
          .login(
            username: 'admin',
            password: MockAuthRepository.demoPassword,
            remember: false,
            agreementAccepted: true,
          );
      expect(container.read(tokenHolderProvider).token, isNotEmpty);

      await container.read(authProvider.notifier).logout();

      expect((await loggedIn(container)).isAuthenticated, isFalse);
      expect(container.read(tokenHolderProvider).token, isNull);
      expect(await AppStorage(store).readSession(), isNull);
    });

    test('新容器读取已有会话可自动恢复登录', () async {
      final ProviderContainer first = createContainer();
      await loggedIn(first);
      await first
          .read(authProvider.notifier)
          .login(
            username: 'admin',
            password: MockAuthRepository.demoPassword,
            remember: false,
            agreementAccepted: true,
          );

      final ProviderContainer second = createContainer();
      final AuthState restored = await loggedIn(second);
      expect(restored.isAuthenticated, isTrue);
      expect(second.read(tokenHolderProvider).token, isNotEmpty);
    });
  });

  group('M0-04 存储', () {
    test('筛选记忆可写入并读回', () async {
      final AppStorage storage = AppStorage(store);
      await storage.saveFilters('home.abnormal', <String, String>{'状态': '处理中'});
      expect(await storage.readFilters('home.abnormal'), <String, String>{
        '状态': '处理中',
      });
    });

    test('搜索历史最多保留 10 条', () async {
      final AppStorage storage = AppStorage(store);
      await storage.saveSearchHistory(
        List<String>.generate(20, (int i) => 'k$i'),
      );
      expect(await storage.readSearchHistory(), hasLength(10));
    });

    test('损坏的会话 JSON 不会导致崩溃', () async {
      await store.write('auth.session', '{bad json');
      expect(await AppStorage(store).readSession(), isNull);
    });
  });
}
