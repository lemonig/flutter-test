import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models/task_item.dart';

/// 分类对应的 Lucide 图标。
IconData iconOfCategory(TaskCategory category) => switch (category) {
  TaskCategory.abnormal => LucideIcons.triangleAlert,
  TaskCategory.inspection => LucideIcons.clipboardCheck,
  TaskCategory.signIn => LucideIcons.mapPinCheckInside,
};

/// 异常 / 巡检 / 签到三分类切换（M3 [SegmentedButton]，支持左右滑动联动）。
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TaskCategory selected;
  final ValueChanged<TaskCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TaskCategory>(
      segments: <ButtonSegment<TaskCategory>>[
        for (final TaskCategory category in TaskCategory.values)
          ButtonSegment<TaskCategory>(
            value: category,
            label: Text(category.label),
            icon: Icon(iconOfCategory(category), size: 16),
          ),
      ],
      selected: <TaskCategory>{selected},
      onSelectionChanged: (Set<TaskCategory> selection) =>
          onChanged(selection.first),
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
    );
  }
}
