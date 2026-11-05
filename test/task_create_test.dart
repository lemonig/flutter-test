import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/features/home/data/repositories/task_write_repository.dart';
import 'package:green_clean_ops/features/home/presentation/create_task_page.dart';

Widget _wrap(Widget child, {List<StationOption>? stations}) => ProviderScope(
  overrides: [
    useMockProvider.overrideWithValue(true),
    managedStationsProvider.overrideWith(
      (Ref ref) async => stations ?? const <StationOption>[],
    ),
  ],
  child: MaterialApp(home: child),
);

void main() {
  group('CreateTaskDraft', () {
    test('提交字段与后端 TaskCreateValidator 对齐', () {
      final DateTime happen = DateTime(2026, 11, 5, 9, 30);
      final DateTime deadline = DateTime(2026, 11, 6, 18, 0);
      final CreateTaskDraft draft = CreateTaskDraft(
        stationId: 209,
        content: '  总氮故障值  ',
        happenAt: happen,
        deadline: deadline,
        remind: 3,
        pictureKeys: <String>['task/2026-11-05/a.jpg'],
      );

      final Map<String, Object?> json = draft.toJson();

      expect(json['stationId'], 209);
      // 后端存的是原文，前后空格由客户端清掉，避免列表里出现视觉空行
      expect(json['content'], '总氮故障值');
      expect(json['gmt_happen'], happen.millisecondsSinceEpoch);
      expect(json['deadline'], deadline.millisecondsSinceEpoch);
      expect(json['remind'], 3);
      expect(json['picturesContent'], <String>['task/2026-11-05/a.jpg']);
    });

    test('无图片时传空数组而不是 null', () {
      final CreateTaskDraft draft = CreateTaskDraft(
        stationId: 1,
        content: 'x',
        happenAt: DateTime(2026),
        deadline: DateTime(2026, 2),
        remind: 0,
      );
      expect(draft.toJson()['picturesContent'], isEmpty);
    });
  });

  group('StationOption', () {
    test('解析后端精简站点', () {
      final StationOption? station = StationOption.tryParse(<String, Object?>{
        'id': 209,
        'name': '夜郎湖',
        'region': '贵州省',
        'city': '安顺市',
      });
      expect(station, isNotNull);
      expect(station!.id, 209);
      expect(station.name, '夜郎湖');
      expect(station.subtitle, '贵州省 · 安顺市');
    });

    test('id 为字符串时也能解析', () {
      expect(
        StationOption.tryParse(<String, Object?>{'id': '88', 'name': 'x'})?.id,
        88,
      );
    });

    test('缺少 id 返回 null，不抛异常', () {
      expect(StationOption.tryParse(<String, Object?>{'name': 'x'}), isNull);
      expect(StationOption.tryParse(null), isNull);
      expect(StationOption.tryParse('bad'), isNull);
    });
  });

  group('RemindOption', () {
    test('覆盖后端 RemindEnum 的 0~5', () {
      expect(RemindOption.all.map((RemindOption o) => o.value), <int>[0, 1, 2, 3, 4, 5]);
      expect(RemindOption.labelOf(0), '不提醒');
      expect(RemindOption.labelOf(5), '截止前 1 天');
    });

    test('未知值回落到第一项而不是抛错', () {
      expect(RemindOption.labelOf(99), '不提醒');
    });
  });

  group('新建异常页', () {
    testWidgets('不是任何站点数据管理员时给出可执行的提示', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const CreateTaskPage()));
      await tester.pumpAndSettle();

      expect(find.text('暂无可创建异常的站点'), findsOneWidget);
      expect(find.textContaining('数据管理员'), findsOneWidget);
      // 没有站点时提交按钮不可点，避免用户点了才被后端拒绝
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '提交异常'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('有站点时渲染完整表单', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const CreateTaskPage(),
          stations: const <StationOption>[
            StationOption(id: 209, name: '夜郎湖', region: '贵州省', city: '安顺市'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('发生站点'), findsOneWidget);
      expect(find.text('异常发生时间'), findsOneWidget);
      expect(find.text('截止时间'), findsOneWidget);
      expect(find.text('提醒'), findsOneWidget);
      expect(find.text('异常现象'), findsOneWidget);
      expect(find.text('现场照片'), findsOneWidget);
      expect(find.text('0/9'), findsWidgets);
      expect(find.text('暂无可创建异常的站点'), findsNothing);
    });

    testWidgets('未选站点直接提交会被拦下', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const CreateTaskPage(),
          stations: const <StationOption>[StationOption(id: 1, name: '测试站')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '提交异常'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('请选择发生站点'), findsOneWidget);
    });

    testWidgets('站点选择面板支持搜索过滤', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const CreateTaskPage(),
          stations: const <StationOption>[
            StationOption(id: 1, name: '夜郎湖'),
            StationOption(id: 2, name: '古新河'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('请选择'));
      await tester.pumpAndSettle();

      expect(find.text('选择发生站点'), findsOneWidget);
      expect(find.text('夜郎湖'), findsOneWidget);
      expect(find.text('古新河'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '古新');
      await tester.pumpAndSettle();

      expect(find.text('夜郎湖'), findsNothing);
      expect(find.text('古新河'), findsOneWidget);
    });
  });
}
