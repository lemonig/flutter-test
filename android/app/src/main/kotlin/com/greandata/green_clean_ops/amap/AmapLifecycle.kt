package com.greandata.green_clean_ops.amap

import com.amap.api.maps.MapView

/**
 * 地图生命周期中转站。
 *
 * Flutter 的 PlatformView 拿不到 Activity 的 onResume / onPause，
 * 而 `MapView` 的生命周期必须跟随 Activity，否则地图会停止渲染、
 * 甚至在后台继续耗电。由 [com.greandata.green_clean_ops.MainActivity] 转发过来。
 */
object AmapLifecycle {

    private val views = LinkedHashSet<MapView>()

    fun attach(mapView: MapView) {
        views.add(mapView)
    }

    fun detach(mapView: MapView) {
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
