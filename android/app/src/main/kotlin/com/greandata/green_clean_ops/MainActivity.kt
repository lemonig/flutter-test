package com.greandata.green_clean_ops

import com.greandata.green_clean_ops.amap.AmapLifecycle
import com.greandata.green_clean_ops.amap.AmapPlatformViewFactory
import com.greandata.green_clean_ops.push.PushBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private lateinit var pushBridge: PushBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 个推桥：初始化 SDK、绑/解别名、取 CID、通知权限。
        // 传 applicationContext 而不是 Activity —— PushManager 内部持有应用级对象，
        // 传 Activity 会在旋转屏 / 重建时泄漏。
        pushBridge = PushBridge(applicationContext) { this }
        pushBridge.attach(flutterEngine.dartExecutor.binaryMessenger)

        // 高德地图 PlatformView（M0-07）：官方插件的 Android 工程是 AGP 3.5 写法，
        // 与 AGP 9 不兼容，所以地图渲染直接由原生 TextureMapView 承载。
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "green_clean_ops/amap",
            AmapPlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
    }

    // TextureMapView 的生命周期必须跟随 Activity，否则地图会停止渲染；
    // PlatformView 拿不到这些回调，只能在这里转发给 AmapLifecycle。
    override fun onResume() {
        super.onResume()
        AmapLifecycle.onResume()
    }

    override fun onPause() {
        AmapLifecycle.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        AmapLifecycle.onDestroy()
        super.onDestroy()
    }
}
