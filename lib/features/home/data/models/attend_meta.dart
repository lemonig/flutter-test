/// 签到相关模型（M5-01）。
///
/// 契约来自 `ops-mobile` 的 `AttendController` / `AttendProfileVO` /
/// `StationDistanceVO`，字段名与后端保持一一对应。
library;

/// 附近站点（`StationDistanceVO`）。
class StationDistance {
  const StationDistance({
    required this.id,
    required this.name,
    required this.distance,
  });

  final int id;
  final String name;

  /// 与当前坐标的直线距离，单位米。后端用 `ST_DISTANCE * 111195` 粗算，
  /// 只用于就近排序和"偏差"提示，不是导航级精度。
  final double distance;

  /// 距离文案：1 公里以内显示米（保留 1 位），超过显示公里。
  String get distanceLabel => distance >= 1000
      ? '${(distance / 1000).toStringAsFixed(2)} 公里'
      : '${distance.toStringAsFixed(1)} 米';

  /// 容错解析：后端字段缺失/类型漂移时不抛异常，直接跳过该站点。
  static StationDistance? tryParse(Object? json) {
    if (json is! Map) return null;
    final int? id = _asInt(json['id']);
    if (id == null) return null;
    final String name = '${json['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    return StationDistance(
      id: id,
      name: name,
      distance: _asDouble(json['distance']) ?? 0,
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v),
    _ => null,
  };

  static double? _asDouble(Object? value) => switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v),
    _ => null,
  };
}

/// 签到页元数据（`POST attend/meta`）。
class AttendMeta {
  const AttendMeta({required this.countToday, required this.stationsNearBy});

  /// 今日已签到次数（后端 `getAttendCountToday`）。
  final int countToday;

  /// 当前位置 20 公里内的站点，按距离升序，最多 15 个。
  final List<StationDistance> stationsNearBy;

  static const AttendMeta empty = AttendMeta(
    countToday: 0,
    stationsNearBy: <StationDistance>[],
  );

  factory AttendMeta.fromJson(Object? json) {
    if (json is! Map) return empty;
    final Object? raw = json['stationsNearBy'];
    final List<StationDistance> stations = raw is List
        ? raw
              .map(StationDistance.tryParse)
              .whereType<StationDistance>()
              .toList(growable: false)
        : const <StationDistance>[];
    return AttendMeta(
      countToday: StationDistance._asInt(json['count']) ?? 0,
      stationsNearBy: stations,
    );
  }
}

/// 提交签到（`POST attend/post`）。
///
/// 后端 `AttendCreateValidator` 的硬约束：
/// - `coordinate1` / `coordinate2` 必填；
/// - `address` 必填，但 `AttendController` 在为空时会兜底成「未获取到地址」；
/// - 传了 `stationId` 就必须落在该站点附近（20 公里内），否则报「当前位置未处在签到站点」。
class AttendDraft {
  const AttendDraft({
    this.stationId,
    required this.coordinate1,
    required this.coordinate2,
    this.address = '',
    this.description = '',
    this.pictureKeys = const <String>[],
  });

  final int? stationId;
  final double coordinate1;
  final double coordinate2;
  final String address;
  final String description;

  /// OSS objectKey 列表（`check/...`），不是完整 URL。
  final List<String> pictureKeys;

  Map<String, Object?> toJson() => <String, Object?>{
    if (stationId != null) 'stationId': stationId,
    'coordinate1': coordinate1,
    'coordinate2': coordinate2,
    'address': address.trim(),
    'description': description.trim(),
    'pictures': pictureKeys,
  };
}
