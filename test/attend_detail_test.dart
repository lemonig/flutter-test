import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/features/home/data/models/attend_detail.dart';
import 'package:green_clean_ops/features/home/data/models/task_activity.dart';
import 'package:green_clean_ops/features/home/data/models/task_detail.dart';
import 'package:green_clean_ops/features/home/data/repositories/attend_detail_repository.dart';
import 'package:green_clean_ops/features/home/presentation/attend_detail_page.dart';

import 'helpers/test_app.dart';

class _FakeAttendDetailRepository implements AttendDetailRepository {
  _FakeAttendDetailRepository({this.detail, this.failWith});

  AttendDetail? detail;
  AppException? failWith;

  List<TaskComment> comments = <TaskComment>[];
  List<TaskComment> likes = <TaskComment>[];
  int toggleCalls = 0;
  String? lastComment;

  @override
  Future<AttendDetail> fetchDetail(String id) async {
    if (failWith != null) throw failWith!;
    return detail ?? AttendDetail(id: id);
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) async => comments;

  @override
  Future<List<TaskComment>> fetchLikes(String id) async => likes;

  @override
  Future<void> addComment(String id, String content) async {
    lastComment = content;
    comments = <TaskComment>[
      TaskComment(id: 99, content: content, person: const TaskPerson(nickname: '张伟')),
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
}

const AttendDetail _demoDetail = AttendDetail(
  id: '54981',
  jobNumber: 'QD202611050001',
  address: '浙江省杭州市拱墅区康景路 88 号',
  description: '现场设备运行正常，巡检完成。',
  longitude: 120.16,
  latitude: 30.37,
  time: '2026-11-05T12:36:48.000+0800',
  person: TaskPerson(id: 16, nickname: '卜幸杰', avatar: ''),
  stationId: 665,
  stationName: '福达工业园',
);

Widget _wrap(String id, _FakeAttendDetailRepository repo) => ProviderScope(
  overrides: [
    useMockProvider.overrideWithValue(true),
    authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
    attendDetailRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(home: AttendDetailPage(attendId: id)),
);

void main() {
  group('AttendDetail.fromJson', () {
    test('解析真实 AttendVO 结构', () {
      final AttendDetail detail = AttendDetail.fromJson(<String, Object?>{
        'id': 54981,
        'jobNumber': 'QD202611050001',
        'address': '浙江省杭州市拱墅区康景路 88 号',
        'description': '客户端联调测试',
        'coordinate1': 120.16,
        'coordinate2': 30.37,
        'gmt_create': '2026-11-05T12:36:48.000+0800',
        'user': <String, Object?>{'id': 16, 'nickname': '卜幸杰', 'avatar': ''},
        'station': <String, Object?>{'id': 665, 'name': '福达工业园'},
        'pictures': <Object?>[
          <String, Object?>{
            'picture': 'check/20261105/a.png',
            'url': 'https://grean-ops.oss-cn-hangzhou.aliyuncs.com/check/a.png',
            'title': null,
          },
        ],
      });

      expect(detail.id, '54981');
      expect(detail.jobNumber, 'QD202611050001');
      expect(detail.personName, '卜幸杰');
      expect(detail.stationName, '福达工业园');
      expect(detail.hasCoordinate, isTrue);
      expect(detail.coordinateLabel, '120.160000, 30.370000');
      expect(detail.pictures.single.url, contains('grean-ops.oss'));
      // gmt_create 是后端已按 +0800 输出的字面时间，不能被设备时区二次换算
      expect(detail.timeText, contains('12:36'));
    });

    test('坐标写成字符串、缺站点时也能解析', () {
      final AttendDetail detail = AttendDetail.fromJson(<String, Object?>{
        'id': '7',
        'coordinate1': '120.16',
        'coordinate2': '30.37',
      });

      expect(detail.longitude, 120.16);
      expect(detail.latitude, 30.37);
      expect(detail.stationName, isEmpty);
      expect(detail.personName, '未知用户');
    });

    test('缺坐标时 hasCoordinate 为 false', () {
      expect(AttendDetail.fromJson(<String, Object?>{'id': 1}).hasCoordinate, isFalse);
      expect(AttendDetail.fromJson(null).coordinateLabel, '未记录');
    });
  });

  group('签到详情页', () {
    testWidgets('渲染站点、单号、地址、坐标与备注', (WidgetTester tester) async {
      final _FakeAttendDetailRepository repo = _FakeAttendDetailRepository(
        detail: _demoDetail,
      );
      await tester.pumpWidget(_wrap('54981', repo));
      await tester.pumpAndSettle();

      expect(find.text('签到详情'), findsOneWidget);
      expect(find.text('福达工业园'), findsWidgets);
      expect(find.text('已签到'), findsOneWidget);
      expect(find.text('QD202611050001'), findsOneWidget);
      expect(find.textContaining('康景路'), findsOneWidget);
      expect(find.textContaining('经度 120.160000'), findsOneWidget);
      expect(find.text('现场设备运行正常，巡检完成。'), findsOneWidget);
      expect(find.text('还没有评论，点这里说点什么'), findsOneWidget);
    });

    testWidgets('无站点无备注时给出占位文案', (WidgetTester tester) async {
      final _FakeAttendDetailRepository repo = _FakeAttendDetailRepository(
        detail: const AttendDetail(id: '3', address: '', description: ''),
      );
      await tester.pumpWidget(_wrap('3', repo));
      await tester.pumpAndSettle();

      expect(find.text('未关联站点'), findsOneWidget);
      expect(find.text('未获取到地址'), findsOneWidget);
      expect(find.text('未记录坐标'), findsOneWidget);
      // 备注为空时不渲染备注卡片
      expect(find.text('备注'), findsNothing);
    });

    testWidgets('点赞按钮走切换接口并刷新计数', (WidgetTester tester) async {
      final _FakeAttendDetailRepository repo = _FakeAttendDetailRepository(
        detail: _demoDetail,
      );
      await tester.pumpWidget(_wrap('54981', repo));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.thumbsUp));
      await tester.pumpAndSettle();

      expect(repo.toggleCalls, 1);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('评论面板可发布评论', (WidgetTester tester) async {
      final _FakeAttendDetailRepository repo = _FakeAttendDetailRepository(
        detail: _demoDetail,
      );
      await tester.pumpWidget(_wrap('54981', repo));
      await tester.pumpAndSettle();

      // 底栏评论按钮常驻可见，比点首屏外的卡片更稳
      await tester.tap(find.byIcon(LucideIcons.messageCircle));
      await tester.pumpAndSettle();

      expect(find.text('评论'), findsWidgets);
      await tester.enterText(find.byType(TextField).last, '现场确认完毕');
      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pumpAndSettle();

      expect(repo.lastComment, '现场确认完毕');
    });

    testWidgets('加载失败给出重试入口', (WidgetTester tester) async {
      final _FakeAttendDetailRepository repo = _FakeAttendDetailRepository(
        failWith: const AppException('签到记录不存在', kind: ApiErrorKind.business),
      );
      await tester.pumpWidget(_wrap('404', repo));
      await tester.pumpAndSettle();

      expect(find.text('签到详情加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    });
  });
}
