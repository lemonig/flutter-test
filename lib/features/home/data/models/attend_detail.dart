import '../../../../shared/utils/backend_time.dart';
import 'task_detail.dart';

/// 签到详情（`GET attend/{id}` → 后端 `AttendVO`）。
///
/// 与列表的区别：详情多了 `pictures`（完整 OSS 直链）、`jobNumber`（服务端
/// 生成的签到单号）和经纬度；评论/点赞计数不在详情里，走 `comment/list`
/// 与 `like/list` 单独取。
class AttendDetail {
  const AttendDetail({
    required this.id,
    this.jobNumber = '',
    this.address = '',
    this.description = '',
    this.longitude,
    this.latitude,
    this.time,
    this.person,
    this.stationId,
    this.stationName = '',
    this.pictures = const <TaskPhoto>[],
  });

  final String id;

  /// 服务端生成：`QD` + `yyyyMMdd` + 自增序号。
  final String jobNumber;

  final String address;
  final String description;

  /// 经度（后端 `coordinate1`）。注意别和纬度写反。
  final double? longitude;

  /// 纬度（后端 `coordinate2`）。
  final double? latitude;

  /// `gmt_create` 原始值，展示时再格式化。
  final String? time;

  final TaskPerson? person;
  final int? stationId;
  final String stationName;
  final List<TaskPhoto> pictures;

  bool get hasCoordinate => longitude != null && latitude != null;

  String get coordinateLabel => hasCoordinate
      ? '${longitude!.toStringAsFixed(6)}, ${latitude!.toStringAsFixed(6)}'
      : '未记录';

  String get timeText => formatBackendFriendly(time, empty: '—');

  String get personName {
    final String nickname = person?.nickname ?? '';
    return nickname.isEmpty ? '未知用户' : nickname;
  }

  static AttendDetail fromJson(Object? raw) {
    final Map<Object?, Object?> json = raw is Map
        ? Map<Object?, Object?>.from(raw)
        : const <Object?, Object?>{};
    final Map<Object?, Object?> station = _asMap(json['station']);
    return AttendDetail(
      id: '${json['id'] ?? ''}',
      jobNumber: '${json['jobNumber'] ?? ''}',
      address: '${json['address'] ?? ''}',
      description: '${json['description'] ?? ''}',
      longitude: _asDouble(json['coordinate1']),
      latitude: _asDouble(json['coordinate2']),
      time: json['gmt_create']?.toString(),
      person: TaskPerson.fromJson(json['user']),
      stationId: _asInt(station['id']),
      stationName: '${station['name'] ?? ''}',
      pictures: TaskPhoto.listFrom(json['pictures']),
    );
  }

  /// 兼容 `comment/list` 等接口把对象再包一层的情况。
  static Map<Object?, Object?> _asMap(Object? value) =>
      value is Map ? Map<Object?, Object?>.from(value) : const <Object?, Object?>{};

  static double? _asDouble(Object? value) => switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v),
    _ => null,
  };

  static int? _asInt(Object? value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v),
    _ => null,
  };
}
