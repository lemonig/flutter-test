import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/amap/amap_view.dart';
import '../../core/constants/app_colors.dart';
import '../../core/location/location_service.dart';
import '../../shared/utils/toast.dart';

/// 地图选点（M0-07）。
///
/// 交互与原 iOS 工程一致：拖动地图让准星对准目标，底部实时显示坐标，
/// 点「使用此位置」把坐标返回给上一页。
///
/// 地图 Key 不可用时地图区是白的，但坐标仍可用（由定位或上次坐标提供），
/// 页面不会崩 —— 等 Key 改绑后地图自然就出来了，不需要再改这一层。
class MapPickerPage extends ConsumerStatefulWidget {
  const MapPickerPage({super.key, this.initialLatitude, this.initialLongitude});

  /// 传入则以此为中心；不传则取当前定位，再不行回落到杭州。
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  ConsumerState<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends ConsumerState<MapPickerPage> {
  AmapViewController? _map;

  late double _latitude = widget.initialLatitude ?? 30.2741;
  late double _longitude = widget.initialLongitude ?? 120.1551;

  /// 地图状态：加载中 → 已就绪 / 不可用。
  ///
  /// 之前只用一个 bool，初始 false 会让页面一进来就显示「地图未加载」，
  /// 即使地图几秒后正常加载 —— 等于每次选点都被吓一次。
  _MapState _mapState = _MapState.loading;

  @override
  void initState() {
    super.initState();
    // 没传坐标时自动定位一次，让「选当前位置」这个常见路径不用手动搜
    if (widget.initialLatitude == null) {
      _locateOnce();
    }
  }

  Future<void> _locateOnce() async {
    final LocationResult result = await const LocationService().locate();
    if (!mounted) return;
    final GeoPoint? point = result.point;
    if (point == null) {
      showToast(context, result.failure?.message ?? '定位失败，可在地图上手动选点');
      return;
    }
    setState(() {
      _latitude = point.latitude;
      _longitude = point.longitude;
    });
    _map?.moveCamera(point.latitude, point.longitude);
  }

  void _onCameraIdle(double latitude, double longitude) {
    // 只有准星位置变化时才重建，否则每次相机微动都 setState 会掉帧
    if (latitude == _latitude && longitude == _longitude) return;
    setState(() {
      _latitude = latitude;
      _longitude = longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('选择位置'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AmapView(
              latitude: _latitude,
              longitude: _longitude,
              // 选点页用固定准星，不用 SDK 的标记：标记会跟着地图走，视觉上没有准星直观
              showCenterMarker: false,
              onCameraIdle: _onCameraIdle,
              onMapClick: (double latitude, double longitude) {
                _map?.moveCamera(latitude, longitude);
                setState(() {
                  _latitude = latitude;
                  _longitude = longitude;
                });
              },
              onCreated: (AmapViewController controller) {
                _map = controller;
                setState(() => _mapState = _MapState.ready);
              },
              onUnavailable: () => setState(() => _mapState = _MapState.unavailable),
            ),
          ),

          // 中心准星：地图拖动时不动，指向的就是底部显示的坐标
          Center(
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(LucideIcons.mapPin, size: 40, color: AppColors.danger),
                  const SizedBox(height: 2),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_mapState != _MapState.ready)
            // 只在「确定不可用」时提示；加载中给轻量提示，
            // 不要用警告色吓用户 —— 地图加载本身就要一两秒。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _mapState == _MapState.unavailable
                      ? AppColors.warningContainer
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    if (_mapState == _MapState.unavailable)
                      Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.warning)
                    else
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _mapState == _MapState.unavailable
                            ? '地图不可用（当前平台或 Key 不匹配）。'
                                  '坐标仍可正常使用，也可先手动指定。'
                            : '地图加载中…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _mapState == _MapState.unavailable
                              ? AppColors.warningOnContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(LucideIcons.crosshair, size: 16, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Text('已选坐标', style: theme.textTheme.labelLarge),
                        const Spacer(),
                        // 交给用户确认精度：坐标保留 6 位小数 ≈ 厘米级，足够选点
                        Text(
                          '${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '拖动地图，让准星对准目标位置',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          // 返回结果用命名字段，避免上层把经纬度搞反（coordinate1 是经度）
                          Navigator.of(context).pop(
                            MapPickerResult(latitude: _latitude, longitude: _longitude),
                          );
                        },
                        icon: const Icon(LucideIcons.check, size: 18),
                        label: const Text('使用此位置'),
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

/// 地图加载状态。
enum _MapState {
  /// 还在创建原生 View（正常情况一两秒内转 ready）。
  loading,

  /// 原生 MapView 已创建，可以交互。**注意**：高德 Key 不匹配时也是这个状态，
  /// 只是瓦片加载不出来、地图是白的 —— Key 校验结果只能看 logcat。
  ready,

  /// 当前平台不支持（iOS / Web / 单测），或原生层创建失败。
  unavailable,
}

/// 选点结果。
///
/// 刻意不直接复用 [GeoPoint]：那个类型带「经度=coordinate1」的业务约定，
/// 选点页是通用组件，不该耦合到后端字段命名上。
class MapPickerResult {
  const MapPickerResult({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}
