import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_env.dart';
import 'core/network/retry_policy.dart';
import 'core/storage/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  if (kDebugMode) debugPrint('[ENV] ${AppEnv.debugSummary}');

  runApp(
    ProviderScope(
      // 关掉 Riverpod 3 的隐式重试，否则后端不可达时页面会永久停在骨架屏。
      retry: noAutoRetry,
      overrides: [
        appStorageProvider.overrideWith(
          (Ref ref) => AppStorage(SharedPreferencesStore(prefs)),
        ),
      ],
      child: const GreenCleanOpsApp(),
    ),
  );
}
