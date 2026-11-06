import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/workbench_models.dart';

/// 上报三件套（M7-02 ~ M7-04）：里程 / 车辆费用 / 水电网费。
///
/// 接口形态（实测）：
/// - 元数据 `GET report/meta`：合同、工程阶段、三类费用枚举；
/// - 列表 `POST report/{kind}/list`（分页），详情 `GET report/{kind}/{id}`；
/// - 提交统一是 **PUT report/{kind}**，不是 POST；
/// - 里程提交前可用 `GET report/mileage/previous?carId=` 取上次读数，
///   服务端校验「必须大于上次里程」。
abstract class ReportRepository {
  Future<ReportMeta> fetchMeta();

  Future<List<Car>> fetchCars({String keyword = ''});

  Future<ReportPage> fetchReports(
    ReportKind kind, {
    int page = 1,
    int pageSize = 15,
  });

  Future<ReportRecord> fetchReportDetail(ReportKind kind, int id);

  /// 该车上次上报的里程表读数（没有记录时为 0）。
  Future<double> fetchPreviousMileage(int carId);

  /// 按省 + 时间区间的里程上报流水（统计详情用，
  /// `POST car/regionSearch`：condition2 = region_key）。
  Future<ReportPage> fetchMileageReports({
    required String regionKey,
    required String startDate,
    required String endDate,
    int page = 1,
    int pageSize = 10,
  });

  Future<void> submit(ReportDraft draft);
}

/// `report/meta` 的响应：表单需要的全部选项。
class ReportMeta {
  const ReportMeta({
    this.contracts = const <Option>[],
    this.stages = const <Option>[],
    this.carFeeTypes = const <Option>[],
    this.stationFeeTypes = const <Option>[],
    this.applyFeeTypes = const <Option>[],
  });

  final List<Option> contracts;
  final List<Option> stages;
  final List<Option> carFeeTypes;
  final List<Option> stationFeeTypes;
  final List<Option> applyFeeTypes;

  static ReportMeta fromJson(Object? raw) {
    if (raw is! Map) return const ReportMeta();
    return ReportMeta(
      contracts: Option.listFrom(raw['contractList']),
      stages: Option.listFrom(raw['projectStageList']),
      carFeeTypes: Option.listFrom(raw['feeCarType']),
      stationFeeTypes: Option.listFrom(raw['feeStationType']),
      applyFeeTypes: Option.listFrom(raw['feeApplyType']),
    );
  }
}

/// 分页结果；hasMore 优先取服务端 `more_items_in_collection`。
class ReportPage {
  const ReportPage({required this.items, required this.hasMore});

  final List<ReportRecord> items;
  final bool hasMore;
}

class RemoteReportRepository implements ReportRepository {
  const RemoteReportRepository(this._api);

  final ApiClient _api;

  @override
  Future<ReportMeta> fetchMeta() async {
    final ApiResponse response = await _api.getRaw('report/meta');
    return ReportMeta.fromJson(response.mapData);
  }

  @override
  Future<List<Car>> fetchCars({String keyword = ''}) async {
    // `GET car` 必须带 JSON body，否则服务端空指针（2026-11-06 实测）。
    final ApiResponse response = await _api.getRaw(
      'car',
      data: const <String, Object?>{},
    );
    final List<Car> cars = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(Car.fromJson)
        .toList();
    final String query = keyword.trim();
    if (query.isEmpty) return cars;
    return cars
        .where((Car car) => car.carNum.contains(query))
        .toList(growable: false);
  }

