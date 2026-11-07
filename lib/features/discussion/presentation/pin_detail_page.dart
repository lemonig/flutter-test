import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../home/data/models/task_activity.dart';
import '../data/models/pin_post.dart';
import '../providers/pin_providers.dart';
import 'discussion_page.dart';

/// 帖子详情（M8-03）：图文 + 点赞 + 评论。
///
/// 评论/点赞走通用家族（itemType=4）；评论输入直接用列表底部输入行
/// （与申请单详情一致），不再弹层 —— 帖子详情是主阅读场景，少一步操作。
class PinDetailPage extends ConsumerStatefulWidget {
  const PinDetailPage({super.key, required this.pinId});

  final int pinId;

  @override
  ConsumerState<PinDetailPage> createState() => _PinDetailPageState();
}

class _PinDetailPageState extends ConsumerState<PinDetailPage> {
  final TextEditingController _commentInput = TextEditingController();
  bool _sendingComment = false;
  bool _liking = false;

  String get _key => '${widget.pinId}';

  @override
  void dispose() {
    _commentInput.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final String text = _commentInput.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      await ref.read(pinActionServiceProvider).addComment(widget.pinId, text);
      _commentInput.clear();
      if (!mounted) return;
      showToast(context, '评论已发布');
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '发送失败：$e');
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      await ref.read(pinActionServiceProvider).toggleLike(widget.pinId);
      if (!mounted) return;
      showToast(context, '已点赞（再次点击取消）');
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '操作失败：$e');
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<PinPost> detail = ref.watch(pinDetailProvider(_key));
    final AsyncValue<List<TaskComment>> comments = ref.watch(
      pinCommentsProvider(_key),
    );
    final AsyncValue<List<TaskComment>> likes = ref.watch(
      pinLikesProvider(_key),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('帖子详情')),
      body: detail.when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.triangleAlert,
          title: '帖子加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重试',
          onAction: () => ref.invalidate(pinDetailProvider(_key)),
        ),
        data: (PinPost post) => Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              AppAvatar(
                                label: post.nickname,
                                size: 38,
                                radius: 12,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      post.nickname.isEmpty
                                          ? '匿名'
                                          : post.nickname,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      formatBackendFriendly(
                                        post.gmtCreate,
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
                              ),
                              if (post.channel.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    post.channel,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                          if (post.title.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              post.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (post.content.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              post.content,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.6,
                              ),
                            ),
                          ],
                          if (post.pictures.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            PinPhotoGrid(urls: post.pictures),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 互动条：点赞（含赞过的人列表摘要）+ 评论数
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: <Widget>[
                          IconButton.outlined(
                            onPressed: _liking ? null : _toggleLike,
                            icon: _liking
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.thumbsUp, size: 16),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '点赞 ${likes.asData?.value.length ?? post.likeCount}',
                            style: theme.textTheme.labelMedium,
                          ),
                          const Spacer(),
                          Icon(
                            LucideIcons.messageCircle,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '评论 ${comments.asData?.value.length ?? post.commentCount}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _CommentList(comments: comments.asData?.value),
                ],
              ),
            ),
            // 底部评论输入行
            SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _commentInput,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendComment(),
                        decoration: InputDecoration(
                          hintText: '写下评论…',
                          isDense: true,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: _sendingComment ? null : _sendComment,
                      icon: _sendingComment
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.send, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 评论列表（itemType=4 CommentVo，解析复用 home 的 TaskComment）。
class _CommentList extends StatelessWidget {
  const _CommentList({required this.comments});

  final List<TaskComment>? comments;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<TaskComment> list = comments ?? const <TaskComment>[];
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Text(
          '还没有评论',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(
            '全部评论（${list.length}）',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final TaskComment comment in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppAvatar(label: comment.person?.nickname ?? '?', size: 32),
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
                              style: theme.textTheme.labelMedium?.copyWith(
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
                      const SizedBox(height: 2),
                      Text(comment.content, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
