/// 运行环境与构建参数。
///
/// 用法：
/// ```bash
/// flutter run --dart-define=FLAVOR=staging --dart-define=USE_MOCK=false
/// flutter build apk --dart-define=FLAVOR=prod --dart-define=USE_MOCK=false \
///   --dart-define=API_BASE_URL=https://your-host/api/
/// ```
/// 所有取值都是编译期常量，切换环境不产生代码改动（M0-03）。
enum AppFlavor { dev, staging, prod }

class AppEnv {
  const AppEnv._();

  static const String flavorName = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// 默认走真实后端：`flutter build apk` 出来的包必须能反映线上数据，
  /// 否则「装了包看不到数据」会被误判成接口故障（踩过一次）。
  /// 需要离线演示时显式传 `--dart-define=USE_MOCK=true`。
  static const bool useMock = bool.fromEnvironment(
    'USE_MOCK',
    defaultValue: false,
  );

  static const bool verboseLog = bool.fromEnvironment(
    'API_LOG',
    defaultValue: true,
  );

  static AppFlavor get flavor => switch (flavorName) {
    'prod' || 'release' => AppFlavor.prod,
    'staging' || 'test' => AppFlavor.staging,
    _ => AppFlavor.dev,
  };

  /// 地址表来自原 iOS 工程 `NetworkTool.swift` / `ProjectTool.swift`。
  static String get _defaultBaseUrl => switch (flavor) {
    AppFlavor.dev => 'http://192.168.188.66:1601/api/',
    AppFlavor.staging => 'http://47.111.166.172:1600/api/',
    AppFlavor.prod => 'https://app.greandata1.com/api/',
  };

  static String get baseUrl =>
      _baseUrlOverride.isEmpty ? _defaultBaseUrl : _baseUrlOverride;

  /// 版本检查是绝对地址，不走 baseUrl（原工程 RootTabBarController）。
  /// 原 iOS 工程写死正式服务器，导致 UAT/开发包也会弹「生产 v29 更新」；
  /// 这里只在生产环境启用，非生产返回 null 跳过检查。
  static String? get versionCheckUrl =>
      isProduction ? 'https://app.greandata1.com/api/version' : null;

  static const String versionKey = '1482d58704e948b48a0dd316710a4cdf';

  static bool get isProduction => flavor == AppFlavor.prod;

  /// 明文 HTTP 只允许在非生产环境使用。
  static bool get usesCleartext => baseUrl.startsWith('http://');

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const int pageSize = 10;

  static String get label => switch (flavor) {
    AppFlavor.dev => '开发',
    AppFlavor.staging => '测试',
    AppFlavor.prod => '生产',
  };

  static Map<String, String> get debugSummary => <String, String>{
    'FLAVOR': flavor.name,
    'baseUrl': baseUrl,
    'useMock': '$useMock',
    'cleartext': '$usesCleartext',
  };
}
