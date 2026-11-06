import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/photo_viewer_page.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/task_activity.dart';
import '../data/models/task_detail.dart';
import '../data/models/task_item.dart';
import '../data/models/task_state_machine.dart';
import '../data/repositories/task_write_repository.dart';
import '../providers/home_providers.dart';
import '../providers/task_detail_providers.dart';
import 'handle_task_page.dart';
import 'widgets/comment_sheet.dart';
import 'widgets/transfer_sheet.dart';

/// 异常详情（M3-02）+ 状态流转（M3-05）。
///
/// 页面结构与 iOS 原工程一致：状态头 → 任务信息 → 处理结果 → 处理进度
/// → 已读/互动 → 评论。差异在于动作入口：原工程收在右上角「更多」里，
/// 这里把**当前身份唯一可做的那件事**提到右下角主按钮，其余收进「更多」，
/// 减少误操作（运维最容易点的就是"确认"，而那是数据管理员的动作）。
class AbnormalDetailPage extends ConsumerWidget {
  const AbnormalDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TaskDetail> detail = ref.watch(taskDetailProvider(taskId));
    final TaskDetail? task = detail.asData?.value;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('异常详情'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(taskDetailProvider(taskId)),
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: task == null
                ? null
                : () => _showMoreSheet(context, ref, task),
            icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(taskDetailProvider(taskId));
          await ref.read(taskDetailProvider(taskId).future);
        },
        child: AsyncValueView<TaskDetail>(
          value: detail,
          errorTitle: '异常详情加载失败',
          onRetry: () => ref.invalidate(taskDetailProvider(taskId)),
          loading: const SkeletonList(count: 4),
          builder: (TaskDetail task) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _HeroCard(task: task),
              const SizedBox(height: 12),
              _InfoCard(task: task),
              if (task.hasProcessResult) ...<Widget>[
                const SizedBox(height: 12),
                _ResultCard(task: task),
              ],
              _ProgressSection(taskId: taskId),
              _EngagementCard(task: task, taskId: taskId),
              _CommentPreview(taskId: taskId),
            ],
          ),
        ),
      ),
      bottomNavigationBar: task == null
          ? null
          : _ActionBar(task: task, taskId: taskId),
    );
  }
}

// ───────────────────────────── 头部 ─────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.task});

  final TaskDetail task;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                StatusPill(status: task.state.label),
                if (task.overtime) ...<Widget>[
                  const SizedBox(width: 8),
                  const StatusPill(status: '超时'),
                ],
                const Spacer(),
                if (task.jobNumber.isNotEmpty)
                  Text(
                    task.jobNumber,
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              task.stationName.isEmpty ? '未知站点' : task.stationName,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (task.regionText.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Icon(
                    LucideIcons.mapPin,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      task.regionText,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (task.hadArrivedStationStr.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        task.hadArrivedStationStr,
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const Divider(height: 26),
            Text(
              task.content.isEmpty ? '（无描述）' : task.content,
              style: text.bodyLarge?.copyWith(height: 1.6),
            ),
            if (task.contentPictures.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              PhotoGrid(photos: task.contentPictures),
            ],
          ],
        ),
      ),
    );
  }
}