  @override
  Future<ReportPage> fetchReports(
    ReportKind kind, {
    int page = 1,
    int pageSize = 15,
  }) async {
    final ApiResponse response = await _api.postRaw(
      '${kind.path}/list',
      data: <String, Object?>{'startPage': page, 'limit': pageSize},
    );
    return ReportPage(
      items: response.listData
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> item) => ReportRecord.fromJson(item, kind))
          .toList(),
      hasMore: response.hasMoreItems ?? false,
    );
  }

  @override
  Future<ReportRecord> fetchReportDetail(ReportKind kind, int id) async {
    final ApiResponse response = await _api.getRaw('${kind.path}/$id');
    return ReportRecord.fromJson(response.mapData, kind);
  }

  @override
  Future<ReportPage> fetchMileageReports({
    required String regionKey,
    required String startDate,
    required String endDate,
    int page = 1,
    int pageSize = 10,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'car/regionSearch',
      data: <String, Object?>{
        'startDate': startDate,
        'endDate': endDate,
        'condition1': '1',
        'condition2': regionKey,
        'startPage': page,
        'limit': pageSize,
      },
    );
    return ReportPage(
      items: response.listData
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                ReportRecord.fromJson(item, ReportKind.mileage),
          )
          .toList(),
      hasMore: response.hasMoreItems ?? false,
    );
  }

  @override
  Future<double> fetchPreviousMileage(int carId) async {
    final ApiResponse response = await _api.getRaw(
      'report/mileage/previous',
      query: <String, Object?>{'carId': carId},
    );
    final Object? value = response.data;
    return value is num ? value.toDouble() : 0;
  }

  @override
  Future<void> submit(ReportDraft draft) =>
      _api.putRaw(draft.kind.path, data: draft.toJson());
}

/// 演示实现：进程内留存，提交即出现在「我的上报」列表顶部，
/// 与 MockTaskDetailRepository 同一套思路（列表说是什么，详情就是什么）。
class MockReportRepository implements ReportRepository {
  MockReportRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static final ReportMeta _meta = const ReportMeta(
    contracts: <Option>[
      Option(label: '2021274NM', value: 280, name: '（外包）包头市流域水环境智慧监管平台'),
      Option(label: '2021450JS', value: 309, name: '江苏淮安开发区环境监测监控能力建设项目'),
      Option(label: '2023126JS', value: 521, name: '连云港6个小型水站三年数据采购服务项目'),
    ],
    stages: <Option>[
      Option(label: '运维阶段', value: 1),
      Option(label: '工程阶段-施工', value: 2),
      Option(label: '售后阶段', value: 3),
      Option(label: '工程阶段-试运行', value: 4),
    ],
    carFeeTypes: <Option>[
      Option(label: '油费', value: 1),
      Option(label: '过路费', value: 2),
      Option(label: '维修保养', value: 3),
      Option(label: '停车费', value: 4),
      Option(label: '其他', value: 5),
    ],
    stationFeeTypes: <Option>[
      Option(label: '水费', value: 1),
      Option(label: '电费', value: 2),
      Option(label: '网络费', value: 3),
      Option(label: '其他', value: 4),
    ],
    applyFeeTypes: <Option>[
      Option(label: '办公用品', value: 1),
      Option(label: '差旅费', value: 2),
      Option(label: '业务招待', value: 3),
      Option(label: '其他', value: 4),
    ],
  );

  static final List<Car> _cars = const <Car>[
    Car(id: 280, carNum: '藏MJ5592', region: '西藏自治区', city: '林芝', company: '工程服务中心'),
    Car(id: 265, carNum: '鲁A8D112', region: '山东省', city: '济南', company: '运维一组'),
    Car(id: 118, carNum: '云A770Q5', region: '云南省', city: '安宁', company: '运维二组'),
    Car(id: 92, carNum: '苏F9823N', region: '江苏省', city: '南通', company: '运维三组'),
    Car(id: 66, carNum: '浙B3K207', region: '浙江省', city: '嘉兴', company: '运维四组'),
    Car(id: 41, carNum: '苏G112XF', region: '江苏省', city: '连云港', company: '运维五组'),
  ];

  static final Map<ReportKind, List<ReportRecord>> _store =
      <ReportKind, List<ReportRecord>>{
        ReportKind.mileage: _seedMileage(),
        ReportKind.carFee: _seedFees(),
        ReportKind.stationFee: _seedStationFees(),
      };

