import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/api_response.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/message_models.dart';
import '../data/repositories/message_repository.dart';

/// 数据源注入点：演示环境用内存实现，`USE_MOCK=false` 时走真实接口。
final Provider<MessageRepository> messageRepositoryProvider =
    Provider<MessageRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockMessageRepository();
      return RemoteMessageRepository(ref.watch(apiClientProvider));
    });

/// 服务端未读总数（M2-08）：`POST message/count_unread`，登录态变化自动重算。
///
/// 它只是「没进消息 Tab 之前」的粗粒度数字：真正把某类消息点开之后，
/// 后端会在 `message/type` 里顺手置为已读，所以还要 [refreshUnread] 重拉一次。
final FutureProvider<int> serverUnreadCountProvider = FutureProvider<int>((
  Ref ref,
) async {
  final AuthState auth = await ref.watch(authProvider.future);
  if (!auth.isAuthenticated) return 0;
  final ApiClient api = ref.watch(apiClientProvider);
  final ApiResponse response = await api.postRaw('message/count_unread');
  final Object? data = response.data;
  return data is int ? data : int.tryParse('$data') ?? 0;
});

/// 消息 Tab 的七个分类（`POST message/list`）。
final AsyncNotifierProvider<MessageCategoriesNotifier, List<MessageCategory>>
messageCategoriesProvider =
    AsyncNotifierProvider<MessageCategoriesNotifier, List<MessageCategory>>(
      MessageCategoriesNotifier.new,
    );

class MessageCategoriesNotifier extends AsyncNotifier<List<MessageCategory>> {
  MessageRepository get _repository => ref.read(messageRepositoryProvider);

  @override
  Future<List<MessageCategory>> build() async {
    final AuthState auth = await ref.watch(authProvider.future);
    if (!auth.isAuthenticated) return const <MessageCategory>[];
    return _repository.fetchCategories();
  }

  /// 下拉刷新；失败时保留旧数据（只把错误抛回页面做提示），避免白屏。
  Future<void> refresh() async {
    try {
      state = AsyncData<List<MessageCategory>>(
        await _repository.fetchCategories(),
      );
    } catch (error, stackTrace) {
      if (state.hasValue) {
        state = AsyncData<List<MessageCategory>>(state.requireValue);
        rethrow;
      }
      state = AsyncError<List<MessageCategory>>(error, stackTrace);
    }
  }

  /// 本地把某个分类的未读清零。
  ///
  /// 后端在 `message/type` 里已经把这个类型整体置为已读，这里只是让界面
  /// 立刻跟上，不用等下一次 `message/list` 回来。
  void clearUnread(MessageType type) {
    final List<MessageCategory>? current = state.value;
    if (current == null) return;
    state = AsyncData<List<MessageCategory>>(<MessageCategory>[
      for (final MessageCategory item in current)
        item.type == type ? item.copyWith(unread: 0) : item,
    ]);
  }

  /// 「全部已读」。
  ///
  /// 后端没有跨分类的批量已读接口，`readMessage` 只按 `message_type` 更新，
  /// 所以这里对有未读的分类逐个请求一次（`limit: 1`，只为触发已读，不看结果）。
  /// 分类数量固定为 7，且只挑有未读的，实际最多 7 次轻请求。
  Future<void> markAllRead() async {
    final List<MessageCategory> current = state.value ?? const <MessageCategory>[];
    final List<MessageCategory> pending = current
        .where((MessageCategory item) => item.hasUnread)
        .toList();
    if (pending.isEmpty) return;

    // 先本地清零：真实环境这里要连打几次接口，等全部回来再变界面会像「没反应」。
    // 若有请求失败，最后的 refresh 会把真实未读数拉回来。
    state = AsyncData<List<MessageCategory>>(<MessageCategory>[
      for (final MessageCategory item in current) item.copyWith(unread: 0),
    ]);

    for (final MessageCategory item in pending) {
      await _repository.fetchMessages(type: item.type, page: 1, pageSize: 1);
    }
    await refresh();
  }
}