/// 九宫格照片：外部只传 [TaskPhoto]，点击进全屏预览，支持左右滑动。
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.photos, this.title});

  final List<TaskPhoto> photos;
  final String? title;

  void _preview(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PhotoViewerPage(
          images: photos.map((TaskPhoto p) => p.url).toList(),
          initialIndex: index,
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (BuildContext context, int index) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: scheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () => _preview(context, index),
            child: Image.network(
              photos[index].url,
              fit: BoxFit.cover,
              cacheWidth: 360,
              loadingBuilder:
                  (
                    BuildContext context,
                    Widget child,
                    ImageChunkEvent? progress,
                  ) => progress == null
                      ? child
                      : Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value:
                                  progress.expectedTotalBytes == null
                                  ? null
                                  : progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!,
                            ),
                          ),
                        ),
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) =>
                      Center(
                        child: Icon(
                          LucideIcons.imageOff,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── 信息 ─────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.task});

  final TaskDetail task;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final ColorScheme scheme = theme.colorScheme;

    final List<Widget> rows = <Widget>[
      _InfoRow(
        icon: LucideIcons.calendarClock,
        label: '发生时间',
        value: formatBackendTime(task.gmtHappen),
      ),
      _InfoRow(
        icon: LucideIcons.alarmClock,
        label: '截止时间',
        value: formatBackendTime(task.deadline),
        valueColor: task.overtime ? AppColors.danger : null,
        trailing: task.overtime ? '已超时' : null,
      ),
      _InfoRow(
        icon: LucideIcons.hourglass,
        label: '处理耗时',
        value: task.timeUsageSolved.isEmpty ? '—' : task.timeUsageSolved,
        trailing: task.state.isOpen ? '进行中' : null,
      ),
      _InfoRow(
        icon: LucideIcons.bell,
        label: '提醒',
        value: RemindOption.labelOf(task.remind),
      ),
      if (task.errorUnit.isNotEmpty)
        _InfoRow(
          icon: LucideIcons.cpu,
          label: '异常单元',
          value: task.errorUnit,
        ),
      _InfoRow(
        icon: LucideIcons.userRound,
        label: '处理人',
        value: task.executor?.nickname ?? '未指派',
      ),
      _InfoRow(
        icon: LucideIcons.userPlus,
        label: '创建人',
        value: task.creator?.nickname ?? '—',
      ),
      _InfoRow(
        icon: LucideIcons.userCog,
        label: '站点负责人',
        value: task.stationManager?.nickname ?? '—',
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '任务信息',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              rows[i],
              if (i != rows.length - 1)
                Divider(height: 1, color: scheme.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: text.labelSmall?.copyWith(color: AppColors.danger),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── 处理结果 ─────────────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.task});

  final TaskDetail task;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final ColorScheme scheme = theme.colorScheme;
    final Map<String, List<TaskPhoto>> grouped = task.submitPicturesByTitle;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(LucideIcons.clipboardCheck, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '处理结果',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (task.causedByProduct != null)
                  StatusPill(
                    status: task.causedByProduct! ? '产品原因' : '非产品原因',
                  ),
              ],
            ),
            if (task.reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _LabeledText(label: '故障原因', value: task.reason),
            ],
            if (task.solution.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _LabeledText(label: '解决办法', value: task.solution),
            ],
            if (task.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _LabeledText(label: '处理备注', value: task.description),
            ],
            for (final MapEntry<String, List<TaskPhoto>> entry
                in grouped.entries) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text(
                    entry.key,
                    style: text.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.value.length}',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PhotoGrid(photos: entry.value, title: entry.key),
            ],
            if (task.gmtSolved != null) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Icon(
                    LucideIcons.circleCheck,
                    size: 14,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '处理完成于 ${formatBackendTime(task.gmtSolved)}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: text.bodyMedium?.copyWith(height: 1.55)),
      ],
    );
  }
}

// ───────────────────────────── 进度 ─────────────────────────────

