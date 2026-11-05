import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/section_header.dart';
import '../../auth/data/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';

/// 工作台 Tab：今日概览 + 上报 / 申请 / 统计 / 资料四组入口。
///
/// M1-03：入口按当前用户角色权限过滤。这里做分组级映射，
/// M7-01 接入后端菜单元数据后可细化到单项。
class WorkbenchPage extends ConsumerWidget {
  const WorkbenchPage({super.key});

  static const List<_Entry> _reportEntries = <_Entry>[
    _Entry(
      '异常上报',
      LucideIcons.triangleAlert,
      Tone.danger,
      AppPermission.handleAbnormal,
    ),
    _Entry(
      '巡检记录',
      LucideIcons.clipboardCheck,
      Tone.brand,
      AppPermission.reportMileage,
    ),
    _Entry(
      '现场签到',
      LucideIcons.mapPinCheckInside,
      Tone.success,
      AppPermission.viewWorkbench,
    ),
    _Entry(
      '事件上报',
      LucideIcons.megaphone,
      Tone.warning,
      AppPermission.viewWorkbench,
    ),
  ];

  static const List<_Entry> _approvalEntries = <_Entry>[
    _Entry(
      '请假申请',
      LucideIcons.calendarDays,
      Tone.brand,
      AppPermission.applyFee,
    ),
    _Entry('加班申请', LucideIcons.clock3, Tone.warning, AppPermission.applyFee),
    _Entry('费用报销', LucideIcons.receipt, Tone.success, AppPermission.applyFee),
    _Entry('出差申请', LucideIcons.plane, Tone.neutral, AppPermission.applyFee),
  ];

  static const List<_Entry> _statEntries = <_Entry>[
    _Entry(
      '任务统计',
      LucideIcons.chartColumn,
      Tone.brand,
      AppPermission.statistics,
    ),
    _Entry('水质趋势', LucideIcons.waves, Tone.success, AppPermission.statistics),
    _Entry('人员绩效', LucideIcons.users, Tone.warning, AppPermission.statistics),
    _Entry(
      '设备台账',
      LucideIcons.hardDrive,
      Tone.neutral,
      AppPermission.statistics,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Set<AppPermission> permissions =
        ref.watch(authProvider).value?.user?.permissions ??
        const <AppPermission>{};

    List<_Entry> visible(List<_Entry> entries) => entries
        .where((_Entry entry) => permissions.contains(entry.permission))
        .toList();

    final List<_Entry> reports = visible(_reportEntries);
    final List<_Entry> approvals = visible(_approvalEntries);
    final List<_Entry> stats = visible(_statEntries);

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台'),
        actions: <Widget>[
          IconButton(
            tooltip: '扫一扫',
            onPressed: () => showToast(context, '扫码功能开发中'),
            icon: const Icon(LucideIcons.scanLine),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          const _OverviewCard(),
          if (reports.isNotEmpty) ...<Widget>[
            const SectionHeader(title: '上报管理'),
            _EntryGrid(entries: reports),
          ],
          if (approvals.isNotEmpty) ...<Widget>[
            const SectionHeader(title: '申请审批'),
            _EntryGrid(entries: approvals),
          ],
          if (stats.isNotEmpty) ...<Widget>[
            const SectionHeader(title: '数据统计'),
            _EntryGrid(entries: stats),
          ],
          const SectionHeader(title: '资料与制度'),
          const _DocumentCard(),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('今日概览', style: theme.textTheme.titleSmall),
                const Spacer(),
                Icon(
                  LucideIcons.calendarDays,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '11 月 04 日 周二',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Row(
              children: <Widget>[
                Expanded(
                  child: _Stat(value: '12', label: '待办任务', tone: Tone.warning),
                ),
                _StatDivider(),
                Expanded(
                  child: _Stat(value: '4', label: '进行中', tone: Tone.brand),
                ),
                _StatDivider(),
                Expanded(
                  child: _Stat(value: '36', label: '本月完成', tone: Tone.success),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.tone});

  final String value;
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: tone.foreground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _EntryGrid extends StatelessWidget {
  const _EntryGrid({required this.entries});

  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: <Widget>[
            for (final _Entry entry in entries)
              Expanded(child: _EntryTile(entry: entry)),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: () => showToast(context, '「${entry.label}」开发中'),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: entry.tone.background,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(entry.icon, size: 22, color: entry.tone.foreground),
            ),
            const SizedBox(height: 8),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard();

  static const List<({String title, String subtitle, IconData icon})> _docs =
      <({String title, String subtitle, IconData icon})>[
        (title: '运维知识库', subtitle: '常见故障处置与备件手册', icon: LucideIcons.bookOpen),
        (title: '操作规程', subtitle: '站房巡检、仪表校准标准流程', icon: LucideIcons.fileText),
        (
          title: '应急预案',
          subtitle: '水质异常与设备故障应急响应',
          icon: LucideIcons.shieldAlert,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _docs.length; i++) ...<Widget>[
            if (i > 0) const Divider(indent: 60, endIndent: 16),
            ListTile(
              onTap: () => showToast(context, '「${_docs[i].title}」开发中'),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _docs[i].icon,
                  size: 19,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              title: Text(_docs[i].title),
              subtitle: Text(_docs[i].subtitle),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry(this.label, this.icon, this.tone, this.permission);

  final String label;
  final IconData icon;
  final Tone tone;
  final AppPermission permission;
}
