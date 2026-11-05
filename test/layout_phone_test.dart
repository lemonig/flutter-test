import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

import 'package:green_clean_ops/shared/widgets/filter_choice_chip.dart';

/// 手机尺寸（390x844）下的布局回归测试：
/// 覆盖五个 Tab、分类切换、筛选面板与列表滚动，确保无溢出异常。
void main() {
  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  testWidgets('首页在手机尺寸下无布局溢出', (WidgetTester tester) async {
    await pumpPhone(tester);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选面板展开与应用无异常', (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.tap(find.widgetWithText(FilterChoiceChip, '筛选'));
    await tester.pumpAndSettle();
    expect(find.text('应用筛选'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('左右滑动切换分类无异常', (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('消息 / 工作台 / 信息填报 / 我的 四个 Tab 均无溢出', (WidgetTester tester) async {
    await pumpPhone(tester);

    for (final String tab in <String>['消息', '工作台', '信息填报', '我的']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$tab 存在布局异常');
    }
  });
}
