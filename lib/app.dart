import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/push/push_bootstrap.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class GreenCleanOpsApp extends ConsumerWidget {
  const GreenCleanOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

    // PushBootstrap 只是无 UI 的副作用挂载点（初始化 SDK + 同步别名），
    // 挂在 MaterialApp 外层，保证无论登录态怎么变都能收到。
    return PushBootstrap(
      child: MaterialApp.router(
        title: '绿洁运维',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
