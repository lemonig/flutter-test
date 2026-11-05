import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_response.dart';
import '../models/filter_group.dart';
import '../models/task_item.dart';

/// 元数据仓储（M2-02）。
///
/// `GET meta/basic` 下发三类筛选条件（后端 `AppService.getMetaBasic`）：
/// `taskConditionList` / `opsConditionList` / `attendConditionList`，
/// 每项为 `{name, list:[{label,value}]}`。省份列表由 orgService 动态生成，
/// 因此必须从接口取，不能硬编码。
class MetaRepository {
  const MetaRepository(this._api);

  final ApiClient _api;

  Future<Map<TaskCategory, List<FilterGroup>>> fetchFilterGroups() async =>
      parse(await _api.getRaw('meta/basic'));

  static Future<Map<TaskCategory, List<FilterGroup>>> fromResponse(
    Future<ApiResponse> response,
  ) async => parse(await response);

  static Map<TaskCategory, List<FilterGroup>> parse(ApiResponse response) {
    final Map<String, Object?> data = response.mapData;
    return <TaskCategory, List<FilterGroup>>{
      TaskCategory.abnormal: parseGroupList(data['taskConditionList']),
      TaskCategory.inspection: parseGroupList(data['opsConditionList']),
      TaskCategory.signIn: parseGroupList(data['attendConditionList']),
    };
  }

  static List<FilterGroup> parseGroupList(Object? raw) {
    if (raw is! List) return const <FilterGroup>[];
    return raw
        .map(FilterGroup.fromMeta)
        .where(
          (FilterGroup group) =>
              group.title.isNotEmpty && group.options.isNotEmpty,
        )
        .toList();
  }
}
