import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';

/// 可作为异常发生站点的精简站点。
///
/// 来源 `POST station/datamanager` —— 后端只返回「当前用户是数据管理员」的站点，
/// 而 `TaskCreateValidator` 又硬性要求 `station.dataManagerId == creatorId`，
/// 所以这个列表就是可创建范围的**唯一权威来源**，不要换成全量站点列表。
class StationOption {
  const StationOption({
    required this.id,
    required this.name,
    this.region,
    this.city,
  });

  final int id;
  final String name;
  final String? region;
  final String? city;

  String get subtitle =>
      <String?>[region, city].whereType<String>().where((String s) => s.isNotEmpty).join(' · ');

  static StationOption? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    final int? parsedId = id is int ? id : int.tryParse('$id');
    if (parsedId == null) return null;
    return StationOption(
      id: parsedId,
      name: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? (raw['name'] as String).trim()
          : '站点 $parsedId',
      region: raw['region'] as String?,
      city: raw['city'] as String?,
    );
  }
}

/// 新建异常的提交载荷。字段与后端 `Task` 实体 + `TaskCreateValidator` 对齐。
class CreateTaskDraft {
  const CreateTaskDraft({
    required this.stationId,
    required this.content,
    required this.happenAt,
    required this.deadline,
    required this.remind,
    this.pictureKeys = const <String>[],
  });

  final int stationId;
  final String content;
  final DateTime happenAt;
  final DateTime deadline;

  /// `RemindEnum`：0 无 / 1 15分钟 / 2 30分钟 / 3 1小时 / 4 4小时 / 5 1天。
  final int remind;

  /// 上传接口返回的 objectKey（`task/...`），不是完整 URL。
  final List<String> pictureKeys;

  Map<String, Object?> toJson() => <String, Object?>{
    'stationId': stationId,
    'content': content.trim(),
    'gmt_happen': happenAt.millisecondsSinceEpoch,
    'deadline': deadline.millisecondsSinceEpoch,
    'remind': remind,
    'picturesContent': pictureKeys,
  };
}

/// 提醒项，文案与 `RemindEnum` 一一对应。
class RemindOption {
  const RemindOption(this.value, this.label);

  final int value;
  final String label;

  static const List<RemindOption> all = <RemindOption>[
    RemindOption(0, '不提醒'),
    RemindOption(1, '截止前 15 分钟'),
    RemindOption(2, '截止前 30 分钟'),
    RemindOption(3, '截止前 1 小时'),
    RemindOption(4, '截止前 4 小时'),
    RemindOption(5, '截止前 1 天'),
  ];

  static String labelOf(int value) =>
      all.firstWhere((RemindOption o) => o.value == value, orElse: () => all.first).label;
}

/// 异常新建的写接口。
abstract class TaskWriteRepository {
  Future<List<StationOption>> fetchManagedStations({String keyword = ''});

  Future<void> createTask(CreateTaskDraft draft);
}

/// 真实实现。
class RemoteTaskWriteRepository implements TaskWriteRepository {
  const RemoteTaskWriteRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<StationOption>> fetchManagedStations({String keyword = ''}) async {
    final String trimmed = keyword.trim();
    final ApiResponse response = await _api.postRaw(
      'station/datamanager',
      data: <String, Object?>{
        'startPage': 1,
        'limit': 200,
        if (trimmed.isNotEmpty) 'keyword': trimmed,
      },
    );
    final Object? data = response.data;
    if (data is! List) return const <StationOption>[];
    return data
        .map(StationOption.tryParse)
        .whereType<StationOption>()
        .toList(growable: false);
  }

  @override
  Future<void> createTask(CreateTaskDraft draft) =>
      _api.postRaw('task/create', data: draft.toJson());
}

/// 演示实现：给出几个假站点，提交后本地成功返回。
///
/// 真实环境里「可用站点」完全由后端 `station.dataManagerId` 决定，
/// 演示包没有真实账号时连表单都填不了，所以这里只服务 `USE_MOCK=true`。
class MockTaskWriteRepository implements TaskWriteRepository {
  const MockTaskWriteRepository();

  static const List<StationOption> demoStations = <StationOption>[
    StationOption(id: 9001, name: '演示站点·夜郎湖', region: '贵州省', city: '安顺市'),
    StationOption(id: 9002, name: '演示站点·古新河', region: '浙江省', city: '嘉兴市'),
    StationOption(id: 9003, name: '演示站点·垅坪水库', region: '浙江省', city: '嘉兴市'),
  ];

  @override
  Future<List<StationOption>> fetchManagedStations({String keyword = ''}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final String q = keyword.trim();
    if (q.isEmpty) return demoStations;
    return demoStations
        .where((StationOption s) => s.name.contains(q))
        .toList(growable: false);
  }

  @override
  Future<void> createTask(CreateTaskDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}

final Provider<TaskWriteRepository> taskWriteRepositoryProvider =
    Provider<TaskWriteRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return const MockTaskWriteRepository();
      return RemoteTaskWriteRepository(ref.watch(apiClientProvider));
    });

/// 当前账号可创建异常的站点。空列表通常意味着「不是任何站点的数据管理员」。
final FutureProvider<List<StationOption>> managedStationsProvider =
    FutureProvider<List<StationOption>>(
      (Ref ref) => ref.watch(taskWriteRepositoryProvider).fetchManagedStations(),
    );
