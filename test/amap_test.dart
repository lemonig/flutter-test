import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/amap/amap_view.dart';
import 'package:green_clean_ops/core/amap/map_picker_page.dart';

void main() {
  group('AmapView', () {
    testWidgets('非 Android 平台不渲染原生地图，回调 onUnavailable 而不是崩', (
      WidgetTester tester,
    ) async {
      // 测试跑在宿主机（Windows/macOS），Platform.isAndroid 为 false，
      // 此时必须走降级分支 —— 否则 AndroidView 在非 Android 上会抛异常。
      bool unavailableCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmapView(
              onUnavailable: () => unavailableCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(unavailableCalled, isTrue);
      expect(find.byType(AndroidView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('MapPickerPage', () {
    testWidgets('渲染准星与坐标，点「使用此位置」返回结果', (
      WidgetTester tester,
    ) async {
      MapPickerResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<MapPickerResult>(
                      MaterialPageRoute<MapPickerResult>(
                        builder: (_) => const ProviderScope(
                          child: MapPickerPage(
                            initialLatitude: 30.2741,
                            initialLongitude: 120.1551,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 页面本身要能起来（即使地图降级）
      expect(find.text('选择位置'), findsOneWidget);
      expect(find.text('使用此位置'), findsOneWidget);
      expect(find.text('已选坐标'), findsOneWidget);

      await tester.tap(find.text('使用此位置'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.latitude, closeTo(30.2741, 0.0001));
      expect(result!.longitude, closeTo(120.1551, 0.0001));
    });

    testWidgets('未传坐标时不崩，仍可确认返回默认位置', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MapPickerPage())),
      );
      await tester.pumpAndSettle();

      // 不传坐标时会触发一次定位（测试环境拿不到定位，走失败分支）
      expect(find.text('使用此位置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
