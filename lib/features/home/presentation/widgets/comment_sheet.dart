import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/api_response.dart';
import '../../../../shared/utils/backend_time.dart';
import '../../../../shared/utils/toast.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/models/task_activity.dart';

/// 评论面板（M3-03 / M5-03）：异常与签到共用。
///
/// 面板本身不关心评论挂在哪种业务上，由调用方传入「评论数据源 Provider」
/// 与「发布评论的动作」；`itemType`（任务 1 / 签到 2）的差异封装在各自的
/// repository 里，避免面板里出现业务分支。
Future<void> showCommentSheet(
  BuildContext context, {
  required FutureProvider<List<TaskComment>> comments,
  required Future<void> Function(String content) onSubmit,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    ),
    child: _CommentSheet(comments: comments, onSubmit: onSubmit),
  ),
);

class _CommentSheet extends ConsumerStatefulWidget {
  const _CommentSheet({required this.comments, required this.onSubmit});

  final FutureProvider<List<TaskComment>> comments;
  final Future<void> Function(String content) onSubmit;

  @override
  ConsumerState<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends ConsumerState<_CommentSheet> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSubmit(text);
      if (!mounted) return;
      _input.clear();
      _focus.unfocus();
      ref.invalidate(widget.comments);
      showToast(context, '评论已发布');
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (mounted) showToast(context, '发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskComment>> comments = ref.watch(widget.comments);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: <Widget>[
                Text(
                  '评论',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${comments.asData?.value.length ?? 0}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: comments.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object error, StackTrace stack) => EmptyState(
                icon: LucideIcons.triangleAlert,
                title: '评论加载失败',
                message: error is AppException ? error.userMessage : '请稍后重试',
                actionLabel: '重试',
                onAction: () =>
                    ref.invalidate(widget.comments),
              ),
              data: (List<TaskComment> list) => list.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.messageCircle,
                      title: '还没有评论',
                      message: '说点什么，处理进展让相关同事都能看到',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (BuildContext context, int index) =>
                          _CommentTile(comment: list[index]),
                    ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '写下评论…',
                        isDense: true,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(22)),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.send, size: 18),
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
        AppAvatar(label: name, size: 34, radius: 11),
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
                    formatBackendFriendly(comment.time, empty: ''),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                comment.content,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
