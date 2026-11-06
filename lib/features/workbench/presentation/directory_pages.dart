import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/amap/amap_view.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/workbench_models.dart';
import '../providers/workbench_providers.dart';

/// 资料库（M7-12，对照 iOS Data 模块）：站点 / 驻点 / 用户 / 车辆。
///
/// 四类共用一个列表页（kind 进路由与 provider family）；
/// 车辆定位只展示文字信息（经纬度 / 定位描述 / 在线状态），
/// 地图展示等高德 Key 改绑后另接（未完成清单 A1）。
class DirectoryPage extends ConsumerStatefulWidget {
  const DirectoryPage({super.key, required this.kind});

  final DirectoryKind kind;

  @override
  ConsumerState<DirectoryPage> createState() => _DirectoryPageState();
}

class _DirectoryPageState extends ConsumerState<DirectoryPage> {
  final TextEditingController _search = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<Object>> items = ref.watch(
      directoryProvider(
        _keyword.isEmpty
            ? widget.kind.name
            : '${widget.kind.name}:$_keyword',
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget.kind.label)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (String value) => setState(() => _keyword = value),
              decoration: InputDecoration(
                hintText: _hint,
                isDense: true,
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: items.when(
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
                onAction: () => ref.invalidate(
                  directoryProvider(
                    _keyword.isEmpty
                        ? widget.kind.name
                        : '${widget.kind.name}:$_keyword',
                  ),
                ),
              ),
              data: (List<Object> list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: LucideIcons.database,
                    title: '没有匹配的记录',
                    message: '换个关键词试试',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(
                    directoryProvider(
                      _keyword.isEmpty
                          ? widget.kind.name
                          : '${widget.kind.name}:$_keyword',
                    ),
                  ),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) =>
                        switch (widget.kind) {
                      DirectoryKind.station => _StationTile(
                        station: list[index] as DirectoryStation,
                      ),
                      DirectoryKind.agency => _AgencyTile(
                        agency: list[index] as Agency,
                      ),
                      DirectoryKind.user => _UserTile(
                        user: list[index] as TaskPerson,
                      ),
                      DirectoryKind.car => _CarTile(
                        item: list[index] as CarLocationItem,
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

  String get _hint => switch (widget.kind) {
    DirectoryKind.station => '搜索站点名称',
    DirectoryKind.agency => '搜索驻点名称',
    DirectoryKind.user => '搜索姓名',
    DirectoryKind.car => '搜索车牌',
  };
}

class _StationTile extends StatelessWidget {
  const _StationTile({required this.station});

  final DirectoryStation station;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            station.firstChar.isEmpty ? '站' : station.firstChar,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(station.name),
        subtitle: Text(
          <String>[station.region, station.city, station.contractNum]
              .where((String s) => s.isNotEmpty)
              .join(' · '),
        ),
      ),
    );
  }
}

class _AgencyTile extends StatelessWidget {
  const _AgencyTile({required this.agency});

  final Agency agency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: const Icon(LucideIcons.home, size: 20),
          ),
          title: Text(agency.name),
          subtitle: Text(
            <String>[
              if (agency.agent.isNotEmpty) '驻点员 ${agency.agent}',
              if (agency.countRoom.isNotEmpty) '房间 ${agency.countRoomUsed}/${agency.countRoom}',
            ].join(' · '),
          ),
          children: <Widget>[
            _kv('驻点员', agency.agent, agency.agentPhone),
            _kv('房东', agency.landlord, agency.landlordPhone),
            _kv('房间（已用/总数）', '${agency.countRoomUsed} / ${agency.countRoom}'),
            _kv('租期', '${agency.startDate} ~ ${agency.endDate}'),
            _kv('年租金', agency.rentOfYear.isEmpty ? '' : '¥${agency.rentOfYear}'),
            _kv('年物业费', agency.feeOfYear.isEmpty ? '' : '¥${agency.feeOfYear}'),
            _kv('付款方式', agency.payMethod),
          ],
        ),
      ),
    );
  }

  static Widget _kv(String label, String value, [String? sub]) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Builder(
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  sub == null || sub.isEmpty ? value : '$value $sub',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final TaskPerson user;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: AppAvatar(label: user.nickname, size: 40),
        title: Text(user.nickname),
      ),
    );
  }
}

class _CarTile extends StatelessWidget {
  const _CarTile({required this.item});

  final CarLocationItem item;

  /// 有有效定位（非 0,0 且坐标可解析）才渲染地图与坐标行。
  bool _hasFix(CarLocationItem item) =>
      double.tryParse(item.lng) != null &&
      double.tryParse(item.lat) != null &&
      double.tryParse(item.lng)!.abs() > 0.001;


  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.car.carNum.isEmpty ? '未上牌' : item.car.carNum,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: item.online
                        ? const Color(0xFFE7F5EC)
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.online ? '在线' : '离线',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: item.online
                          ? const Color(0xFF2E9E5B)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              <String>[
                if (item.car.region.isNotEmpty) item.car.region,
                if (item.car.city.isNotEmpty) item.car.city,
                if (item.car.company.isNotEmpty) item.car.company,
                if (item.car.description.isNotEmpty) item.car.description,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (item.locDesc.isNotEmpty ||
                _hasFix(item)) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                <String>[
                  if (item.locDesc.isNotEmpty) item.locDesc,
                  if (_hasFix(item)) '${item.lng}, ${item.lat}',
                  if (item.speed > 0) '时速 ${item.speed.toStringAsFixed(0)} km/h',
                  if (item.gpsTime.isNotEmpty)
                    '定位于 ${formatBackendFriendly(item.gpsTime, empty: '')}',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // 高德 Key 改绑（2026-11-06）后接入的地图卡：只读展示，
            // 拖动 / 缩放可用但不响应点击；0,0 视为无定位不渲染。
            if (_hasFix(item))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 180,
                    child: AmapView(
                      latitude: double.tryParse(item.lat) ?? 0,
                      longitude: double.tryParse(item.lng) ?? 0,
                      zoom: 14,
                      showCenterMarker: true,
                      onMapClick: (_, _) {},
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
