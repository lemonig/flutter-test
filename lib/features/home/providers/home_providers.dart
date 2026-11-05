import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../core/network/api_response.dart';
import '../data/models/filter_group.dart';
import '../data/models/task_item.dart';
import '../data/repositories/home_repository.dart';
import '../data/repositories/meta_repository.dart';
import '../data/repositories/remote_home_repository.dart';

final Provider<MetaRepository> metaRepositoryProvider =
    Provider<MetaRepository>(
      (Ref ref) => MetaRepository(ref.watch(apiClientProvider)),
    );

/// 筛选条件配置（M2-02）：真实环境从 `meta/basic` 拉取，
/// 接口失败或 Mock 模式回落到与后端一致的本地配置。
final filterConfigProvider =
    FutureProvider.family<List<FilterGroup>, TaskCategory>((
      Ref ref,
      TaskCategory category,
    ) async {
      final List<FilterGroup> fallback = TaskFilterConfig.of(category);
      if (ref.watch(useMockProvider)) return fallback;
      try {
        final Map<TaskCategory, List<FilterGroup>> remote = await ref
            .watch(metaRepositoryProvider)
            .fetchFilterGroups();
        final List<FilterGroup>? groups = remote[category];
        return (groups == null || groups.isEmpty) ? fallback : groups;
      } on Object {
        return fallback;
      }
    });

/// 数据源注入点（M2-01）：默认演示数据；
/// `--dart-define=USE_MOCK=false` 后自动切到真实 timeline 接口。
final Provider<HomeRepository> homeRepositoryProvider =
    Provider<HomeRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockHomeRepository();
      return RemoteHomeRepository(
        ref.watch(apiClientProvider),
        groupsResolver: (TaskCategory category) =>
            ref.watch(filterConfigProvider(category)).value ??
            TaskFilterConfig.of(category),
      );
    });

/// 深链直达详情页时按 id 查数据（M2-05）。
/// 真实环境调 `GET task/{id}` / `opsrecord/{id}` / `attend/{id}`；
/// Mock 环境仍从演示列表里查找。
final taskByIdProvider =
    FutureProvider.family<TaskItem?, ({TaskCategory category, String id})>((
      Ref ref,
      ({TaskCategory category, String id}) arg,
    ) async {
      if (!ref.watch(useMockProvider)) {
        final ApiResponse response = await ref
            .watch(apiClientProvider)
            .getRaw('${arg.category.detailEndpoint}/${arg.id}');
        final Map<String, Object?> data = response.mapData;
        // 异常详情 VO 用 contentPictures，列表 VO 用 pictures，统一一下。
        if (data['pictures'] == null && data['contentPictures'] != null) {
          data['pictures'] = data['contentPictures'];
        }
        return RemoteHomeRepository.mapTaskItem(arg.category, data);
      }

      final HomeRepository repository = ref.watch(homeRepositoryProvider);
      const int pageSize = 20;
      for (int page = 1; page <= 3; page++) {
        final List<TaskItem> items = await repository.fetchTasks(
          category: arg.category,
          page: page,
          pageSize: pageSize,
        );
        for (final TaskItem item in items) {
          if (item.id == arg.id) return item;
        }
        if (items.length < pageSize) break;
      }
      return null;
    });

/// 首页单个分类的列表状态（分页 + 筛选 + 加载态）。
class TaskListState {
  const TaskListState({
    required this.items,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.filters = const <String, String>{},
  });

  final List<TaskItem> items;
  final bool isLoadingMore;
  final bool hasMore;
  final Map<String, String> filters;

  TaskListState copyWith({
    List<TaskItem>? items,
    bool? isLoadingMore,
    bool? hasMore,
    Map<String, String>? filters,
  }) {
    return TaskListState(
      items: items ?? this.items,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      filters: filters ?? this.filters,
    );
  }
}

/// 每个分类独立一份列表状态，页面切换时互不干扰。
final taskListProvider =
    AsyncNotifierProvider.family<TaskListNotifier, TaskListState, TaskCategory>(
      TaskListNotifier.new,
    );

class TaskListNotifier extends AsyncNotifier<TaskListState> {
  TaskListNotifier(this.category);

  final TaskCategory category;

  static const int pageSize = 10;

  int _page = 1;

  HomeRepository get _repository => ref.read(homeRepositoryProvider);

  /// 优先用服务端的 more_items_in_collection；Mock 数据源按返回条数推断。
  bool _hasMore(List<TaskItem> items, int size) =>
      _repository.lastResponseHasMore ?? (items.length >= size);

  @override
  Future<TaskListState> build() async {
    _page = 1;
    final List<TaskItem> items = await _repository.fetchTasks(
      category: category,
      page: 1,
      pageSize: pageSize,
    );
    return TaskListState(items: items, hasMore: _hasMore(items, pageSize));
  }

  /// 下拉刷新：保留筛选条件，回到第一页。
  /// 刷新期间由 RefreshIndicator 承担加载反馈，已有数据保持可见。
  Future<void> refresh() async {
    final Map<String, String> filters =
        state.value?.filters ?? const <String, String>{};
    try {
      _page = 1;
      final List<TaskItem> items = await _repository.fetchTasks(
        category: category,
        page: 1,
        pageSize: pageSize,
        filters: filters,
      );
      state = AsyncData<TaskListState>(
        TaskListState(
          items: items,
          hasMore: _hasMore(items, pageSize),
          filters: filters,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError<TaskListState>(error, stackTrace);
    }
  }

  /// 触底加载下一页。
  Future<void> loadMore() async {
    final TaskListState? current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData<TaskListState>(current.copyWith(isLoadingMore: true));

    final int nextPage = _page + 1;
    try {
      final List<TaskItem> items = await _repository.fetchTasks(
        category: category,
        page: nextPage,
        pageSize: pageSize,
        filters: current.filters,
      );
      _page = nextPage;
      state = AsyncData<TaskListState>(
        current.copyWith(
          items: <TaskItem>[...current.items, ...items],
          isLoadingMore: false,
          hasMore: _hasMore(items, pageSize),
        ),
      );
    } catch (_) {
      state = AsyncData<TaskListState>(current.copyWith(isLoadingMore: false));
    }
  }

  /// 应用筛选条件并重新拉取第一页。
  Future<void> applyFilters(Map<String, String> filters) async {
    try {
      _page = 1;
      final List<TaskItem> items = await _repository.fetchTasks(
        category: category,
        page: 1,
        pageSize: pageSize,
        filters: filters,
      );
      state = AsyncData<TaskListState>(
        TaskListState(
          items: items,
          hasMore: _hasMore(items, pageSize),
          filters: filters,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError<TaskListState>(error, stackTrace);
    }
  }
}
