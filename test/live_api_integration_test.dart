import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/network/api_client.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/features/auth/data/repositories/auth_repository.dart';
import 'package:green_clean_ops/features/home/data/models/filter_group.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/meta_repository.dart';
import 'package:green_clean_ops/features/home/data/repositories/remote_home_repository.dart';

/// 真实后端联调（只读 + 一次正常登录，不产生业务写操作）。
///
/// 基础用例（无需账号）：
/// ```bash
/// flutter test --dart-define=RUN_LIVE_TESTS=true test/live_api_integration_test.dart
/// ```
/// 完整端到端（凭据走环境变量，不写进代码/命令行历史）：
/// ```bash
/// LIVE_USERNAME=<账号> LIVE_PASSWORD=<密码> \
///   flutter test --dart-define=RUN_LIVE_TESTS=true test/live_api_integration_test.dart
/// ```
/// 默认全部跳过，后端不可达时不影响日常 `flutter test`。
const bool _runLive = bool.fromEnvironment('RUN_LIVE_TESTS');
const String _baseUrl = String.fromEnvironment(
  'LIVE_BASE_URL',
  defaultValue: 'http://192.168.188.66:1601/api/',
);

final String? _username = Platform.environment['LIVE_USERNAME'];
final String? _password = Platform.environment['LIVE_PASSWORD'];

String? _liveSkip({required bool needCredentials}) {
  if (!_runLive) return '需 RUN_LIVE_TESTS=true';
  if (needCredentials && (_username == null || _password == null)) {
    return '需 LIVE_USERNAME / LIVE_PASSWORD 环境变量';
  }
  return null;
}

ApiClient _client({String? Function()? tokenReader}) => ApiClient(
  dio: Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  ),
  tokenReader: tokenReader,
  enableLog: false,
);

void main() {
  test('登录参数错误 → 业务异常，保留后端原文', () async {
    final ApiClient api = _client();
    await expectLater(
      api.postRaw(
        'login',
        data: const <String, Object?>{'username': '', 'password': ''},
      ),
      throwsA(
        isA<AppException>().having(
          (AppException e) => e.userMessage,
          'message',
          '账户或密码不能为空',
        ),
      ),
    );
  }, skip: _liveSkip(needCredentials: false));

  test('无 token 访问 meta/basic → UNAUTHENTICATED 触发登出回调', () async {
    final ApiClient api = _client();
    int logoutCalls = 0;
    api.onUnauthenticated = () => logoutCalls++;
    await expectLater(api.getRaw('meta/basic'), throwsA(isA<AppException>()));
    expect(logoutCalls, 1);
  }, skip: _liveSkip(needCredentials: false));

  test('无 token 请求 task/timeline → 统一 401 且不重试死循环', () async {
    final ApiClient api = _client();
    await expectLater(
      api.postRaw(
        'task/timeline',
        data: const <String, Object?>{
          'startPage': 1,
          'limit': 10,
          'condition1': '1',
          'condition2': '1',
          'condition3': '1',
          'condition4': '1',
        },
      ),
      throwsA(
        isA<AppException>().having(
          (AppException e) => e.isUnauthenticated,
          'unauthenticated',
          isTrue,
        ),
      ),
    );
  }, skip: _liveSkip(needCredentials: false));

  test(
    '端到端：登录 → 动态筛选元数据 → 三类列表 → 详情 → 筛选 → 未读数',
    () async {
      String? token;
      final ApiClient api = _client(tokenReader: () => token);

      // 1. 登录（走真实 RemoteAuthRepository，验证 SimpleUser 解析）
      final RemoteAuthRepository auth = RemoteAuthRepository(api);
      final user = await auth.login(username: _username!, password: _password!);
      expect(user.token, isNotEmpty);
      expect(user.displayName, isNotEmpty);
      expect(user.permissions, isNotEmpty);
      token = user.token;

      // 2. meta/basic 动态条件（省份 value 应为行政区划码）
      final Map<TaskCategory, List<FilterGroup>> groups = await MetaRepository(
        api,
      ).fetchFilterGroups();
      expect(groups[TaskCategory.abnormal]!.length, 4);
      expect(groups[TaskCategory.inspection]!.length, 3);
      expect(groups[TaskCategory.signIn]!.length, 2);
      final FilterGroup region = groups[TaskCategory.abnormal]!.firstWhere(
        (FilterGroup g) => g.title == '所属省份',
      );
      expect(region.options.length, greaterThan(1));
      expect(region.valueOf('浙江省'), isNot('1'));

      // 3. 三类 timeline（真实数据，验证字段映射）
      final RemoteHomeRepository home = RemoteHomeRepository(api);
      String? firstTaskId;
      for (final TaskCategory category in TaskCategory.values) {
        final List<TaskItem> items = await home.fetchTasks(
          category: category,
          page: 1,
          pageSize: 3,
        );
        expect(items, isNotEmpty, reason: '${category.label} 应有真实数据');
        for (final TaskItem item in items) {
          expect(item.id, isNotEmpty);
          expect(item.stationName, isNotEmpty);
          expect(item.content, isNotEmpty);
          expect(item.timeText, isNotEmpty);
        }
        if (category == TaskCategory.abnormal) {
          firstTaskId = items.first.id;
        }
      }

      // 4. 详情 GET（异常详情图片字段是 contentPictures）
      final ApiResponse detail = await api.getRaw('task/$firstTaskId');
      expect(detail.success, isTrue);
      expect(detail.mapData['id'].toString(), firstTaskId);

      // 5. 状态筛选真实生效：只取「待处理」(condition2=2)
      final Map<String, Object?> filteredBody =
          RemoteHomeRepository.buildTimelineBody(
            category: TaskCategory.abnormal,
            page: 1,
            pageSize: 3,
            filters: const <String, String>{'任务状态': '待处理'},
            groups: groups[TaskCategory.abnormal],
          );
      expect(filteredBody['condition2'], '2');
      final ApiResponse filtered = await api.postRaw(
        'task/timeline',
        data: filteredBody,
      );
      expect(filtered.success, isTrue);
      for (final Object? row in filtered.listData) {
        if (row is Map) {
          expect(row['state'], 1, reason: '待处理筛选应只返回 state=1');
        }
      }

      // 6. 服务端未读数
      final ApiResponse unread = await api.postRaw('message/count_unread');
      expect(unread.success, isTrue);
      expect(unread.data, isA<int>());
    },
    skip: _liveSkip(needCredentials: true),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