  static List<ReportRecord> _seedMileage() => <ReportRecord>[
    ReportRecord(
      id: 110303,
      kind: ReportKind.mileage,
      description: '月度例行巡检往返',
      pictures: <String>[
        'https://picsum.photos/seed/gc-m1/900',
      ],
      submitter: const TaskPerson(id: 16, nickname: '卜幸杰'),
      gmtCreate: '2026-11-04T15:27:44.000+0800',
      reportNumber: 'SB2026110401',
      carId: 118,
      carNum: '云A770Q5',
      mileage: 22237,
      cost: 120,
      contractId: 258,
      contractNum: '2021014YN',
      stage: 1,
      stageStr: '运维阶段',
      checkStateStr: '待审核',
    ),
    ReportRecord(
      id: 110287,
      kind: ReportKind.mileage,
      description: '站点应急处理',
      gmtCreate: '2026-11-02T09:10:00.000+0800',
      reportNumber: 'SB2026110202',
      carId: 66,
      carNum: '浙B3K207',
      mileage: 48210,
      cost: 65,
      contractId: 521,
      contractNum: '2023126JS',
      stage: 1,
      stageStr: '运维阶段',
      checkStateStr: '已审核',
    ),
  ];

  static List<ReportRecord> _seedFees() => <ReportRecord>[
    ReportRecord(
      id: 3174,
      kind: ReportKind.carFee,
      description: '高速过路费',
      pictures: <String>[
        'https://picsum.photos/seed/gc-cf1/900',
      ],
      submitter: const TaskPerson(id: 16, nickname: '卜幸杰'),
      gmtCreate: '2026-11-03T16:02:11.000+0800',
      reportNumber: 'CF2026110301',
      carId: 92,
      carNum: '苏F9823N',
      feeType: 2,
      feeTypeStr: '过路费',
      money: 86.5,
      contractId: 521,
      contractNum: '2023126JS',
      stage: 1,
      stageStr: '运维阶段',
    ),
  ];

  static List<ReportRecord> _seedStationFees() => <ReportRecord>[
    ReportRecord(
      id: 2082,
      kind: ReportKind.stationFee,
      description: '11 月站房电费',
      pictures: <String>[
        'https://picsum.photos/seed/gc-sf1/900',
      ],
      submitter: const TaskPerson(id: 16, nickname: '卜幸杰'),
      gmtCreate: '2026-11-01T10:20:00.000+0800',
      reportNumber: 'SF2026110101',
      stationId: 1919,
      station: '小兴闸',
      feeType: 2,
      feeTypeStr: '电费',
      money: 412.8,
      payDate: '2026-11-01',
      nextPayDate: '2026-12-01',
      contractId: 521,
      contractNum: '2023126JS',
      stage: 1,
      stageStr: '运维阶段',
    ),
  ];

  static int _nextId = 900000;

  @override
  Future<ReportMeta> fetchMeta() async {
    await Future<void>.delayed(delay);
    return _meta;
  }

  @override
  Future<List<Car>> fetchCars({String keyword = ''}) async {
    await Future<void>.delayed(delay);
    final String query = keyword.trim();
    if (query.isEmpty) return List<Car>.unmodifiable(_cars);
    return _cars.where((Car car) => car.carNum.contains(query)).toList();
  }

  @override
  Future<ReportPage> fetchReports(
    ReportKind kind, {
    int page = 1,
    int pageSize = 15,
  }) async {
    await Future<void>.delayed(delay);
    final List<ReportRecord> all = _store[kind] ?? const <ReportRecord>[];
    final int start = (page - 1) * pageSize;
    final List<ReportRecord> slice = start >= all.length
        ? const <ReportRecord>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return ReportPage(
      items: List<ReportRecord>.unmodifiable(slice),
      hasMore: start + pageSize < all.length,
    );
  }

  @override
  Future<ReportRecord> fetchReportDetail(ReportKind kind, int id) async {
    await Future<void>.delayed(delay);
    for (final ReportRecord record in _store[kind] ?? const <ReportRecord>[]) {
      if (record.id == id) return record;
    }
    throw AppException(
      '记录不存在',
      kind: ApiErrorKind.business,
      code: 'NOT_FOUND',
    );
  }

