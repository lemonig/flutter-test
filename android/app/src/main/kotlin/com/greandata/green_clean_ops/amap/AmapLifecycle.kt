package com.greandata.green_clean_ops.amap

import com.amap.api.maps.TextureMapView

/**
 * 地图生命周期中转站。
 *
 * Flutter 的 PlatformView 拿不到 Activity 的 onResume / onPause，
 * 而 `TextureMapView` 的生命周期必须跟随 Activity，否则地图会停止渲染、
 * 甚至在后台继续耗电。由 [com.greandata.green_clean_ops.MainActivity] 转发过来。
 *
 * 用 `TextureMapView` 而不是 `MapView`：后者基于 SurfaceView，
 * 在 Flutter 的 PlatformView 合成里是独立 surface —— 截屏合成拿不到内容、
 * 多张地图卡在滚动列表里还会互相穿透出黑块；TextureView 则正常参与合成。
 */
object AmapLifecycle {

    private val views = LinkedHashSet<TextureMapView>()

    fun attach(mapView: TextureMapView) {
        views.add(mapView)
    }

    fun detach(mapView: TextureMapView) {
        views.remove(mapView)
    }

    fun onResume() {
        views.forEach { it.onResume() }
    }

    fun onPause() {
        views.forEach { it.onPause() }
    }

    fun onDestroy() {
        views.forEach { it.onDestroy() }
        views.clear()
    }
}
