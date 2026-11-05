package com.greandata.green_clean_ops.amap

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * 地图 View 工厂：Dart 侧用 `AndroidView(viewType: 'green_clean_ops/amap')` 挂载。
 */
class AmapPlatformViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    @Suppress("UNCHECKED_CAST")
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<String, Any?>) ?: emptyMap()
        return AmapPlatformView(context, messenger, viewId, params)
    }
}
