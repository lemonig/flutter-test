import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_response.dart';
import '../models/message_models.dart';

/// 消息模块数据源。
///
/// 后端三条接口（`MessageController`）：
/// - `POST message/list`  → 七个分类的最新一条 + 各自未读数
/// - `POST message/type`  → 某分类的消息明细分页；**取一次即把该分类标记为已读**
/// - `POST message/transfer` → 转交任务同意 / 拒绝
abstract class MessageRepository {
  /// 上次分页请求后端是否还有下一页；演示数据源返回 null 由调用方按条数推断。
  bool? get lastResponseHasMore;

  Future<List<MessageCategory>> fetchCategories();

  Future<List<MessageItem>> fetchMessages({
    required MessageType type,
    required int page,
    required int pageSize,
  });

  /// 转交任务处置。[accepted] 为 true 同意、false 拒绝。
  Future<void> transfer({required int messageId, required bool accepted});
}

class RemoteMessageRepository implements MessageRepository {
  RemoteMessageRepository(this._api);

  final ApiClient _api;

  bool? _lastHasMore;

  @override
  bool? get lastResponseHasMore => _lastHasMore;

  @override
  Future<List<MessageCategory>> fetchCategories() async {
    final ApiResponse response = await _api.postRaw('message/list');
    return response.listData
        .map(MessageCategory.fromJson)
        .whereType<MessageCategory>()
        .toList();
  }

  @override
  Future<List<MessageItem>> fetchMessages({
    required MessageType type,
    required int page,
    required int pageSize,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'message/type',
      data: <String, Object?>{
        'type': type.code,
        'startPage': page,
        'limit': pageSize,
      },
    );
    _lastHasMore = response.hasMoreItems;
    return response.listData
        .map(MessageItem.fromJson)
        .whereType<MessageItem>()
        .toList();
  }

  @override
  Future<void> transfer({
    required int messageId,
    required bool accepted,
  }) async {
    await _api.postRaw(
      'message/transfer',
      data: <String, Object?>{'id': messageId, 'accepted': accepted},
    );
  }
}

/// 演示数据源：七个分类齐全，其中转交分类留一条待处理消息，
/// 让「同意 / 拒绝」在演示包里也能点通（结果只存在内存里）。
class MockMessageRepository implements MessageRepository {
  MockMessageRepository();

  @override
  bool? get lastResponseHasMore => _lastHasMore;

  bool? _lastHasMore;

  static const List<MessageCategory> _categories = <MessageCategory>[
    MessageCategory(
      type: MessageType.task,
      name: '异常任务',
      latestTitle: '南湖水质自动监测站-氨氮数据异常',
      latestTime: '2026-11-05 09:46',
      unread: 2,
    ),
    MessageCategory(
      type: MessageType.ops,
      name: '巡检任务',
      latestTitle: '澉浦断面监测站-日常巡检任务',
      latestTime: '2026-11-05 08:10',
      unread: 1,
    ),
    MessageCategory(
      type: MessageType.transfer,
      name: '转交任务',
      latestTitle: '王强转交了一条巡检任务给你',
      latestTime: '2026-11-04 17:20',
      unread: 1,
    ),
    MessageCategory(
      type: MessageType.comment,
      name: '收到评论',
      latestTitle: '【异常任务】李娜评论了你',
      latestTime: '2026-11-04 15:02',
      unread: 0,
    ),
    MessageCategory(
      type: MessageType.like,
      name: '收到的赞',
      latestTitle: '【巡检任务】王强给你点了个赞',
      latestTime: '2026-11-03 11:35',
      unread: 0,
    ),
    MessageCategory(
      type: MessageType.apply,
      name: '我的申请',
      latestTitle: '您的试剂申请已通过',
      latestTime: '2026-11-02 10:12',
      unread: 0,
    ),
    MessageCategory(
      type: MessageType.approve,
      name: '我的审批',
      latestTitle: '李娜的试剂申请',
      latestTime: '2026-11-01 09:03',
      unread: 0,
    ),
  ];

