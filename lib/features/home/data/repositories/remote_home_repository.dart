import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_response.dart';
import '../models/filter_group.dart';
import '../models/task_item.dart';
import 'home_repository.dart';

/// 真实后端数据源（M2-01，契约来自 `ops-mobile` 源码）。
///
/// 三个 timeline 均为 `POST`，body 为
/// `{startPage, limit, condition1..conditionN}`，condition 是**数字编码**
/// （见后端 `AppService.translateXxxQueryForm`），不是中文文案。
/// 响应 `data` 为数组，`additional_data` 为分页对象。
class RemoteHomeRepository implements HomeRepository {
  RemoteHomeRepository(this._api, {this.groupsResolver});

  final ApiClient _api;
  final List<FilterGroup> Function(TaskCategory category)? groupsResolver;

  bool? _lastHasMore;

  @override
  bool? get lastResponseHasMore => _lastHasMore;

  @override
  Future<List<TaskItem>> search({
    required TaskCategory category,
    required String keyword,
    required int page,
    int pageSize = 10,
  }) async {
    final ApiResponse response = await _api.postRaw(
      category.searchEndpoint,
      data: <String, Object?>{
        'keyword': keyword.trim(),
        'startPage': page,
        'limit': pageSize,
      },
    );
    _lastHasMore = response.hasMoreItems;
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> row) => mapTaskItem(category, row))
        .toList();
  }

  @override
  Future<List<TaskItem>> fetchTasks({
    required TaskCategory category,
    required int page,
    required int pageSize,
    Map<String, String> filters = const <String, String>{},
  }) async {
    final ApiResponse response = await _api.postRaw(
      category.endpoint,
      data: buildTimelineBody(
        category: category,
        page: page,
        pageSize: pageSize,
        filters: filters,
        groups: groupsResolver?.call(category),
      ),
    );
    _lastHasMore = response.hasMoreItems;
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> row) => mapTaskItem(category, row))
        .toList();
  }

  /// 单独暴露便于单测：把 UI 选中的中文 label 翻译成后端 condition 编码。
  static Map<String, Object?> buildTimelineBody({
    required TaskCategory category,
    required int page,
    required int pageSize,
    Map<String, String> filters = const <String, String>{},
    List<FilterGroup>? groups,
  }) {
    final List<FilterGroup> resolved = groups ?? TaskFilterConfig.of(category);
    final List<String> order =
        TaskFilterConfig.conditionOrder[category] ?? const <String>[];

    final Map<String, Object?> body = <String, Object?>{
      'startPage': page,
      'limit': pageSize,
    };
    // 日期区间是保留字筛选：不占 condition 编码，直接拼顶层
    // startDate/endDate（后端 `BETWEEN gmt_create`，yyyy-MM-dd）。
    final String? dateRange = filters[TaskFilterConfig.dateRangeKey];
    if (dateRange != null && dateRange.contains('|')) {
      final List<String> parts = dateRange.split('|');
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        body['startDate'] = parts[0];
        body['endDate'] = parts[1];
      }
    }
    for (int i = 0; i < order.length; i++) {
      final String title = order[i];
      FilterGroup? group;
      for (final FilterGroup candidate in resolved) {
        if (candidate.title == title) {
          group = candidate;
          break;
        }
      }
      final String label = filters[title] ?? TaskFilterConfig.defaultOption;
      // 后端把 null / "1" 都当作「不过滤」，统一显式传 "1"。
      body['condition${i + 1}'] = group == null ? '1' : group.valueOf(label);
    }
    return body;
  }

  /// 单独暴露便于单测：三类响应 → 统一模型。
  static TaskItem mapTaskItem(
    TaskCategory category,
    Map<Object?, Object?> json,
  ) {
    final Map<Object?, Object?> station = _asMap(json['station']);
    final Map<Object?, Object?> person = _asMap(
      json['executor'] ?? json['user'],
    );
    final String stationName = _text(
      station['name'] ?? station['stationFullName'] ?? json['address'],
    );
    final String personName = _text(
      person['nickname'] ?? person['name'] ?? json['jobNumber'],
    );
    final String time = _formatTime(
      json['gmt_create'] ?? json['createTime'] ?? json['time'],
    );

    // 真实数据里巡检/签到的 description 常年为空，补一段可读摘要，
    // 否则列表卡片会整片显示「暂无描述」。
    String content = _text(json['content'] ?? json['description']);
    if (content.isEmpty) {
      final int itemSize = _int(json['itemSize']);
      final String address = _text(json['address']);
      content = switch (category) {
        TaskCategory.abnormal => '暂无描述',
        TaskCategory.inspection =>
          '${itemSize > 0 ? '$itemSize 个检查项 · ' : ''}'
              '${stationName.isEmpty ? '站点' : stationName}巡检任务',
        TaskCategory.signIn =>
          address.isEmpty
              ? '${stationName.isEmpty ? '站点' : stationName}现场签到'
              : '现场签到 · $address',
      };
    }
    final List<String> tags = switch (category) {
      TaskCategory.abnormal => <String>[abnormalStateLabel(json['state'])],
      TaskCategory.inspection => <String>[
        if (json['terminated'] == true)
          '已终止'
        else if (json['opsTaskDone'] == true)
          '已完成'
        else
          '未完成',
      ],
      TaskCategory.signIn => const <String>['已签到'],
    };

    return TaskItem(
      id: _text(json['id']),
      stationName: stationName.isEmpty ? '未知站点' : stationName,
      timeText: time,
      content: content,
      executor: personName.isEmpty ? '未指派' : personName,
      tags: tags.where((String tag) => tag.isNotEmpty).toList(),
      images: _photos(json['pictures']),
      readCount: _int(json['countRead']),
      commentCount: _int(json['countComment']),
      likeCount: _int(json['countLike']),
    );
  }

  /// 后端 `TaskStateEnum`：1 待处理 / 2 处理中 / 3 已修复 / 4 非异常
  /// / 5 已关闭 / 6 已拒绝 / 7 已终止。
  static String abnormalStateLabel(Object? state) {
    final int? code = state is int ? state : int.tryParse('$state');
    return switch (code) {
      1 => '待处理',
      2 => '处理中',
      3 => '已修复',
      4 => '非异常',
      5 => '已关闭',
      6 => '已拒绝',
      7 => '已终止',
      null => '',
      _ => '状态 $code',
    };
  }

  /// 后端 Timestamp 可能是毫秒数、ISO 字符串或 `yyyy-MM-dd HH:mm:ss`。
  static String _formatTime(Object? raw) {
    if (raw == null) return '';
    if (raw is int) {
      return _stamp(DateTime.fromMillisecondsSinceEpoch(raw));
    }
    final String source = '$raw';
    // 后端已按 GMT+8 输出，保留字面时间，避免设备时区把 ISO 串二次换算成 UTC。
    final RegExpMatch? literal = RegExp(
      r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})',
    ).firstMatch(source);
    if (literal != null) {
      return '${literal.group(1)} ${literal.group(2)}';
    }
    final DateTime? parsed = DateTime.tryParse(source);
    return parsed == null ? source : _stamp(parsed);
  }

  static String _stamp(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  static List<String> _photos(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((Object? element) {
          if (element is String) return element;
          if (element is Map) {
            return _text(element['url'] ?? element['picture']);
          }
          return '';
        })
        .where((String value) => value.isNotEmpty)
        .toList();
  }

  static Map<Object?, Object?> _asMap(Object? value) => value is Map
      ? Map<Object?, Object?>.from(value)
      : const <Object?, Object?>{};

  static String _text(Object? value) => value == null ? '' : '$value';

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