class _ProgressSection extends ConsumerWidget {
  const _ProgressSection({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskLogEntry>> logs = ref.watch(
      taskLogProvider(taskId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(title: '处理进度'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: logs.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (Object error, StackTrace stack) => Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      error is AppException ? error.userMessage : '进度加载失败',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(taskLogProvider(taskId)),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (List<TaskLogEntry> list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '暂无操作记录',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Column(
                      children: <Widget>[
                        for (int i = 0; i < list.length; i++)
                          _LogTile(
                            entry: list[i],
                            isLast: i == list.length - 1,
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry, required this.isLast});

  final TaskLogEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final bool first = entry.stateLabel == '待处理';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: first ? scheme.outline : scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 10 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.content,
                    style: text.bodyMedium?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${entry.user?.nickname ?? '系统'} · '
                    '${formatBackendShort(entry.time)}',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

// ───────────────────────────── 已读 / 互动 ─────────────────────────────

class _EngagementCard extends ConsumerWidget {
  const _EngagementCard({required this.task, required this.taskId});

  final TaskDetail task;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final AsyncValue<List<TaskReader>> readers = ref.watch(
      taskReadersProvider(taskId),
    );
    final List<TaskReader> list = readers.asData?.value ?? const <TaskReader>[];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: list.isEmpty
              ? null
              : () => _showReadersSheet(context, list),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(
                  LucideIcons.eye,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('已读', style: text.bodyMedium),
                const SizedBox(width: 6),
                Text(
                  '${list.length}',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
                const Spacer(),
                if (list.isNotEmpty)
                  SizedBox(
                    height: 26,
                    width: (list.length.clamp(1, 4) * 20 + 12).toDouble(),
                    child: Stack(
                      children: <Widget>[
                        for (int i = list.length.clamp(1, 4) - 1; i >= 0; i--)
                          Positioned(
                            left: i * 20,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 2,
                                ),
                              ),
                              child: AppAvatar(
                                label: list[i].name,
                                size: 26,
                                radius: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _showReadersSheet(
    BuildContext context,
    List<TaskReader> readers,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '已读人员 · ${readers.length}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: readers.length,
              itemBuilder: (BuildContext context, int index) {
                final TaskReader reader = readers[index];
                return ListTile(
                  leading: AppAvatar(label: reader.name, size: 36, radius: 12),
                  title: Text(reader.name),
                  subtitle: Text(formatBackendTime(reader.time)),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _CommentPreview extends ConsumerWidget {
  const _CommentPreview({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskComment>> comments = ref.watch(
      taskCommentsProvider(taskId),
    );
    final List<TaskComment> list =
        comments.asData?.value ?? const <TaskComment>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: '评论${list.isEmpty ? '' : ' · ${list.length}'}',
          actionLabel: list.isEmpty ? null : '全部',
          onAction: list.isEmpty
              ? null
              : () => showCommentSheet(
                  context,
                  comments: taskCommentsProvider(taskId),
                  onSubmit: (String text) => ref
                      .read(taskActionServiceProvider)
                      .addComment(taskId, text),
                ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: comments.isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : list.isEmpty
                ? InkWell(
                    onTap: () => showCommentSheet(
                  context,
                  comments: taskCommentsProvider(taskId),
                  onSubmit: (String text) => ref
                      .read(taskActionServiceProvider)
                      .addComment(taskId, text),
                ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            LucideIcons.messageCirclePlus,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '还没有评论，说点什么',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final TaskComment comment in list.take(2))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              AppAvatar(
                                label: comment.person?.nickname ?? '?',
                                size: 30,
                                radius: 10,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            comment.person?.nickname ?? '未知用户',
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          formatBackendFriendly(
                                            comment.time,
                                            empty: '',
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      comment.content,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(height: 1.45),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── 底部操作 ─────────────────────────────

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.task, required this.taskId});

  final TaskDetail task;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AsyncValue<List<TaskComment>> likes = ref.watch(
      taskLikesProvider(taskId),
    );
    final List<TaskComment> likeList =
        likes.asData?.value ?? const <TaskComment>[];
    final String? myId = ref.watch(authProvider).asData?.value.user?.id;
    final bool liked = likeList.any(
      (TaskComment c) => myId != null && '${c.creatorId}' == myId,
    );

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: <Widget>[
            _IconAction(
              icon: LucideIcons.thumbsUp,
              active: liked,
              label: '${likeList.length}',
              onTap: () => _toggleLike(context, ref),
            ),
            _IconAction(
              icon: LucideIcons.messageCircle,
              label: '评论',
              onTap: () => showCommentSheet(
                  context,
                  comments: taskCommentsProvider(taskId),
                  onSubmit: (String text) => ref
                      .read(taskActionServiceProvider)
                      .addComment(taskId, text),
                ),
            ),
            const SizedBox(width: 6),
            Expanded(child: _primaryButton(context, ref)),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(taskActionServiceProvider).toggleLike(taskId);
      if (!context.mounted) return;
      ref.invalidate(taskLikesProvider(taskId));
    } on AppException catch (error) {
      if (context.mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (context.mounted) showToast(context, '操作失败：$error');
    }
  }

  Widget _primaryButton(BuildContext context, WidgetRef ref) {
    final TaskAction? action = primaryTaskAction(task);
    if (action == null) {
      // 不可操作时不再是「点了没反应」或直接消失，而是置灰 + 说明原因（M3-06）
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        child: Text(blockedReasonOf(task)),
      );
    }
    if (action.key == 'submit') {
      return FilledButton.icon(
        onPressed: () => _openProcess(context, ref),
        icon: const Icon(LucideIcons.wrench, size: 18),
        label: Text(action.label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => _showReviewSheet(context, ref),
      icon: const Icon(LucideIcons.badgeCheck, size: 18),
      label: Text(action.label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
      ),
    );
  }

  Future<void> _openProcess(BuildContext context, WidgetRef ref) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => HandleTaskPage(task: task),
      ),
    );
    if (changed == true && context.mounted) {
      ref.invalidate(taskDetailProvider(taskId));
      ref.invalidate(taskLogProvider(taskId));
      await ref.read(taskListProvider(TaskCategory.abnormal).notifier).refresh();
    }
  }

  Future<void> _showReviewSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  '审核处理结果',
                  style: Theme.of(sheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: AppColors.successContainer,
                leading: const Icon(
                  LucideIcons.badgeCheck,
                  color: AppColors.success,
                ),
                title: const Text('确认通过'),
                subtitle: const Text('问题已解决，关闭这条异常'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _confirm(context, ref);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: AppColors.dangerContainer,
                leading: const Icon(
                  LucideIcons.circleX,
                  color: AppColors.danger,
                ),
                title: const Text('拒绝修复'),
                subtitle: const Text('问题仍在，退回处理人继续跟进'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _reject(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认关闭异常？'),
        content: const Text('关闭后该异常不再出现在待处理列表，处理人也会收到通知。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认关闭'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(taskActionServiceProvider).confirm(taskId);
      if (!context.mounted) return;
      ref.invalidate(taskDetailProvider(taskId));
      ref.invalidate(taskLogProvider(taskId));
      await ref.read(taskListProvider(TaskCategory.abnormal).notifier).refresh();
      if (context.mounted) showToast(context, '异常已关闭');
    } on AppException catch (error) {
      if (context.mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (context.mounted) showToast(context, '操作失败：$error');
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final String? reason = await _askReason(
      context,
      title: '拒绝修复',
      hint: '说明问题为什么还没解决（必填）',
      confirmLabel: '确认拒绝',
    );
    if (reason == null || !context.mounted) return;

    try {
      await ref.read(taskActionServiceProvider).reject(taskId, reason);
      if (!context.mounted) return;
      ref.invalidate(taskDetailProvider(taskId));
      ref.invalidate(taskLogProvider(taskId));
      await ref.read(taskListProvider(TaskCategory.abnormal).notifier).refresh();
      if (context.mounted) showToast(context, '已拒绝，任务退回处理人');
    } on AppException catch (error) {
      if (context.mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (context.mounted) showToast(context, '操作失败：$error');
    }
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    this.label,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = active ? AppColors.brand : scheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            if (label != null) ...<Widget>[
              const SizedBox(height: 1),
              Text(
                label!,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 更多操作 ─────────────────────────────

Future<void> _showMoreSheet(
  BuildContext context,
  WidgetRef ref,
  TaskDetail task,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (BuildContext sheetContext) {
    // 主按钮已经承担「处理 / 审核」，这里列出其余动作。
    // 不可用的动作**不隐藏**而是置灰 + 给出原因，用户才知道差在哪（M3-06）。
    final List<TaskAction> actions = taskActionsFor(task)
        .where((TaskAction a) => a.key != 'submit' && a.key != 'confirm')
        .toList(growable: false);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(LucideIcons.copy, size: 20),
            title: const Text('复制记录编号'),
            subtitle: Text(
              task.jobNumber.isEmpty ? '${task.id}' : task.jobNumber,
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await Clipboard.setData(
                ClipboardData(
                  text: task.jobNumber.isEmpty ? '${task.id}' : task.jobNumber,
                ),
              );
              if (context.mounted) showToast(context, '已复制');
            },
          ),
          for (final TaskAction action in actions)
            ListTile(
              enabled: action.enabled,
              leading: Icon(
                _actionIcon(action.key),
                size: 20,
                color: action.enabled && action.danger
                    ? AppColors.danger
                    : null,
              ),
              title: Text(action.label),
              subtitle: Text(action.reason),
              onTap: !action.enabled
                  ? null
                  : () async {
                      Navigator.of(sheetContext).pop();
                      if (action.key == 'terminate') {
                        await _terminate(context, ref, task);
                      }
                      if (action.key == 'transfer' && context.mounted) {
                        await showTransferSheet(context, ref: ref, task: task);
                      }
                    },
            ),
        ],
      ),
    );
  },
);

IconData _actionIcon(String key) => switch (key) {
  'terminate' => LucideIcons.ban,
  'transfer' => LucideIcons.arrowRightLeft,
  'edit' => LucideIcons.pencil,
  _ => LucideIcons.moreHorizontal,
};

Future<void> _terminate(
  BuildContext context,
  WidgetRef ref,
  TaskDetail task,
) async {
  final String? reason = await _askReason(
    context,
    title: '终止任务',
    hint: '说明终止原因（必填）',
    confirmLabel: '确认终止',
    danger: true,
  );
  if (reason == null || !context.mounted) return;

  try {
    await ref.read(taskActionServiceProvider).terminate('${task.id}', reason);
    if (!context.mounted) return;
    ref.invalidate(taskDetailProvider('${task.id}'));
    ref.invalidate(taskLogProvider('${task.id}'));
    await ref.read(taskListProvider(TaskCategory.abnormal).notifier).refresh();
    if (context.mounted) showToast(context, '任务已终止');
  } on AppException catch (error) {
    if (context.mounted) showToast(context, error.userMessage);
  } catch (error) {
    if (context.mounted) showToast(context, '操作失败：$error');
  }
}

/// 需要一个「必填理由」的确认框，终止与拒绝共用。
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  bool danger = false,
}) {
  final TextEditingController controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () {
            final String text = controller.text.trim();
            if (text.isEmpty) {
              showToast(dialogContext, '请填写原因');
              return;
            }
            Navigator.of(dialogContext).pop(text);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
