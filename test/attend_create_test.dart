import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/features/home/data/models/attend_meta.dart';
import 'package:green_clean_ops/features/home/data/repositories/attend_write_repository.dart';
import 'package:green_clean_ops/features/home/data/repositories/home_repository.dart';
import 'package:green_clean_ops/features/home/presentation/create_attend_page.dart';
import 'package:green_clean_ops/features/home/providers/home_providers.dart';

/// 记录调用参数的假仓库：签到页的提交内容没有返回值可断言，
/// 只能靠它把 draft 截下来逐字段核对。
class _RecordingAttendRepository implements AttendWriteRepository {
  AttendDraft? lastDraft;
  List<double>? lastMetaPoint;
  int metaCalls = 0;
  List<StationDistance> stations =
      MockAttendWriteRepository.demoStations;

  @override
  Future<AttendMeta> fetchMeta({
    required double longitude,
    required double latitude,
  }) async {
    metaCalls++;
    lastMetaPoint = <double>[longitude, latitude];
    return AttendMeta(countToday: 2, stationsNearBy: stations);
  }

  @override
  Future<void> createAttend(AttendDraft draft) async {
    lastDraft = draft;
  }
}

/// 签到页会 `Navigator.pop`，宿主必须能提供一个真实的返回栈。
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const CreateAttendPage(),
          ),
        ),
        child: const Text('打开签到'),
      ),
    ),
  );
}

Widget _wrap(AttendWriteRepository repo) => ProviderScope(
  overrides: [
    useMockProvider.overrideWithValue(true),
    attendWriteRepositoryProvider.overrideWithValue(repo),
    // 提交成功后会刷新签到列表，默认演示仓库带 450ms 延时，这里去掉省测试时间
    homeRepositoryProvider.overrideWithValue(
      MockHomeRepository(delay: Duration.zero),
    ),
  ],
  child: const MaterialApp(home: _Host()),
);

Future<void> _openPage(WidgetTester tester) async {
  await tester.tap(find.text('打开签到'));
  await tester.pumpAndSettle();
}

