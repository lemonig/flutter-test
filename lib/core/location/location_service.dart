import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// 经纬度（系统 GPS 原始坐标）。
///
/// 字段命名对齐后端 `Attend`：`coordinate1` 是经度、`coordinate2` 是纬度，
/// 提交时不要写反 —— 后端只校验非空，写反了不会报错，但会存成错误位置。
class GeoPoint {
  const GeoPoint({required this.longitude, required this.latitude});

  final double longitude;
  final double latitude;

  /// 展示用坐标串，固定 6 位小数（约 0.1 米精度，够现场记录）。
  String get label =>
      '${longitude.toStringAsFixed(6)}, ${latitude.toStringAsFixed(6)}';

  @override
  String toString() => label;
}

/// 定位失败原因，文案直接给用户看，页面不再二次翻译。
enum LocationFailure {
  serviceDisabled('设备定位服务未开启，请打开 GPS 后重试'),
  permissionDenied('未授权定位权限，无法获取当前位置'),
  permissionPermanentlyDenied('定位权限已被永久拒绝，请到系统设置中开启'),
  timeout('定位超时，请到空旷处或开启 GPS 后重试'),
  unsupported('当前设备不支持定位'),
  unknown('定位失败，请重试');

  const LocationFailure(this.message);

  final String message;
}

/// 定位结果：成功带坐标，失败带原因，不回 null 让调用方猜。
class LocationResult {
  const LocationResult.success(GeoPoint this.point) : failure = null;

  const LocationResult.failed(LocationFailure this.failure) : point = null;

  final GeoPoint? point;
  final LocationFailure? failure;

  bool get isSuccess => point != null;
}

/// 定位服务（M5-01 的前置能力）。
///
/// 对应原工程 `ReleaseSignInLocationController` 里 AMapLocationKit 的职责：
/// 只负责拿到「当前经纬度」，签到页再拿坐标去换附近站点、回填地址。
/// D3 已定案地图用高德，但地图可视化需要单独申请 Key；这里先用系统定位把
/// 签到主链路跑通，M0-07 接入高德后再把「地图选点」叠上来。
class LocationService {
  const LocationService();

  /// 调试坐标：与原工程 iOS `#if DEBUG` 里写死的坐标保持一致
  /// （`120.16 / 30.37`，杭州拱墅）。模拟器没有 GPS 时靠它验流程。
  static const GeoPoint debugPoint = GeoPoint(
    longitude: 120.16,
    latitude: 30.37,
  );

  Future<LocationResult> locate({
    Duration timeout = const Duration(seconds: 12),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationFailure.serviceDisabled);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failed(LocationFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(
          LocationFailure.permissionPermanentlyDenied,
        );
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeout,
        ),
      );

      return LocationResult.success(
        GeoPoint(
          longitude: position.longitude,
          latitude: position.latitude,
        ),
      );
    } on TimeoutException {
      return const LocationResult.failed(LocationFailure.timeout);
    } on LocationServiceDisabledException {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    } on PermissionDeniedException {
      return const LocationResult.failed(LocationFailure.permissionDenied);
    } catch (_) {
      return const LocationResult.failed(LocationFailure.unknown);
    }
  }

  /// 跳系统定位开关，权限被拒时给用户一条自救路径。
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// 跳本应用设置页，处理「永久拒绝」。
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());
