import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/section_header.dart';
import '../../auth/data/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/workbench_models.dart';
import '../providers/workbench_providers.dart';

/// 工作台（M7-01）：Banner + 今日概览 + 按权限过滤的功能入口。
///
/// M7-02 ~ M7-10 的入口在这里集中接线；异常 / 巡检 / 签到是三条
/// 业务闭环的快捷方式，直接复用已有路由。数据统计与资料库
/// （M7-11 / M7-12）仍未排期，入口保留占位并明确提示。
class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  @override
  Widget build(BuildContext context) {
    final Set<AppPermission> permissions =
        ref.watch(authProvider).value?.user?.permissions ??
        const <AppPermission>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台'),
        actions: <Widget>[
          IconButton(
            tooltip: '我的申请',
            onPressed: () => context.push('/workbench/apply-records'),
            icon: const Icon(LucideIcons.fileClock, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          const _Banner(),
          const _OverviewCard(),
          _entryGroup(
            context,
            title: '数据上报',
            entries: <_Entry>[
              _Entry(
                '里程上报',
                LucideIcons.gauge,
                Tone.brand,
                AppPermission.reportMileage,
                onTap: () => context.push('/workbench/report/mileage'),
              ),
              _Entry(
                '车辆费用',
                LucideIcons.car,
                Tone.warning,
                AppPermission.reportCarFee,
                onTap: () => context.push('/workbench/report/carFee'),
              ),
              _Entry(
                '水电网费',
                LucideIcons.plugZap,
                Tone.success,
                AppPermission.reportStationFee,
                onTap: () => context.push('/workbench/report/stationFee'),
              ),
            ],
            permissions: permissions,
          ),
          _entryGroup(
            context,
            title: '申请审批',
            entries: <_Entry>[
              _Entry(
                '试剂申请',
                LucideIcons.flaskConical,
                Tone.brand,
                AppPermission.applyReagent,
                onTap: () => context.push('/workbench/apply/reagent'),
              ),
              _Entry(
                '配件申请',
                LucideIcons.cog,
                Tone.warning,
                AppPermission.applyPart,
                onTap: () => context.push('/workbench/apply/part'),
              ),
              _Entry(
                '运维工具',
                LucideIcons.wrench,
                Tone.success,
                AppPermission.applyTool,
                onTap: () => context.push('/workbench/apply/tool'),
              ),
              _Entry(
                '临时费用',
                LucideIcons.banknote,
                Tone.danger,
                AppPermission.applyFee,
                onTap: () => context.push('/workbench/apply/fee'),
              ),
              _Entry(
                '审批中心',
                LucideIcons.stamp,
                Tone.brand,
                AppPermission.approve,
                onTap: () => context.push('/workbench/approvals'),
              ),
            ],
            permissions: permissions,
          ),
          _entryGroup(
            context,
            title: '业务闭环',
            entries: <_Entry>[
              _Entry(
                '异常上报',
                LucideIcons.triangleAlert,
                Tone.danger,
                AppPermission.handleAbnormal,
                onTap: () => context.push('/task/create'),
              ),
              _Entry(
                '首页时间线',
                LucideIcons.house,
                Tone.brand,
                AppPermission.viewWorkbench,
                onTap: () => context.go('/home'),
              ),
              _Entry(
                '现场签到',
                LucideIcons.mapPinCheckInside,
                Tone.success,
                AppPermission.viewWorkbench,
                onTap: () => context.push('/attend/create'),
              ),
            ],
            permissions: permissions,
          ),
          _entryGroup(
            context,
            title: '数据统计',
            entries: <_Entry>[
              _Entry(
                '异常统计',
                LucideIcons.triangleAlert,
                Tone.danger,
                AppPermission.statistics,
                onTap: () => context.push('/workbench/stats/abnormal'),
              ),
              _Entry(
                '巡检统计',
                LucideIcons.clipboardCheck,
                Tone.brand,
                AppPermission.statistics,
                onTap: () => context.push('/workbench/stats/inspection'),
              ),
              _Entry(
                '里程统计',
                LucideIcons.route,
                Tone.success,
                AppPermission.statistics,
                onTap: () => context.push('/workbench/stats/mileage'),
              ),
            ],
            permissions: permissions,
          ),
          _entryGroup(
            context,
            title: '资料库',
            entries: <_Entry>[
              _Entry(
                '站点资料',
                LucideIcons.mapPin,
                Tone.brand,
                AppPermission.stationData,
                onTap: () => context.push('/workbench/directory/station'),
              ),
              _Entry(
                '驻点资料',
                LucideIcons.home,
                Tone.warning,
                AppPermission.stationData,
                onTap: () => context.push('/workbench/directory/agency'),
              ),
              _Entry(
                '用户资料',
                LucideIcons.users,
                Tone.success,
                AppPermission.stationData,
                onTap: () => context.push('/workbench/directory/user'),
              ),
              _Entry(
                '车辆资料',
                LucideIcons.car,
                Tone.neutral,
                AppPermission.stationData,
                onTap: () => context.push('/workbench/directory/car'),
              ),
            ],
            permissions: permissions,
          ),
          const SectionHeader(title: '资料与制度'),
          const _DocumentCard(),
        ],
      ),
    );
  }

  Widget _entryGroup(
    BuildContext context, {
    required String title,
    required List<_Entry> entries,
    required Set<AppPermission> permissions,
  }) {
    final List<_Entry> visible = entries
        .where((_Entry entry) => permissions.contains(entry.permission))
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        SectionHeader(title: title),
        _EntryGrid(entries: visible),
      ],
    );
  }
}

