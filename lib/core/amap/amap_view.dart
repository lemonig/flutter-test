import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 高德地图承载组件（M0-07）。
///
/// 为什么不直接用官方 `amap_flutter_map`：它的 Android 工程是 AGP 3.5 写法
/// （`compileSdkVersion 29`、`jcenter()`、manifest 里写 `package=`），
/// 与本项目的 AGP 9 + Gradle 9 编译不过。地图渲染改由原生 `MapView` 承载，
/// 通过 `AndroidView` 挂进来，Dart 只负责配置与回调。
///
/// Key 在 `android/app/src/main/AndroidManifest.xml` 的
/// `com.amap.api.v2.apikey`；高德按「包名 + 签名 SHA1」校验，
/// 不匹配时地图只是**白屏**，不抛异常 —— 错误只在 logcat 里。
class AmapView extends StatefulWidget {
  const AmapView({
    super.key,
    this.latitude = 30.2741,
    this.longitude = 120.1551,
    this.zoom = 15,
    this.showCenterMarker = true,
    this.onCameraIdle,
    this.onMapClick,
    this.onCreated,
    this.onUnavailable,
  });

  /// 初始中心点坐标（默认杭州）。
  final double latitude;
  final double longitude;

  /// 初始缩放级别，3（世界）~ 20（楼宇）。
  final double zoom;

  /// 是否在中心点放一个标记（选点页用准星，关掉这个）。
  final bool showCenterMarker;

  /// 地图拖动停下后的中心点。
  final void Function(double latitude, double longitude)? onCameraIdle;

  /// 点击地图某处的坐标。
  final void Function(double latitude, double longitude)? onMapClick;

  /// 地图原生视图创建完成，可用于后续调用 [AmapViewController]。
  final void Function(AmapViewController controller)? onCreated;

  /// 当前平台不支持地图（iOS / Web / 测试）时回调，用于降级 UI。
  final VoidCallback? onUnavailable;

  @override
  State<AmapView> createState() => _AmapViewState();
}

class _AmapViewState extends State<AmapView> {
  MethodChannel? _channel;

  /// 地图只在 Android 上有实现；其它平台（含测试）直接走 [AmapView.onUnavailable]，
  /// 不能让页面崩掉。
  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (!_supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onUnavailable?.call());
    }
  }

  void _onPlatformViewCreated(int id) {
    final MethodChannel channel = MethodChannel('green_clean_ops/amap_$id');
    channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onCameraIdle':
          final Map<Object?, Object?> args =
              Map<Object?, Object?>.from(call.arguments as Map? ?? const <Object?, Object?>{});
          widget.onCameraIdle?.call(
            (args['latitude'] as num?)?.toDouble() ?? 0,
            (args['longitude'] as num?)?.toDouble() ?? 0,
          );
        case 'onMapClick':
          final Map<Object?, Object?> args =
              Map<Object?, Object?>.from(call.arguments as Map? ?? const <Object?, Object?>{});
          widget.onMapClick?.call(
            (args['latitude'] as num?)?.toDouble() ?? 0,
            (args['longitude'] as num?)?.toDouble() ?? 0,
          );
      }
      return null;
    });
    setState(() => _channel = channel);
    widget.onCreated?.call(AmapViewController(channel));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.expand();

    return AndroidView(
      viewType: 'green_clean_ops/amap',
      creationParams: <String, Object?>{
        'latitude': widget.latitude,
        'longitude': widget.longitude,
        'zoom': widget.zoom,
        'showCenterMarker': widget.showCenterMarker,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}

/// 地图控制器：取中心点、移动相机。
class AmapViewController {
  const AmapViewController(this._channel);

  final MethodChannel _channel;

  Future<({double latitude, double longitude})> getCenter() async {
    final Object? raw = await _channel.invokeMethod<Object>('getCenter');
    final Map<Object?, Object?> map =
        Map<Object?, Object?>.from(raw as Map? ?? const <Object?, Object?>{});
    return (
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<bool> moveCamera(
    double latitude,
    double longitude, {
    double zoom = 16,
  }) async {
    final bool? ok = await _channel.invokeMethod<bool>('moveCamera', <String, Object?>{
      'latitude': latitude,
      'longitude': longitude,
      'zoom': zoom,
    });
    return ok ?? false;
  }

  /// 地图原生层是否已就绪。Key 校验失败时为 false（原生 MapView 没起来）。
  Future<bool> isReady() async {
    final bool? ready = await _channel.invokeMethod<bool>('isReady');
    return ready ?? false;
  }
}
