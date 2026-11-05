import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/features/auth/data/repositories/auth_repository.dart';

import 'helpers/test_app.dart';

void main() {
  Future<void> pumpUnauthenticated(WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp(authenticated: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> fillCredentials(
    WidgetTester tester, {
    String password = MockAuthRepository.demoPassword,
  }) async {
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), MockAuthRepository.demoUsername);
    await tester.enterText(fields.at(1), password);
    await tester.pump();
  }

  testWidgets('未登录冷启动落到登录页', (WidgetTester tester) async {
    await pumpUnauthenticated(tester);

    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('绿洁运维'), findsOneWidget);
    expect(find.text('登 录'), findsOneWidget);
    expect(find.text('运维工作台'), findsNothing);
  });

  testWidgets('未勾选协议时拒绝登录并给出提示', (WidgetTester tester) async {
    await pumpUnauthenticated(tester);
    await fillCredentials(tester);

    await tester.tap(find.text('登 录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请先阅读并同意'), findsOneWidget);
    expect(find.text('运维工作台'), findsNothing);
  });

  testWidgets('错误密码显示后端原文提示', (WidgetTester tester) async {
    await pumpUnauthenticated(tester);
    await fillCredentials(tester, password: 'wrong-password');
    await tester.tap(find.byType(Checkbox).at(1)); // 协议勾选
    await tester.pump();

    await tester.tap(find.text('登 录'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.textContaining('账号或密码错误'), findsOneWidget);
  });

  testWidgets('正确账号登录成功后进入首页', (WidgetTester tester) async {
    await pumpUnauthenticated(tester);
    await fillCredentials(tester);
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();

    await tester.tap(find.text('登 录'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('运维工作台'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