void main() {
  group('AttendDraft', () {
    test('不选站点时不下发 stationId，文本前后空格清掉', () {
      final AttendDraft draft = AttendDraft(
        coordinate1: 120.16,
        coordinate2: 30.37,
        address: '  浙江省杭州市拱墅区  ',
        description: '  现场正常  ',
        pictureKeys: const <String>['check/2026-11-05/a.jpg'],
      );

      final Map<String, Object?> json = draft.toJson();

      expect(json.containsKey('stationId'), isFalse);
      expect(json['coordinate1'], 120.16);
      expect(json['coordinate2'], 30.37);
      expect(json['address'], '浙江省杭州市拱墅区');
      expect(json['description'], '现场正常');
      expect(json['pictures'], <String>['check/2026-11-05/a.jpg']);
    });

    test('选了站点时下发 stationId，无照片传空数组', () {
      final AttendDraft draft = AttendDraft(
        stationId: 665,
        coordinate1: 120.16,
        coordinate2: 30.37,
      );

      expect(draft.toJson()['stationId'], 665);
      expect(draft.toJson()['pictures'], isEmpty);
    });
  });

  group('AttendMeta', () {
    test('解析今日次数与附近站点，脏数据跳过而不抛错', () {
      final AttendMeta meta = AttendMeta.fromJson(<String, Object?>{
        'count': 3,
        'stationsNearBy': <Object?>[
          <String, Object?>{
            'id': 665,
            'name': '福达工业园',
            'distance': 58.268726394594545,
          },
          <String, Object?>{'id': '672', 'name': '青海湖站测试', 'distance': '70.9'},
          <String, Object?>{'name': '缺 id 的站点'},
          null,
        ],
      });

      expect(meta.countToday, 3);
      expect(meta.stationsNearBy.length, 2);
      expect(meta.stationsNearBy.first.name, '福达工业园');
      expect(meta.stationsNearBy.first.distanceLabel, '58.3 米');
      expect(meta.stationsNearBy[1].id, 672);
      expect(meta.stationsNearBy[1].distanceLabel, '70.9 米');
    });

    test('超过 1 公里改用公里展示', () {
      const StationDistance station = StationDistance(
        id: 2094,
        name: '杭州拱墅项目',
        distance: 1696.97,
      );
      expect(station.distanceLabel, '1.70 公里');
    });

    test('非 Map 输入退回空数据', () {
      expect(AttendMeta.fromJson(null).stationsNearBy, isEmpty);
      expect(AttendMeta.fromJson('bad').countToday, 0);
    });
  });

  group('新建签到页', () {
    testWidgets('演示坐标下自动定位并渲染完整表单', (WidgetTester tester) async {
      final _RecordingAttendRepository repo = _RecordingAttendRepository();
      await tester.pumpWidget(_wrap(repo));
      await _openPage(tester);

      expect(find.text('新建签到'), findsOneWidget);
      expect(find.text('当前位置'), findsOneWidget);
      expect(find.text('已定位'), findsOneWidget);
      expect(find.textContaining('120.160000'), findsOneWidget);
      expect(find.text('签到站点'), findsOneWidget);
      expect(find.text('今日已签到 2 次'), findsOneWidget);
      expect(find.text('备注'), findsOneWidget);
      expect(find.text('现场照片'), findsOneWidget);

      // 定位坐标要原样传给 attend/meta
      expect(repo.metaCalls, 1);
      expect(repo.lastMetaPoint, <double>[120.16, 30.37]);
    });

    testWidgets('未决定站点时提交按钮不可点', (WidgetTester tester) async {
      final _RecordingAttendRepository repo = _RecordingAttendRepository();
      await tester.pumpWidget(_wrap(repo));
      await _openPage(tester);

      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '提交签到'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('选中附近站点后回填名称与距离', (WidgetTester tester) async {
      final _RecordingAttendRepository repo = _RecordingAttendRepository();
      await tester.pumpWidget(_wrap(repo));
      await _openPage(tester);

      await tester.tap(find.text('请选择'));
      await tester.pumpAndSettle();
      expect(find.text('选择签到站点'), findsOneWidget);
      expect(find.text('距当前位置 18.4 米'), findsOneWidget);

      await tester.tap(find.text('演示站点·夜郎湖'));
      await tester.pumpAndSettle();

      expect(find.text('演示站点·夜郎湖 · 距 18.4 米'), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '提交签到'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('提交把地址、备注、坐标与站点一起下发', (WidgetTester tester) async {
      final _RecordingAttendRepository repo = _RecordingAttendRepository();
      await tester.pumpWidget(_wrap(repo));
      await _openPage(tester);

      await tester.tap(find.text('请选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('演示站点·夜郎湖'));
      await tester.pumpAndSettle();

      // 第一个输入框是位置，第二个是备注
      await tester.enterText(find.byType(TextField).first, '拱墅区康景路 88 号');
      await tester.enterText(find.byType(TextField).last, '现场设备运行正常');

      await tester.tap(find.widgetWithText(FilledButton, '提交签到'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final AttendDraft? draft = repo.lastDraft;
      expect(draft, isNotNull);
      expect(draft!.stationId, 9001);
      expect(draft.coordinate1, 120.16);
      expect(draft.coordinate2, 30.37);
      expect(draft.address, '拱墅区康景路 88 号');
      expect(draft.description, '现场设备运行正常');
      expect(draft.pictureKeys, isEmpty);
    });

    testWidgets('支持显式「不选择站点」，此时 stationId 为空', (WidgetTester tester) async {
      final _RecordingAttendRepository repo = _RecordingAttendRepository();
      await tester.pumpWidget(_wrap(repo));
      await _openPage(tester);

      await tester.tap(find.text('请选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不选择站点'));
      await tester.pumpAndSettle();

      expect(find.text('不选择站点'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '提交签到'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(repo.lastDraft, isNotNull);
      expect(repo.lastDraft!.stationId, isNull);
    });
  });
}
