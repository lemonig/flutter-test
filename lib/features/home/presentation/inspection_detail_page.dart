import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/photo_viewer_page.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/ops_detail.dart';
import '../data/models/task_activity.dart';
import '../data/models/task_detail.dart';
import '../data/repositories/ops_detail_repository.dart';
import '../providers/ops_detail_providers.dart';
import 'widgets/comment_sheet.dart';

/// 巡检详情（M4-01 / M4-03 / M4-04）。
///
/// 对应原工程 `InspectionDetailController`：头部是「站点 / 编号 / 项目数 /
/// 处理人 / 时间」，中间是按单元分组的巡检项，底部是评论与点赞。
///
/// 与原工程的两处差异，都以后端为准：
/// - 巡检项没有「正常 / 异常 / 不适用」三态，完成度由**备注 + 照片**表达；
/// - 填报入口走独立页面（M4-02），提交前必须过 `opsrecord/submit/check`
///   的站内校验，站房外会直接失败。
class InspectionDetailPage extends ConsumerWidget {
  const InspectionDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<OpsDetail> detail = ref.watch(opsDetailProvider(recordId));

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('巡检详情'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          if (detail.asData?.value.auth.canOperate ?? false)
            _MoreMenu(detail: detail.asData!.value),
        ],
      ),
      bottomNavigationBar: _ActionBar(recordId: recordId, detail: detail.asData?.value),
      body: detail.when(
        loading: () => const SkeletonList(count: 3),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.cloudOff,
          title: '巡检详情加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重新加载',
          onAction: () => ref.invalidate(opsDetailProvider(recordId)),
        ),
        data: (OpsDetail data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(opsDetailProvider(recordId));
            await ref.read(opsDetailProvider(recordId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              _HeroCard(detail: data),
              const SizedBox(height: 16),
              SectionHeader(
                title: '巡检项',
                actionLabel: '已完成 ${data.doneCount}/${data.items.length}',
              ),
              const SizedBox(height: 10),
              for (final OpsGroup group in data.groups) ...<Widget>[
                _ItemGroupCard(group: group),
                const SizedBox(height: 10),
              ],
              if (data.description.trim().isNotEmpty ||
                  data.pictures.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                _NoteSection(detail: data),
              ],
              const SizedBox(height: 16),
              _CommentPreview(recordId: recordId),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.detail});

  final OpsDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.ellipsisVertical),
      onSelected: (String value) {
        switch (value) {
          case 'submit':
            context.push('/inspection/${detail.id}/submit');
          case 'terminate':
            _confirmTerminate(context, ref);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (detail.auth.canSubmit)
          const PopupMenuItem<String>(
            value: 'submit',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(LucideIcons.clipboardPen, size: 18),
              title: Text('填报任务'),
            ),
          ),
        if (detail.auth.canTerminate)
          const PopupMenuItem<String>(
            value: 'terminate',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(LucideIcons.ban, size: 18),
              title: Text('终止任务'),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmTerminate(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('终止巡检任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('终止后该任务不可再填报，需要说明原因：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如：站点改造停运，本期巡检取消',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认终止'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final String reason = controller.text.trim();
    if (reason.isEmpty) {
      if (context.mounted) showToast(context, '请填写终止原因');
      return;
    }
    try {
      await ref
          .read(opsDetailRepositoryProvider)
          .terminate(detail.id, reason);
      ref.invalidate(opsDetailProvider(detail.id));
      if (context.mounted) showToast(context, '任务已终止');
    } on AppException catch (error) {
      if (context.mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (context.mounted) showToast(context, '终止失败：$error');
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.detail});

  final OpsDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String station = detail.stationName.isEmpty ? '未关联站点' : detail.stationName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppAvatar(
                label: station,
                icon: LucideIcons.building2,
                size: 44,
                radius: 14,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      station,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail.stationAddress.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        detail.stationAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(status: detail.statusText),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          _KvRow(label: '编号', value: detail.jobNumber.isEmpty ? '—' : detail.jobNumber),
          _KvRow(label: '巡检项目', value: '${detail.itemSize} 条'),
          _KvRow(label: '处理人员', value: detail.executorName),
          _KvRow(label: '站点负责人', value: detail.stationManagerName),
          _KvRow(label: '创建时间', value: detail.createText),
          _KvRow(label: '截止时间', value: detail.deadlineText),
          if (detail.done) _KvRow(label: '完成时间', value: detail.finishText),
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemGroupCard extends StatelessWidget {
  const _ItemGroupCard({required this.group});

  final OpsGroup group;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                group.category,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.doneCount}/${group.items.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final OpsItemDetail item in group.items)
            _ItemTile(item: item),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final OpsItemDetail item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> urls = item.photos
        .map((TaskPhoto photo) => photo.url)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  item.done
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circle,
                  size: 16,
                  color: item.done
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
              if (item.requirePhoto)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 1),
                  child: _Chip(text: '需拍照', tone: Tone.warning),
                ),
            ],
          ),
          if (item.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Text(
                item.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          if (urls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 8),
              child: SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: urls.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) =>
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => PhotoViewerPage(
                              images: urls,
                              initialIndex: index,
                              title: item.name,
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            urls[index],
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (
                                  BuildContext context,
                                  Object error,
                                  StackTrace? _,
                                ) => Container(
                                  width: 64,
                                  height: 64,
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    LucideIcons.imageOff,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                          ),
                        ),
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteSection extends StatelessWidget {
  const _NoteSection({required this.detail});

  final OpsDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> urls = detail.pictures
        .map((TaskPhoto photo) => photo.url)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                LucideIcons.penLine,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('巡检备注', style: theme.textTheme.labelLarge),
            ],
          ),
          if (detail.description.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              detail.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
          if (urls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: urls.length,
              itemBuilder: (BuildContext context, int index) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => PhotoViewerPage(
                      images: urls,
                      initialIndex: index,
                      title: '巡检备注照片',
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[index],
                    fit: BoxFit.cover,
                    errorBuilder:
                        (BuildContext context, Object error, StackTrace? _) =>
                            Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                LucideIcons.imageOff,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentPreview extends ConsumerWidget {
  const _CommentPreview({required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskComment>> comments = ref.watch(
      opsCommentsProvider(recordId),
    );
    final List<TaskComment> list = comments.asData?.value ?? const <TaskComment>[];

    void open() => showCommentSheet(
      context,
      comments: opsCommentsProvider(recordId),
      onSubmit: (String text) =>
          ref.read(opsDetailRepositoryProvider).addComment(recordId, text),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: '评论${list.isEmpty ? '' : ' · ${list.length}'}',
          actionLabel: list.isEmpty ? null : '全部',
          onAction: list.isEmpty ? null : open,
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: comments.isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
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
                  onTap: open,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          LucideIcons.messageCirclePlus,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '还没有评论，点这里说点什么',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  itemCount: list.length > 3 ? 3 : list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (BuildContext context, int index) {
                    final TaskComment comment = list[index];
                    final String name = comment.person?.nickname ?? '未知用户';
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppAvatar(label: name, size: 32, radius: 10),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    formatCommentTime(comment.time),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                comment.content,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.recordId, required this.detail});

  final String recordId;
  final OpsDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskComment>> likes = ref.watch(
      opsLikesProvider(recordId),
    );
    final List<TaskComment> likeList = likes.asData?.value ?? const <TaskComment>[];
    final String? myId = ref.watch(authProvider).asData?.value.user?.id;
    final bool liked = likeList.any(
      (TaskComment c) => myId != null && '${c.creatorId}' == myId,
    );
    final bool canSubmit = detail?.auth.canSubmit ?? false;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
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
                comments: opsCommentsProvider(recordId),
                onSubmit: (String text) => ref
                    .read(opsDetailRepositoryProvider)
                    .addComment(recordId, text),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: canSubmit
                  ? FilledButton.icon(
                      onPressed: () => context.push(
                        '/inspection/$recordId/submit',
                      ),
                      icon: const Icon(LucideIcons.clipboardPen, size: 18),
                      label: const Text('填报巡检'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: recordId),
                        );
                        if (context.mounted) showToast(context, '巡检编号已复制');
                      },
                      icon: const Icon(LucideIcons.hash, size: 18),
                      label: Text(
                        detail == null ? '复制编号' : '${detail!.statusText} · 复制编号',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(opsDetailRepositoryProvider).toggleLike(recordId);
      ref.invalidate(opsLikesProvider(recordId));
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
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.tone});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: tone.onBackground),
      ),
    );
  }
}
