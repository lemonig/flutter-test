import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_response.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/workbench_models.dart';
import '../data/repositories/apply_repository.dart';
import '../providers/workbench_providers.dart';

/// 申请记录与审批（M7-08 ~ M7-10）。
///
/// 「我的申请」按类型筛选（family key 切换）；审批中心是待办 / 已办 /
/// 抄送三箱。详情页按身份出动作：申请人（审批中）可撤回，
/// 当前审批人（待审批）可通过或驳回 —— 与 `ApplyController` 语义一致。

// ───────────────────────────── 我的申请 ─────────────────────────────

class ApplyRecordsPage extends ConsumerStatefulWidget {
  const ApplyRecordsPage({super.key});

  @override
  ConsumerState<ApplyRecordsPage> createState() => _ApplyRecordsPageState();
}

class _ApplyRecordsPageState extends ConsumerState<ApplyRecordsPage> {
  /// 类型筛选：切换即换 family key（后端 apply/list 支持 type 参数），
  /// 纯 UI 状态，不必进 provider。
  ApplyType? _selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ApplyType? selected = _selected;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('我的申请')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: <Widget>[
                _FilterChip(
                  label: '全部',
                  selected: selected == null,
                  onTap: () => setState(() => _selected = null),
                ),
                for (final ApplyType type in ApplyType.values)
                  _FilterChip(
                    label: type.label,
                    selected: selected == type,
                    onTap: () => setState(() => _selected = type),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _ApplyListView(
              providerKey: selected == null
                  ? const ApplyListKey.my().value
                  : ApplyListKey.my(selected).value,
              isApprovalBox: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
        onSelected: (bool _) => onTap(),
        labelStyle: theme.textTheme.labelMedium,
      ),
    );
  }
}

// ───────────────────────────── 审批中心 ─────────────────────────────

class ApprovalCenterPage extends StatelessWidget {
  const ApprovalCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('审批中心'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '待我审批'),
              Tab(text: '已审批'),
              Tab(text: '我的抄送'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final ApplyBox box in ApplyBox.values)
              _ApplyListView(providerKey: box.name, isApprovalBox: true),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 列表体 ─────────────────────────────

class _ApplyListView extends ConsumerWidget {
  const _ApplyListView({required this.providerKey, required this.isApprovalBox});

  final String providerKey;
  final bool isApprovalBox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ApplyPageState> page = isApprovalBox
        ? ref.watch(approvalBoxProvider(providerKey))
        : ref.watch(myAppliesProvider(providerKey));

    Future<void> refresh() async => ref.invalidate(
      isApprovalBox
          ? approvalBoxProvider(providerKey)
          : myAppliesProvider(providerKey),
    );

    return page.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (Object error, StackTrace stack) => EmptyState(
        icon: LucideIcons.triangleAlert,
        title: '加载失败',
        message: error is AppException ? error.userMessage : '请稍后重试',
        actionLabel: '重试',
        onAction: refresh,
      ),
      data: (ApplyPageState state) {
        if (state.items.isEmpty) {
          return EmptyState(
            icon: isApprovalBox ? LucideIcons.inbox : LucideIcons.fileText,
            title: isApprovalBox ? '暂无待处理' : '还没有申请记录',
            message: isApprovalBox
                ? '有需要你审批的申请时会出现在这里'
                : '从工作台提交申请后可在这里跟踪进度',
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: state.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) => _ApplyCard(
              record: state.items[index],
              showApplicant: isApprovalBox,
            ),
          ),
        );
      },
    );
  }
}

Color _stateColor(ApplyState state, ColorScheme scheme) => switch (state) {
  ApplyState.approved => const Color(0xFF2E9E5B),
  ApplyState.rejected => AppColors.danger,
  ApplyState.withdrawn => scheme.onSurfaceVariant,
  _ => AppColors.warning,
};

class _ApplyCard extends StatelessWidget {
  const _ApplyCard({required this.record, this.showApplicant = false});