/// 顶部轮播（`GET meta/banner`）。加载失败静默收起，不占版面；
/// 单图不轮播，多图 4 秒自动翻页。
class _Banner extends ConsumerStatefulWidget {
  const _Banner();

  @override
  ConsumerState<_Banner> createState() => _BannerState();
}

class _BannerState extends ConsumerState<_Banner> {
  PageController? _controller;
  Timer? _timer;
  int _index = 0;
  int _length = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _ensureTimer(int length) {
    if (length == _length) return;
    _length = length;
    _timer?.cancel();
    _timer = null;
    if (length <= 1) return;
    _controller ??= PageController();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !(_controller?.hasClients ?? false)) return;
      final int next = (_index + 1) % length;
      _controller!.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<WorkBanner>> banners = ref.watch(workBannersProvider);
    final List<WorkBanner> list = banners.asData?.value ?? const <WorkBanner>[];
    // Timer 的启停在帧尾处理，避免 build 期间改状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureTimer(list.length);
    });
    if (list.isEmpty) return const SizedBox.shrink();

    final Widget content = list.length == 1
        ? _imageOf(list.first)
        : PageView.builder(
            controller: _controller,
            itemCount: list.length,
            onPageChanged: (int index) => _index = index,
            itemBuilder: (BuildContext context, int index) =>
                _imageOf(list[index]),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(height: 108, child: content),
      ),
    );
  }

  Widget _imageOf(WorkBanner banner) => Image.network(
    banner.imageUrl,
    fit: BoxFit.cover,
    width: double.infinity,
    errorBuilder: (_, _, _) =>
        Container(color: Theme.of(context).colorScheme.surfaceContainerHigh),
  );
}

// ───────────────────────────── 概览与入口 ─────────────────────────────

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
                  '数据口径待后端统计接口，暂为占位',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryGrid extends StatelessWidget {
  const _EntryGrid({required this.entries});

  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    // 每行最多 4 个入口；超出换行，避免 5 项挤在一行文字被截断。
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const int perRow = 4;
            final double width =
                (constraints.maxWidth - (perRow - 1) * 8) / perRow;
            return Wrap(
              spacing: 8,
              runSpacing: 12,
              children: <Widget>[
                for (final _Entry entry in entries)
                  SizedBox(width: width, child: _EntryTile(entry: entry)),
              ],
            );
          },
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
      onTap: entry.onTap,
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
  const _Entry(this.label, this.icon, this.tone, this.permission, {this.onTap});

  final String label;
  final IconData icon;
  final Tone tone;
  final AppPermission permission;
  final VoidCallback? onTap;
}
