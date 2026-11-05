import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/attend_meta.dart';

/// 签到写入端口（M5-01）。
///
/// 拆成抽象 + 远程/演示两套实现，页面只依赖接口，
/// 这样单测与演示包都不需要真实后端。
abstract class AttendWriteRepository {
  /// 打卡页元数据：今日次数 + 附近站点（含距离）。
  ///
  /// 后端用 POST，坐标走请求体 `{coordinate1, coordinate2}`。
  Future<AttendMeta> fetchMeta({
    required double longitude,
    required double latitude,
  });

  /// 提交签到。失败时抛 `AppException`，`message` 直接可展示。
  Future<void> createAttend(AttendDraft draft);
}

class RemoteAttendWriteRepository implements AttendWriteRepository {
  const RemoteAttendWriteRepository(this._api);

  final ApiClient _api;

  @override
  Future<AttendMeta> fetchMeta({
    required double longitude,
    required double latitude,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'attend/meta',
      data: <String, Object?>{
        'coordinate1': longitude,
        'coordinate2': latitude,
      },
    );
    return AttendMeta.fromJson(response.data);
  }

  @override
  Future<void> createAttend(AttendDraft draft) async {
    // 后端返回空 ApiResponse（只有 success），没有业务数据要解析。
    await _api.postRaw('attend/post', data: draft.toJson());
  }
}

/// 演示实现：给出固定坐标附近的假站点，提交后本地成功返回。
class MockAttendWriteRepository implements AttendWriteRepository {
  const MockAttendWriteRepository();

  /// 与 `LocationService.debugPoint` 同一片区域（杭州拱墅）。
  static const List<StationDistance> demoStations = <StationDistance>[
    StationDistance(id: 9001, name: '演示站点·夜郎湖', distance: 18.4),
    StationDistance(id: 9002, name: '演示站点·古新河', distance: 320.6),
    StationDistance(id: 9003, name: '演示站点·垅坪水库', distance: 1696.97),
  ];

  @override
  Future<AttendMeta> fetchMeta({
    required double longitude,
    required double latitude,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    return const AttendMeta(countToday: 2, stationsNearBy: demoStations);
  }

  @override
  Future<void> createAttend(AttendDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}

final Provider<AttendWriteRepository> attendWriteRepositoryProvider =
    Provider<AttendWriteRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return const MockAttendWriteRepository();
      return RemoteAttendWriteRepository(ref.watch(apiClientProvider));
    });
