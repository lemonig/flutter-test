import 'task_item.dart';

/// 单个筛选分组。
///
/// [options] 是展示文案，[values] 是与之一一对应的后端 condition 编码。
/// 后端（AppService.getTaskConditionList 等）返回的是
/// `MetaConditionVO{name, list:[{label,value}]}`，value 为 "1"~"8" 或省份 key。
class FilterGroup {
  const FilterGroup({
    required this.title,
    required this.options,
    this.values = const <String, String>{},
  });

  final String title;
  final List<String> options;
  final Map<String, String> values;

  /// label → 后端编码；未匹配时回落到 "1"（全部）。
  String valueOf(String label) => values[label] ?? '1';

  String labelOf(String value) => values.entries
      .firstWhere(
        (MapEntry<String, String> e) => e.value == value,
        orElse: () => const MapEntry<String, String>('全部', '1'),
      )
      .key;

  factory FilterGroup.fromMeta(Object? raw) {
    if (raw is! Map) return const FilterGroup(title: '', options: <String>[]);
    final String title = raw['name']?.toString() ?? '';
    final Object? list = raw['list'];
    final List<String> options = <String>[];
    final Map<String, String> values = <String, String>{};
    if (list is List) {
      for (final Object? item in list) {
        if (item is! Map) continue;
        final String label = item['label']?.toString() ?? '';
        final String value = item['value']?.toString() ?? '1';
        if (label.isEmpty) continue;
        options.add(label);
        values[label] = value;
      }
    }
    return FilterGroup(title: title, options: options, values: values);
  }
}

/// 筛选条件配置（M2-02）。
///
/// 默认配置与后端 `AppService` 的硬编码分组完全一致，用作接口不可用时的
/// fallback；真实环境下由 `filterConfigProvider` 从 `GET meta/basic` 动态拉取，
/// 后端新增条件项（如新增省份）无需发版。
class TaskFilterConfig {
  /// 日期区间在 filters map 里的保留 key；值格式 `start|end`（yyyy-MM-dd）。
  static const String dateRangeKey = '日期区间';

  const TaskFilterConfig._();

  static const String defaultOption = '全部';

  /// 每个 conditionN 对应的分组名，顺序由后端 `translateXxxQueryForm` 决定。
  static Map<TaskCategory, List<String>> get conditionOrder =>
      <TaskCategory, List<String>>{
        TaskCategory.abnormal: const <String>['可见范围', '任务状态', '其他', '所属省份'],
        TaskCategory.inspection: const <String>['可见范围', '任务状态', '所属省份'],
        TaskCategory.signIn: const <String>['可见范围', '所属省份'],
      };

  static List<FilterGroup> of(TaskCategory category) => switch (category) {
    TaskCategory.abnormal => <FilterGroup>[
      _group(
        '任务状态',
        const <String>[
          '全部',
          '待处理',
          '处理中',
          '已提交-非异常',
          '已提交-已修复',
          '已关闭',
          '已终止',
          '超时',
        ],
        const <String>['1', '2', '3', '4', '5', '6', '7', '8'],
      ),
      _visibility(const <String>['全部', '我处理的', '我发出的', '我转交的', '未读']),
      _group('其他', const <String>['全部', '产品缺陷导致'], const <String>['1', '2']),
      _region(),
    ],
    TaskCategory.inspection => <FilterGroup>[
      _group(
        '任务状态',
        const <String>['全部', '未完成', '已完成', '已过期', '已终止'],
        const <String>['1', '2', '3', '4', '5'],
      ),
      _visibility(const <String>['全部', '我处理的', '我转交的', '未读']),
      _region(),
    ],
    TaskCategory.signIn => <FilterGroup>[
      _visibility(const <String>['全部', '我的签到']),
      _region(),
    ],
  };

  static FilterGroup _visibility(List<String> options) => _group(
    '可见范围',
    options,
    List<String>.generate(options.length, (int i) => '${i + 1}'),
  );

  static FilterGroup _region() => const FilterGroup(
    title: '所属省份',
    options: <String>['全部'],
    values: <String, String>{'全部': '1'},
  );

  static FilterGroup _group(
    String title,
    List<String> options,
    List<String> values,
  ) => FilterGroup(
    title: title,
    options: options,
    values: <String, String>{
      for (int i = 0; i < options.length; i++)
        options[i]: i < values.length ? values[i] : '${i + 1}',
    },
  );
}
