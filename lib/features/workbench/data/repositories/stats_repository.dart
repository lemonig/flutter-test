import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/workbench_models.dart';

/// 统计三件套（M7-11，对照 iOS `Statistical(统计)` 模块）。
///
/// 接口（2026-11-06 实测，body 均可传 `startDate` / `endDate`）：
/// - 异常 `POST task/statestat`：`title/region_key/state_*/total`；
/// - 巡检 `POST opsrecord/statestat`：`title/region_key/total/todo/done/overtime/termination`；
/// - 里程 `POST car/state`：`region/region_key/car_number/reported/no_reported`。
///
/// 展示对齐 iOS：日 / 周 / 月切换 + 按省列表（无图表，纯数字卡）。
abstract class StatsRepository {
  Future<List<AbnormalStat>> fetchAbnormalStats({DateTimeRange? range});

  Future<List<InspectionStat>> fetchInspectionStats({DateTimeRange? range});

  Future<List<MileageStat>> fetchMileageStats({DateTimeRange? range});
}

/// iOS 统计页的日期区间（日/周/月换算见 [StatPeriodX.range]）。
class DateTimeRange {
  const DateTimeRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Map<String, Object?> toBody() => <String, Object?>{
    'startDate': _fmt(start),
    'endDate': _fmt(end),
  };

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class RemoteStatsRepository implements StatsRepository {
  const RemoteStatsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AbnormalStat>> fetchAbnormalStats({
    DateTimeRange? range,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'task/statestat',
      data: range?.toBody() ?? const <String, Object?>{},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(AbnormalStat.fromJson)
        .toList();
  }

  @override
  Future<List<InspectionStat>> fetchInspectionStats({
    DateTimeRange? range,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'opsrecord/statestat',
      data: range?.toBody() ?? const <String, Object?>{},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(InspectionStat.fromJson)
        .toList();
  }

  @override
  Future<List<MileageStat>> fetchMileageStats({DateTimeRange? range}) async {
    final ApiResponse response = await _api.postRaw(
      'car/state',
      data: range?.toBody() ?? const <String, Object?>{},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(MileageStat.fromJson)
        .toList();
  }
}

/// 演示实现：全国 + 三个省的静态分布，与真实响应同构。
class MockStatsRepository implements StatsRepository {
  MockStatsRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static const List<AbnormalStat> _abnormal = <AbnormalStat>[
    AbnormalStat(
      title: '全国',
      regionKey: '1',
      total: 46,
      todo: 8,
      doing: 12,
      fixed: 9,
      notError: 4,
      confirmed: 10,
      terminated: 3,
      overtime: 5,
    ),
    AbnormalStat(
      title: '浙江省',
      regionKey: '330000',
      total: 21,
      todo: 3,
      doing: 6,
      fixed: 4,
      notError: 2,
      confirmed: 5,
      terminated: 1,
      overtime: 2,
    ),
    AbnormalStat(
      title: '江苏省',
      regionKey: '320000',
      total: 18,
      todo: 4,
      doing: 4,
      fixed: 3,
      notError: 2,
      confirmed: 4,
      terminated: 1,
      overtime: 2,
    ),
    AbnormalStat(
      title: '云南省',
      regionKey: '530000',
      total: 7,
      todo: 1,
      doing: 2,
      fixed: 2,
      notError: 0,
      confirmed: 1,
      terminated: 1,
      overtime: 1,
    ),
  ];

  static const List<InspectionStat> _inspection = <InspectionStat>[
    InspectionStat(
      title: '全国',
      regionKey: '1',
      total: 34,
      todo: 9,
      done: 20,
      overtime: 3,
      termination: 2,
    ),
    InspectionStat(
      title: '浙江省',
      regionKey: '330000',
      total: 16,
      todo: 4,
      done: 10,
      overtime: 1,
      termination: 1,
    ),
    InspectionStat(
      title: '江苏省',
      regionKey: '320000',
      total: 13,
      todo: 3,
      done: 8,
      overtime: 2,
      termination: 0,
    ),
    InspectionStat(
      title: '云南省',
      regionKey: '530000',
      total: 5,
      todo: 2,
      done: 2,
      overtime: 0,
      termination: 1,
    ),
  ];

  static const List<MileageStat> _mileage = <MileageStat>[
    MileageStat(region: '浙江省', regionKey: '330000', carNumber: 12, reported: 9, noReported: 3),
    MileageStat(region: '江苏省', regionKey: '320000', carNumber: 15, reported: 11, noReported: 4),
    MileageStat(region: '云南省', regionKey: '530000', carNumber: 6, reported: 3, noReported: 3),
    MileageStat(region: '山东省', regionKey: '370000', carNumber: 9, reported: 5, noReported: 4),
  ];

  @override
  Future<List<AbnormalStat>> fetchAbnormalStats({
    DateTimeRange? range,
  }) async {
    await Future<void>.delayed(delay);
    return List<AbnormalStat>.unmodifiable(_abnormal);
  }

  @override
  Future<List<InspectionStat>> fetchInspectionStats({
    DateTimeRange? range,
  }) async {
    await Future<void>.delayed(delay);
    return List<InspectionStat>.unmodifiable(_inspection);
  }

  @override
  Future<List<MileageStat>> fetchMileageStats({DateTimeRange? range}) async {
    await Future<void>.delayed(delay);
    return List<MileageStat>.unmodifiable(_mileage);
  }
}

final Provider<StatsRepository> statsRepositoryProvider =
    Provider<StatsRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockStatsRepository();
      return RemoteStatsRepository(ref.watch(apiClientProvider));
    });
