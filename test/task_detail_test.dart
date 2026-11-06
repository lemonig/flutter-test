import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/features/home/data/models/task_activity.dart';
import 'package:green_clean_ops/features/home/data/models/task_detail.dart';
import 'package:green_clean_ops/features/home/data/models/task_process.dart';
import 'package:green_clean_ops/features/home/data/repositories/task_detail_repository.dart';
import 'package:green_clean_ops/features/home/presentation/abnormal_detail_page.dart';

/// 后端 `GET task/{id}` 的真实响应（取自 192.168.188.66:1601）。
Map<String, Object?> get _payload => <String, Object?>{
  'id': 68081,
  'gmt_create': '2026-11-05T08:38:32.000+0800',
  'station': <String, Object?>{
    'id': 1919,
    'name': '小兴闸',
    'regionTitle': '江苏省',
    'cityTitle': '连云港市',
    'districtTitle': '灌云县',
  },
  'content': '质控氨氮跨度漂移不合格',
  'state': 3,
  'executor': <String, Object?>{'id': 925, 'nickname': '张子龙'},
  'creator': <String, Object?>{'id': 834, 'nickname': '胡华鑫'},
  'stationManager': <String, Object?>{'id': 925, 'nickname': '张子龙'},
  'deadline': '2026-11-05T20:00:00.000+0800',
  'gmt_happen': '2026-11-05T00:00:00.000+0800',
  'gmt_solved': '2026-11-05T09:10:00.000+0800',
  'remind': 4,
  'overtime': false,
  'timeUsageSolved': '32分钟',
  'errorUnit': 'CODcr分析仪GR-2116、采水单元',
  'reason': '标液过期',
  'solution': '重新配置标液',
  'hadArrivedStationStr': '到站提交',
  'contentPictures': <Object?>[
    <String, Object?>{'url': 'https://cdn/a.jpg', 'title': '异常描述'},
  ],
  'submitPictures': <Object?>[
    <String, Object?>{'url': 'https://cdn/b.jpg', 'title': '处理前'},
    <String, Object?>{'url': 'https://cdn/c.jpg', 'title': '处理后'},
  ],
  'auth': <String, Object?>{
    'enableToSubmit': false,
    'enableToTerminate': false,
    'enableToConfirm': true,
  },
  'isArrived': true,
  'jobNumber': 'YC012026110568081',
};

TaskDetail get _detail => TaskDetail.fromJson(_payload);

class _FakeRepo implements TaskDetailRepository {
  _FakeRepo(this.detail);

  TaskDetail detail;
  final List<String> calls = <String>[];

  @override
  Future<TaskDetail> fetchDetail(String id) async => detail;

  @override
  Future<List<TaskLogEntry>> fetchLog(String id) async => <TaskLogEntry>[
    TaskLogEntry(
      id: 1,
      content: '创建了故障',
      stateLabel: '待处理',
      time: '2026-11-05T08:38:33.000+0800',
      user: const TaskPerson(nickname: '胡华鑫'),
    ),
  ];

  @override
  Future<List<TaskReader>> fetchReaders(String id) async => <TaskReader>[
    const TaskReader(
      userId: 834,
      person: TaskPerson(nickname: '胡华鑫'),
      time: '2026-11-05T08:39:13.000+0800',
    ),
  ];

  @override
  Future<List<TaskComment>> fetchComments(String id) async =>
      const <TaskComment>[];

  @override
  Future<List<TaskComment>> fetchLikes(String id) async =>
      const <TaskComment>[];

  @override
  Future<void> addComment(String id, String content) async {}

  @override
  Future<void> toggleLike(String id) async {}

  @override
  Future<ErrorUnitCatalog> fetchErrorUnits(String id) async =>
      const ErrorUnitCatalog();

  @override
  Future<void> submitProcess(ProcessDraft draft) async {
    calls.add('submit:${draft.outcome.name}');
  }

  @override
  Future<void> saveDraft(ProcessDraft draft) async => calls.add('draft');

  @override
  Future<void> confirm(String id) async => calls.add('confirm:$id');

  @override
  Future<void> reject(String id, String description) async =>
      calls.add('reject:$description');

  @override
  Future<void> terminate(String id, String description) async =>
      calls.add('terminate:$description');

