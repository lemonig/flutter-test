import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/filter_group.dart';
import '../data/models/task_item.dart';
import '../data/repositories/home_repository.dart';
import 'home_providers.dart';

/// 「我的事件」（M9-02 / M3-07）的状态。
class MyEventsState {
  const MyEventsState({
    this.items = const <TaskItem>[],
    this.status = TaskFilterConfig.defaultOption,
    this.isRefreshing = false,
  });

  final List<TaskItem> items;

  /// 当前选中的「任务状态」筛选文案。
  final String status;

  final bool isRefreshing;

  MyEventsState copyWith({
    List<TaskItem>? items,
    String? status,
    bool? isRefreshing,
  }) => MyEventsState(
    items: items ?? this.items,
    status: status ?? this.status,
    isRefreshing: isRefreshing ?? this.isRefreshing,
  );
}

/// 「我的事件」三类各自一份状态。
///
/// 刻意**不复用**首页的 `taskListProvider`：首页的筛选是用户临时挑的，
/// 我的事件固定按「我处理的 / 我的签到」取数，共用一份状态会互相污染
/// （从我的事件切回首页，首页的筛选条件会被悄悄改掉）。
final myEventsProvider =
    AsyncNotifierProvider.family<MyEventsNotifier, MyEventsState, TaskCategory>(
      MyEventsNotifier.new,
    );

class MyEventsNotifier extends AsyncNotifier<MyEventsState> {
  MyEventsNotifier(this.category);

  final TaskCategory category;

  static const int pageSize = 20;

  /// 「我的」维度：异常/巡检是「我处理的」，签到是「我的签到」。
  static String visibilityOf(TaskCategory category) => switch (category) {
    TaskCategory.abnormal || TaskCategory.inspection => '我处理的',
    TaskCategory.signIn => '我的签到',
  };

  /// 状态筛选项；签到没有任务状态，返回空表示不展示筛选条。
  static List<String> statusOptionsOf(TaskCategory category) {
    for (final FilterGroup group in TaskFilterConfig.of(category)) {
      if (group.title == '任务状态') return group.options;
    }
    return const <String>[];
  }

  HomeRepository get _repository => ref.read(homeRepositoryProvider);

  Map<String, String> _filters(String status) => <String, String>{
    '可见范围': visibilityOf(category),
    '任务状态': status,
  };

  @override
  Future<MyEventsState> build() async {
    final List<TaskItem> items = await _repository.fetchTasks(
      category: category,
      page: 1,
      pageSize: pageSize,
      filters: _filters(TaskFilterConfig.defaultOption),
    );
    return MyEventsState(items: items);
  }

  Future<void> changeStatus(String status) async {
    final MyEventsState? current = state.value;
    if (current == null || current.status == status) return;
    state = AsyncData(current.copyWith(status: status, isRefreshing: true));
    try {
      final List<TaskItem> items = await _repository.fetchTasks(
        category: category,
        page: 1,
        pageSize: pageSize,
        filters: _filters(status),
      );
      state = AsyncData(MyEventsState(items: items, status: status));
    } catch (error, stackTrace) {
      state = AsyncError<MyEventsState>(error, stackTrace);
    }
  }

  Future<void> refresh() async {
    final MyEventsState? current = state.value;
    final String status = current?.status ?? TaskFilterConfig.defaultOption;
    try {
      final List<TaskItem> items = await _repository.fetchTasks(
        category: category,
        page: 1,
        pageSize: pageSize,
        filters: _filters(status),
      );
      state = AsyncData(MyEventsState(items: items, status: status));
    } catch (error, stackTrace) {
      state = AsyncError<MyEventsState>(error, stackTrace);
    }
  }
}
