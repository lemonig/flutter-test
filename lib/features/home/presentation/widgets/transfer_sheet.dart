import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/api_response.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/utils/toast.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/models/task_detail.dart';
import '../../data/models/task_item.dart';
import '../../data/repositories/ops_user_repository.dart';
import '../../providers/home_providers.dart';
import '../../providers/task_detail_providers.dart';

/// 转交任务（C7）：从在职运维里选一位接收人。
///
/// 候选人来自 `POST user/ops/list`（服务端已过滤离职与非运维人员），
/// 客户端只补一条规则：不能转给自己 —— 后端 `TaskTransferValidator`
/// 同样校验，这里先挡一道，省一次注定失败的请求。
///
/// UI 风格对齐 [showCommentSheet]：可滚动面板 + 搜索框 + 空态重试。
Future<void> showTransferSheet(
  BuildContext context, {
  required WidgetRef ref,
  required TaskDetail task,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext sheetContext) => _TransferSheet(task: task),
);

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet({required this.task});

  final TaskDetail task;

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final TextEditingController _search = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _transferTo(OpsUser user) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('转交给 ${user.nickname}？'),
        content: const Text(
          '提交后对方会收到转交请求，接受前任务双方都不能处理。转交后不可撤回。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认转交'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref
          .read(taskActionServiceProvider)
          .transfer('${widget.task.id}', user.id);
      if (!mounted) return;
      ref.invalidate(taskDetailProvider('${widget.task.id}'));
      ref.invalidate(taskLogProvider('${widget.task.id}'));
      await ref.read(taskListProvider(TaskCategory.abnormal).notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, '已转交给${user.nickname}，等待对方接受');
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (mounted) showToast(context, '转交失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? myId = ref.watch(
      authProvider.select((AsyncValue<AuthState> state) {
        final AuthState? value = state.asData?.value;
        return value?.user?.id;
      }),
    );
    final AsyncValue<List<OpsUser>> candidates = ref.watch(
      transferCandidatesProvider(_keyword),
    );

    // 候选人排除自己；已转交过的任务服务端不会再放行，这里保持列表原样。
    final List<OpsUser> visible = candidates.asData?.value
        .where((OpsUser user) => user.id.toString() != myId)
        .toList(growable: false) ?? const <OpsUser>[];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '转交任务',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.task.stationName.isEmpty
                      ? '选择一位在职运维人员接收该任务'
                      : '${widget.task.stationName} · 选择一位在职运维人员接收',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              onChanged: (String value) => setState(() => _keyword = value),
              decoration: const InputDecoration(
                hintText: '搜索昵称 / 拼音 / 简拼',
                isDense: true,
                prefixIcon: Icon(LucideIcons.search, size: 18),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: candidates.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object error, StackTrace stack) => EmptyState(
                icon: LucideIcons.triangleAlert,
                title: '人员加载失败',
                message: error is AppException ? error.userMessage : '请稍后重试',
                actionLabel: '重试',
                onAction: () =>
                    ref.invalidate(transferCandidatesProvider(_keyword)),
              ),
              data: (List<OpsUser> list) => visible.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.users,
                      title: '没有匹配的运维人员',
                      message: '换个关键词试试，或确认对方已开通运维权限',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (BuildContext context, int index) {
                        final OpsUser user = visible[index];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: AppAvatar(label: user.nickname, size: 38),
                          title: Text(
                            user.nickname,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: user.firstChar.isEmpty
                              ? null
                              : Text(user.firstChar),
                          trailing: const Icon(
                            LucideIcons.chevronRight,
                            size: 18,
                          ),
                          onTap: () => _transferTo(user),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
