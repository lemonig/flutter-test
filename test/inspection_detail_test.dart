import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/core/network/retry_policy.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/features/home/data/models/ops_detail.dart';
import 'package:green_clean_ops/features/home/data/models/task_activity.dart';
import 'package:green_clean_ops/features/home/data/models/task_detail.dart';
import 'package:green_clean_ops/features/home/data/repositories/ops_detail_repository.dart';
import 'package:green_clean_ops/features/home/presentation/inspection_detail_page.dart';
import 'package:green_clean_ops/features/home/presentation/submit_inspection_page.dart';

import 'helpers/test_app.dart';

class _FakeOpsRepository implements OpsDetailRepository {
  _FakeOpsRepository({this.detail, this.failWith, this.onSite = true});

  OpsDetail? detail;
  AppException? failWith;
  bool onSite;

  List<TaskComment> comments = <TaskComment>[];
  List<TaskComment> likes = <TaskComment>[];
  int toggleCalls = 0;
  int submitCalls = 0;
  int checkCalls = 0;
  String? lastTerminateReason;
  OpsSubmitDraft? lastDraft;

  @override
  Future<OpsDetail> fetchDetail(String id) async {
    if (failWith != null) throw failWith!;
    return detail ?? OpsDetail(id: id);
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) async => comments;

  @override
  Future<List<TaskComment>> fetchLikes(String id) async => likes;

  @override
  Future<void> addComment(String id, String content) async {
    comments = <TaskComment>[
      TaskComment(
        id: 99,
        content: content,
        person: const TaskPerson(nickname: '张伟'),
      ),
      ...comments,
    ];
  }

  @override
  Future<void> toggleLike(String id) async {
    toggleCalls++;
    likes = likes.isEmpty
        ? <TaskComment>[
            const TaskComment(
              id: 1,
              content: '',
              creatorId: 1001,
              person: TaskPerson(nickname: '张伟'),
            ),
          ]
        : <TaskComment>[];
  }

  @override
  Future<OpsSiteCheck> checkBeforeSubmit(
    String id, {
    required double longitude,
    required double latitude,
  }) async {
    checkCalls++;
    return OpsSiteCheck(
      onSite: onSite,
      message: onSite ? '' : '请在站房内提交巡检任务',
    );
  }

  @override
  Future<void> submit(String id, OpsSubmitDraft draft) async {
    submitCalls++;
    lastDraft = draft;
  }

  @override
  Future<void> terminate(String id, String reason) async {
    lastTerminateReason = reason;
  }
}

const OpsDetail _editableDetail = OpsDetail(
  id: '12495900',
  jobNumber: 'XJ202611010001',
  stationId: 9001,
  stationName: '测试-老虎潭水库',
  stationAddress: '浙江省湖州市吴兴区老虎潭水库',
  longitude: 120.022264,
  latitude: 30.285378,
  executor: TaskPerson(id: 16, nickname: '卜幸杰'),
  stationManager: TaskPerson(id: 771, nickname: '严正'),
  gmtCreate: '2026-05-29T15:43:11.000+0800',
  deadline: '2026-12-05T19:00:00.000+0800',
  itemSize: 3,
  auth: OpsAuth(canSubmit: true, canTerminate: true, canTransfer: true),
  items: <OpsItemDetail>[
    OpsItemDetail(
      id: 1,
      category: '采配水单元',
      name: '沉淀池清洗',
      requirePhoto: true,
    ),
    OpsItemDetail(
      id: 2,
      category: '分析单元',
      name: '检查试剂及纯水量',
      description: '试剂量充足',
      requirePhoto: true,
      photos: <TaskPhoto>[
        TaskPhoto(url: 'https://grean-ops.oss-cn-hangzhou.aliyuncs.com/ops/a.jpg'),
      ],
      pictureKeys: <String>['ops/a.jpg'],
    ),
    OpsItemDetail(id: 3, category: '其他', name: '站房卫生'),
  ],
);

