import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_response.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/app_storage.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/task_item.dart';
import '../providers/home_providers.dart';
import 'widgets/task_card.dart';

/// 全局搜索（M2-04，对照 iOS Search 模块）。
///
/// 三类结果共用一个关键词，分 Tab 展示；关键词提交后记入历史
/// （`AppStorage.readSearchHistory`，最新在前、去重、上限 10 条）。
/// 候选接口为 `task|opsrecord|attend/search`，响应与 timeline 同构。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  TaskCategory _category = TaskCategory.abnormal;
  String _submitted = '';
  List<String> _history = const <String>[];
  bool _searching = false;
  bool _hasMore = false;
  int _page = 1;
  final List<TaskItem> _results = <TaskItem>[];
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // 输入即搜（300ms 防抖），无需按回车；历史记录在提交后才写入。
    _input.addListener(_onChanged);
    _reloadHistory();
  }

  Future<void> _reloadHistory() async {
    final List<String> items = await ref.read(appStorageProvider).readSearchHistory();
    if (mounted) setState(() => _history = items);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.removeListener(_onChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final String text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _submitted = '';
        _results.clear();
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _search(String keyword) async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _submitted = keyword;
      _page = 1;
      _results.clear();
      _error = null;
    });
    try {
      final List<TaskItem> items = await ref
          .read(homeRepositoryProvider)
          .search(category: _category, keyword: keyword, page: 1);
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(items);
        _hasMore = items.length >= 10;
      });
      if (keyword == _input.text.trim()) {
        await _remember(keyword);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (e) {
      if (mounted) setState(() => _error = '搜索失败：$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadMore() async {
    if (_searching || !_hasMore || _submitted.isEmpty) return;
    setState(() => _searching = true);
    try {
      final List<TaskItem> items = await ref
          .read(homeRepositoryProvider)
          .search(category: _category, keyword: _submitted, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _results.addAll(items);
        _hasMore = items.length >= 10;
      });
    } catch (_) {
      // 加载更多失败静默保留已有结果，触底重试即可。
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _remember(String keyword) async {
    final AppStorage storage = ref.read(appStorageProvider);
    final List<String> rest = _history.where((String k) => k != keyword).toList();
    final List<String> next = <String>[keyword, ...rest];
    await storage.saveSearchHistory(next);
    if (mounted) setState(() => _history = next);
  }

  Future<void> _clearHistory() async {
    await ref.read(appStorageProvider).saveSearchHistory(<String>[]);
    if (mounted) setState(() => _history = const <String>[]);
  }

  void _openDetail(TaskItem item) =>
      context.push(detailPathFor(_category, item.id), extra: item);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _input,
            focusNode: _focus,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '搜索内容、站点、处理人',
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              suffixIcon: _input.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () {
                        _input.clear();
                        _focus.requestFocus();
                      },
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: _submitted.isEmpty
          ? _HistorySection(
              items: _history,
              onPick: (String keyword) {
                _input.text = keyword;
                _search(keyword);
              },
              onClear: _clearHistory,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SegmentedButton<TaskCategory>(
                    segments: const <ButtonSegment<TaskCategory>>[
                      ButtonSegment<TaskCategory>(
                        value: TaskCategory.abnormal,
                        label: Text('异常'),
                      ),
                      ButtonSegment<TaskCategory>(
                        value: TaskCategory.inspection,
                        label: Text('巡检'),
                      ),
                      ButtonSegment<TaskCategory>(
                        value: TaskCategory.signIn,
                        label: Text('签到'),
                      ),
                    ],
                    selected: <TaskCategory>{_category},
                    onSelectionChanged: (Set<TaskCategory> selection) {
                      _category = selection.first;
                      if (_submitted.isNotEmpty) _search(_submitted);
                    },
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? EmptyState(
                          icon: LucideIcons.triangleAlert,
                          title: '搜索失败',
                          message: _error!,
                          actionLabel: '重试',
                          onAction: () => _search(_submitted),
                        )
                      : _results.isEmpty && !_searching
                      ? EmptyState(
                          icon: LucideIcons.searchX,
                          title: '没有找到相关内容',
                          message: '换个关键词试试，支持内容、站点、处理人',
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (ScrollNotification n) {
                            if (n.metrics.pixels >
                                n.metrics.maxScrollExtent - 200) {
                              _loadMore();
                            }
                            return false;
                          },
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: _results.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int index) {
                              if (index == _results.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return TaskCard(
                                item: _results[index],
                                onTap: () => _openDetail(_results[index]),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

/// 搜索历史：chips + 一键清空。空历史时不渲染。
class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.items,
    required this.onPick,
    required this.onClear,
  });

  final List<String> items;
  final void Function(String keyword) onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (items.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.search,
        title: '搜索全局任务',
        message: '支持按内容、站点名称、处理人搜索',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('搜索历史', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(LucideIcons.trash2, size: 14),
              label: const Text('清空'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String keyword in items)
              ActionChip(
                label: Text(keyword),
                onPressed: () => onPick(keyword),
              ),
          ],
        ),
      ],
    );
  }
}
