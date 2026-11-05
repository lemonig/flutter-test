import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/widgets/filter_choice_chip.dart';
import '../../data/models/filter_group.dart';
import '../../data/models/task_item.dart';

/// 打开筛选底部面板，返回 null 表示取消，否则返回生效的筛选条件。
///
/// [groups] 由首页从 `filterConfigProvider` 取得（真实环境下来自 `meta/basic`），
/// 面板本身不关心条件是本地配置还是服务端下发。
Future<Map<String, String>?> showTaskFilterSheet(
  BuildContext context, {
  required TaskCategory category,
  required Map<String, String> initialFilters,
  required List<FilterGroup> groups,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => TaskFilterSheet(
      category: category,
      initialFilters: initialFilters,
      groups: groups,
    ),
  );
}

/// 高级筛选面板：分组单选 + 重置 / 应用。
class TaskFilterSheet extends StatefulWidget {
  const TaskFilterSheet({
    super.key,
    required this.category,
    required this.initialFilters,
    required this.groups,
  });

  final TaskCategory category;
  final Map<String, String> initialFilters;
  final List<FilterGroup> groups;

  @override
  State<TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<TaskFilterSheet> {
  late Map<String, String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = <String, String>{
      for (final FilterGroup group in widget.groups)
        group.title:
            widget.initialFilters[group.title] ??
            TaskFilterConfig.defaultOption,
    };
  }

  int get _activeCount => _selected.values
      .where((String value) => value != TaskFilterConfig.defaultOption)
      .length;

  void _reset() {
    setState(() {
      _selected = <String, String>{
        for (final FilterGroup group in widget.groups)
          group.title: TaskFilterConfig.defaultOption,
      };
    });
  }

  void _apply() {
    final Map<String, String> effective = <String, String>{
      for (final MapEntry<String, String> entry in _selected.entries)
        if (entry.value != TaskFilterConfig.defaultOption)
          entry.key: entry.value,
    };
    Navigator.of(context).pop(effective);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: <Widget>[
                  Text('筛选', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  if (_activeCount > 0)
                    Text(
                      '已选 $_activeCount 项',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final FilterGroup group in widget.groups)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              group.title,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                for (final String option in group.options)
                                  FilterChoiceChip(
                                    label: option,
                                    selected: _selected[group.title] == option,
                                    onTap: () => setState(() {
                                      _selected[group.title] = option;
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('应用筛选'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
