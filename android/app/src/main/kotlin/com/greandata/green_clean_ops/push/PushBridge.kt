package com.greandata.green_clean_ops.push

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.igexin.sdk.PushManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 个推 SDK 的最小 Dart 桥。
 *
 * 为什么不用官方 `getuiflut` 插件：它的 Android 工程还停留在 AGP 4.2 写法
 * （`compileSdkVersion`、`jcenter()`、`lintOptions`），与项目的 AGP 9 + Gradle 9 不兼容。
 * 本项目只需要「初始化 / 绑别名 / 解绑 / 取 CID / 通知权限」五件事，
 * 自己包一层比改造插件更可控。
 *
 * 客户端只用 AppID（见 app/build.gradle.kts 的 manifestPlaceholders），
 * AppKey / AppSecret / MasterSecret 只在服务端推消息时使用。
 */
class PushBridge(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "green_clean_ops/push"
        private const val NOTIFICATION_PERMISSION_REQUEST = 0x9E01

        private var channel: MethodChannel? = null

        /**
         * CID 是异步下发的，可能早于 Dart 侧挂载（冷启动时 SDK 先回调）。
         * 先缓存，等 attach 时补发，避免「第一次永远拿不到 CID」。
         */
        private var pendingClientId: String? = null

        /** 由 [GreenIntentService] 收到 CID 时调用。 */
        fun onClientIdArrived(cid: String?) {
            if (cid.isNullOrEmpty()) return
            pendingClientId = cid
            channel?.invokeMethod("onClientId", cid)
        }
    }

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        pendingClientId?.let { channel?.invokeMethod("onClientId", it) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                try {
                    PushManager.getInstance().initialize(context)
                    result.success(PushManager.getInstance().getClientid(context))
                } catch (error: Throwable) {
                    // 初始化失败不能拖垮启动流程：推送是增强能力，不是主链路
                    result.error("PUSH_INIT_FAILED", error.message, null)
                }
            }

            "getClientId" -> result.success(PushManager.getInstance().getClientid(context))

            "bindAlias" -> {
                val alias = call.argument<String>("alias")
                if (alias.isNullOrEmpty()) {
                    result.error("INVALID_ALIAS", "alias 不能为空", null)
                } else {
                    try {
                        // 与服务端 AppPushService 保持一致：alias = "LJYW" + userId
                        PushManager.getInstance().bindAlias(context, alias)
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error("BIND_FAILED", error.message, null)
                    }
                }
            }

            "unbindAlias" -> {
                val alias = call.argument<String>("alias")
                if (alias.isNullOrEmpty()) {
                    result.error("INVALID_ALIAS", "alias 不能为空", null)
                } else {
                    try {
                        PushManager.getInstance().unBindAlias(context, alias, false)
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error("UNBIND_FAILED", error.message, null)
                    }
                }
            }

            "isNotificationPermissionGranted" -> result.success(notificationGranted())

            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    // Android 13 以下没有该运行时权限，装了就能收到
                    result.success(notificationGranted())
                    return
                }
                val activity = activityProvider()
                if (activity == null) {
                    result.success(false)
                    return
                }
                activity.requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST,
                )
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun notificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }
}
