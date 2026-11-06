import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/amap/amap_view.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/workbench_models.dart';
import '../data/repositories/directory_repository.dart';

/// 全部车辆一张图（对照 iOS `CarInfoLocationController`）。
///
/// 为什么不用列表内嵌地图：几百台车的列表每行一张 TextureMapView，
/// 滚动时纹理与内存都会爆（iOS 原版同样是「一张地图 + 全量 annotation」）。
/// 点击标记在底部浮出车辆信息卡；在线状态用标题文案区分。
class CarMapPage extends ConsumerStatefulWidget {
  const CarMapPage({super.key});

  @override
  ConsumerState<CarMapPage> createState() => _CarMapPageState();
}

class _CarMapPageState extends ConsumerState<CarMapPage> {
  List<CarLocationItem> _cars = const <CarLocationItem>[];
  bool _loading = true;
  String? _error;
  CarLocationItem? _selected;

  /// 有有效坐标的车才上标记（0,0 是设备没定位的默认值）。
  List<CarLocationItem> get _fixCars => _cars
      .where(
        (CarLocationItem c) =>
            double.tryParse(c.lng) != null &&
            double.tryParse(c.lat) != null &&
            double.tryParse(c.lng)!.abs() > 0.001,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final List<CarLocationItem> cars = await ref
          .read(directoryRepositoryProvider)
          .fetchCarsWithLocation();
      if (!mounted) return;
      setState(() {
        _cars = cars;
        _loading = false;
        _error = null;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  void _onMarkerClick(String tag) {
    for (final CarLocationItem car in _fixCars) {
      if ('${car.car.id}' == tag) {
        setState(() => _selected = car);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<CarLocationItem> cars = _fixCars;

    // 全量车的视野太散（全国），初始视野放到覆盖全部标记的几何中心，
    // 缩到省级别由用户自己操作。
    double lat = 35.86;
    double lng = 104.19;
    if (cars.isNotEmpty) {
      lat = cars.map((CarLocationItem c) => double.parse(c.lat)).reduce(
            (double a, double b) => a + b,
          ) /
          cars.length;
      lng = cars.map((CarLocationItem c) => double.parse(c.lng)).reduce(
            (double a, double b) => a + b,
          ) /
          cars.length;
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text('车辆地图（${cars.length}）')),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _error != null
          ? EmptyState(
              icon: LucideIcons.triangleAlert,
              title: '车辆加载失败',
              message: _error!,
              actionLabel: '重试',
              onAction: () {
                setState(() => _loading = true);
                _reload();
              },
            )
          : cars.isEmpty
          ? const EmptyState(
              icon: LucideIcons.map,
              title: '没有带定位的车辆',
              message: '设备定位后再来查看',
            )
          : Stack(
              children: <Widget>[
                AmapView(
                  latitude: lat,
                  longitude: lng,
                  zoom: 5,
                  showCenterMarker: false,
                  markers: <AmapMarker>[
                    for (final CarLocationItem car in cars)
                      AmapMarker(
                        latitude: double.parse(car.lat),
                        longitude: double.parse(car.lng),
                        title: car.car.carNum,
                        tag: '${car.car.id}',
                      ),
                  ],
                  onMarkerClick: _onMarkerClick,
                ),
                if (_selected != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    _selected!.car.carNum,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Text(
                                  _selected!.online ? '在线' : '离线',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _selected!.online
                                        ? const Color(0xFF2E9E5B)
                                        : theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _selected = null),
                                  child: const Icon(LucideIcons.x, size: 16),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              <String>[
                                if (_selected!.locDesc.isNotEmpty)
                                  _selected!.locDesc,
                                if (_selected!.speed > 0)
                                  '时速 ${_selected!.speed.toStringAsFixed(0)} km/h',
                                if (_selected!.gpsTime.isNotEmpty)
                                  '定位于 ${formatBackendFriendly(_selected!.gpsTime, empty: '')}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