  final ApplyRecord record;
  final bool showApplicant;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String headline = switch (record.type) {
      ApplyType.fee => '¥${record.money?.toStringAsFixed(2) ?? '-'}',
      _ => record.items.isEmpty
          ? record.description
          : record.items
                .map((ApplyItem item) => '${item.itemName} ×${item.quantity}')
                .join('、'),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => ApplyDetailPage(record: record),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      record.type.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    record.stateLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _stateColor(record.state, theme.colorScheme),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  if (showApplicant && record.applicant != null) ...<Widget>[
                    Text(
                      record.applicant!.nickname,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      formatBackendFriendly(record.applyDate, empty: ''),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (record.canWithdraw)
                    Text(
                      '可撤回',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                      ),
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

// ───────────────────────────── 详情 ─────────────────────────────

class ApplyDetailPage extends ConsumerStatefulWidget {
  const ApplyDetailPage({super.key, required this.record});

  /// 列表带来的记录用于首屏；详情以接口返回为准（审批意见只在详情里）。
  final ApplyRecord record;

  @override
  ConsumerState<ApplyDetailPage> createState() => _ApplyDetailPageState();
}

class _ApplyDetailPageState extends ConsumerState<ApplyDetailPage> {
  bool _busy = false;
  bool _sendingComment = false;
  final TextEditingController _commentInput = TextEditingController();

  @override
  void dispose() {
    _commentInput.dispose();
    super.dispose();
  }

  String get _detailKey => '${widget.record.type.code}:${widget.record.id}';

  /// 发表申请单评论（itemType=5）。成功后失效详情与评论家族。
  Future<void> _sendComment() async {
    final String text = _commentInput.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      await ref
          .read(applyRepositoryProvider)
          .postApplyComment(widget.record.id, text);
      _commentInput.clear();
      if (!mounted) return;
      ref.invalidate(applyCommentsProvider(widget.record.id.toString()));
      showToast(context, '评论已发布');
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '发送失败：$e');
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action,
    String successToast,
  ) async {
    try {
      setState(() => _busy = true);
      await action();
      if (!mounted) return;
      ref.invalidate(applyDetailProvider(_detailKey));
      showToast(context, successToast);
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('撤回这份申请？'),
        content: const Text('撤回后审批人将不再处理，需要时可以重新提交。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(applyActionServiceProvider)
          .withdraw(widget.record.id, widget.record.type),
      '申请已撤回',
    );
  }

  Future<void> _approve() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('通过这份申请？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认通过'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(applyActionServiceProvider)
          .approve(widget.record.id, widget.record.type),
      '已通过',
    );
  }

  Future<void> _reject() async {
    final String? reason = await _askReason(
      context,
      title: '驳回申请',
      hint: '说明驳回原因（必填）',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => ref
          .read(applyActionServiceProvider)
          .reject(widget.record.id, widget.record.type, reason),
      '已驳回',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<ApplyRecord> detail = ref.watch(
      applyDetailProvider(_detailKey),
    );
    final ApplyRecord record = detail.asData?.value ?? widget.record;
    // 动作可见性：撤回是申请人（审批中）的能力；通过 / 驳回只给当前审批人。
    final String? myId = ref.watch(
      authProvider.select((AsyncValue<AuthState> state) {
        final AuthState? value = state.asData?.value;
        return value?.user?.id;
      }),
    );
    final bool showWithdraw = record.canWithdraw;
    final bool showApprove =
        record.canApprove &&
        record.approveUserId != null &&
        record.approveUserId.toString() == myId;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text('${record.type.label}详情')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Column(
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
                              Expanded(
                                child: Text(
                                  record.applyNumber.isEmpty
                                      ? '#${record.id}'
                                      : record.applyNumber,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                record.stateLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _stateColor(
                                    record.state,
                                    theme.colorScheme,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '申请于 ${formatBackendFriendly(record.applyDate, empty: '-')}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _Section(title: '申请内容'),
                  Card(
                    child: Column(
                      children: <Widget>[
                        if (record.type == ApplyType.fee)
                          _Row(
                            label: '金额',
                            value: '¥${record.money?.toStringAsFixed(2) ?? '-'}',
                          )
                        else
                          for (final ApplyItem item in record.items)
                            _Row(label: item.itemName, value: '× ${item.quantity}'),
                        if (record.requireDate.isNotEmpty)
                          _Row(label: '需求日期', value: record.requireDate),
                        if (record.description.isNotEmpty)
                          _Row(label: '说明', value: record.description),
                        if (record.deliveryName.isNotEmpty)
                          _Row(label: '收货人', value: record.deliveryName),
                        if (record.deliveryAddress.isNotEmpty)
                          _Row(label: '收货地址', value: record.deliveryAddress),
                      ],
                    ),
                  ),
                  if (record.approveDescription1.isNotEmpty ||
                      record.rejectReason.isNotEmpty ||
                      record.approveDate.isNotEmpty) ...<Widget>[
                    const _Section(title: '审批意见'),
                    Card(
                      child: Column(
                        children: <Widget>[
                          if (record.approveDescription1.isNotEmpty)
                            _Row(
                              label: '审批意见',
                              value: record.approveDescription1,
                            ),
                          if (record.rejectReason.isNotEmpty)
                            _Row(label: '驳回原因', value: record.rejectReason),
                          if (record.approveDate.isNotEmpty)
                            _Row(
                              label: '审批时间',
                              value: formatBackendFriendly(
                                record.approveDate,
                                empty: '-',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const _Section(title: '沟通记录'),
                  _CommentSection(
                    applyId: widget.record.id,
                    controller: _commentInput,
                    sending: _sendingComment,
                    onSend: _sendComment,
                  ),
                ],
              ),
            ),
            if (showWithdraw || showApprove)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: <Widget>[
                      if (showWithdraw) ...<Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _withdraw,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                            child: const Text('撤回申请'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (showApprove) ...<Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _reject,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              foregroundColor: AppColors.danger,
                            ),
                            child: const Text('驳回'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : _approve,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                            child: const Text('通过'),
                          ),
                        ),
                      ],
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

/// 驳回理由（对齐终止任务同款交互：AlertDialog + 必填文本框）。
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String hint,
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
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('确认'),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 申请单评论区：评论列表 + 底部输入行（itemType=5 的 comment 家族）。
class _CommentSection extends ConsumerWidget {
  const _CommentSection({
    required this.applyId,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final int applyId;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<ApplyComment>> comments = ref.watch(
      applyCommentsProvider('$applyId'),
    );

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          comments.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (Object e, StackTrace s) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '评论加载失败',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            data: (List<ApplyComment> list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '还没有沟通记录',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final ApplyComment comment in list)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              AppAvatar(
                                label: comment.person?.nickname ?? '?',
                                size: 32,
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
                                            comment.person?.nickname ??
                                                '未知用户',
                                            style: theme
                                                .textTheme.labelMedium
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
                                    const SizedBox(height: 2),
                                    Text(
                                      comment.content,
                                      style: theme.textTheme.bodyMedium,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '补充说明或回复…',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: sending ? null : onSend,
                  icon: sending
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
        ],
      ),
    );
  }
}
