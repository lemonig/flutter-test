import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

import 'package:green_clean_ops/shared/widgets/filter_choice_chip.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(buildTestApp());
  await tester.pump();
  // 等待 mock 数据源返回（450ms）
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('底部导航栏展示 5 个 Tab', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('信息填报'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('首页展示标题、搜索框、三分类与任务卡片', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('运维工作台'), findsOneWidget);
    expect(find.text('搜索站点、任务、人员'), findsOneWidget);
    expect(find.text('异常'), findsOneWidget);
    expect(find.text('巡检'), findsOneWidget);
    expect(find.text('签到'), findsOneWidget);
    expect(find.textContaining('南湖水质自动监测站'), findsWidgets);
    expect(find.text('详情'), findsWidgets);
  });

  testWidgets('点击「巡检」切换到巡检分类', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('巡检'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.textContaining('日常巡检'), findsWidgets);
  });

  testWidgets('快捷筛选切换到「待处理」后重新拉取列表', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(FilterChoiceChip, '待处理'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('筛选 · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选面板可展开并应用', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(FilterChoiceChip, '筛选'));
    await tester.pumpAndSettle();

    expect(find.text('应用筛选'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);

    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('新建入口弹出异常与签到操作', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();

    expect(find.text('新建异常'), findsOneWidget);
    expect(find.text('新建签到'), findsOneWidget);
  });

  testWidgets('消息 Tab 展示未读汇总并可全部已读', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();

    expect(find.textContaining('条未读消息'), findsOneWidget);

    await tester.tap(find.text('全部已读').first);
    // 演示数据源每次请求有 220ms 延时，3 个未读分类 + 一次刷新，
    // 光 pumpAndSettle 不会推进这些无帧定时器，得显式推进时间。
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('消息已全部读完'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工作台 Tab 展示今日概览与功能宫格', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('工作台'));
    await tester.pumpAndSettle();

    expect(find.text('今日概览'), findsOneWidget);
    // M7 改造后首屏是「数据上报」组（里程 / 车辆费用 / 水电网费）。
    expect(find.text('里程上报'), findsOneWidget);
    expect(find.text('车辆费用'), findsOneWidget);
    expect(find.text('水电网费'), findsOneWidget);

    // 业务闭环组与资料卡在首屏之外，滚动后可见。
    // 一次拖到底（测试屏 600 高，列表总高约 1200）。
    await tester.drag(find.text('今日概览'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('运维知识库'), findsOneWidget);
  });

  testWidgets('信息填报 Tab 展示填报进度与帖子流', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('信息填报'));
    await tester.pumpAndSettle();

    expect(find.text('本周信息填报'), findsOneWidget);
    expect(find.textContaining('采水单元'), findsWidgets);
  });

  testWidgets('我的 Tab 展示个人资料与设置项', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('张伟'), findsOneWidget);
    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });
}
