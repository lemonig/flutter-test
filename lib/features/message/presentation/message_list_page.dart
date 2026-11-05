import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_response.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../home/data/models/task_item.dart';
import '../data/models/message_models.dart';
import '../providers/message_providers.dart';

/// 某个消息分类的明细列表。
///
/// 后端在 `message/type` 里把这批消息整体置为已读，所以进页面就会清角标；
/// 转交任务（type=3）额外给出同意 / 拒绝，处置后不可再改。
class MessageListPage extends ConsumerStatefulWidget {
  const MessageListPage({super.key, required this.type});

  final MessageType type;

  @override
  ConsumerState<MessageListPage> createState() => _MessageListPageState();
}

class _MessageListPageState extends ConsumerState<MessageListPage> {
  final ScrollController _scroll = ScrollController();
  bool _unreadRefreshed = false;

  /// 正在处置的转交消息 id，避免重复点击。
  int? _respondingId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      ref.read(messageListProvider(widget.type).notifier).loadMore();
    }
  }

  /// 首次拿到数据后刷新一次未读口径（分类角标 + 底部导航角标）。
  ///
  /// 放在 build 之外的监听里做，避免在 build 期间改别的 provider。
  void _markUnreadRefreshedIfNeeded() {
    if (_unreadRefreshed) return;
    if (!ref.read(messageListProvider(widget.type)).hasValue) return;
    _unreadRefreshed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refreshMessageUnread(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MessageListState> list = ref.watch(
      messageListProvider(widget.type),
    );
    _markUnreadRefreshedIfNeeded();

    return Scaffold(
      appBar: AppBar(title: Text(widget.type.defaultName)),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref
                .read(messageListProvider(widget.type).notifier)
                .refresh();
          } catch (error) {
            if (context.mounted) showToast(context, '刷新失败：$error');
          }
        },
        child: AsyncValueView<MessageListState>(
          value: list,
          errorTitle: '消息加载失败',
          onRetry: () => ref.invalidate(messageListProvider(widget.type)),
          builder: (MessageListState state) {
            if (state.items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.only(top: 80),
                children: <Widget>[
                  EmptyState(
                    icon: widget.type.icon,
                    tone: widget.type.tone,
                    title: '暂无${widget.type.defaultName}',
                    message: widget.type.isTransfer
                        ? '有任务转交给你时会在这里提醒'
                        : '有新消息时会在这里提醒',
                  ),
                ],
              );
            }
            return ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final MessageItem item = state.items[index];
                return _MessageCard(
                  item: item,
                  responding: _respondingId == item.id,
                  onTap: () => _openTarget(item),
                  onAccept: item.isPendingTransfer
                      ? () => _respond(item, accepted: true)
                      : null,
                  onReject: item.isPendingTransfer
                      ? () => _respond(item, accepted: false)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// 点卡片：异常 / 巡检直接进详情；申请、审批、评论、赞没有独立详情页。
  void _openTarget(MessageItem item) {
    final TaskCategory? category = item.taskCategory;
    if (category != null && item.jobId != null) {
      context.push(detailPathFor(category, '${item.jobId}'));
      return;
    }
    showToast(context, switch (item.type) {
      MessageType.apply => '申请详情请在「信息填报」里查看',
      MessageType.approve => '审批详情请在「工作台」里查看',
      _ => '该消息没有可跳转的详情',
    });
  }

  Future<void> _respond(MessageItem item, {required bool accepted}) async {
    final String action = accepted ? '同意' : '拒绝';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: Icon(
          accepted ? LucideIcons.checkCheck : LucideIcons.x,
          color: accepted ? AppColors.success : AppColors.danger,
        ),
        title: Text('$action转交任务'),
        content: Text(
          accepted
              ? '同意后这条任务会转由你处理，原处理人会收到通知。\n\n请确认你有条件按时完成。'
              : '拒绝后任务会退回原处理人，需要对方另行转交。\n\n处置结果不可撤回。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: accepted
                ? null
                : FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _respondingId = item.id);
    try {
      await ref
          .read(messageListProvider(widget.type).notifier)
          .respondTransfer(item, accepted: accepted);
      if (!mounted) return;
      showToast(context, accepted ? '已同意，任务已转给你' : '已拒绝，任务已退回');
      refreshMessageUnread(ref);
    } on AppException catch (error) {
      // 后端 `MessageTransferValidator` 的原文最有信息量（消息不存在 /
      // 消息无法变更状态 / 无权限操作），直接透出。
      if (mounted) showToast(context, error.userMessage);
      if (mounted) {
        await ref.read(messageListProvider(widget.type).notifier).refresh();
      }
    } catch (error) {
      if (mounted) showToast(context, '操作失败：$error');
    } finally {
      if (mounted) setState(() => _respondingId = null);
    }
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.item,
    required this.onTap,
    required this.responding,
    this.onAccept,
    this.onReject,
  });

  final MessageItem item;
  final VoidCallback onTap;
  final bool responding;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool pending = item.isPendingTransfer;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppAvatar(
                    label: item.type.defaultName,
                    icon: item.type.icon,
                    tone: item.type.tone,
                    size: 40,
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
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: pending
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.timeText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (item.content.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                            item.content,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                        if (item.leftLabel.isNotEmpty ||
                            item.rightLabel.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: <Widget>[
                              if (item.leftLabel.isNotEmpty)
                                _MetaText(text: item.leftLabel),
                              if (item.rightLabel.isNotEmpty)
                                _MetaText(text: item.rightLabel),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (item.type.isTransfer) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    StatusPill(status: item.transferResultLabel, compact: true),
                    const Spacer(),
                    if (pending) ...<Widget>[
                      OutlinedButton(
                        onPressed: responding ? null : onReject,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.danger,
                        ),
                        child: const Text('拒绝'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: responding ? null : onAccept,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: responding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('同意'),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
