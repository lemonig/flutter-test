import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/workbench_models.dart';
import 'detail_pages.dart';
import '../providers/workbench_providers.dart';

/// 统计三页（M7-11，对照 iOS Statistical 模块）：异常 / 巡检 / 里程。
///
/// 展示对齐 iOS：日 / 周 / 月切换 + 按省数字卡（后端直接给计数，
/// 无需图表库 —— fl_chart 与 AGP 9 不兼容，见未完成清单 A 系取舍）。
class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key, required this.kind});

  final StatsKind kind;

  String get _title => switch (kind) {
    StatsKind.abnormal => '异常统计',
    StatsKind.inspection => '巡检统计',
    StatsKind.mileage => '里程统计',
  };

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  StatPeriod _period = StatPeriod.day;

  String get _providerKey => '${widget.kind.name}:${_period.name}';

  void _openDetail(Object stat) {
    final (String, String) range = _period.range(DateTime.now());
    final String regionKey = switch (stat) {
      AbnormalStat s => s.regionKey,
      InspectionStat s => s.regionKey,
      MileageStat s => s.regionKey,
      _ => '',
    };
    final String regionTitle = switch (stat) {
      AbnormalStat s => s.title,
      InspectionStat s => s.title,
      MileageStat s => s.region,
      _ => '',
    };
    if (regionKey.isEmpty || regionTitle.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => StatDetailPage(
          kind: widget.kind,
          regionKey: regionKey,
          regionTitle: regionTitle,
          startDate: range.$1,
          endDate: range.$2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<Object>> stats = ref.watch(statsProvider(_providerKey));

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget._title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<StatPeriod>(
              segments: <ButtonSegment<StatPeriod>>[
                for (final StatPeriod period in StatPeriod.values)
                  ButtonSegment<StatPeriod>(
                    value: period,
                    label: Text(period.label),
                  ),
              ],
              selected: <StatPeriod>{_period},
              onSelectionChanged: (Set<StatPeriod> selection) =>
                  setState(() => _period = selection.first),
            ),
          ),
          Expanded(
            child: stats.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object error, StackTrace stack) => EmptyState(
                icon: LucideIcons.triangleAlert,
                title: '统计加载失败',
                message: error is AppException ? error.userMessage : '请稍后重试',
                actionLabel: '重试',
                onAction: () => ref.invalidate(statsProvider(_providerKey)),
              ),
              data: (List<Object> list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: LucideIcons.chartNoAxesColumn,
                    title: '暂无数据',
                    message: '该时间维度内没有统计记录',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(statsProvider(_providerKey)),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) =>
                        switch (widget.kind) {
                      StatsKind.abnormal => _AbnormalCard(
                        stat: list[index] as AbnormalStat,
                        onTap: () => _openDetail(list[index]),
                      ),
                      StatsKind.inspection => _InspectionCard(
                        stat: list[index] as InspectionStat,
                        onTap: () => _openDetail(list[index]),
                      ),
                      StatsKind.mileage => _MileageCard(
                        stat: list[index] as MileageStat,
                        onTap: () => _openDetail(list[index]),
                      ),
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.totalLabel,
    required this.totalTone,
    required this.cells,
    required this.onTap,
  });

  final String title;
  final String totalLabel;
  final Color totalTone;
  final List<(String, int)> cells;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  totalLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: totalTone,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final (String, int) cell in cells)
                  _Cell(label: cell.$1, value: cell.$2),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label $value',
        style: theme.textTheme.labelMedium?.copyWith(
          color: value > 0
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: value > 0 ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _AbnormalCard extends StatelessWidget {
  const _AbnormalCard({required this.stat, required this.onTap});

  final AbnormalStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _StatCard(
      title: stat.title,
      totalLabel: '共 ${stat.total} 单',
      totalTone: AppColors.brand,
      onTap: onTap,
      cells: <(String, int)>[
        ('待处理', stat.todo),
        ('处理中', stat.doing),
        ('已修复', stat.fixed),
        ('非异常', stat.notError),
        ('已关闭', stat.confirmed),
        ('已终止', stat.terminated),
        ('超时', stat.overtime),
      ],
    );
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.stat, required this.onTap});

  final InspectionStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _StatCard(
      title: stat.title,
      totalLabel: '共 ${stat.total} 次',
      totalTone: AppColors.success,
      onTap: onTap,
      cells: <(String, int)>[
        ('未完成', stat.todo),
        ('已完成', stat.done),
        ('超时', stat.overtime),
        ('已终止', stat.termination),
      ],
    );
  }
}

class _MileageCard extends StatelessWidget {
  const _MileageCard({required this.stat, required this.onTap});

  final MileageStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _StatCard(
      title: stat.region,
      totalLabel: '车辆 ${stat.carNumber} 台',
      totalTone: AppColors.warning,
      onTap: onTap,
      cells: <(String, int)>[
        ('已上报', stat.reported),
        ('未上报', stat.noReported),
      ],
    );
  }
}