Widget _wrapDetail(String id, _FakeOpsRepository repo) => ProviderScope(
  retry: noAutoRetry,
  overrides: [
    useMockProvider.overrideWithValue(true),
    authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
    opsDetailRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(home: InspectionDetailPage(recordId: id)),
);

Widget _wrapSubmit(String id, _FakeOpsRepository repo) => ProviderScope(
  retry: noAutoRetry,
  overrides: [
    useMockProvider.overrideWithValue(true),
    authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
    opsDetailRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(home: SubmitInspectionPage(recordId: id)),
);

void main() {
  group('OpsDetail.fromJson', () {
    test('解析真实巡检详情结构', () {
      final OpsDetail detail = OpsDetail.fromJson(<String, Object?>{
        'id': 12495900,
        'station': <String, Object?>{
          'id': 9001,
          'name': '测试-老虎潭水库',
          'address': '浙江省湖州市吴兴区',
          'coordinate1': 120.022264,
          'coordinate2': 30.285378,
        },
        'executor': <String, Object?>{'id': 16, 'nickname': '卜幸杰'},
        'stationManager': <String, Object?>{'id': 771, 'nickname': '严正'},
        'gmt_create': '2026-05-29T15:43:11.000+0800',
        'deadline': '2026-12-05T19:00:00.000+0800',
        'itemSize': 2,
        'opsTaskDone': false,
        'overtime': false,
        'terminated': false,
        'auth': <String, Object?>{
          'enableToSubmit': true,
          'enableToTerminate': false,
          'enableToTransfer': false,
          'enableToForceTransfer': false,
        },
        'opsDetailList': <Object?>[
          <String, Object?>{
            'id': 1557468,
            'category': '其他',
            'opsItemName': '采样器',
            'requirePhoto': false,
          },
          <String, Object?>{
            'id': 1557469,
            'category': '采配水单元',
            'opsItemName': '沉淀池清洗',
            'requirePhoto': true,
            'picturesPreview': <Object?>[
              <String, Object?>{
                'picture': 'ops/2026/a.jpg',
                'url': 'https://grean-ops.oss-cn-hangzhou.aliyuncs.com/ops/a.jpg',
              },
            ],
          },
        ],
      });

      expect(detail.id, '12495900');
      expect(detail.stationName, '测试-老虎潭水库');
      expect(detail.executorName, '卜幸杰');
      expect(detail.stationManagerName, '严正');
      expect(detail.items, hasLength(2));
      expect(detail.auth.canSubmit, isTrue);
      expect(detail.auth.canTerminate, isFalse);
      expect(detail.statusText, '未完成');
      expect(detail.doneCount, 1);
      // 图片既要有直链展示，也要留住 objectKey 供重新提交
      expect(detail.items[1].photos.single.url, contains('grean-ops.oss'));
      expect(detail.items[1].pictureKeys.single, 'ops/2026/a.jpg');
    });

    test('分组时「其他」固定排最后', () {
      final OpsDetail detail = OpsDetail.fromJson(<String, Object?>{
        'opsDetailList': <Object?>[
          <String, Object?>{'id': 1, 'category': '其他', 'opsItemName': '卫生'},
          <String, Object?>{'id': 2, 'category': '分析单元', 'opsItemName': '校准'},
          <String, Object?>{'id': 3, 'category': '采配水单元', 'opsItemName': '清洗'},
        ],
      });

      expect(
        detail.groups.map((OpsGroup g) => g.category).toList(),
        <String>['分析单元', '采配水单元', '其他'],
      );
    });

    test('状态优先级：终止 > 过期 > 完成', () {
      const OpsDetail base = OpsDetail(id: '1');
      expect(
        const OpsDetail(id: '1', done: true, terminated: true).statusText,
        '已终止',
      );
      expect(const OpsDetail(id: '1', done: true, overtime: true).statusText, '已过期');
      expect(const OpsDetail(id: '1', done: true).statusText, '已完成');
      expect(base.statusText, '未完成');
    });

    test('备注图片兼容裸 objectKey 数组', () {
      final ParsedPhotos parsed = OpsDetail.parsePhotos(<Object?>[
        'ops/2026/x.jpg',
        <String, Object?>{'picture': 'ops/2026/y.jpg', 'url': null},
        <String, Object?>{},
      ]);

      expect(parsed.photos, hasLength(2));
      expect(parsed.photos.first.url, startsWith('https://grean-ops.oss'));
      expect(parsed.keys, <String>['ops/2026/x.jpg', 'ops/2026/y.jpg']);
    });

    test('缺 id 的巡检项直接跳过', () {
      final OpsDetail detail = OpsDetail.fromJson(<String, Object?>{
        'opsDetailList': <Object?>[
          <String, Object?>{'category': '其他'},
          <String, Object?>{'id': 9, 'opsItemName': '有效项'},
        ],
      });
      expect(detail.items.single.id, 9);
    });
  });

  group('OpsSubmitDraft', () {
    test('id 转数字、备注去空格、保留已有图片 key', () {
      final Map<String, Object?> json = const OpsSubmitDraft(
        items: <OpsSubmitItem>[
          OpsSubmitItem(
            id: 1557469,
            description: '  已清洗  ',
            pictures: <String>['ops/a.jpg', 'ops/new.jpg'],
          ),
        ],
        description: '  整体正常  ',
        pictures: <String>['ops/note.jpg'],
      ).toJson('12495900');

      expect(json['id'], 12495900);
      expect(json['description'], '整体正常');
      expect(json['pictures'], <String>['ops/note.jpg']);
      final List<Object?> itemList = json['itemList']! as List<Object?>;
      final Map<Object?, Object?> first = itemList.single! as Map<Object?, Object?>;
      expect(first['id'], 1557469);
      expect(first['description'], '已清洗');
      expect(first['pictures'], <String>['ops/a.jpg', 'ops/new.jpg']);
    });
  });

  group('巡检详情页', () {
    testWidgets('渲染站点、编号、状态与巡检项', (WidgetTester tester) async {
      final _FakeOpsRepository repo = _FakeOpsRepository(detail: _editableDetail);
      await tester.pumpWidget(_wrapDetail('12495900', repo));
      await tester.pumpAndSettle();

      expect(find.text('巡检详情'), findsOneWidget);
      expect(find.text('测试-老虎潭水库'), findsOneWidget);
      expect(find.text('XJ202611010001'), findsOneWidget);
      expect(find.text('未完成'), findsWidgets);
      expect(find.text('已完成 1/3'), findsOneWidget);
      expect(find.text('沉淀池清洗'), findsOneWidget);
      expect(find.text('检查试剂及纯水量'), findsOneWidget);
      expect(find.text('试剂量充足'), findsOneWidget);
      // 分组标题顺序由 OpsDetail.groups 单测覆盖，这里只验证首屏可见的
      expect(find.text('采配水单元'), findsOneWidget);
    });

    testWidgets('可填报时底栏给「填报巡检」', (WidgetTester tester) async {
      final _FakeOpsRepository repo = _FakeOpsRepository(detail: _editableDetail);
      await tester.pumpWidget(_wrapDetail('12495900', repo));
      await tester.pumpAndSettle();

      expect(find.text('填报巡检'), findsOneWidget);
      // 可操作时右上角才有「更多」菜单
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    });

    testWidgets('无权限时只给复制编号', (WidgetTester tester) async {
      final _FakeOpsRepository repo = _FakeOpsRepository(
        detail: const OpsDetail(
          id: '1',
          stationName: '某站',
          done: true,
          itemSize: 2,
        ),
      );
      await tester.pumpWidget(_wrapDetail('1', repo));
      await tester.pumpAndSettle();

      expect(find.text('填报巡检'), findsNothing);
      expect(find.text('已完成 · 复制编号'), findsOneWidget);
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);
    });

    testWidgets('点赞按钮走切换接口并刷新计数', (WidgetTester tester) async {
      final _FakeOpsRepository repo = _FakeOpsRepository(detail: _editableDetail);
      await tester.pumpWidget(_wrapDetail('12495900', repo));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.thumbsUp));
      await tester.pumpAndSettle();

      expect(repo.toggleCalls, 1);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('加载失败给出重试入口', (WidgetTester tester) async {
      final _FakeOpsRepository repo = _FakeOpsRepository(
        failWith: const AppException('巡检任务不存在', kind: ApiErrorKind.business),
      );
      await tester.pumpWidget(_wrapDetail('404', repo));
      await tester.pumpAndSettle();

      expect(find.text('巡检详情加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
      expect(repo.checkCalls, 0);
    });
  });

  group('巡检填报页', () {
    testWidgets('必传照片缺失时本地拦截', (WidgetTester tester) async {
      final _FakeOpsRepository repo = _FakeOpsRepository(detail: _editableDetail);
      await tester.pumpWidget(_wrapSubmit('12495900', repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('提交巡检'));
      await tester.pump();

      expect(find.textContaining('沉淀池清洗'), findsWidgets);
      expect(find.textContaining('需要上传照片'), findsOneWidget);
      expect(repo.submitCalls, 0);
      expect(repo.checkCalls, 0);
    });

    testWidgets('站房外提交被拦下且给出后端文案', (WidgetTester tester) async {
      // 两项都补上照片，避开本地照片校验，专门验证站内校验分支
      final _FakeOpsRepository repo = _FakeOpsRepository(
        detail: const OpsDetail(
          id: '12534276',
          stationName: '测试-老虎潭水库',
          auth: OpsAuth(canSubmit: true),
          items: <OpsItemDetail>[
            OpsItemDetail(
              id: 1952594,
              category: '分析单元',
              name: '检查试剂及纯水量',
              requirePhoto: false,
            ),
          ],
        ),
        onSite: false,
      );
      await tester.pumpWidget(_wrapSubmit('12534276', repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('提交巡检'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 开发包下站外提交会先给「使用调试坐标重试」的兜底对话框
      expect(find.text('不在站点范围内'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.checkCalls, 1);
      expect(repo.submitCalls, 0);
      expect(find.text('请在站房内提交巡检任务'), findsOneWidget);
    });

    testWidgets('只提交改动过的巡检项', (WidgetTester tester) async {
      // 用一组「不强制拍照」的项，避免被本地照片校验先拦下
      final _FakeOpsRepository repo = _FakeOpsRepository(
        detail: const OpsDetail(
          id: '12495900',
          stationName: '测试-老虎潭水库',
          auth: OpsAuth(canSubmit: true),
          items: <OpsItemDetail>[
            OpsItemDetail(id: 1, category: '分析单元', name: '检查试剂及纯水量'),
            OpsItemDetail(
              id: 2,
              category: '分析单元',
              name: '站房卫生',
              description: '已打扫',
            ),
          ],
        ),
      );
      await tester.pumpWidget(_wrapSubmit('12495900', repo));
      await tester.pumpAndSettle();

      // 第 2 个输入框是「站房卫生」的备注，改成别的内容
      await tester.enterText(find.byType(TextField).at(1), '已打扫并通风');
      await tester.pumpAndSettle();

      await tester.tap(find.text('提交巡检'));
      await tester.pumpAndSettle();

      expect(repo.submitCalls, 1);
      final OpsSubmitDraft draft = repo.lastDraft!;
      expect(draft.items, hasLength(1));
      expect(draft.items.single.id, 2);
      expect(draft.items.single.description, '已打扫并通风');
      expect(draft.items.single.pictures, isEmpty);
    });
  });
}
