import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/widgets/filter_choice_chip.dart';

/// 快捷筛选条：高级筛选入口固定在左侧，状态选项可横向滚动。
///
/// 真实后端的「任务状态」有 8 个选项（含省份动态项），
/// 若把筛选按钮放在滚动区末尾，用户必须横滑才能找到它。
class QuickFilterBar extends StatelessWidget {
  const QuickFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.activeCount,
    required this.onSelected,
    required this.onOpenFilter,
  });

  final List<String> options;
  final String selected;

  /// 已生效的筛选条件数量（不含「全部」）。
  final int activeCount;
  final ValueChanged<String> onSelected;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    final bool hasFilter = activeCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: <Widget>[
          FilterChoiceChip(
            label: hasFilter ? '筛选 · $activeCount' : '筛选',
            selected: hasFilter,
            icon: LucideIcons.slidersHorizontal,
            onTap: onOpenFilter,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final String option in options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChoiceChip(
                        label: option,
                        selected: option == selected,
                        onTap: () => onSelected(option),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