  @override
  Future<void> transfer(String id, int toUserId, {bool force = false}) async =>
      calls.add('transfer:$id:$toUserId');
}

Widget _wrap(TaskDetailRepository repo, {String taskId = '68081'}) =>
    ProviderScope(
      overrides: [
        useMockProvider.overrideWithValue(true),
        taskDetailRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: AbnormalDetailPage(taskId: taskId)),
    );

void main() {
  group('TaskDetail 解析', () {
    test('对齐后端 TaskDetailItemVO 字段', () {
      final TaskDetail detail = _detail;

      expect(detail.id, 68081);
      expect(detail.jobNumber, 'YC012026110568081');
      expect(detail.state, TaskState.fixed);
      expect(detail.stationName, '小兴闸');
      expect(detail.regionText, '江苏省 连云港市 灌云县');
      expect(detail.executor?.nickname, '张子龙');
      expect(detail.creator?.nickname, '胡华鑫');
      expect(detail.overtime, isFalse);
      expect(detail.timeUsageSolved, '32分钟');
      expect(detail.errorUnit, 'CODcr分析仪GR-2116、采水单元');
      expect(detail.contentPictures.single.title, '异常描述');
      expect(detail.auth.enableToConfirm, isTrue);
      expect(detail.auth.enableToSubmit, isFalse);
      expect(detail.hadArrivedStationStr, '到站提交');
    });

    test('处理照片按 title 分组', () {
      final Map<String, List<TaskPhoto>> grouped = _detail.submitPicturesByTitle;

      expect(grouped.keys, containsAll(<String>['处理前', '处理后']));
      expect(grouped['处理前']!.single.url, 'https://cdn/b.jpg');
    });

    test('缺字段时不抛异常并给出空值兜底', () {
      final TaskDetail empty = TaskDetail.fromJson(<String, Object?>{});

      expect(empty.state, TaskState.unknown);
      expect(empty.stationName, '');
      expect(empty.contentPictures, isEmpty);
      expect(empty.auth.hasAny, isFalse);
    });

    test('TaskState 覆盖后端 1~7 全部状态', () {
      expect(TaskState.fromCode(1), TaskState.todo);
      expect(TaskState.fromCode(2), TaskState.doing);
      expect(TaskState.fromCode(3), TaskState.fixed);
      expect(TaskState.fromCode(4), TaskState.notError);
      expect(TaskState.fromCode(5), TaskState.confirmed);
      expect(TaskState.fromCode(6), TaskState.rejected);
      expect(TaskState.fromCode(7), TaskState.terminated);
      // 后端用字符串回传时也要能解
      expect(TaskState.fromCode('2'), TaskState.doing);
    });

    test('状态分组决定主按钮与可操作性', () {
      expect(TaskState.todo.isOpen, isTrue);
      expect(TaskState.doing.isOpen, isTrue);
      expect(TaskState.fixed.isSubmitted, isTrue);
      expect(TaskState.notError.isSubmitted, isTrue);
      expect(TaskState.confirmed.isTerminal, isTrue);
      expect(TaskState.terminated.isTerminal, isTrue);
    });
  });

  group('ProcessDraft 校验', () {
    ProcessDraft draft({
      String reason = '原因',
      String solution = '办法',
      List<int> units = const <int>[1],
      bool arrived = true,
      Map<ProcessPhotoSlot, List<String>> photos =
          const <ProcessPhotoSlot, List<String>>{},
    }) => ProcessDraft(
      taskId: 1,
      outcome: ProcessOutcome.fixed,
      reason: reason,
      solution: solution,
      unitIds: units,
      photos: photos,
      isArrived: arrived,
    );

    test('原因与解决办法必填', () {
      expect(draft(reason: ' ').validate(), '请填写故障原因');
      expect(draft(solution: '').validate(), '请填写解决办法');
    });

    test('异常单元与仪器至少选一个', () {
      expect(
        draft(units: const <int>[]).validate(),
        '请至少选择一个异常单元或异常仪器',
      );
    });

    test('到站提交要求六类照片中的五项必传', () {
      final String? error = draft().validate();
      expect(error, '请上传「处理前」照片');
    });

    test('离站提交只需处理前与处理后', () {
      final ProcessDraft value = draft(
        arrived: false,
        photos: <ProcessPhotoSlot, List<String>>{
          ProcessPhotoSlot.before: <String>['k1'],
          ProcessPhotoSlot.after: <String>['k2'],
        },
      );
      expect(value.validate(), isNull);
    });

    test('到站提交必须补齐处理中 / 站房卫生 / 取水口 / 运维记录', () {
      final ProcessDraft value = draft(
        photos: <ProcessPhotoSlot, List<String>>{
          ProcessPhotoSlot.before: <String>['k1'],
          ProcessPhotoSlot.after: <String>['k2'],
        },
      );
      expect(value.validate(), '请上传「处理中」照片');
    });

    test('提交字段与后端 TaskSubmitValidator 一一对应', () {
      final ProcessDraft value = draft(
        photos: <ProcessPhotoSlot, List<String>>{
          ProcessPhotoSlot.before: <String>['before-key'],
          ProcessPhotoSlot.after: <String>['after-key'],
        },
      );
      final Map<String, Object?> json = value.toJson();

      expect(json['id'], 1);
      expect(json['errorUnitList'], <int>[1]);
      // 缺省字段不出现，避免后端把 null 当作显式清空
      expect(json.containsKey('instrumentList'), isTrue);
      expect(json['picturesBefore'], <String>['before-key']);
      expect(json['picturesAfter'], <String>['after-key']);
      expect(json.containsKey('picturesProcessing'), isFalse);
      expect(value.outcome.endpoint, 'task/submit/fixed');
      expect(ProcessOutcome.notError.endpoint, 'task/submit/noterror');
    });
  });

  group('异常详情页', () {
    testWidgets('渲染真实详情并给出确认入口', (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo(_detail);
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('小兴闸'), findsOneWidget);
      expect(find.text('已修复'), findsWidgets);
      expect(find.text('YC012026110568081'), findsOneWidget);
      expect(find.text('CODcr分析仪GR-2116、采水单元'), findsOneWidget);
      expect(find.text('审核处理结果'), findsOneWidget);

      // 处理进度在首屏之外，ListView 懒加载需要滚到可视区才会构建。
      await tester.scrollUntilVisible(
        find.text('创建了故障'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('创建了故障'), findsOneWidget);
    });

    testWidgets('处理权限账号看到「处理任务」并能进入处理页', (WidgetTester tester) async {
      final TaskDetail submitable = TaskDetail.fromJson(<String, Object?>{
        ..._payload,
        'state': 2,
        'auth': <String, Object?>{'enableToSubmit': true},
      });
      await tester.pumpWidget(_wrap(_FakeRepo(submitable)));
      await tester.pumpAndSettle();

      expect(find.text('处理任务'), findsOneWidget);
      await tester.tap(find.text('处理任务'));
      await tester.pumpAndSettle();

      expect(find.text('处理异常'), findsOneWidget);
      expect(find.text('提交处理'), findsOneWidget);
      expect(find.text('存草稿'), findsOneWidget);
    });

    testWidgets('确认通过会调用 confirm 接口', (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo(_detail);
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('审核处理结果'));
      await tester.pumpAndSettle();
      expect(find.text('确认通过'), findsOneWidget);
      expect(find.text('拒绝修复'), findsOneWidget);

      await tester.tap(find.text('确认通过'));
      await tester.pumpAndSettle();
      expect(find.text('确认关闭异常？'), findsOneWidget);

      await tester.tap(find.text('确认关闭'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('confirm:68081'));

      // 确认后会刷新首页列表，把演示仓储的延时计时器跑完，避免测试残留 pending timer。
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('已关闭任务的按钮置灰并说明原因', (WidgetTester tester) async {
      final TaskDetail closed = TaskDetail.fromJson(<String, Object?>{
        ..._payload,
        'state': 5,
        'auth': <String, Object?>{},
      });
      await tester.pumpWidget(_wrap(_FakeRepo(closed)));
      await tester.pumpAndSettle();

      expect(find.text('已关闭，无需操作'), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '已关闭，无需操作'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('加载失败给出重试入口', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(_FailingRepo()));
      await tester.pumpAndSettle();

      expect(find.text('异常详情加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    });
  });
}

class _FailingRepo extends _FakeRepo {
  _FailingRepo() : super(_detail);

  @override
  Future<TaskDetail> fetchDetail(String id) async => throw Exception('boom');
}
