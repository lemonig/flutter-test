/// Riverpod 3 的自动重试策略：**关闭**。
///
/// Riverpod 3 起，Provider 抛错后默认按指数退避自动重建
/// （200ms → 400ms → …），这意味着后端不可达时：
/// 1. 页面会永远停在骨架屏 —— 每次重建都把状态打回 loading，
///    `ErrorRetryView` 根本没机会出现；
/// 2. 一个断网的后端会被持续请求，日志里看起来像死循环。
///
/// 本项目已有两层显式容错，不需要再叠一层隐式重试：
/// - 传输层：`_RetryInterceptor` 对断网 / 超时 / 5xx 重试 1 次；
/// - UI 层：每个页面都有「重新加载 / 重试」入口，由用户决定何时重试。
///
/// 需要恢复默认行为时，把 `ProviderScope.retry` 传 `null` 即可。
Duration? noAutoRetry(int retryCount, Object error) => null;
