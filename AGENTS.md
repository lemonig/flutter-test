# 绿洁运维 App — 开发交接说明

> 本文件给接手的开发者 / AI 工具（zcode、Cursor 等）看。
> 目标：**读完这一份就能开工**，不必翻历史对话。
>
> 最后更新：2026-11-05
> 配套文档：`docs/开发任务规划.md`（任务拆解 + 逐轮进度）· `docs/接口契约.md`（后端接口实测）· `docs/未完成功能清单.md`（还没做什么、卡在哪）

---

## 一、这是什么

运维现场人员的移动端 App（Flutter，当前只做 Android）。核心是三条业务闭环：

**异常**（上报 → 处理 → 审核确认） · **巡检**（任务 → 逐项填报 → 提交） · **签到**（定位 → 匹配站点 → 打卡）

外加：消息（推送流水 + 转交任务处置）、个推推送、个人资料与设置。

**当前状态**：三条业务闭环全部打通，消息/推送接入真实后端。`flutter analyze` 0 issue，`flutter test` **205 通过 + 4 跳过**。

---

## 二、快速开始

```bash
cd F:/yunwei/green_clean_ops

# 构建（注意：必须设 NO_PROXY，否则 flutter test 全部加载失败）
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="localhost,127.0.0.1,::1"

flutter analyze
flutter test

# 打包（项目自带脚本，dev/demo/uat/prod 四个 flavor）
powershell -File tool/build_apk.ps1 -Target dev
```

**环境**：Flutter 3.47.9 · Dart 3.13.7 · AGP 9.1.0 · Gradle 9.3.1 · Kotlin 2.4.0 · Java 17（`JAVA_HOME=E:/JDK`）· Android SDK `E:/tools/android-sdk`

**后端**：局域网 `http://192.168.188.66:1601/api/`（本机 `ops-mobile` 项目，Spring Boot，profile=uat）· 正式 `https://app.greandata1.com/api/`

**联调账号**（内网测试环境）：

| 账号 | 密码 | 权限 |
|---|---|---|
| `xbuxingjie` | `123456` | 主管，全权限，id=16 卜幸杰 |
| `test2` | `test22345` | is_manager |
| `zhaoliang` | `zhaoliang5519` | id=25 |

---

## 三、目录结构

```
lib/
├── core/
│   ├── amap/          地图（AmapView + MapPickerPage）— 待 Key 改绑
│   ├── cache/         缓存统计与清理
│   ├── config/        AppEnv（flavor/URL/useMock）、AppInfo、env_probe
│   ├── location/      定位服务（geolocator 封装）
│   ├── media/         图片选择/压缩/上传
│   ├── network/       ApiClient / ApiResponse / 重试策略 / 服务端时间
│   ├── push/          个推推送（PushService + PushBootstrap）
│   ├── router/        GoRouter 路由表 + 鉴权守卫
│   └── storage/       AppStorage（SharedPreferences 封装）
├── features/
│   ├── auth/          登录、改密、版本更新
│   ├── home/          首页 + 异常/巡检/签到 三条业务线（最核心）
│   ├── message/       消息分类 + 明细 + 转交处置
│   ├── profile/       个人资料、我的事件、设置项
│   ├── workbench/     工作台（**还是空壳**）
│   └── discussion/    讨论区（**还是空壳**）
├── navigation/        MainShell（底部 5 Tab）
└── shared/            共享组件（状态标签、空态、骨架屏、图片九宫格…）

android/app/src/main/kotlin/.../
├── amap/              高德地图 PlatformView
└── push/              个推原生桥

test/                  21 个测试文件，205 个用例
tool/build_apk.ps1     一键出包（-Target dev|demo|uat|prod|all）
docs/                  规划 / 契约 / 未完成清单 / 截图
```

---

## 四、代码约定

