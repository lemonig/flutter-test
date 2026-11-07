import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../../../../features/home/data/models/task_activity.dart';
import '../../../../features/home/data/models/task_detail.dart';
import '../models/pin_post.dart';

/// 讨论区（M8，对照 iOS Discussion / PostArticle 模块）。
///
/// 接口（2026-11-07 实测）：
/// - 频道 `POST pin/channel` → `[{id, name}]`；
/// - 列表 `POST pin/list` body `{startPage, limit, type?}`（type=频道 id，
///   不传 = 全部）；分页看 `additional_data.more_items_in_collection`；
/// - 详情 `POST pin/{id}/info`（body 可空 `{}`）；
/// - 发帖 `POST pin/post` body `{channel_id, content, pictures[]}`，
///   pictures 是 `upload/5/file` 产出的 objectKey，服务端补 userId；
/// - 评论 / 点赞走通用家族：`itemType = 4`（iOS postType 4 同源）。
abstract class PinRepository {
  Future<List<PinChannel>> fetchChannels();

  Future<PinPage> fetchPosts({int channelId = 0, int page = 1, int pageSize = 10});

  Future<PinPost> fetchDetail(int id);

  Future<void> createPost({
    required int channelId,
    required String content,
    List<String> pictures = const <String>[],
  });

  Future<List<TaskComment>> fetchComments(int pinId);

  /// 点赞人列表（`like/list`，itemType=4，CommentVo 同构）。
  Future<List<TaskComment>> fetchLikes(int pinId);

  Future<void> addComment(int pinId, String content);

  Future<void> toggleLike(int pinId);
}

/// 分页结果；hasMore 优先取服务端 `more_items_in_collection`。
class PinPage {
  const PinPage({required this.items, required this.hasMore});

  final List<PinPost> items;
  final bool hasMore;
}

class RemotePinRepository implements PinRepository {
  const RemotePinRepository(this._api);

  final ApiClient _api;

  static const int _kItemTypePin = 4;

