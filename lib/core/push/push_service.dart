import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 推送桥（M6-04）。
///
/// 走原生 `MethodChannel('green_clean_ops/push')`，对应
/// `android/.../push/PushBridge.kt`。没用官方 `getuiflut` 插件 ——
/// 它的 Android 工程是 AGP 4.2 写法，和本项目的 AGP 9 + Gradle 9 不兼容。
///
/// 客户端只依赖个推 AppID（已写进 `app/build.gradle.kts` 的 manifestPlaceholders），
/// AppKey / AppSecret / MasterSecret 只在服务端推消息时使用。
class PushService {
  PushService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'green_clean_ops/push';

  /// 与服务端 `AppPushService.PREFIX` 保持一致：推送按别名下发，别名 = LJYW + userId。
  ///
  /// 原 Android 工程这里有个 bug：`MyApplication.onCreate` 冷启动绑的是**不带前缀**的
  /// userId，而登录后绑的是带前缀的，后端统一加前缀推送 → 冷启动那条绑定永远收不到。
  /// 这里只用带前缀的一套。
  static const String aliasPrefix = 'LJYW';

  final MethodChannel _channel;

  /// 当前生效的 CID，`init` / 回调里更新，用于排查「收不到推送」。
  final ValueNotifier<String?> clientId = ValueNotifier<String?>(null);

  /// 只在 Android 上有实现；其它平台（含 Web、单元测试）全部走空实现。
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 绑定原生侧回调。App 启动时调一次。
  void listen() {
    if (!isSupported) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onClientId') {
        final String? cid = call.arguments as String?;
        if (cid != null && cid.isNotEmpty) {
          clientId.value = cid;
          debugPrint('[PUSH] 收到 CID：$cid');
        }
      }
    });
  }

  /// 初始化 SDK，返回 CID（可能为空，SDK 是异步下发的，拿到后会通过回调补上）。
  Future<String?> init() async {
    if (!isSupported) return null;
    try {
      final String? cid = await _channel.invokeMethod<String>('init');
      if (cid != null && cid.isNotEmpty) {
        clientId.value = cid;
        debugPrint('[PUSH] init 完成，CID：$cid');
      } else {
        debugPrint('[PUSH] init 完成，CID 待异步下发');
      }
      return cid;
    } on PlatformException catch (error) {
      debugPrint('[PUSH] init 失败：${error.message}');
      return null;
    } on MissingPluginException {
      debugPrint('[PUSH] 原生通道不存在，跳过推送');
      return null;
    }
  }

  Future<bool> bindAlias(String alias) async {
    if (!isSupported || alias.isEmpty) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'bindAlias',
        <String, Object?>{'alias': alias},
      );
      debugPrint('[PUSH] 绑定别名 $alias -> ${ok ?? false}');
      return ok ?? false;
    } on PlatformException catch (error) {
      debugPrint('[PUSH] 绑定别名失败：${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> unbindAlias(String alias) async {
    if (!isSupported || alias.isEmpty) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'unbindAlias',
        <String, Object?>{'alias': alias},
      );
      debugPrint('[PUSH] 解绑别名 $alias -> ${ok ?? false}');
      return ok ?? false;
    } on PlatformException catch (error) {
      debugPrint('[PUSH] 解绑别名失败：${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isNotificationPermissionGranted() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isNotificationPermissionGranted',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android 13+ 的 POST_NOTIFICATIONS 运行时权限。
  /// 返回 true 只代表「弹窗已弹出」，真实结果要用
  /// [isNotificationPermissionGranted] 在回到前台后复查。
  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final Provider<PushService> pushServiceProvider = Provider<PushService>((
  Ref ref,
) {
  final PushService service = PushService()..listen();
  ref.onDispose(service.clientId.dispose);
  return service;
});

/// 推送别名的唯一生成处，避免调用方各自拼前缀。
String pushAliasFor(String userId) => '${PushService.aliasPrefix}$userId';
