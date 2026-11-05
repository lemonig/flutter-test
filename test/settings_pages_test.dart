import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/cache/app_cache_service.dart';
import 'package:green_clean_ops/features/profile/presentation/about_page.dart';
import 'package:green_clean_ops/features/profile/presentation/help_feedback_page.dart';
import 'package:green_clean_ops/features/profile/presentation/privacy_policy_page.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatBytes', () {
    test('小于 1 KB 直接给字节', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('KB 区间：个位数保留一位小数，两位数取整', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(10 * 1024), '10 KB');
      expect(formatBytes(512 * 1024), '512 KB');
    });

    test('MB / GB 区间', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(
        formatBytes((12.3 * 1024 * 1024).round()),
        '12.3 MB',
      );
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });

  group('LocalAppCacheService', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('cache_test_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('统计只算文件、跳过子目录本身', () async {
      File('${root.path}/a.txt').writeAsBytesSync(List<int>.filled(100, 1));
      Directory('${root.path}/sub').createSync();
      File(
        '${root.path}/sub/b.bin',
      ).writeAsBytesSync(List<int>.filled(250, 2));

      final LocalAppCacheService service = LocalAppCacheService(
        directories: <Directory>[root],
      );
      expect(await service.computeSize(), 350);
    });

    test('清理后目录还在、内容清空', () async {
      File('${root.path}/a.txt').writeAsBytesSync(List<int>.filled(10, 1));
      Directory('${root.path}/sub').createSync();
      File('${root.path}/sub/b.bin').writeAsBytesSync(List<int>.filled(10, 2));

      final LocalAppCacheService service = LocalAppCacheService(
        directories: <Directory>[root],
      );
      await service.clear();

      // 目录本身必须保留：某些插件会拿着这个路径继续写文件。
      expect(root.existsSync(), isTrue);
      expect(root.listSync(), isEmpty);
      expect(await service.computeSize(), 0);
    });

    test('目录不存在时返回 0 而不是抛异常', () async {
      final LocalAppCacheService service = LocalAppCacheService(
        directories: <Directory>[Directory('${root.path}/nope')],
      );
      expect(await service.computeSize(), 0);
      await service.clear();
    });
  });

  group('关于页', () {
    testWidgets('展示版本、环境、数据源与服务器地址', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const AboutPage()));
      await tester.pumpAndSettle();

      expect(find.text('绿洁运维'), findsOneWidget);
      expect(find.text('v1.0.0 (1)'), findsWidgets);
      expect(find.text('版本'), findsOneWidget);
      expect(find.text('环境'), findsOneWidget);
      expect(find.text('服务器'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('开源许可'), findsOneWidget);
    });

    testWidgets('非生产环境点检查更新只提示、不发请求', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const AboutPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('不检查线上版本'), findsOneWidget);
    });
  });

  group('隐私政策页', () {
    testWidgets('渲染章节与生效日期', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPolicyPage()));
      await tester.pumpAndSettle();

      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.textContaining('版本 v1.0'), findsOneWidget);
      expect(find.text('一、我们收集哪些信息'), findsOneWidget);
      // 定位只用于签到与巡检，这条是商店审核最容易挑的点，必须写明
      expect(find.textContaining('不做后台持续定位'), findsOneWidget);

      // 后半部分章节在首屏之外（ListView 懒构建），滚下去再断言
      final Finder permission = find.text('四、权限说明');
      await tester.scrollUntilVisible(
        permission,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      expect(permission, findsOneWidget);

      final Finder effective = find.textContaining('本政策自 2026-11-05 起生效');
      await tester.scrollUntilVisible(
        effective,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      expect(effective, findsOneWidget);
    });
  });

  group('帮助与反馈页', () {
    testWidgets('常见问题可展开', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const HelpFeedbackPage()));
      await tester.pumpAndSettle();

      expect(find.text('常见问题'), findsOneWidget);
      const String question = '签到提示「当前位置未处在签到站点」';
      expect(find.text(question), findsOneWidget);
      // 折叠时答案不可见
      expect(find.textContaining('走到站点范围内再签到'), findsNothing);

      await tester.tap(find.text(question));
      await tester.pumpAndSettle();
      expect(find.textContaining('走到站点范围内再签到'), findsOneWidget);
    });

    testWidgets('提供复制诊断信息入口', (WidgetTester tester) async {
      // 测试环境没有真实剪贴板，拦下 platform channel 让 Clipboard.setData 走成功分支
      final List<MethodCall> platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(_wrap(const HelpFeedbackPage()));
      await tester.pumpAndSettle();

      expect(find.text('复制诊断信息'), findsOneWidget);
      await tester.tap(find.text('复制诊断信息'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('诊断信息已复制'), findsOneWidget);
      final MethodCall copy = platformCalls.firstWhere(
        (MethodCall call) => call.method == 'Clipboard.setData',
      );
      expect(
        (copy.arguments as Map<Object?, Object?>)['text'],
        contains('诊断信息'),
      );
    });
  });
}
