import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../auth/providers/auth_provider.dart';
import '../data/models/attend_detail.dart';
import '../data/models/task_activity.dart';
import '../data/models/task_detail.dart';
import '../data/repositories/attend_detail_repository.dart';
import '../providers/attend_detail_providers.dart';
import 'widgets/comment_sheet.dart';

/// 签到详情（M5-03）。
///
/// 对应原工程 `SignInDetailController` + `SignInDetailHeaderView`：
/// 头部是「站点 / 签到人 / 时间 / 位置 / 照片」，底部是评论与点赞。
///
/// 地图可视化依赖 M0-07（D3 定高德，Key 未申请），当前用「地址 + 经纬度」
/// 表达签到点，坐标可一键复制给同事核对；`station` 为空的记录也能正常展示。
class AttendDetailPage extends ConsumerWidget {
  const AttendDetailPage({super.key, required this.attendId});

  final String attendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<AttendDetail> detail = ref.watch(
      attendDetailProvider(attendId),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('签到详情'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBar: _ActionBar(attendId: attendId),
      body: detail.when(
        loading: () => const SkeletonList(count: 3),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.cloudOff,
          title: '签到详情加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重新加载',
          onAction: () => ref.invalidate(attendDetailProvider(attendId)),
        ),
        data: (AttendDetail data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(attendDetailProvider(attendId));
            await ref.read(attendDetailProvider(attendId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              _HeroCard(detail: data),
              const SizedBox(height: 12),
              _LocationCard(detail: data),
              if (data.description.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _NoteCard(text: data.description),
              ],
              if (data.pictures.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                SectionHeader(
                  title: '现场照片',
                  actionLabel: '${data.pictures.length} 张',
                ),
                const SizedBox(height: 10),
                _PhotoGrid(pictures: data.pictures),
              ],
              const SizedBox(height: 16),
              _CommentPreview(attendId: attendId),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.detail});

  final AttendDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String station = detail.stationName.isEmpty
        ? '未关联站点'
        : detail.stationName;

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
                icon: LucideIcons.mapPin,
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.timeText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _Tag(text: '已签到', tone: Tone.success),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: <Widget>[
              AppAvatar(label: detail.personName, size: 32, radius: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Text(detail.personName, style: theme.textTheme.bodyMedium),
              ),
              Text(
                detail.jobNumber.isEmpty ? '单号待生成' : detail.jobNumber,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.detail});

  final AttendDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                LucideIcons.mapPinCheckInside,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('签到位置', style: theme.textTheme.labelLarge),
              const Spacer(),
              if (detail.hasCoordinate)
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: detail.coordinateLabel),
                    );
                    if (context.mounted) {
                      showToast(context, '坐标已复制');
                    }
                  },
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: const Text('复制'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail.address.trim().isEmpty ? '未获取到地址' : detail.address,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  LucideIcons.crosshair,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail.hasCoordinate
                        ? '经度 ${detail.longitude!.toStringAsFixed(6)}　'
                              '纬度 ${detail.latitude!.toStringAsFixed(6)}'
                        : '未记录坐标',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (detail.stationName.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '签到时匹配到站点「${detail.stationName}」，坐标与站点位置一致才允许提交',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
              Text('备注', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.pictures});

  final List<TaskPhoto> pictures;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> urls = pictures
        .map((TaskPhoto p) => p.url)
        .toList(growable: false);

    return GridView.builder(
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
              title: '现场照片',
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            urls[index],
            fit: BoxFit.cover,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
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
    );
  }
}

class _CommentPreview extends ConsumerWidget {
  const _CommentPreview({required this.attendId});

  final String attendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskComment>> comments = ref.watch(
      attendCommentsProvider(attendId),
    );
    final List<TaskComment> list =
        comments.asData?.value ?? const <TaskComment>[];

    void open() => showCommentSheet(
      context,
      comments: attendCommentsProvider(attendId),
      onSubmit: (String text) => ref
          .read(attendDetailRepositoryProvider)
          .addComment(attendId, text),
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
                  itemBuilder: (BuildContext context, int index) =>
                      _CommentTile(comment: list[index]),
                ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final TaskComment comment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
                      style: theme.textTheme.labelLarge?.copyWith(
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
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.attendId});

  final String attendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskComment>> likes = ref.watch(
      attendLikesProvider(attendId),
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
                comments: attendCommentsProvider(attendId),
                onSubmit: (String text) => ref
                    .read(attendDetailRepositoryProvider)
                    .addComment(attendId, text),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: attendId),
                  );
                  if (context.mounted) showToast(context, '签到编号已复制');
                },
                icon: const Icon(LucideIcons.hash, size: 18),
                label: const Text('复制编号'),
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
      await ref
          .read(attendDetailRepositoryProvider)
          .toggleLike(attendId);
      ref.invalidate(attendLikesProvider(attendId));
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

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: tone.onBackground),
      ),
    );
  }
}
