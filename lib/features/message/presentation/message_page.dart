import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/models/message_models.dart';
import '../providers/message_providers.dart';

/// 消息 Tab：七个分类（异常/巡检/转交/评论/赞/申请/审批）+ 未读汇总。
///
/// 七个分类是固定的（后端 `PushMessageEnum`），没有消息的分类也照常展示，
/// 只把副标题写成「暂无消息」——和原 iOS / Android 一致：
/// 让用户知道「不是漏了，是确实没有」。
class MessagePage extends ConsumerWidget {
  const MessagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MessageCategory>> categories = ref.watch(
      messageCategoriesProvider,
    );
    final int unread = ref.watch(unreadMessageCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: <Widget>[
          IconButton(
            tooltip: '全部已读',
            onPressed: unread == 0
                ? null
                : () => _markAllRead(context, ref),
            icon: const Icon(LucideIcons.checkCheck),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(messageCategoriesProvider.notifier).refresh();
            ref.invalidate(serverUnreadCountProvider);
          } catch (error) {
            if (context.mounted) showToast(context, '刷新失败：$error');
          }
        },
        child: AsyncValueView<List<MessageCategory>>(
          value: categories,
          errorTitle: '消息加载失败',
          onRetry: () => ref.invalidate(messageCategoriesProvider),
          builder: (List<MessageCategory> data) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: data.length + 1,
            separatorBuilder: (BuildContext context, int index) =>
                SizedBox(height: index == 0 ? 14 : 10),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return _UnreadSummary(
                  unread: unread,
                  onMarkAllRead: () => _markAllRead(context, ref),
                );
              }
              final MessageCategory category = data[index - 1];
              return _CategoryTile(
                category: category,
                onTap: () {
                  // 进列表时后端会把该分类整体置为已读；本地先清角标，
                  // 免得用户返回后还看到一个红点。
                  ref
                      .read(messageCategoriesProvider.notifier)
                      .clearUnread(category.type);
                  context.push('/message/${category.type.code}');
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(messageCategoriesProvider.notifier).markAllRead();
      refreshMessageUnread(ref);
      if (context.mounted) showToast(context, '已全部标记为已读');
    } catch (error) {
      if (context.mounted) showToast(context, '操作失败：$error');
    }
  }
}

class _UnreadSummary extends StatelessWidget {
  const _UnreadSummary({required this.unread, required this.onMarkAllRead});

  final int unread;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasUnread = unread > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              hasUnread ? LucideIcons.inbox : LucideIcons.circleCheck,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hasUnread ? '$unread 条未读消息' : '消息已全部读完',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasUnread ? '点开分类即视为已读' : '有新的派发任务时会再次提醒',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasUnread)
            FilledButton.tonal(
              onPressed: onMarkAllRead,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.primary,
              ),
              child: const Text('全部已读'),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final MessageCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasUnread = category.hasUnread;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppAvatar(
                label: category.name,
                icon: category.type.icon,
                tone: category.type.tone,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category.latestTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            category.latestTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hasUnread
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ),
                        if (hasUnread) ...<Widget>[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Badge.count(
                              count: category.unread,
                              maxCount: 99,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
