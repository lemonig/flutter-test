/// 讨论区帖子模型（M8-01 ~ M8-03）。
///
/// 后端契约见 `ops-mobile` 的 `PinController` + iOS `DiscussionListModel`：
/// `pin/list` / `pin/{id}/info` 返回 `Pin`（评论点赞走通用 comment/like
/// 家族，itemType=4，2026-11-07 实测）。
library;

class PinChannel {
  const PinChannel({required this.id, this.name = ''});

  final int id;
  final String name;

  static PinChannel fromJson(Object? raw) {
    if (raw is! Map) return const PinChannel(id: 0);
    return PinChannel(
      id: raw['id'] is int ? raw['id']! as int : 0,
      name: (raw['name'] ?? '').toString(),
    );
  }
}

/// 帖子；[pictures] 与任务图片同构（`[{url}]` 或 `[url]` 两种实测形态都兼容）。
class PinPost {
  const PinPost({
    required this.id,
    this.content = '',
    this.title = '',
    this.channel = '',
    this.channelId = 0,
    this.nickname = '',
    this.avatar = '',
    this.pictures = const <String>[],
    this.gmtCreate = '',
    this.beenTop = false,
    this.commentCount = 0,
    this.likeCount = 0,
  });

  final int id;
  final String title;
  final String content;
  final String channel;
  final int channelId;
  final String nickname;
  final String avatar;
  final List<String> pictures;
  final String gmtCreate;
  final bool beenTop;
  final int commentCount;
  final int likeCount;

  static PinPost fromJson(Object? raw) {
    if (raw is! Map) return const PinPost(id: 0);
    String t(Object? v) => (v ?? '').toString();
    int n(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    final Object? user = raw['user'];
    return PinPost(
      id: n(raw['id']),
      title: t(raw['title']),
      content: t(raw['content']),
      channel: t(raw['channel']),
      channelId: n(raw['channelId'] ?? raw['channel_id']),
      nickname: user is Map ? t(user['nickname']) : t(raw['nickname']),
      avatar: user is Map ? t(user['avatar']) : t(raw['avatar']),
      pictures: _pictures(raw['pictures'] ?? raw['pictureList']),
      gmtCreate: t(raw['gmt_create']),
      beenTop: raw['been_top'] == true,
      commentCount: n(raw['countComment']),
      likeCount: n(raw['countLike']),
    );
  }

  /// 后端两种形态：字符串数组（发帖提交的 objectKey）或
  /// `[{url, title}]`（列表/详情返回 PictureBO）。
  static List<String> _pictures(Object? raw) {
    if (raw is! List) return const <String>[];
    return <String>[
      for (final Object? item in raw)
        if (item is String && item.isNotEmpty)
          item
        else if (item is Map)
          (item['url'] ?? '').toString(),
    ].where((String url) => url.isNotEmpty).toList(growable: false);
  }
}
