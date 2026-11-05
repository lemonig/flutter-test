import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/push/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(PushService.channelName);

  void mockNative(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('别名规则', () {
    test('与服务端 AppPushService.PREFIX 一致：LJYW + userId', () {
      // 后端推消息时 alias = "LJYW" + userId，客户端绑错前缀就永远收不到
      expect(pushAliasFor('16'), 'LJYW16');
      expect(PushService.aliasPrefix, 'LJYW');
    });
  });

  group('原生桥调用', () {
    test('init 拿回 CID 并写进 clientId', () async {
      mockNative((MethodCall call) async {
        if (call.method == 'init') return 'cid-abc-123';
        return null;
      });

      final PushService push = PushService();
      expect(await push.init(), 'cid-abc-123');
      expect(push.clientId.value, 'cid-abc-123');
      push.clientId.dispose();
    });

    test('绑定别名传的是完整别名，不让原生自己拼前缀', () async {
      final List<MethodCall> calls = <MethodCall>[];
      mockNative((MethodCall call) async {
        calls.add(call);
        return true;
      });

      final PushService push = PushService();
      expect(await push.bindAlias(pushAliasFor('16')), isTrue);
      expect(calls.single.method, 'bindAlias');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['alias'],
        'LJYW16',
      );
      push.clientId.dispose();
    });

    test('空别名直接返回 false，不打原生', () async {
      int calls = 0;
      mockNative((MethodCall call) async {
        calls++;
        return true;
      });

      final PushService push = PushService();
      expect(await push.bindAlias(''), isFalse);
      expect(await push.unbindAlias(''), isFalse);
      expect(calls, 0);
      push.clientId.dispose();
    });

    test('原生抛错时不冒泡，推送失败不能拖垮业务', () async {
      mockNative((MethodCall call) async {
        throw PlatformException(code: 'BIND_FAILED', message: '模拟失败');
      });

      final PushService push = PushService();
      expect(await push.bindAlias('LJYW16'), isFalse);
      expect(await push.init(), isNull);
      push.clientId.dispose();
    });

    test('通知权限默认读原生，未实现时按未授权处理', () async {
      mockNative((MethodCall call) async {
        throw MissingPluginException('no impl');
      });

      final PushService push = PushService();
      expect(await push.isNotificationPermissionGranted(), isFalse);
      expect(await push.requestNotificationPermission(), isFalse);
      push.clientId.dispose();
    });
  });
}