  static const Map<MessageType, List<MessageItem>> _messages =
      <MessageType, List<MessageItem>>{
        MessageType.task: <MessageItem>[
          MessageItem(
            id: 9001,
            type: MessageType.task,
            title: '南湖水质自动监测站-氨氮数据异常',
            content: '氨氮连续 4 小时超标，已派发处理任务',
            leftLabel: '来源:张海峰',
            rightLabel: '截止时间:2026-11-06 09:46',
            timeText: '11-05 09:46',
            jobId: null,
          ),
          MessageItem(
            id: 9002,
            type: MessageType.task,
            title: '运河三塔断面-COD 数据缺测',
            content: '传输模块离线，需现场排查',
            leftLabel: '来源:李娜',
            rightLabel: '截止时间:2026-11-05 18:00',
            timeText: '11-04 16:20',
            jobId: null,
          ),
        ],
        MessageType.ops: <MessageItem>[
          MessageItem(
            id: 9010,
            type: MessageType.ops,
            title: '澉浦断面监测站-日常巡检任务',
            content: '',
            leftLabel: '巡检项目:12条',
            rightLabel: '截止时间:2026-11-06 08:00',
            timeText: '11-05 08:10',
            jobId: null,
          ),
        ],
        MessageType.transfer: <MessageItem>[
          MessageItem(
            id: 9020,
            type: MessageType.transfer,
            title: '王强转交了一条巡检任务给你',
            content: '',
            leftLabel: '站点:北郊河站',
            rightLabel: '截止时间:2026-11-07 18:00',
            timeText: '11-04 17:20',
            jobId: null,
          ),
        ],
        MessageType.comment: <MessageItem>[
          MessageItem(
            id: 9030,
            type: MessageType.comment,
            title: '【异常任务】李娜评论了你',
            content: '现场照片已补，麻烦复核',
            leftLabel: '',
            rightLabel: '',
            timeText: '11-04 15:02',
            jobId: null,
          ),
        ],
        MessageType.like: <MessageItem>[
          MessageItem(
            id: 9040,
            type: MessageType.like,
            title: '【巡检任务】王强给你点了个赞',
            content: '',
            leftLabel: '',
            rightLabel: '',
            timeText: '11-03 11:35',
            jobId: null,
          ),
        ],
        MessageType.apply: <MessageItem>[
          MessageItem(
            id: 9050,
            type: MessageType.apply,
            title: '您的试剂申请已通过',
            content: '',
            leftLabel: '',
            rightLabel: '申请时间:2026-11-02 10:12',
            timeText: '11-02 10:12',
            jobId: null,
          ),
        ],
        MessageType.approve: <MessageItem>[
          MessageItem(
            id: 9060,
            type: MessageType.approve,
            title: '李娜的试剂申请',
            content: '',
            leftLabel: '申请人:李娜',
            rightLabel: '申请时间:2026-11-01 09:03',
            timeText: '11-01 09:03',
            jobId: null,
          ),
        ],
      };

  /// 转交处置结果（内存态，重启即还原）。
  final Map<int, bool> _transferResults = <int, bool>{};

  /// 已读过的分类。
  ///
  /// 后端 `getMessageListByType` 会先 `readMessage` 再把数据查出来，
  /// 即「取一次列表 = 该分类全部已读」。演示数据源必须照着做，
  /// 否则点进去再返回，角标还在，和真机表现不一致。
  final Set<MessageType> _readTypes = <MessageType>{};

  @override
  Future<List<MessageCategory>> fetchCategories() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return <MessageCategory>[
      for (final MessageCategory item in _categories)
        _readTypes.contains(item.type) ? item.copyWith(unread: 0) : item,
    ];
  }

  @override
  Future<List<MessageItem>> fetchMessages({
    required MessageType type,
    required int page,
    required int pageSize,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    _readTypes.add(type);
    _lastHasMore = false;
    final List<MessageItem> items = _messages[type] ?? const <MessageItem>[];
    return <MessageItem>[
      for (final MessageItem item in items)
        if (_transferResults.containsKey(item.id))
          MessageItem(
            id: item.id,
            type: item.type,
            title: item.title,
            content: _transferResults[item.id]! ? '已同意' : '已拒绝',
            leftLabel: item.leftLabel,
            rightLabel: item.rightLabel,
            timeText: item.timeText,
            jobId: item.jobId,
            accepted: _transferResults[item.id],
          )
        else
          item,
    ];
  }

  @override
  Future<void> transfer({
    required int messageId,
    required bool accepted,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _transferResults[messageId] = accepted;
  }
}
