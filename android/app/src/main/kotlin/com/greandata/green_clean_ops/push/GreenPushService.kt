package com.greandata.green_clean_ops.push

import com.igexin.sdk.PushService

/**
 * 个推核心服务，必须继承 SDK 的 [PushService] 并单独跑在 `:pushservice` 进程，
 * 否则 SDK 拿不到长连接、收不到推送（个推文档的硬性要求）。
 */
class GreenPushService : PushService()