  @override
  Future<List<PinChannel>> fetchChannels() async {
    final ApiResponse response = await _api.postRaw(
      'pin/channel',
      data: const <String, Object?>{},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(PinChannel.fromJson)
        .toList();
  }

  @override
  Future<PinPage> fetchPosts({
    int channelId = 0,
    int page = 1,
    int pageSize = 10,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'pin/list',
      data: <String, Object?>{
        'startPage': page,
        'limit': pageSize,
        if (channelId > 0) 'type': channelId,
      },
    );
    return PinPage(
      items: response.listData
          .whereType<Map<Object?, Object?>>()
          .map(PinPost.fromJson)
          .toList(),
      hasMore: response.hasMoreItems ?? false,
    );
  }

  @override
  Future<PinPost> fetchDetail(int id) async {
    final ApiResponse response = await _api.postRaw(
      'pin/$id/info',
      data: const <String, Object?>{},
    );
    return PinPost.fromJson(response.mapData);
  }

  @override
  Future<void> createPost({
    required int channelId,
    required String content,
    List<String> pictures = const <String>[],
  }) => _api.postRaw(
    'pin/post',
    data: <String, Object?>{
      if (channelId > 0) 'channel_id': channelId,
      'content': content.trim(),
      if (pictures.isNotEmpty) 'pictures': pictures,
    },
  );

  @override
  Future<List<TaskComment>> fetchComments(int pinId) async {
    final ApiResponse response = await _api.postRaw(
      'comment/list',
      data: <String, Object?>{'itemType': _kItemTypePin, 'itemId': pinId},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(TaskComment.fromJson)
        .toList();
  }

  @override
  Future<List<TaskComment>> fetchLikes(int pinId) async {
    final ApiResponse response = await _api.postRaw(
      'like/list',
      data: <String, Object?>{'itemType': _kItemTypePin, 'itemId': pinId},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(TaskComment.fromJson)
        .toList();
  }

  @override
  Future<void> addComment(int pinId, String content) => _api.postRaw(
    'comment',
    data: <String, Object?>{
      'itemType': _kItemTypePin,
      'itemId': pinId,
      'content': content.trim(),
    },
  );

  @override
  Future<void> toggleLike(int pinId) => _api.postRaw(
    'like',
    data: <String, Object?>{'itemType': _kItemTypePin, 'itemId': pinId},
  );
}

/// 演示实现：进程内留存（发帖/评论/点赞都有副作用），与真实后端同语义。
class MockPinRepository implements PinRepository {
  MockPinRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static const List<PinChannel> _channels = <PinChannel>[
    PinChannel(id: 1, name: 'App反馈'),
    PinChannel(id: 2, name: '问与答'),
    PinChannel(id: 3, name: '经验分享'),
  ];

  static final List<PinPost> _store = <PinPost>[
    const PinPost(
      id: 262,
      title: '漠江站运维任务无法填报',
      content: '因无法定位，运维任务填不了，换了手机也一样，麻烦看下是什么原因。',
      channel: 'App反馈',
      channelId: 1,
      nickname: '陈二冬',
      gmtCreate: '2026-11-05T12:53:12.000+0800',
      commentCount: 1,
      likeCount: 2,
    ),
    const PinPost(
      id: 261,
      content: '问一下大家 COD 试剂开封后的有效期是多久？说明书上写的一个月，你们一般怎么管理？',
      channel: '问与答',
      channelId: 2,
      nickname: '吴天阁',
      gmtCreate: '2026-11-04T09:20:00.000+0800',
      commentCount: 0,
      likeCount: 1,
    ),
    const PinPost(
      id: 260,
      content: '分享一个蠕动泵管更换的小技巧：先把泵头松半圈再抽管，比硬拔省力很多，也不会伤到卡槽。',
      channel: '经验分享',
      channelId: 3,
      nickname: '许海洋',
      gmtCreate: '2026-11-03T16:40:00.000+0800',
      likeCount: 5,
    ),
  ];

  static final Map<int, List<TaskComment>> _comments = <int, List<TaskComment>>{
    262: <TaskComment>[
      TaskComment(
        id: 1,
        content: '已反馈给研发，下个版本修复定位问题。',
        time: '2026-11-06T08:37:20.000+0800',
        person: const TaskPerson(id: 16, nickname: '卜幸杰'),
        creatorId: 16,
      ),
    ],
  };

  static final Set<int> _liked = <int>{};
  static int _nextId = 900;
  static int _nextCommentId = 100;

  @override
  Future<List<PinChannel>> fetchChannels() async {
    await Future<void>.delayed(delay);
    return List<PinChannel>.unmodifiable(_channels);
  }

  @override
  Future<PinPage> fetchPosts({
    int channelId = 0,
    int page = 1,
    int pageSize = 10,
  }) async {
    await Future<void>.delayed(delay);
    final List<PinPost> matched = channelId <= 0
        ? _store
        : _store.where((PinPost post) => post.channelId == channelId).toList();
    final int start = (page - 1) * pageSize;
    return PinPage(
      items: start >= matched.length
          ? const <PinPost>[]
          : List<PinPost>.unmodifiable(
              matched.sublist(start, (start + pageSize).clamp(0, matched.length)),
            ),
      hasMore: start + pageSize < matched.length,
    );
  }

  @override
  Future<PinPost> fetchDetail(int id) async {
    await Future<void>.delayed(delay);
    for (final PinPost post in _store) {
      if (post.id == id) return post;
    }
    throw AppException('帖子不存在或已被删除', kind: ApiErrorKind.business);
  }

  @override
  Future<void> createPost({
    required int channelId,
    required String content,
    List<String> pictures = const <String>[],
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (content.trim().isEmpty) {
      throw const AppException('内容不能为空', kind: ApiErrorKind.business);
    }
    String channel = '';
    for (final PinChannel c in _channels) {
      if (c.id == channelId) channel = c.name;
    }
    _store.insert(
      0,
      PinPost(
        id: ++_nextId,
        content: content.trim(),
        channel: channel,
        channelId: channelId,
        nickname: '张伟',
        gmtCreate: DateTime.now().toIso8601String(),
        pictures: List<String>.of(pictures),
      ),
    );
  }

  @override
  Future<List<TaskComment>> fetchComments(int pinId) async {
    await Future<void>.delayed(delay);
    return List<TaskComment>.unmodifiable(
      _comments.putIfAbsent(pinId, () => <TaskComment>[]),
    );
  }

  @override
  Future<List<TaskComment>> fetchLikes(int pinId) async {
    await Future<void>.delayed(delay);
    if (!_liked.contains(pinId)) return const <TaskComment>[];
    return <TaskComment>[
      const TaskComment(id: 1, content: '', person: TaskPerson(nickname: '我')),
    ];
  }

  @override
  Future<void> addComment(int pinId, String content) async {
    await Future<void>.delayed(delay);
    final List<TaskComment> list = _comments.putIfAbsent(pinId, () => <TaskComment>[]);
    list.insert(
      0,
      TaskComment(
        id: ++_nextCommentId,
        content: content.trim(),
        time: DateTime.now().toIso8601String(),
        person: const TaskPerson(id: 1001, nickname: '张伟'),
        creatorId: 1001,
      ),
    );
  }

  @override
  Future<void> toggleLike(int pinId) async {
    await Future<void>.delayed(delay);
    if (!_liked.remove(pinId)) _liked.add(pinId);
  }
}

final Provider<PinRepository> pinRepositoryProvider =
    Provider<PinRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockPinRepository();
      return RemotePinRepository(ref.watch(apiClientProvider));
    });
