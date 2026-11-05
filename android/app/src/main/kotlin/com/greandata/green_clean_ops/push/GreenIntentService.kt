package com.greandata.green_clean_ops.push

import com.igexin.sdk.GTIntentService
import com.igexin.sdk.message.GTCmdMessage
import com.igexin.sdk.message.GTNotificationMessage
import com.igexin.sdk.message.GTTransmitMessage

/**
 * 个推回调服务。
 *
 * 原 Android 工程（`push/MyIntentService.java`）六个回调全是空的 ——
 * 也就是说它连 CID 都没往外传，别名只靠登录时 bind，服务端推送走了「别名」通道。
 * 这里至少把 CID 交给 [PushBridge]，便于排查「推送收不到」是没绑定还是没送达。
 *
 * 通知点击（[onNotificationMessageClicked]）目前不跳详情：
 * 服务端 `AppPushService` 只设了 `clickType=startapp`、没有 payload，
 * 想在点通知后直达任务详情，需要服务端先在 pushDTO 里补 payload。
 */
class GreenIntentService : GTIntentService() {

    override fun onReceiveServicePid(context: android.content.Context, pid: Int) = Unit

    override fun onReceiveClientId(context: android.content.Context, clientId: String?) {
        PushBridge.onClientIdArrived(clientId)
    }

    override fun onReceiveMessageData(
        context: android.content.Context,
        message: GTTransmitMessage?,
    ) = Unit

    override fun onReceiveOnlineState(context: android.content.Context, online: Boolean) = Unit

    override fun onReceiveCommandResult(
        context: android.content.Context,
        message: GTCmdMessage?,
    ) = Unit

    override fun onNotificationMessageArrived(
        context: android.content.Context,
        message: GTNotificationMessage?,
    ) = Unit

    override fun onNotificationMessageClicked(
        context: android.content.Context,
        message: GTNotificationMessage?,
    ) = Unit
}