- **状态管理**：Riverpod 3.x。`AsyncNotifier` + `family` 做列表分页；`Provider` 做依赖注入；**严禁**在 Provider 里做全局副作用。
- **路由**：GoRouter 18，`StatefulShellRoute` 承载 5 Tab，详情页是顶层路由。**路由注册顺序敏感**：`/task/create` 必须在 `/task/:id` 之前，否则被当成 id 吃掉。
- **UI**：Material 3 + `lucide_icons_flutter`。`const` 优先。**ListTile 不能挂在带背景色的 Container 下**（会断言"水波纹不可见"），用 `Material(color:, borderRadius:, clipBehavior:)`。
- **数据层**：Repository 抽象 + Remote/Mock 双实现，由 `useMockProvider` 切换。Mock 实现必须模拟真实后端的副作用（如"取列表即已读"）。
- **后端响应**：`{success, message, data, additional_data}`，ApiClient 已解包。分页看 `additional_data.more_items_in_collection`。
- **时间**：后端给 `2026-11-05T09:46:39.000+0800` 这种格式，用 `shared/utils/backend_time.dart` 的 `formatBackendFriendly` 等工具，别自己截字符串。
- **测试**：widget 测试里 `ListView` 是懒加载的，首屏外的元素要先 `scrollUntilVisible`；Mock 仓库有人为延时（220ms）时要 `pump(const Duration(seconds: 1))` 推进时间，否则 `pumpAndSettle` 会带着 pending timer 报错。

---

## 五、踩过的坑（务必先读，能省大量时间）

### 1. 老插件与 AGP 9 不兼容（已踩两次）

你的项目是 **AGP 9.1 + Gradle 9.3.1**，Flutter 生态里 2021–2023 年的插件几乎都不兼容：

| 插件 | 问题 | 解法 |
|---|---|---|
| `getuiflut`（个推） | `compileSdkVersion`、`jcenter()`、`lintOptions` | 弃用，自写 MethodChannel |
| `amap_flutter_map`（高德） | 同上，manifest 里还写 `package=` | 弃用，自写 PlatformView |

**接第三方 SDK 前，先看插件的 `android/build.gradle`**，而不是先写业务代码。

### 2. `flutter test` 全部加载失败

症状：16 个文件在 loading 阶段报 `Invalid WebSocket upgrade request`。
根因：环境里 `HTTP_PROXY=127.0.0.1:50274` 而 `NO_PROXY` 为空，flutter_tester 的 VM Service WebSocket 被代理劫持。
解法：跑测试前 `export NO_PROXY="localhost,127.0.0.1,::1"`。

### 3. Riverpod 3 的隐式自动重试

后端不可达时页面永久骨架屏 + 持续发请求。已在 `main.dart` 和 `test/helpers/test_app.dart` 用 `ProviderScope(retry: noAutoRetry)` 关掉。**新建测试容器时记得也带上**。

### 4. PowerShell 构建脚本

- `$args` 是自动变量不能赋值，用 `$flutterArgs`；
- flutter 的提示走 stderr，会被 `$ErrorActionPreference='Stop'` 升级成终止错误 → 判 `$LASTEXITCODE` 而不是看 stderr；
- 脚本存成 **UTF-8 with BOM**，否则 PS 5.1 读中文乱码。

### 5. 模拟器 adb 跨命令失效

每条 bash 命令结束时 adb daemon 会被杀，跨命令操作设备变 `offline`。
解法：**所有 adb 操作（start-server → reconnect → install → input → screencap）写在同一条命令里**。
模拟器是雷电 LDPlayer14（`E:\雷电\leidian\LDPlayer14`），设备名 `emulator-5554`，物理分辨率 900×1600（截图 612×1080，点击坐标要 ×1.47）。

### 6. 后端接口的几个反直觉点

- **`submit/check` 的 `success` 为真不代表能提交**：站外返回 `{success:true, data:false}`，只看 `success` 会把站外当站内放行。站内判定 = 站点 20km 以内。
- **巡检项没有"正常/异常/不适用"三态**：`ops_record_detail` 表只有 `pictures` + `description`，完成度靠"有无备注或照片"推导。
- **巡检提交是整体覆盖**：`updateOpsRecordDetail` 直接 set，重提交必须带回原 `pictureKeys`，否则旧图被冲掉。实现里"只提交改动过的项"就是为这个。
- **消息"取列表即已读"**：`message/type` 会先把该分类全部置读，客户端必须同步清角标。
- **评论/点赞的 `itemType` 传错不报错**：任务=1、签到=2、巡检=3，传错只是静默读不到。
- **个推推送文案有敏感词**：含"个推"二字会返回 `code 20001 param contains sensitive word`。