/// 底部导航与首页铃铛共用的未读总数。
///
/// 没有「全部已读」的独立接口（后端只有按分类的 `readMessage`），
/// 演示环境由本地分类求和，真实环境读 `message/count_unread`。
final Provider<int> unreadMessageCountProvider = Provider<int>((Ref ref) {
  if (!ref.watch(useMockProvider)) {
    return ref.watch(serverUnreadCountProvider).value ?? 0;
  }
  final List<MessageCategory>? categories =
      ref.watch(messageCategoriesProvider).value;
  if (categories == null) return 0;
  return categories.fold<int>(
    0,
    (int sum, MessageCategory item) => sum + item.unread,
  );
});

/// 读完消息后统一刷新未读口径：分类列表 + 服务端总数。
void refreshMessageUnread(WidgetRef ref) {
  ref.invalidate(messageCategoriesProvider);
  ref.invalidate(serverUnreadCountProvider);
}

/// 单个分类的消息明细状态（分页）。
class MessageListState {
  const MessageListState({
    required this.items,
    this.isLoadingMore = false,
    this.hasMore = true,
  });

  final List<MessageItem> items;
  final bool isLoadingMore;
  final bool hasMore;

  MessageListState copyWith({
    List<MessageItem>? items,
    bool? isLoadingMore,
    bool? hasMore,
  }) => MessageListState(
    items: items ?? this.items,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
  );
}

/// 每个分类独立一份明细状态，切换分类互不影响。
final messageListProvider =
    AsyncNotifierProvider.family<
      MessageListNotifier,
      MessageListState,
      MessageType
    >(MessageListNotifier.new);

class MessageListNotifier extends AsyncNotifier<MessageListState> {
  MessageListNotifier(this.type);

  final MessageType type;

  static const int pageSize = 20;

  int _page = 1;

  MessageRepository get _repository => ref.read(messageRepositoryProvider);

  bool _hasMore(List<MessageItem> items, int size) =>
      _repository.lastResponseHasMore ?? (items.length >= size);

  @override
  Future<MessageListState> build() async {
    _page = 1;
    final List<MessageItem> items = await _repository.fetchMessages(
      type: type,
      page: 1,
      pageSize: pageSize,
    );
    return MessageListState(items: items, hasMore: _hasMore(items, pageSize));
  }

  Future<void> refresh() async {
    try {
      _page = 1;
      final List<MessageItem> items = await _repository.fetchMessages(
        type: type,
        page: 1,
        pageSize: pageSize,
      );
      state = AsyncData<MessageListState>(
        MessageListState(items: items, hasMore: _hasMore(items, pageSize)),
      );
    } catch (error, stackTrace) {
      if (state.hasValue) rethrow;
      state = AsyncError<MessageListState>(error, stackTrace);
    }
  }

  Future<void> loadMore() async {
    final MessageListState? current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData<MessageListState>(current.copyWith(isLoadingMore: true));

    final int nextPage = _page + 1;
    try {
      final List<MessageItem> items = await _repository.fetchMessages(
        type: type,
        page: nextPage,
        pageSize: pageSize,
      );
      _page = nextPage;
      state = AsyncData<MessageListState>(
        current.copyWith(
          items: <MessageItem>[...current.items, ...items],
          isLoadingMore: false,
          hasMore: _hasMore(items, pageSize),
        ),
      );
    } catch (_) {
      state = AsyncData<MessageListState>(
        current.copyWith(isLoadingMore: false),
      );
    }
  }

  /// 转交任务同意 / 拒绝。
  ///
  /// 后端 `message/transfer` 只改消息并同步业务表、不回传新消息体，
  /// 所以先就地更新这一条让界面立刻有反馈，再拉一次第一页做校准。
  Future<void> respondTransfer(
    MessageItem item, {
    required bool accepted,
  }) async {
    await _repository.transfer(messageId: item.id, accepted: accepted);
    final MessageListState? current = state.value;
    if (current != null) {
      state = AsyncData<MessageListState>(
        current.copyWith(
          items: <MessageItem>[
            for (final MessageItem row in current.items)
              row.id == item.id
                  ? MessageItem(
                      id: row.id,
                      type: row.type,
                      title: row.title,
                      content: accepted ? '已同意' : '已拒绝',
                      leftLabel: row.leftLabel,
                      rightLabel: row.rightLabel,
                      timeText: row.timeText,
                      jobId: row.jobId,
                      accepted: accepted,
                    )
                  : row,
          ],
        ),
      );
    }
    await refresh();
  }
}
