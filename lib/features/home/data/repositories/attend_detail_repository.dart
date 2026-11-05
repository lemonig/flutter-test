import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/attend_detail.dart';
import '../models/task_activity.dart';
import '../models/task_detail.dart';

/// 签到详情与互动（M5-03）。
///
/// 详情走 `GET attend/{id}`；评论与点赞复用任务那套接口，但
/// `itemType` 必须是 `CommentTypeEnum.Attend(2)`，用 1 会把评论挂到任务上，
/// 签到详情里永远看不到。
abstract class AttendDetailRepository {
  Future<AttendDetail> fetchDetail(String id);

  Future<List<TaskComment>> fetchComments(String id);

  Future<void> addComment(String id, String content);

  Future<List<TaskComment>> fetchLikes(String id);

  /// 后端 `/like` 是切换语义：点一次赞，再点一次取消。
  Future<void> toggleLike(String id);
}

/// 对齐后端 `CommentTypeEnum.Attend(2)`。
const int kAttendItemType = 2;

class RemoteAttendDetailRepository implements AttendDetailRepository {
  const RemoteAttendDetailRepository(this._api);

  final ApiClient _api;

  static int _parseId(String id) {
    final int? parsed = int.tryParse(id);
    if (parsed == null) {
      throw const AppException(
        '签到记录编号无效',
        kind: ApiErrorKind.parse,
        code: 'BAD_ATTEND_ID',
      );
    }
    return parsed;
  }

  @override
  Future<AttendDetail> fetchDetail(String id) async {
    final ApiResponse response = await _api.getRaw('attend/${_parseId(id)}');
    return AttendDetail.fromJson(response.data);
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) =>
      _comments('comment/list', _parseId(id));

  @override
  Future<List<TaskComment>> fetchLikes(String id) =>
      _comments('like/list', _parseId(id));

  Future<List<TaskComment>> _comments(String path, int itemId) async {
    final ApiResponse response = await _api.postRaw(
      path,
      data: <String, Object?>{'itemType': kAttendItemType, 'itemId': itemId},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(TaskComment.fromJson)
        .toList();
  }

  @override
  Future<void> addComment(String id, String content) => _api.postRaw(
    'comment',
    data: <String, Object?>{
      'itemType': kAttendItemType,
      'itemId': _parseId(id),
      'content': content.trim(),
    },
  );

  @override
  Future<void> toggleLike(String id) => _api.postRaw(
    'like',
    data: <String, Object?>{
      'itemType': kAttendItemType,
      'itemId': _parseId(id),
    },
  );
}

/// 演示实现：状态存在内存里，点赞与评论在本次运行内可见。
class MockAttendDetailRepository implements AttendDetailRepository {
  MockAttendDetailRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static final Map<String, List<TaskComment>> _comments =
      <String, List<TaskComment>>{};
  static final Set<String> _liked = <String>{};

  static const TaskPerson _demoPerson = TaskPerson(
    id: 1001,
    nickname: '张伟',
    avatar: '',
  );

  static AttendDetail demoDetail(String id) {
    final bool second = id.endsWith('2');
    return AttendDetail(
      id: id,
      jobNumber: second ? 'QD20261103001' : 'QD20261104007',
      address: second
          ? '浙江省嘉兴市海盐县澉浦镇南北湖大道 18 号'
          : '浙江省嘉兴市南湖区南湖景区东侧监测站',
      description: second
          ? '陪同厂家工程师检修 4G 传输模块，现场数据恢复正常。'
          : '到达站点完成定位签到，今日计划完成异常处置与仪表核查。',
      longitude: second ? 120.9453 : 120.7628,
      latitude: second ? 30.4712 : 30.7489,
      time: second ? '2026-11-03T08:12:00.000+0800' : '2026-11-04T07:58:00.000+0800',
      person: _demoPerson,
      stationId: second ? 9002 : 9001,
      stationName: second ? '嘉兴市海盐县澉浦断面监测站' : '嘉兴市南湖水质自动监测站',
      pictures: second
          ? const <TaskPhoto>[]
          : const <TaskPhoto>[
              TaskPhoto(url: 'https://picsum.photos/seed/gc-si1/900'),
              TaskPhoto(url: 'https://picsum.photos/seed/gc-si1b/900'),
            ],
    );
  }

  @override
  Future<AttendDetail> fetchDetail(String id) async {
    await Future<void>.delayed(delay);
    return demoDetail(id);
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) async {
    await Future<void>.delayed(delay);
    return _comments[id] ?? const <TaskComment>[];
  }

  @override
  Future<List<TaskComment>> fetchLikes(String id) async {
    await Future<void>.delayed(delay);
    return _liked.contains(id) ? demoLikes : const <TaskComment>[];
  }

  @override
  Future<void> addComment(String id, String content) async {
    await Future<void>.delayed(delay);
    final List<TaskComment> list = _comments.putIfAbsent(
      id,
      () => <TaskComment>[],
    );
    list.insert(
      0,
      TaskComment(
        id: DateTime.now().millisecondsSinceEpoch,
        content: content,
        time: DateTime.now().toIso8601String(),
        person: _demoPerson,
        creatorId: _demoPerson.id,
      ),
    );
  }

  @override
  Future<void> toggleLike(String id) async {
    await Future<void>.delayed(delay);
    if (!_liked.remove(id)) _liked.add(id);
  }

  static const List<TaskComment> demoLikes = <TaskComment>[
    TaskComment(id: 1, content: '', person: _demoPerson, creatorId: 1001),
  ];
}

final Provider<AttendDetailRepository> attendDetailRepositoryProvider =
    Provider<AttendDetailRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockAttendDetailRepository();
      return RemoteAttendDetailRepository(ref.watch(apiClientProvider));
    });