### 7. 别名规则（推送）

服务端 `AppPushService.PREFIX = "LJYW"`，`alias = "LJYW" + userId`。客户端必须绑同一个别名（`pushAliasFor(userId)`）。原 Android 工程冷启动时绑了不带前缀的 userId，属于 bug，别照抄。

---

## 六、第三方服务与 Key 现状

| 服务 | 状态 | 备注 |
|---|---|---|
| **个推** 推送 | ✅ 已跑通 | AppID `xD7UWWJDKl8jmq6AiuNnC2`（在 `app/build.gradle.kts` 的 manifestPlaceholders）。AppKey/Secret/MasterSecret 只在服务端（`ops-mobile/application.properties` 的 `gpush.*`），别放客户端。已实测 CID + 别名 + 真实推送到达通知栏。 |
| **高德 Android Key** | ❌ 不可用 | `f6457d0b866d0dc5e93e7f95f4a9bdc5` 绑的是旧包名 `com.xiyoukeji.operations`，实测 `INVALID_USER_SCODE`(10008)。**需在控制台改绑** `com.greandata.green_clean_ops` + SHA1 `8A:30:16:40:75:1C:24:E9:5F:20:CC:E4:EE:86:91:9A:E9:DF:19:A3`。改绑后地图立即可用，代码不用动。 |
| **高德 Web 服务 Key** | ❌ 缺安全密钥 | `989f15a5d1efca77bd42d7a0dfaad11b` 开了数字签名，REST 返回 `10007`。要安全密钥，或关掉签名。**注意**：私钥别硬编码进 APK，应让后端代理（`ops-mobile` 目前没有高德代理，需加接口）。 |
| **高德 iOS Key** | 备用 | `7580e1cfe1ae7e6e243b28d8edc3513a`（iOS 暂不做） |
| 阿里云 OSS | ✅ | 上传走后端代传 `POST api/upload/{type}/file`（type：1异常 3头像 4巡检 6签到），产物是 `task/` `avatar/` `ops/` `check/` 前缀的 objectKey |
| Bugly 崩溃监控 | 未接 | 原工程有 appid `dbba7d47e0`，建议复用 |

---

## 七、下一步做什么

按性价比排序（详见 `docs/未完成功能清单.md`）：

1. **C7 委派任务** —— 异常详情里"转交"按钮现在是灰的（`task_state_machine.dart` 的 `transfer` 固定 `enabled:false`）。后端 `task/transfer` 已存在，补个人员选择器就闭环了。
2. **C1 工作台 M7-02~M7-07** —— 里程上报/车辆费用/水电网费/试剂申请等，套路一致可批量做。现在 `workbench_page.dart` 里全是 `showToast('开发中')`。
3. **C4 + C5 搜索页与日期区间筛选** —— 首页搜索框现在点了没反应。
4. **B4 申请/审批契约** —— 后端 `ApplyController` 存在但契约没提取，确认后再做 M7-08~M7-10。
5. **A1/B2 地图与地址** —— 等 Key 改绑；在此之前地址管理可以先做"文本地址 + 经纬度手填"。
6. **A2 厂商通道 + A3 发布** —— 上线前必须完成（离线推送、签名、混淆、隐私清单）。

---

## 八、接手后先跑这个验证

```bash
cd F:/yunwei/green_clean_ops
export NO_PROXY="localhost,127.0.0.1,::1"
flutter analyze          # 期望：No issues found
flutter test             # 期望：All tests passed!（205 通过 + 4 跳过）
powershell -File tool/build_apk.ps1 -Target dev   # 期望：dist/green-ops-dev.apk
```

三条都绿，说明环境与代码是好的，可以开工。任何一条红，先看上面「踩过的坑」。
