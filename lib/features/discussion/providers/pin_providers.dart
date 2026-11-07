import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/home/data/models/task_activity.dart';
import '../data/models/pin_post.dart';
import '../data/repositories/pin_repository.dart';

/// 讨论区数据家族（M8）。
///
/// 列表按 channelId 分 family（切换频道即换条目）；
/// 发帖/评论/点赞后由页面 invalidate 对应家族。

final pinChannelsProvider = FutureProvider<List<PinChannel>>(
  (Ref ref) => ref.watch(pinRepositoryProvider).fetchChannels(),
);

/// 帖子分页状态。
class PinListState {
  const PinListState({this.items = const <PinPost>[], this.hasMore = false});

  final List<PinPost> items;
  final bool hasMore;
}

/// key = channelId（0 = 全部）。
class PinListNotifier extends AsyncNotifier<PinListState> {
  PinListNotifier(this.channelId);

  final int channelId;

  static const int pageSize = 10;

  int _page = 1;

  PinRepository get _repo => ref.read(pinRepositoryProvider);

  @override
  Future<PinListState> build() async {
    _page = 1;
    final PinPage page = await _repo.fetchPosts(
      channelId: channelId,
      page: 1,
      pageSize: pageSize,
    );
    return PinListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> refresh() async {
    try {
      _page = 1;
      final PinPage page = await _repo.fetchPosts(
        channelId: channelId,
        page: 1,
        pageSize: pageSize,
      );
      state = AsyncValue<PinListState>.data(
        PinListState(items: page.items, hasMore: page.hasMore),
      );
    } on Exception catch (error, stackTrace) {
      state = AsyncError<PinListState>(error, stackTrace);
    }
  }

  Future<void> loadMore() async {
    final PinListState? current = state.value;
    if (current == null || !current.hasMore) return;
    _page += 1;
    final PinPage page = await _repo.fetchPosts(
      channelId: channelId,
      page: _page,
      pageSize: pageSize,
    );
    state = AsyncValue<PinListState>.data(
      PinListState(
        items: <PinPost>[...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }
}

final pinListProvider =
    AsyncNotifierProvider.family<PinListNotifier, PinListState, int>(
      PinListNotifier.new,
    );

/// 帖子详情，key = pin id。刷新列表时详情一并失效。
final pinDetailProvider = FutureProvider.family<PinPost, String>((
  Ref ref,
  String pinId,
) => ref.watch(pinRepositoryProvider).fetchDetail(int.tryParse(pinId) ?? 0));

/// 帖子评论（itemType=4 的 comment 家族），key = pin id。
final pinCommentsProvider = FutureProvider.family<List<TaskComment>, String>((
  Ref ref,
  String pinId,
) => ref.watch(pinRepositoryProvider).fetchComments(int.tryParse(pinId) ?? 0));

/// 帖子点赞人列表（itemType=4 的 like 家族），key = pin id。
final pinLikesProvider = FutureProvider.family<List<TaskComment>, String>((
  Ref ref,
  String pinId,
) => ref.watch(pinRepositoryProvider).fetchLikes(int.tryParse(pinId) ?? 0));

/// 讨论区动作出口：发帖/评论/点赞后失效相关家族。
class PinActionService {
  PinActionService(this._ref);

  final Ref _ref;

  PinRepository get _repo => _ref.read(pinRepositoryProvider);

  Future<void> createPost({
    required int channelId,
    required String content,
    List<String> pictures = const <String>[],
  }) async {
    await _repo.createPost(
      channelId: channelId,
      content: content,
      pictures: pictures,
    );
    _ref.invalidate(pinListProvider);
  }

  Future<void> addComment(int pinId, String content) async {
    await _repo.addComment(pinId, content);
    _ref.invalidate(pinCommentsProvider('$pinId'));
    _ref.invalidate(pinDetailProvider('$pinId'));
    _ref.invalidate(pinListProvider);
  }

  /// 切换点赞（后端 toggle 语义），返回是否处于「已赞」。
  Future<bool> toggleLike(int pinId) async {
    await _repo.toggleLike(pinId);
    _ref.invalidate(pinLikesProvider('$pinId'));
    return true;
  }
}

final Provider<PinActionService> pinActionServiceProvider =
    Provider<PinActionService>((Ref ref) => PinActionService(ref));
