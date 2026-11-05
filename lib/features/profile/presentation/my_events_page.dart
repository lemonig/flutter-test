import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_response.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/filter_choice_chip.dart';
import '../../../shared/widgets/state_views.dart';
import '../../home/data/models/task_item.dart';
import '../../home/presentation/widgets/task_card.dart';
import '../../home/providers/my_events_providers.dart';

/// 我的事件（M9-02 / M3-07）。
///
/// 三类任务各一个 Tab，固定按「我处理的 / 我的签到」取数，点击进入各自详情。
/// 与首页列表的区别只有两点：**数据维度固定**、**没有高级筛选**（只有状态快捷条）。
///
/// 详情入口统一走 `detailPathFor`，避免这里和各处手拼路径拼错分类
/// —— 巡检用 `/inspection/:id`、签到用 `/attend/:id`，拼错就进错详情页。
class MyEventsPage extends ConsumerWidget {
  const MyEventsPage({super.key});

  static const List<TaskCategory> _categories = <TaskCategory>[
    TaskCategory.abnormal,
    TaskCategory.inspection,
    TaskCategory.signIn,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        appBar: AppBar(
          title: const Text('我的事件'),
          centerTitle: true,
          backgroundColor: theme.colorScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          bottom: TabBar(
            tabs: <Widget>[
              for (final TaskCategory category in _categories)
                Tab(text: category.label),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final TaskCategory category in _categories)
              _MyEventsList(category: category),
          ],
        ),
      ),
    );
  }
}

class _MyEventsList extends ConsumerWidget {
  const _MyEventsList({required this.category});

  final TaskCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<MyEventsState> async = ref.watch(
      myEventsProvider(category),
    );
    final MyEventsState? data = async.asData?.value;
    final List<String> statusOptions = MyEventsNotifier.statusOptionsOf(
      category,
    );

    return Column(
      children: <Widget>[
        if (statusOptions.isNotEmpty)
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: statusOptions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final String label = statusOptions[index];
                  return FilterChoiceChip(
                    label: label,
                    selected: (data?.status ?? '全部') == label,
                    onTap: () => ref
                        .read(myEventsProvider(category).notifier)
                        .changeStatus(label),
                  );
                },
              ),
            ),
          ),
        Expanded(
          child: async.when(
            loading: () => const SkeletonList(count: 3),
            error: (Object error, StackTrace stack) => EmptyState(
              icon: LucideIcons.cloudOff,
              title: '${category.label}记录加载失败',
              message: error is AppException ? error.userMessage : '请稍后重试',
              actionLabel: '重新加载',
              onAction: () => ref.invalidate(myEventsProvider(category)),
            ),
            data: (MyEventsState state) {
              if (state.items.isEmpty) {
                return const EmptyState(
                  icon: LucideIcons.inbox,
                  title: '暂无相关记录',
                  message: '这里只会显示与你相关的任务，换个状态筛选试试',
                );
              }
              return RefreshIndicator(
                onRefresh: () =>
                    ref.read(myEventsProvider(category).notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final TaskItem item = state.items[index];
                    return TaskCard(
                      item: item,
                      onTap: () =>
                          context.push(detailPathFor(category, item.id)),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
