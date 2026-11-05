import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/toast.dart';
import '../../auth/data/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../message/providers/message_providers.dart';
import '../data/models/filter_group.dart';
import '../data/models/task_item.dart';
import '../providers/home_providers.dart';
import 'widgets/category_selector.dart';
import 'widgets/home_header.dart';
import 'widgets/quick_create_sheet.dart';
import 'widgets/quick_filter_bar.dart';
import 'widgets/task_filter_sheet.dart';
import 'widgets/task_list_view.dart';

/// 首页：搜索 + 分类切换 + 快捷筛选 + 任务流。
///
/// 筛选分组优先用 `filterConfigProvider`（真实环境由 `meta/basic` 下发），
/// 加载中或失败时回落到与后端一致的本地配置。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final PageController _pageController = PageController();

  int _categoryIndex = 0;

  TaskCategory get _category => TaskCategory.values[_categoryIndex];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<FilterGroup> _groups(TaskCategory category) =>
      ref.read(filterConfigProvider(category)).value ??
      TaskFilterConfig.of(category);

  /// 快捷筛选条显示第一组；真实分组里异常/巡检是「任务状态」，签到是「可见范围」。
  String _quickKey(TaskCategory category) {
    final List<FilterGroup> groups = _groups(category);
    return groups.isEmpty ? '任务状态' : groups.first.title;
  }

  void _changeCategory(TaskCategory next) {
    final int index = TaskCategory.values.indexOf(next);
    if (index == _categoryIndex) return;
    setState(() => _categoryIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Map<String, String> _currentFilters() => Map<String, String>.from(
    ref.read(taskListProvider(_category)).value?.filters ??
        const <String, String>{},
  );

  void _selectStatus(String option) {
    final Map<String, String> next = _currentFilters();
    final String key = _quickKey(_category);
    if (option == TaskFilterConfig.defaultOption) {
      next.remove(key);
    } else {
      next[key] = option;
    }
    ref.read(taskListProvider(_category).notifier).applyFilters(next);
  }

  Future<void> _openFilterSheet(List<FilterGroup> groups) async {
    final Map<String, String>? result = await showTaskFilterSheet(
      context,
      category: _category,
      initialFilters: _currentFilters(),
      groups: groups,
    );
    if (result == null || !mounted) return;
    await ref.read(taskListProvider(_category).notifier).applyFilters(result);
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> filters =
        ref.watch(taskListProvider(_category)).value?.filters ??
        const <String, String>{};
    final int unread = ref.watch(unreadMessageCountProvider);
    final List<FilterGroup> groups =
        ref.watch(filterConfigProvider(_category)).value ??
        TaskFilterConfig.of(_category);
    final List<String> quickOptions = groups.isEmpty
        ? const <String>['全部']
        : groups.first.options;
    final String quickKey = _quickKey(_category);
    final AppUser? user = ref.watch(authProvider).value?.user;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            HomeHeader(
              unreadCount: unread,
              account: user?.nickname.isNotEmpty == true
                  ? user!.nickname
                  : user?.username,
              role: user?.role.label,
              onNotificationTap: () => context.go('/messages'),
              onCreateTap: () => showQuickCreateSheet(context),
              onSearchTap: () => showToast(context, '搜索功能开发中'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: CategorySelector(
                selected: _category,
                onChanged: _changeCategory,
              ),
            ),
            QuickFilterBar(
              options: quickOptions,
              selected: filters[quickKey] ?? TaskFilterConfig.defaultOption,
              activeCount: filters.values
                  .where(
                    (String value) => value != TaskFilterConfig.defaultOption,
                  )
                  .length,
              onSelected: _selectStatus,
              onOpenFilter: () => _openFilterSheet(groups),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (int index) =>
                    setState(() => _categoryIndex = index),
                children: const <Widget>[
                  TaskListView(category: TaskCategory.abnormal),
                  TaskListView(category: TaskCategory.inspection),
                  TaskListView(category: TaskCategory.signIn),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
