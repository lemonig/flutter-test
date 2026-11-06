import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/core/network/retry_policy.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/home_repository.dart';
import 'package:green_clean_ops/features/home/providers/home_providers.dart';
import 'package:green_clean_ops/features/home/providers/my_events_providers.dart';
import 'package:green_clean_ops/features/profile/presentation/my_events_page.dart';
import 'package:green_clean_ops/shared/widgets/filter_choice_chip.dart';

TaskItem _item(String id, String station, {List<String> tags = const <String>[]}) =>
    TaskItem(
      id: id,
      stationName: station,
      timeText: '今天 09:20',
      content: '现场情况说明',
      executor: '卜幸杰',
      tags: tags,
    );

class _FakeHomeRepository implements HomeRepository {

  @override
  Future<List<TaskItem>> fetchTasksByRegion({
    required TaskCategory category,
    required String regionKey,
    required String startDate,
    required String endDate,
    required int page,
    int pageSize = 10,
  }) async => const <TaskItem>[];

  @override
  Future<List<TaskItem>> search({
    required TaskCategory category,
    required String keyword,
    required int page,
    int pageSize = 10,
  }) async => const <TaskItem>[];


  _FakeHomeRepository({this.fail = false});

  bool fail;
  int calls = 0;
  Map<String, String>? lastFilters;
  Map<TaskCategory, List<TaskItem>> data = <TaskCategory, List<TaskItem>>{
    TaskCategory.abnormal: <TaskItem>[
      _item('101', '福达工业园', tags: const <String>['待处理']),
    ],
    TaskCategory.inspection: <TaskItem>[_item('202', '东风水库')],
    TaskCategory.signIn: <TaskItem>[_item('303', '南湖监测站', tags: const <String>['已签到'])],
  };

  @override
  bool? get lastResponseHasMore => null;

  @override
  Future<List<TaskItem>> fetchTasks({
    required TaskCategory category,
    required int page,
    required int pageSize,
    Map<String, String> filters = const <String, String>{},
  }) async {
    calls++;
    lastFilters = filters;
    if (fail) {
      throw const AppException('网络不可用', kind: ApiErrorKind.network);
    }
    return data[category] ?? const <TaskItem>[];
  }
}

Widget _wrap(_FakeHomeRepository repo) => ProviderScope(
  retry: noAutoRetry,
  overrides: [homeRepositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: MyEventsPage()),
);

void main() {
  group('我的事件', () {
    testWidgets('三个分类 Tab 齐全，默认展示异常记录', (WidgetTester tester) async {
      final _FakeHomeRepository repo = _FakeHomeRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('我的事件'), findsOneWidget);
      expect(find.text('异常'), findsOneWidget);
      expect(find.text('巡检'), findsOneWidget);
      expect(find.text('签到'), findsOneWidget);
      expect(find.text('福达工业园'), findsOneWidget);
      // 异常维度固定按「我处理的」取数
      expect(repo.lastFilters?['可见范围'], '我处理的');
      expect(repo.lastFilters?['任务状态'], '全部');
    });

    testWidgets('切换状态筛选会带上「我处理的」重新取数', (WidgetTester tester) async {
      final _FakeHomeRepository repo = _FakeHomeRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      final int before = repo.calls;
      // 卡片上的状态标签也叫「待处理」，必须限定在筛选 chip 上点
      await tester.tap(find.widgetWithText(FilterChoiceChip, '待处理'));
      await tester.pumpAndSettle();

      expect(repo.calls, greaterThan(before));
      expect(repo.lastFilters?['任务状态'], '待处理');
      expect(repo.lastFilters?['可见范围'], '我处理的');
    });

    testWidgets('签到 Tab 没有状态筛选，按「我的签到」取数', (WidgetTester tester) async {
      final _FakeHomeRepository repo = _FakeHomeRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('签到'));
      await tester.pumpAndSettle();

      expect(repo.lastFilters?['可见范围'], '我的签到');
      // 签到没有「任务状态」分组，筛选条不出现
      expect(find.text('处理中'), findsNothing);
      expect(find.text('南湖监测站'), findsOneWidget);
    });

    testWidgets('无数据时展示空态', (WidgetTester tester) async {
      final _FakeHomeRepository repo = _FakeHomeRepository();
      repo.data = <TaskCategory, List<TaskItem>>{};
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('暂无相关记录'), findsOneWidget);
    });

    testWidgets('加载失败给出重试入口', (WidgetTester tester) async {
      final _FakeHomeRepository repo = _FakeHomeRepository(fail: true);
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('异常记录加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    });
  });

  group('维度映射', () {
    test('三类任务的「我的」维度', () {
      expect(MyEventsNotifier.visibilityOf(TaskCategory.abnormal), '我处理的');
      expect(MyEventsNotifier.visibilityOf(TaskCategory.inspection), '我处理的');
      expect(MyEventsNotifier.visibilityOf(TaskCategory.signIn), '我的签到');
    });

    test('签到没有任务状态筛选项', () {
      expect(MyEventsNotifier.statusOptionsOf(TaskCategory.signIn), isEmpty);
      expect(
        MyEventsNotifier.statusOptionsOf(TaskCategory.abnormal),
        contains('待处理'),
      );
    });
  });
}
