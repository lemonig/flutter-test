import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/widgets/section_header.dart';
import '../../home/data/models/task_item.dart';
import '../../home/providers/home_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/models/workbench_models.dart';
import '../data/repositories/directory_repository.dart';
import '../data/repositories/report_repository.dart';
import '../providers/workbench_providers.dart';

/// 站点详情（对照 iOS StationHome 模块）：
/// 头部计数卡（异常/巡检/签到）+ 站点信息。
///
/// iOS 还做了仪器列表与子页签，这里先做信息聚合页；
/// 三个计数卡点击可跳对应统计，延续「资料 → 业务」的动线。
class StationDetailPage extends ConsumerWidget {
  const StationDetailPage({super.key, required this.stationId});

  final int stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<StationProfile> profile = ref.watch(
      stationProfileProvider(stationId),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('站点详情')),
      body: profile.when(
        loading: () => const SkeletonList(count: 3),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.triangleAlert,
          title: '站点详情加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重试',
          onAction: () => ref.invalidate(stationProfileProvider(stationId)),
        ),
        data: (StationProfile data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Icon(
                          LucideIcons.mapPin,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data.address.isEmpty
                                ? data.regionText
                                : '${data.regionText} · ${data.address}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader(title: '业务概览'),
            Row(
              children: <Widget>[
                Expanded(
                  child: _CountCard(
                    icon: LucideIcons.triangleAlert,
                    tone: AppColors.danger,
                    label: '异常任务',
                    value: data.taskCount,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountCard(
                    icon: LucideIcons.clipboardCheck,
                    tone: AppColors.brand,
                    label: '巡检记录',
                    value: data.opsRecordCount,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountCard(
                    icon: LucideIcons.mapPinCheckInside,
                    tone: AppColors.success,
                    label: '现场签到',
                    value: data.attendCount,
                  ),
                ),
              ],
            ),
            const SectionHeader(title: '站点信息'),
            Card(
              child: Column(
                children: <Widget>[
                  if (data.dataManager.isNotEmpty)
                    _Row(label: '数据管理员', value: data.dataManager),
                  if (data.assistant.isNotEmpty)
                    _Row(label: '站长助理', value: data.assistant),
                  if (data.ops.isNotEmpty) _Row(label: '运维单位', value: data.ops),
                  if (data.stationTypeStr.isNotEmpty)
                    _Row(label: '站点类型', value: data.stationTypeStr),
                  if (data.buildDate.isNotEmpty)
                    _Row(label: '建站日期', value: data.buildDate),
                  if (data.mn.isNotEmpty) _Row(label: '设备 MN 号', value: data.mn),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final stationProfileProvider = FutureProvider.family<StationProfile, int>((
  Ref ref,
  int stationId,
) => ref.watch(directoryRepositoryProvider).fetchStationProfile(stationId));

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color tone;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 20, color: tone),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: tone,
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
        ),
      ),
    );
  }
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

// ───────────────────── 统计详情（异常 / 巡检 / 里程）─────────────────────

/// 统计卡点击进入的按省流水（对照 iOS STAbnormalList / STInspectionList /
/// STMileReportList 三个 Controller）。
///
/// - 异常 / 巡检：对应 timeline + 省份 condition + 日期区间，复用 TaskCard；
/// - 里程：`POST car/regionSearch` 返回该省里程上报流水（CarMileageForm），
///   用简化行展示。
class StatDetailPage extends ConsumerStatefulWidget {
  const StatDetailPage({
    super.key,
    required this.kind,
    required this.regionKey,
    required this.regionTitle,
    required this.startDate,
    required this.endDate,
  });

  final StatsKind kind;
  final String regionKey;
  final String regionTitle;
  final String startDate;
  final String endDate;

  @override
  ConsumerState<StatDetailPage> createState() => _StatDetailPageState();
}

class _StatDetailPageState extends ConsumerState<StatDetailPage> {
  bool _loading = true;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  final List<TaskItem> _tasks = <TaskItem>[];
  final List<ReportRecord> _mileages = <ReportRecord>[];

  bool get _isMileage => widget.kind == StatsKind.mileage;

  @override
  void initState() {
    super.initState();
    _load(page: 1);
  }

  Future<void> _load({required int page}) async {
    setState(() {
      _loading = page == 1;
      _error = null;
    });
    try {
      if (_isMileage) {
        final ReportPage result = await ref
            .read(reportRepositoryProvider)
            .fetchMileageReports(
              regionKey: widget.regionKey,
              startDate: widget.startDate,
              endDate: widget.endDate,
              page: page,
            );
        if (!mounted) return;
        setState(() {
          _page = page;
          if (page == 1) _mileages.clear();
          _mileages.addAll(result.items);
          _hasMore = result.hasMore;
          _loading = false;
        });
        return;
      }
      final List<TaskItem> items = await ref
          .read(homeRepositoryProvider)
          .fetchTasksByRegion(
            category: widget.kind == StatsKind.abnormal
                ? TaskCategory.abnormal
                : TaskCategory.inspection,
            regionKey: widget.regionKey,
            startDate: widget.startDate,
            endDate: widget.endDate,
            page: page,
          );
      if (!mounted) return;
      setState(() {
        _page = page;
        if (page == 1) _tasks.clear();
        _tasks.addAll(items);
        _hasMore = items.length >= 10;
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.userMessage;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败：$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = '${widget.regionTitle}·$_kindLabel';

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(title)),
      body: _error != null
          ? EmptyState(
              icon: LucideIcons.triangleAlert,
              title: '加载失败',
              message: _error!,
              actionLabel: '重试',
              onAction: () => _load(page: 1),
            )
          : _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : (_isMileage ? _mileages.isEmpty : _tasks.isEmpty)
          ? const EmptyState(
              icon: LucideIcons.inbox,
              title: '该时间维度内没有记录',
              message: '换个周期再看看',
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                if (_hasMore &&
                    n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                  _load(page: _page + 1);
                }
                return false;
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _isMileage ? _mileages.length : _tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (_isMileage) {
                    return _MileageRow(record: _mileages[index]);
                  }
                  final TaskItem item = _tasks[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        item.stationName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          item.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      trailing: Text(
                        item.timeText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String get _kindLabel => switch (widget.kind) {
    StatsKind.abnormal => '异常',
    StatsKind.inspection => '巡检',
    StatsKind.mileage => '里程上报',
  };
}

class _MileageRow extends StatelessWidget {
  const _MileageRow({required this.record});

  final ReportRecord record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          record.carNum.isEmpty ? '未上牌' : record.carNum,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            <String>[
              if (record.mileage != null)
                '${record.mileage!.toStringAsFixed(0)} km',
              if (record.description.isNotEmpty) record.description,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              record.submitter?.nickname ?? '',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            Text(
              formatBackendFriendly(record.gmtCreate, empty: ''),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
