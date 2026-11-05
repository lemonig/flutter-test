import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/task_item.dart';
import '../../providers/home_providers.dart';
import 'task_card.dart';

/// 单个分类的任务列表（M2-07）：
/// 骨架屏 + 下拉刷新 + 触底加载 + 错误重试 + 空态区分「无数据/无筛选结果」。
class TaskListView extends ConsumerStatefulWidget {
  const TaskListView({super.key, required this.category});

  final TaskCategory category;

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      ref.read(taskListProvider(widget.category).notifier).loadMore();
    }
  }

  Future<void> _refresh() =>
      ref.read(taskListProvider(widget.category).notifier).refresh();

  void _retry() => ref.invalidate(taskListProvider(widget.category));

  void _openDetail(TaskItem item) =>
      context.push(detailPathFor(widget.category, item.id), extra: item);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final AsyncValue<TaskListState> state = ref.watch(
      taskListProvider(widget.category),
    );

    return AsyncValueView<TaskListState>(
      value: state,
      onRetry: _retry,
      builder: (TaskListState data) {
        if (data.items.isEmpty) {
          final bool hasActiveFilter = data.filters.values.any(
            (String value) => value.isNotEmpty && value != '全部',
          );
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: EmptyState(
                      icon: hasActiveFilter
                          ? LucideIcons.searchX
                          : LucideIcons.inbox,
                      title: hasActiveFilter
                          ? '没有符合筛选条件的记录'
                          : '暂无${widget.category.label}记录',
                      message: hasActiveFilter ? '试着放宽筛选条件，或点击重置' : '下拉刷新试试',
                      actionLabel: hasActiveFilter ? '清空筛选' : '刷新',
                      onAction: hasActiveFilter
                          ? () => ref
                                .read(
                                  taskListProvider(widget.category).notifier,
                                )
                                .applyFilters(const <String, String>{})
                          : _refresh,
                    ),
                  ),
                ),
              );
            },
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: data.items.length + 1,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              if (index == data.items.length) {
                return _ListFooter(
                  isLoading: data.isLoadingMore,
                  hasMore: data.hasMore,
                );
              }
              return TaskCard(
                item: data.items[index],
                onTap: () => _openDetail(data.items[index]),
              );
            },
          ),
        );
      },
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.isLoading, required this.hasMore});

  final bool isLoading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          hasMore ? '上拉加载更多' : '已加载全部',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
