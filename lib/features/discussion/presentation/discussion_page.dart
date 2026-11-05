import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/status_pill.dart';
import '../data/models/post_item.dart';

/// 信息填报（讨论区）Tab：填报进度 + 帖子流 + 发帖入口。
class DiscussionPage extends StatelessWidget {
  const DiscussionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('信息填报'),
        actions: <Widget>[
          IconButton(
            tooltip: '筛选',
            onPressed: () => showToast(context, '填报筛选开发中'),
            icon: const Icon(LucideIcons.slidersHorizontal),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showToast(context, '发帖功能开发中'),
        icon: const Icon(LucideIcons.penLine, size: 20),
        label: const Text('发帖'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: mockPostItems.length + 1,
        separatorBuilder: (BuildContext context, int index) =>
            SizedBox(height: index == 0 ? 14 : 10),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) return const _ProgressCard();
          return _PostCard(item: mockPostItems[index - 1]);
        },
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const int done = 2;
    const int total = 3;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  LucideIcons.clipboardList,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text('本周信息填报', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '$done / $total 条',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '还差 1 条即可完成本周考核，重点补充异常处置与巡检记录。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatefulWidget {
  const _PostCard({required this.item});

  final PostItem item;

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PostItem item = widget.item;

    return Card(
      child: InkWell(
        onTap: () => showToast(context, '帖子详情开发中'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  AppAvatar(
                    label: item.author,
                    tone: item.tone,
                    size: 38,
                    radius: 12,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(item.author, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${item.department} · ${item.timeText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: item.tag, compact: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(item.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                item.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _Action(
                    icon: LucideIcons.thumbsUp,
                    label: '${item.likeCount + (_liked ? 1 : 0)}',
                    active: _liked,
                    onTap: () => setState(() => _liked = !_liked),
                  ),
                  const SizedBox(width: 6),
                  _Action(
                    icon: LucideIcons.messageCircle,
                    label: '${item.commentCount}',
                    onTap: () => showToast(context, '评论功能开发中'),
                  ),
                  const Spacer(),
                  Text(
                    '查看详情',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
