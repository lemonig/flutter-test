import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_client.dart';
import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/features/workbench/data/models/workbench_models.dart';
import 'package:green_clean_ops/features/workbench/data/repositories/apply_repository.dart';
import 'package:green_clean_ops/features/workbench/data/repositories/directory_repository.dart';
import 'package:green_clean_ops/features/workbench/data/repositories/report_repository.dart';
import 'package:green_clean_ops/features/workbench/presentation/apply_record_pages.dart';
import 'package:green_clean_ops/features/workbench/presentation/apply_pages.dart';
import 'package:green_clean_ops/features/workbench/presentation/directory_pages.dart';
import 'package:green_clean_ops/features/workbench/presentation/stats_pages.dart';
import 'package:green_clean_ops/features/workbench/providers/workbench_providers.dart';

import 'helpers/test_app.dart';

/// 工作台（M7-02 ~ M7-10）：模型解析、仓库副作用、请求体与关键 UI 流程。
void main() {
  group('模型解析（对齐后端实测响应）', () {
    test('ReportRecord 解析里程上报详情', () {
      final ReportRecord record = ReportRecord.fromJson(<String, Object?>{
        'id': 110303,
        'description': '月度例行巡检往返',
        'pictures': <String>['https://oss/form/a.jpg'],
        'user': <String, Object?>{'id': 16, 'nickname': '卜幸杰'},
        'gmt_create': '2025-09-24T15:27:44.000+0800',
        'car_num': '云A770Q5',
        'car_id': 118,
        'mileage': 22237.0,
        'cost': 1.0,
        'contract_id': 258,
        'contract_num': '2021014YN',
        'stage': 1,
        'stage_str': '运维阶段',
        'report_number': 'SB2025',
      }, ReportKind.mileage);

      expect(record.id, 110303);
      expect(record.carNum, '云A770Q5');
      expect(record.mileage, 22237);
      expect(record.submitter?.nickname, '卜幸杰');
      expect(record.pictures, hasLength(1));
    });

    test('ApplyRecord 解析申请单与明细，状态文案优先用后端拼接', () {
      final ApplyRecord record = ApplyRecord.fromJson(<String, Object?>{
        'id': 934,
        'apply_type': 2,
        'apply_state': 1,
        'is_approved_str': '审批中',
        'apply_date': '2022-05-16T15:00:10.000+0800',
        'require_date': '2022-05-16',
        'approve_user_id': 16,
        'itemList': <Object?>[
          <String, Object?>{
            'item_id': 303,
            'item_name': '总磷试剂',
            'quantity': 1,
            'material_code': '700203000357',
          },
        ],
      });

      expect(record.type, ApplyType.reagent);
      expect(record.stateLabel, '审批中');
      expect(record.canApprove, isTrue);
      expect(record.items.single.itemName, '总磷试剂');
      expect(record.items.single.quantity, 1);
    });

    test('ApplyType / ApplyState 覆盖后端数字编码', () {
      expect(ApplyType.fromCode(1), ApplyType.part);
      expect(ApplyType.fromCode(2), ApplyType.reagent);
      expect(ApplyType.fromCode(3), ApplyType.fee);
      expect(ApplyType.fromCode(4), ApplyType.tool);
      expect(ApplyState.fromCode(5), ApplyState.withdrawn);
      expect(ApplyState.fromCode('3'), ApplyState.approved);
    });

    test('ReportDraft.toJson 按 kind 只带差异字段（PUT 报文）', () {
      final Map<String, Object?> mileage = ReportDraft(
        kind: ReportKind.mileage,
        carId: 118,
        carNum: '云A770Q5',
        mileage: 23000,
        cost: 90,
        feeType: null,
        money: null,
        stationId: null,
        station: '',
        payDate: '',
        nextPayDate: '',
        contractId: 258,
        stage: 1,
        description: ' 月度巡检 ',
        pictures: const <String>['form/a.jpg'],
      ).toJson();
      expect(mileage['car_id'], 118);
      expect(mileage['mileage'], 23000);
      expect(mileage.containsKey('money'), isFalse);
      expect(mileage['description'], '月度巡检');
      expect(mileage['pictures'], <String>['form/a.jpg']);

      final Map<String, Object?> stationFee = ReportDraft(
        kind: ReportKind.stationFee,
        carId: null,
        carNum: '',
        mileage: null,
        cost: null,
        feeType: 2,
        money: 412.8,
        stationId: 1919,
        station: '小兴闸',
        payDate: '2026-11-01',
        nextPayDate: '',
        contractId: null,
        stage: null,
        description: '',
        pictures: const <String>[],
      ).toJson();
      expect(stationFee['station_id'], 1919);
      expect(stationFee['pay_date'], '2026-11-01');
      expect(stationFee.containsKey('next_pay_date'), isFalse);
    });
  });

  group('Mock 上报仓库副作用', () {
    test('里程提交进入列表顶部并校验大于上次读数', () async {
      final MockReportRepository repo = MockReportRepository();

      final double previous = await repo.fetchPreviousMileage(118);
      expect(previous, 22237);

      await expectLater(
        repo.submit(ReportDraft(
          kind: ReportKind.mileage,
          carId: 118,
          carNum: '云A770Q5',
          mileage: 100,
          cost: null,
          feeType: null,
          money: null,
          stationId: null,
          station: '',
          payDate: '',
          nextPayDate: '',
          contractId: 258,
          stage: 1,
          description: '',
          pictures: const <String>[],
        )),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.userMessage,
            'message',
            '上报里程必须大于上次里程',
          ),
        ),
      );

      await repo.submit(ReportDraft(
        kind: ReportKind.mileage,
        carId: 118,
        carNum: '云A770Q5',
        mileage: 23000,
        cost: 90,
        feeType: null,
        money: null,
        stationId: null,
        station: '',
        payDate: '',
        nextPayDate: '',
        contractId: 258,
        stage: 1,
        description: '补充巡检',
        pictures: const <String>[],
      ));

      final ReportPage page = await repo.fetchReports(ReportKind.mileage);
      expect(page.items.first.description, '补充巡检');
      expect(page.items.first.mileage, 23000);
      expect(page.items.first.stageStr, '运维阶段');
    });

    test('费用提交校验金额为非零正数', () async {
      final MockReportRepository repo = MockReportRepository();

      await expectLater(
        repo.submit(ReportDraft(
          kind: ReportKind.carFee,
          carId: 92,
          carNum: '苏F9823N',
          mileage: null,
          cost: null,
          feeType: 2,
          money: -5,
          stationId: null,
          station: '',
          payDate: '',
          nextPayDate: '',
          contractId: null,
          stage: null,
          description: '',
          pictures: const <String>[],
        )),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.userMessage,
            'message',
            '合同id不能为空',
          ),
        ),
      );

      await expectLater(
        repo.submit(ReportDraft(
          kind: ReportKind.carFee,
          carId: 92,
          carNum: '苏F9823N',
          mileage: null,
          cost: null,
          feeType: 2,
          money: -5,
          stationId: null,
          station: '',
          payDate: '',
          nextPayDate: '',
          contractId: 258,
          stage: null,
          description: '',
          pictures: const <String>[],
        )),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.userMessage,
            'message',
            '数值异常！上报金额为非零正数！',
          ),
        ),
      );
    });
  });

  group('Mock 申请与审批流转', () {
    test('提交 → 待审批箱可见 → 通过后进已审批', () async {
      final MockApplyRepository repo = MockApplyRepository();

      final int todoBefore = (await repo.fetchApprovalBox(ApplyBox.todo)).length;
      await repo.submit(ApplyDraft(
        type: ApplyType.reagent,
        description: '氨氮试剂补货',
        requireDate: '2026-11-20',
        approveUserId: MockApplyRepository.demoUserId,
        feeType: null,
        money: null,
        pictures: const <String>[],
        items: const <ApplyItem>[
          ApplyItem(itemId: 337, itemName: '氨氮试剂D', quantity: 2),
        ],
        stationId: null,
        contractId: null,
        toolId: null,
        deliveryName: '',
        deliveryAddress: '',
        deliveryPhone: '',
      ));

      final List<ApplyRecord> mine = await repo.fetchMyApplies();
      expect(mine.first.state, ApplyState.processing);
      expect(mine.first.items.single.quantity, 2);

      final List<ApplyRecord> todo = await repo.fetchApprovalBox(ApplyBox.todo);
      expect(todo.length, todoBefore + 1);
      final int newId = todo.first.id;

      await repo.approve(newId);
      final List<ApplyRecord> done = await repo.fetchApprovalBox(ApplyBox.done);
      expect(
        done.where((ApplyRecord r) => r.id == newId),
        isNotEmpty,
      );
      expect(
        (await repo.fetchApprovalBox(ApplyBox.todo)).where(
          (ApplyRecord r) => r.id == newId,
        ),
        isEmpty,
      );
    });

    test('驳回必须带原因，撤回后不可再审批', () async {
      final MockApplyRepository repo = MockApplyRepository();

      await expectLater(
        repo.reject(901, '  '),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.userMessage,
            'message',
            '拒绝原因不能为空！',
          ),
        ),
      );

      await repo.reject(901, '库存充足');
      final ApplyRecord rejected = await repo.fetchApplyDetail(
        ApplyType.reagent,
        901,
      );
      expect(rejected.state, ApplyState.rejected);
      expect(rejected.rejectReason, '库存充足');
      expect(rejected.canApprove, isFalse);

      await expectLater(
        repo.withdraw(901),
        throwsA(isA<AppException>()),
      );
    });

    test('试剂目录按站点分组返回', () async {
      final MockApplyRepository repo = MockApplyRepository();
      final List<ReagentGroup> groups = await repo.fetchReagentGroups(1919);
      expect(groups, hasLength(2));
      expect(groups.first.instrumentName, '氨氮分析仪');

      final List<ReagentGroup> filtered = await repo.fetchReagentGroups(
        1919,
        keyword: '总磷',
      );
      expect(filtered.single.items.single.name, '总磷试剂');
    });
  });

  group('统计与资料库解析（对齐 2026-11-06 实测响应）', () {
    test('异常统计解析 task/statestat 行', () {
      final AbnormalStat stat = AbnormalStat.fromJson(<String, Object?>{
        'title': '全国',
        'region_key': '1',
        'state_todo': 3,
        'state_doing': 4,
        'state_fixed': 2,
        'state_noterror': 1,
        'state_confirmed': 5,
        'state_terminated': 1,
        'state_overtime': 2,
        'total': 16,
      });
      expect(stat.title, '全国');
      expect(stat.total, 16);
      expect(stat.todo, 3);
      expect(stat.overtime, 2);
    });

    test('巡检统计解析 opsrecord/statestat 行', () {
      final InspectionStat stat = InspectionStat.fromJson(<String, Object?>{
        'title': '浙江省',
        'region_key': '330000',
        'total': 16,
        'todo': 4,
        'done': 10,
        'overtime': 1,
        'termination': 1,
      });
      expect(stat.done, 10);
      expect(stat.termination, 1);
    });

    test('里程统计解析 car/state 行', () {
      final MileageStat stat = MileageStat.fromJson(<String, Object?>{
        'region': '浙江省',
        'region_key': '330000',
        'car_number': 69,
        'reported': 0,
        'no_reported': 69,
      });
      expect(stat.carNumber, 69);
      expect(stat.noReported, 69);
    });

    test('StatPeriod 的日/周/月区间口径', () {
      final DateTime now = DateTime(2026, 11, 6, 9, 30); // 周五
      expect(StatPeriod.day.range(now).$1, '2026-11-06');
      expect(StatPeriod.day.range(now).$2, '2026-11-06');
      expect(StatPeriod.week.range(now).$1, '2026-11-02'); // 本周一
      expect(StatPeriod.week.range(now).$2, '2026-11-06');
      expect(StatPeriod.month.range(now).$1, '2026-11-01');
    });

    test('资料库模型解析', () {
      final DirectoryStation station = DirectoryStation.fromJson(<String, Object?>{
        'id': 1919,
        'name': '小兴闸',
        'region': '江苏省',
        'city': '连云港市',
        'contract_num': '2023126JS',
        'firstchar': 'X',
      });
      expect(station.name, '小兴闸');
      expect(station.contractNum, '2023126JS');

      final Agency agency = Agency.fromJson(<String, Object?>{
        'id': 1,
        'name': '湖州办事处',
        'agent': '王建国',
        'landlord': '瞿阿芳',
        'count_room': '2',
        'count_room_used': '1',
        'rent_of_year': '22320',
      });
      expect(agency.landlord, '瞿阿芳');
      expect(agency.countRoomUsed, '1');

      final CarLocationItem car = CarLocationItem.fromJson(<String, Object?>{
        'lng': '120.755',
        'lat': '30.746',
        'gps_time': '2026-11-06T08:40:00.000+0800',
        'activation_flag': true,
        'speed': 42.0,
        'imei': '868120350206117',
        'loc_desc': '嘉兴市南湖区',
        'car': <String, Object?>{'id': 66, 'car_num': '浙B3K207'},
      });
      expect(car.car.carNum, '浙B3K207');
      expect(car.online, isTrue);
      expect(car.speed, 42.0);
    });

    test('Mock 目录仓库 keyword 过滤', () async {
      final MockDirectoryRepository repo = MockDirectoryRepository(
        delay: Duration.zero,
      );
      expect((await repo.fetchStations(keyword: '小兴闸')).single.id, 1919);
      expect((await repo.fetchAgencies(keyword: '湖州')).single.id, 1);
      expect((await repo.fetchUsers(keyword: '赵亮')).single.nickname, '赵亮');
      expect(
        (await repo.fetchCarsWithLocation(keyword: '浙B3K207')).single.car.id,
        66,
      );
    });

    test('Mock 抄送人候选与申请评论副作用', () async {
      final MockApplyRepository repo = MockApplyRepository(delay: Duration.zero);

      final List<TaskPerson> cc = await repo.fetchCcUsers(keyword: '赵');
      expect(cc.single.nickname, '赵亮');

      await repo.postApplyComment(934, '试剂今日已寄出');
      final List<ApplyComment> comments = await repo.fetchApplyComments(934);
      expect(comments.single.content, '试剂今日已寄出');
      expect(comments.single.person?.nickname, '张伟');
    });
  });

  group('Remote 请求体', () {
    /// 每个用例独立构造：捕获拦截器必须是第一个注册的，
    /// 否则前面的 resolve 拦截器会短路整个 onRequest 链。
    Future<(ApiClient, List<RequestOptions>)> stubbedApi() async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/'));
      final ApiClient api = ApiClient(
        dio: dio,
        tokenReader: () => 'real-token',
        enableLog: false,
      );
      final List<RequestOptions> captured = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                captured.add(options);
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object?>{'success': true, 'data': null},
                  ),
                );
              },
        ),
      );
      return (api, captured);
    }

    test('上报提交是 PUT report/{kind}', () async {
      final (ApiClient api, List<RequestOptions> captured) =
          await stubbedApi();

      await RemoteReportRepository(api).submit(ReportDraft(
        kind: ReportKind.mileage,
        carId: 118,
        carNum: '云A770Q5',
        mileage: 23000,
        cost: null,
        feeType: null,
        money: null,
        stationId: null,
        station: '',
        payDate: '',
        nextPayDate: '',
        contractId: 258,
        stage: 1,
        description: '',
        pictures: const <String>[],
      ));

      final RequestOptions put = captured.single;
      expect(put.method, 'PUT');
      expect(put.uri.path, endsWith('/report/mileage'));
    });

    test('试剂申请提交体带 itemList 与审批人', () async {
      final (ApiClient api, List<RequestOptions> captured) =
          await stubbedApi();

      await RemoteApplyRepository(api).submit(ApplyDraft(
        type: ApplyType.reagent,
        description: '补货',
        requireDate: '2026-11-20',
        approveUserId: 16,
        feeType: null,
        money: null,
        pictures: const <String>[],
        items: const <ApplyItem>[
          ApplyItem(itemId: 337, itemName: '氨氮试剂D', quantity: 2),
        ],
        stationId: 1919,
        contractId: null,
        toolId: null,
        deliveryName: '张三',
        deliveryAddress: '小兴闸站房',
        deliveryPhone: '',
        applyCopy: const <int>[16, 25],
      ));

      final RequestOptions post = captured.single;
      expect(post.method, 'POST');
      expect(post.uri.path, endsWith('/apply/reagent'));
      final Map<Object?, Object?> body = post.data! as Map<Object?, Object?>;
      expect(body['approve_user_id'], 16);
      expect(body['station_id'], 1919);
      expect((body['itemList']! as List).length, 1);
      expect(body['delivery_name'], '张三');
      expect(body['apply_copy'], <int>[16, 25]);
    });

    test('审批驳回带 reason 字段', () async {
      final (ApiClient api, List<RequestOptions> captured) =
          await stubbedApi();

      await RemoteApplyRepository(api).reject(934, '库存充足');

      final RequestOptions reject = captured.single;
      expect(reject.uri.path, endsWith('/apply/934/reject'));
      expect(
        (reject.data! as Map<Object?, Object?>)['reason'],
        '库存充足',
      );
    });
  });

  group('申请流程 UI', () {
    setUp(() => MockApplyRepository.resetForTest());

    Widget wrap({MockApplyRepository? repo}) {
      final MockApplyRepository repository =
          repo ?? MockApplyRepository(delay: Duration.zero);
      return ProviderScope(
        overrides: [
          useMockProvider.overrideWithValue(true),
          authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
          applyRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ApprovalCenterPage()),
      );
    }

    testWidgets('审批中心待办列表展示试剂申请并可进详情', (WidgetTester tester) async {
      final MockApplyRepository repo = MockApplyRepository(delay: Duration.zero);
      await tester.pumpWidget(wrap(repo: repo));

      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('试剂申请'), findsWidgets);
      expect(find.text('张子龙'), findsOneWidget);

      await tester.tap(find.text('试剂申请').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 演示账号 id=1001 是这条申请的审批人，详情页应出现通过 / 驳回。
      expect(find.text('通过'), findsOneWidget);
      expect(find.text('驳回'), findsOneWidget);
    });

    testWidgets('统计页日/周/月切换与资料库列表', (WidgetTester tester) async {
      final ProviderScope scope = ProviderScope(
        overrides: [useMockProvider.overrideWithValue(true)],
        child: const MaterialApp(home: StatisticsPage(kind: StatsKind.abnormal)),
      );
      await tester.pumpWidget(scope);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('全国'), findsOneWidget);
      expect(find.text('共 46 单'), findsOneWidget);

      await tester.tap(find.text('月'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('共 46 单'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [useMockProvider.overrideWithValue(true)],
          child: const MaterialApp(home: DirectoryPage(kind: DirectoryKind.car)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('浙B3K207'), findsOneWidget);
      expect(find.text('在线'), findsWidgets);
    });

    testWidgets('申请详情评论区可发评论', (WidgetTester tester) async {
      final MockApplyRepository repo = MockApplyRepository(delay: Duration.zero);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            useMockProvider.overrideWithValue(true),
            authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
            applyRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: ApplyDetailPage(
              record: const ApplyRecord(
                id: 901,
                type: ApplyType.reagent,
                state: ApplyState.processing,
                applyNumber: 'SJ2026110501',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('沟通记录'), findsOneWidget);
      expect(find.text('还没有沟通记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '试剂已寄出');
      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('试剂已寄出'), findsOneWidget);
      expect(find.text('评论已发布'), findsOneWidget);
    });

    testWidgets('购物车加购后去填单并提交', (WidgetTester tester) async {
      final MockApplyRepository repo = MockApplyRepository(delay: Duration.zero);
      final ProviderScope scope = ProviderScope(
        overrides: [
          useMockProvider.overrideWithValue(true),
          authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
          applyRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: ShopPickPage(kind: ApplyType.tool),
        ),
      );
      await tester.pumpWidget(scope);
      await tester.pump(const Duration(milliseconds: 50));

      // 给「总磷分析仪」加购。
      await tester.tap(find.byIcon(LucideIcons.plus).first);
      await tester.pump();

      await tester.tap(find.text('去填申请单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('填写运维工具单'), findsOneWidget);
      expect(find.text('总磷分析仪'), findsWidgets);

      // 工具申请不需要选审批人（保管人自动审批），直接提交。
      // 新增抄送人行后提交按钮在首屏之外，先拖到底。
      await tester.drag(find.text('抄送人'), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交申请'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // testWidgets 的 FakeAsync zone 里直接 await mock 的 delayed Future
      // 会挂死，用 runAsync 走真实事件循环断言副作用。
      await tester.runAsync(() async {
        final List<ApplyRecord> mine = await repo.fetchMyApplies(
          type: ApplyType.tool,
        );
        expect(mine.first.items.single.itemName, '总磷分析仪');
        expect(mine.first.state, ApplyState.processing);
      });
    });
  });
}
