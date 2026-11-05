/// 应用自身信息。
///
/// 刻意写常量，不依赖 `package_info_plus`：它目前只是 `geolocator` 的
/// 传递依赖，直接引用会触发 `depend_on_referenced_packages`，
/// 而且 DevTools 里读到的版本号在热重载时并不可靠。
///
/// ⚠️ 改 `pubspec.yaml` 的 `version:` 时，这里要一起改。
class AppInfo {
  const AppInfo._();

  static const String name = '绿洁运维';
  static const String version = '1.0.0';
  static const String build = '1';

  /// 展示用：`v1.0.0 (1)`。
  static const String versionLabel = 'v$version ($build)';

  /// 隐私政策的生效日期与版本，改文案时一起更新。
  static const String privacyUpdatedAt = '2026-11-05';
  static const String privacyVersion = '1.0';
}
