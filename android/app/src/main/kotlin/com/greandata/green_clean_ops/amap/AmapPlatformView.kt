package com.greandata.green_clean_ops.amap

import android.content.Context
import android.view.View
import android.view.ViewGroup
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.MarkerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * 地图 PlatformView（M0-07）。
 *
 * 官方 `amap_flutter_map` 3.0.0 的 Android 工程是 AGP 3.5 写法
 * （`compileSdkVersion 29`、`jcenter()`），与 AGP 9 不兼容，
 * 所以地图渲染由这里直接承载原生 `MapView`，Dart 侧用 `AndroidView` 挂载。
 *
 * Key 来自 AndroidManifest 的 `com.amap.api.v2.apikey`；
 * 高德按「包名 + 签名 SHA1」校验，Key 不匹配时地图只是白屏、**不抛异常**，
 * 真正的错误只在 logcat 里（`auth error: INVALID_USER_SCODE` 等）。
 *
 * 每个实例一个 MethodChannel（`green_clean_ops/amap_<viewId>`），
 * 能取中心坐标 / 移动相机 / 回传点击与相机事件。
 */
class AmapPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val params: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val channel: MethodChannel = MethodChannel(messenger, "green_clean_ops/amap_$viewId")
    private val container: ViewGroup = android.widget.FrameLayout(context)
    private var mapView: MapView? = null
    private var aMap: AMap? = null

    init {
        try {
            // 高德 9.x 隐私合规：必须先声明已取得用户同意，否则 MapView 创建直接抛异常。
            // 这里的 true 对应「隐私政策已弹给用户且用户同意」，与 App 内隐私政策页一致。
            MapsInitializer.updatePrivacyShow(context, true, true)
            MapsInitializer.updatePrivacyAgree(context, true)

            val map = MapView(context)
            container.addView(
                map,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            map.onCreate(null)
            mapView = map
            AmapLifecycle.attach(map)

            aMap = map.map?.also { amap ->
                amap.uiSettings.isZoomControlsEnabled = false
                amap.uiSettings.isMyLocationButtonEnabled = false

                val latitude = (params["latitude"] as? Number)?.toDouble() ?: 30.2741
                val longitude = (params["longitude"] as? Number)?.toDouble() ?: 120.1551
                val zoom = (params["zoom"] as? Number)?.toFloat() ?: 15f

                amap.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom))

                if (params["showCenterMarker"] != false) {
                    amap.addMarker(
                        MarkerOptions()
                            .position(LatLng(latitude, longitude))
                            .draggable(true),
                    )
                }

                // 中心坐标变化：拖动地图时把中心点坐标回传 Dart，
                // 选点页靠它拿到「准星位置」的经纬度。
                amap.setOnCameraChangeListener(object : AMap.OnCameraChangeListener {
                    override fun onCameraChange(position: com.amap.api.maps.model.CameraPosition?) = Unit

                    override fun onCameraChangeFinish(position: com.amap.api.maps.model.CameraPosition?) {
                        val target = position?.target ?: return
                        channel.invokeMethod(
                            "onCameraIdle",
                            mapOf("latitude" to target.latitude, "longitude" to target.longitude),
                        )
                    }
                })

                // 点击地图：把坐标回传，便于「点哪选哪」。
                amap.setOnMapClickListener { latLng ->
                    channel.invokeMethod(
                        "onMapClick",
                        mapOf("latitude" to latLng.latitude, "longitude" to latLng.longitude),
                    )
                }
            }
        } catch (error: Throwable) {
            // 隐私未声明 / SDK 内部错误时不能让整个页面崩掉，退回空白容器，
            // 错误留 logcat 给排查用。
            android.util.Log.e("AMAP", "地图初始化失败", error)
        }

        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val amap = aMap
        when (call.method) {
            "getCenter" -> {
                val target = amap?.cameraPosition?.target
                result.success(
                    mapOf(
                        "latitude" to (target?.latitude ?: 0.0),
                        "longitude" to (target?.longitude ?: 0.0),
                    ),
                )
            }

            "moveCamera" -> {
                val latitude = (call.argument<Double>("latitude")) ?: return result.success(false)
                val longitude = (call.argument<Double>("longitude")) ?: return result.success(false)
                val zoom = (call.argument<Double>("zoom"))?.toFloat() ?: 15f
                amap?.animateCamera(
                    CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom),
                )
                result.success(true)
            }

            "isReady" -> result.success(amap != null)

            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        // MapView 的生命周期必须手动释放，否则多次进出页面会泄漏并卡帧。
        mapView?.let {
            AmapLifecycle.detach(it)
            it.onDestroy()
        }
        mapView = null
        aMap = null
    }
}
