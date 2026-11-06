import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_client.dart';
import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/features/home/data/models/task_detail.dart';
import 'package:green_clean_ops/features/home/data/models/task_process.dart';
import 'package:green_clean_ops/features/home/data/models/task_activity.dart';
import 'package:green_clean_ops/features/home/data/repositories/ops_user_repository.dart';
import 'package:green_clean_ops/features/home/data/repositories/task_detail_repository.dart';
import 'package:green_clean_ops/features/home/presentation/widgets/transfer_sheet.dart';

import 'helpers/test_app.dart';

/// C7 委派任务：候选人接口、转交请求体、Mock 副作用与弹层交互。
void main() {
  group('OpsUser 解析', () {
    test('对齐后端 SimpleUser 返回列', () {
      final OpsUser user = OpsUser.fromJson(<String, Object?>{
        'id': 16,
        'nickname': '卜幸杰',
        'pinyin': 'buxingjie',
        'jianpin': 'bxj',
        'firstchar': 'B',
      });
      expect(user.id, 16);
      expect(user.nickname, '卜幸杰');
      expect(user.pinyin, 'buxingjie');
      expect(user.jianpin, 'bxj');
      expect(user.firstChar, 'B');
    });

    test('id 为字符串时也能解析', () {
      final OpsUser user = OpsUser.fromJson(<String, Object?>{
        'id': '925',
        'nickname': '张子龙',
      });
      expect(user.id, 925);
      expect(user.firstChar, isEmpty);
    });

    test('非 Map 数据抛解析异常', () {
      expect(() => OpsUser.fromJson('bad'), throwsA(isA<AppException>()));
    });
  });

  group('Mock 候选人列表', () {
    test('keyword 匹配昵称 / 拼音 / 简拼，并按首字母排序', () async {
      final MockOpsUserRepository repo = MockOpsUserRepository(
        delay: Duration.zero,
      );

      final List<OpsUser> all = await repo.fetchOpsUsers();
      expect(all, hasLength(5));
      // 服务端 order by firstchar：首字母非降序。
      for (int i = 1; i < all.length; i++) {
        expect(
          all[i].firstChar.compareTo(all[i - 1].firstChar),
          isNonNegative,
        );
      }

      final List<OpsUser> byNickname = await repo.fetchOpsUsers(keyword: '李');
      expect(byNickname.single.nickname, '李娜');

      final List<OpsUser> byPinyin = await repo.fetchOpsUsers(keyword: 'wang');
      expect(byPinyin.single.nickname, '王强');

      final List<OpsUser> byJianpin = await repo.fetchOpsUsers(keyword: 'Zm');
      expect(byJianpin.single.nickname, '赵敏');

      expect(await repo.fetchOpsUsers(keyword: '不存在的'), isEmpty);
    });
  });

  group('Mock 转交副作用', () {
    test('待处理任务转交后进入转交冻结并写入日志', () async {
      final MockTaskDetailRepository repo = MockTaskDetailRepository();

      // ab-1002 在演示列表里是「待处理」。
      final TaskDetail before = await repo.fetchDetail('ab-1002');
      expect(before.state, TaskState.todo);
      expect(before.auth.enableToSubmit, isTrue);

      await repo.transfer('ab-1002', 2); // 李娜

      final TaskDetail after = await repo.fetchDetail('ab-1002');
      // 接收人接受前双方都不能处理（taskNotInTransferFrozen = false）。
      expect(after.auth.hasAny, isFalse);

      final List<TaskLogEntry> logs = await repo.fetchLog('ab-1002');
      expect(logs.first.content, '转交任务给李娜，待接受');
    });

    test('非待处理任务转交抛业务异常', () async {
      final MockTaskDetailRepository repo = MockTaskDetailRepository();

      // ab-1003 在演示列表里是「已修复」。
      await expectLater(
        repo.transfer('ab-1003', 2),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.userMessage,
            'message',
            '仅待处理的任务可以转交',
          ),
        ),
      );
    });
  });

  group('Remote 请求体', () {
    test('POST task/transfer 对齐 JobTransferLog 必要字段', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/'));
      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                captured = options;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object?>{'success': true, 'data': null},
                  ),
                );
              },
        ),
      );
      final ApiClient api = ApiClient(
        dio: dio,
        tokenReader: () => 'real-token',
        enableLog: false,
      );

      await RemoteTaskDetailRepository(api).transfer('68081', 925);

      expect(captured!.uri.path, endsWith('/task/transfer'));
      expect(captured!.data, <String, Object?>{
        'jobId': 68081,
        'toUserId': 925,
        'force': false,
      });
    });

    test('POST user/ops/list 携带 keyword 并解析 SimpleUser 列表', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/'));
      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                captured = options;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object?>{
                      'success': true,
                      'data': <Object?>[
                        <String, Object?>{
                          'id': 25,
                          'nickname': '赵亮',
                          'pinyin': 'zhaoliang',
                          'jianpin': 'zl',
                          'firstchar': 'Z',
                        },
                      ],
                    },
                  ),
                );
              },
        ),
      );
      final ApiClient api = ApiClient(
        dio: dio,
        tokenReader: () => 'real-token',
        enableLog: false,
      );

      final List<OpsUser> users = await RemoteOpsUserRepository(
        api,
      ).fetchOpsUsers(keyword: 'zl');

      expect(captured!.uri.path, endsWith('/user/ops/list'));
      expect(captured!.data, <String, Object?>{'keyword': 'zl'});
      expect(users.single.nickname, '赵亮');
    });
  });

  group('转交弹层', () {
    final TaskDetail task = const TaskDetail(
      id: 123,
      state: TaskState.todo,
      content: '采水单元压力异常',
      stationName: '小兴闸',
    );

    late _RecordingRepo repo;

    Widget wrap() => ProviderScope(
      overrides: [
        useMockProvider.overrideWithValue(true),
        authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
        taskDetailRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Consumer(
          builder:
              (
                BuildContext context,
                WidgetRef ref,
                _,
              ) => Scaffold(
                body: FilledButton(
                  onPressed: () => showTransferSheet(
                    context,
                    ref: ref,
                    task: task,
                  ),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    );

    setUp(() => repo = _RecordingRepo());

    testWidgets('展示候选人、排除自己并支持搜索', (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 演示账号张伟（1001）不出现。
      expect(find.text('张伟'), findsNothing);
      expect(find.text('李娜'), findsOneWidget);
      expect(find.text('陈刚'), findsOneWidget);
      expect(find.textContaining('小兴闸'), findsOneWidget);

      // 搜索走 family 参数切换：新条目先 loading，timer 到期后再 build 一帧
      // 才显示 data，所以每次输入后要推进两帧。
      await tester.enterText(find.byType(TextField), 'wang');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('王强'), findsOneWidget);
      expect(find.text('李娜'), findsNothing);

      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('没有匹配的运维人员'), findsOneWidget);
    });

    testWidgets('点选 → 确认 → 调用转交并提示', (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('王强'));
      await tester.pump();
      expect(find.text('转交给 王强？'), findsOneWidget);

      await tester.tap(find.text('确认转交'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(repo.calls, <String>['transfer:123:3']);
      expect(find.text('已转交给王强，等待对方接受'), findsOneWidget);
    });

    testWidgets('确认框取消时不发请求', (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('李娜'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(seconds: 1));

      expect(repo.calls, isEmpty);
    });
  });
}

/// 记录转交调用的假仓库；弹层只用得到 transfer。
class _RecordingRepo implements TaskDetailRepository {
  final List<String> calls = <String>[];

  @override
  Future<TaskDetail> fetchDetail(String id) async =>
      const TaskDetail(id: 123, state: TaskState.todo, content: '');

  @override
  Future<List<TaskLogEntry>> fetchLog(String id) async => const <TaskLogEntry>[];

  @override
  Future<List<TaskReader>> fetchReaders(String id) async =>
      const <TaskReader>[];

  @override
  Future<List<TaskComment>> fetchComments(String id) async =>
      const <TaskComment>[];

  @override
  Future<List<TaskComment>> fetchLikes(String id) async => const <TaskComment>[];

  @override
  Future<void> addComment(String id, String content) async {}

  @override
  Future<void> toggleLike(String id) async {}

  @override
  Future<ErrorUnitCatalog> fetchErrorUnits(String id) async =>
      const ErrorUnitCatalog();

  @override
  Future<void> submitProcess(ProcessDraft draft) async {}

  @override
  Future<void> saveDraft(ProcessDraft draft) async {}

  @override
  Future<void> confirm(String id) async {}

  @override
  Future<void> reject(String id, String description) async {}

  @override
  Future<void> terminate(String id, String description) async {}

  @override
  Future<void> transfer(String id, int toUserId, {bool force = false}) async {
    calls.add('transfer:$id:$toUserId');
  }
}