  @override
  Future<ReportPage> fetchMileageReports({
    required String regionKey,
    required String startDate,
    required String endDate,
    int page = 1,
    int pageSize = 10,
  }) async {
    await Future<void>.delayed(delay);
    final DateTime start = DateTime.parse(startDate);
    final DateTime end = DateTime.parse(endDate).add(const Duration(days: 1));
    final List<ReportRecord> matched = _store[ReportKind.mileage]!
        .where((ReportRecord record) {
          final DateTime? created = DateTime.tryParse(
            record.gmtCreate.replaceFirst(' ', 'T'),
          );
          return created == null ||
              (!created.isBefore(start) && created.isBefore(end));
        })
        .toList();
    final int pos = (page - 1) * pageSize;
    return ReportPage(
      items: pos >= matched.length
          ? const <ReportRecord>[]
          : matched.sublist(pos, (pos + pageSize).clamp(0, matched.length)),
      hasMore: pos + pageSize < matched.length,
    );
  }

  @override
  Future<double> fetchPreviousMileage(int carId) async {
    await Future<void>.delayed(delay);
    for (final ReportRecord record in _store[ReportKind.mileage]!) {
      if (record.carId == carId && record.mileage != null) {
        return record.mileage!;
      }
    }
    return 0;
  }

  @override
  Future<void> submit(ReportDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final ReportKind kind = draft.kind;
    // 对齐服务端校验（2026-11-06 实测：三类上报都强制合同归属）。
    if (draft.contractId == null) {
      throw const AppException('合同id不能为空', kind: ApiErrorKind.business);
    }
    if (kind == ReportKind.mileage) {
      if (draft.carId == null) {
        throw const AppException('车辆id不能为空', kind: ApiErrorKind.business);
      }
      if (draft.mileage == null) {
        throw const AppException('上报里程不能为空', kind: ApiErrorKind.business);
      }
      final double previous = await fetchPreviousMileage(draft.carId!);
      if (draft.mileage! - previous <= 0) {
        throw const AppException(
          '上报里程必须大于上次里程',
          kind: ApiErrorKind.business,
        );
      }
    } else {
      if (draft.money == null) {
        throw const AppException('请输入金额！', kind: ApiErrorKind.business);
      }
      if (draft.money! <= 0 || draft.money! > 100000000) {
        throw const AppException(
          '数值异常！上报金额为非零正数！',
          kind: ApiErrorKind.business,
        );
      }
    }

    final String prefix = switch (kind) {
      ReportKind.mileage => 'SB',
      ReportKind.carFee => 'CF',
      ReportKind.stationFee => 'SF',
    };
    final ReportRecord record = ReportRecord(
      id: ++_nextId,
      kind: kind,
      description: draft.description,
      pictures: List<String>.of(draft.pictures),
      submitter: const TaskPerson(id: 1001, nickname: '张伟'),
      gmtCreate: DateTime.now().toIso8601String(),
      reportNumber: '$prefix${_nextId % 1000000}',
      carId: draft.carId,
      carNum: draft.carNum,
      mileage: draft.mileage,
      cost: draft.cost,
      feeType: draft.feeType,
      feeTypeStr: switch (kind) {
        ReportKind.carFee => _labelOf(_meta.carFeeTypes, draft.feeType),
        ReportKind.stationFee => _labelOf(_meta.stationFeeTypes, draft.feeType),
        _ => '',
      },
      money: draft.money,
      stationId: draft.stationId,
      station: draft.station,
      payDate: draft.payDate,
      nextPayDate: draft.nextPayDate,
      contractId: draft.contractId,
      contractNum: _contractNumOf(draft.contractId),
      stage: draft.stage,
      stageStr: _labelOf(_meta.stages, draft.stage),
      checkStateStr: kind == ReportKind.mileage ? '待审核' : '',
    );
    _store[kind]!.insert(0, record);
  }

  static String _labelOf(List<Option> options, int? value) {
    for (final Option option in options) {
      if (option.value == value) return option.label;
    }
    return '';
  }

  static String _contractNumOf(int? contractId) {
    for (final Option contract in _meta.contracts) {
      if (contract.value == contractId) return contract.label;
    }
    return '';
  }
}

final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockReportRepository();
      return RemoteReportRepository(ref.watch(apiClientProvider));
    });
