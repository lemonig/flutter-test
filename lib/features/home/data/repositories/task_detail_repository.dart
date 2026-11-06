import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/task_activity.dart';
import '../models/task_detail.dart';
import '../models/task_item.dart';
import '../models/task_process.dart';
import 'home_repository.dart';
import 'ops_user_repository.dart';

/// 异常详情与操作的读写入口（M3-02 ~ M3-05）。
///
/// 所有「能不能做」的判断都来自详情接口返回的 `auth`，
/// 客户端只负责把 `auth` 翻译成按钮的可用状态。
abstract class TaskDetailRepository {
  Future<TaskDetail> fetchDetail(String id);

  Future<List<TaskLogEntry>> fetchLog(String id);

  Future<List<TaskReader>> fetchReaders(String id);

  Future<List<TaskComment>> fetchComments(String id);

  Future<void> addComment(String id, String content);

  Future<List<TaskComment>> fetchLikes(String id);

  /// 后端 `/like` 是**切换语义**：点一次赞，再点一次取消。
  Future<void> toggleLike(String id);

  Future<ErrorUnitCatalog> fetchErrorUnits(String id);

  Future<void> submitProcess(ProcessDraft draft);

  Future<void> saveDraft(ProcessDraft draft);

  Future<void> confirm(String id);

  Future<void> reject(String id, String description);

  Future<void> terminate(String id, String description);

  /// `POST task/transfer`：把任务转交给其他运维人员（C7）。
  ///
  /// 服务端校验：仅待处理、只能转交一次、不能转给自己、
  /// 接收人必须是在职运维；接收人接受前任务处于「转交冻结」，
  /// 双方都不能提交处理结果。
  Future<void> transfer(String id, int toUserId, {bool force = false});
}

/// 评论 / 点赞的目标类型，对齐后端 `CommentTypeEnum.Task(1)`。
const int _kItemTypeTask = 1;

class RemoteTaskDetailRepository implements TaskDetailRepository {
  const RemoteTaskDetailRepository(this._api);

  final ApiClient _api;

  static int _parseId(String id) {
    final int? parsed = int.tryParse(id);
    if (parsed == null) {
      throw const AppException(
        '记录编号无效',
        kind: ApiErrorKind.parse,
        code: 'BAD_TASK_ID',
      );
    }
    return parsed;
  }

  @override
  Future<TaskDetail> fetchDetail(String id) async {
    final ApiResponse response = await _api.getRaw('task/${_parseId(id)}');
    return TaskDetail.fromJson(response.mapData);
  }

  @override
  Future<List<TaskLogEntry>> fetchLog(String id) async {
    final ApiResponse response = await _api.postRaw(
      'task/${_parseId(id)}/log',
      data: const <String, Object?>{},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(TaskLogEntry.fromJson)
        .toList();
  }

  @override
  Future<List<TaskReader>> fetchReaders(String id) async {
    final ApiResponse response = await _api.postRaw(
      'task/${_parseId(id)}/read',
      data: const <String, Object?>{},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(TaskReader.fromJson)
        .toList();
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) => _comments(
    'comment/list',
    _parseId(id),
  );

  @override
  Future<List<TaskComment>> fetchLikes(String id) =>
      _comments('like/list', _parseId(id));

  Future<List<TaskComment>> _comments(String path, int taskId) async {
    final ApiResponse response = await _api.postRaw(
      path,
      data: <String, Object?>{'itemType': _kItemTypeTask, 'itemId': taskId},
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
      'itemType': _kItemTypeTask,
      'itemId': _parseId(id),
      'content': content.trim(),
    },
  );

  @override
  Future<void> toggleLike(String id) => _api.postRaw(
    'like',
    data: <String, Object?>{
      'itemType': _kItemTypeTask,
      'itemId': _parseId(id),
    },
  );

  @override
  Future<ErrorUnitCatalog> fetchErrorUnits(String id) async {
    final ApiResponse response = await _api.getRaw(
      'task/${_parseId(id)}/errorunit',
    );
    return ErrorUnitCatalog.fromJson(response.mapData);
  }

  @override
  Future<void> submitProcess(ProcessDraft draft) =>
      _api.postRaw(draft.outcome.endpoint, data: draft.toJson());

  /// 存草稿与提交走同一个 `updateTask`，区别是状态留在「处理中」，
  /// 且不做 `TaskSubmitValidator` 的必填校验。
  @override
  Future<void> saveDraft(ProcessDraft draft) => _api.postRaw(
    'task/draft',
    data: <String, Object?>{
      'id': draft.taskId,
      'reason': draft.reason.trim(),
      'solution': draft.solution.trim(),
      'instrumentList': draft.instrumentIds,
      'errorUnitList': draft.unitIds,
      'isArrived': draft.isArrived,
      'description': draft.description,
    },
  );

  @override
  Future<void> confirm(String id) => _api.postRaw(
    'task/${_parseId(id)}/confirm',
    data: const <String, Object?>{},
  );

  @override
  Future<void> reject(String id, String description) => _api.postRaw(
    'task/${_parseId(id)}/reject',
    data: <String, Object?>{'description': description.trim()},
  );

  @override
  Future<void> terminate(String id, String description) => _api.postRaw(
    'task/${_parseId(id)}/terminate',
    data: <String, Object?>{'description': description.trim()},
  );

  /// 对齐后端 `JobTransferLog`：`fromUserId` 由服务端从 token 解出，
  /// `jobType` 只在巡检转交时才有意义，故障转交无需传。
  @override
  Future<void> transfer(String id, int toUserId, {bool force = false}) =>
      _api.postRaw(
        'task/transfer',
        data: <String, Object?>{
          'jobId': _parseId(id),
          'toUserId': toUserId,
          'force': force,
        },
      );
}

/// 演示实现：让 `green-ops-demo.apk` 在没有后端时也能走完
/// 「处理 → 确认 / 终止」整条链路，状态在进程内留存。
class MockTaskDetailRepository implements TaskDetailRepository {
  MockTaskDetailRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static final Map<String, TaskDetail> _store = <String, TaskDetail>{};
  static final Map<String, List<TaskLogEntry>> _logs =
      <String, List<TaskLogEntry>>{};
  static final Map<String, List<TaskComment>> _comments =
      <String, List<TaskComment>>{};
  static final Set<String> _liked = <String>{};

  static const List<TaskPerson> _people = <TaskPerson>[
    TaskPerson(id: 1, nickname: '张伟'),
    TaskPerson(id: 2, nickname: '李娜'),
    TaskPerson(id: 3, nickname: '王强'),
    TaskPerson(id: 4, nickname: '赵敏'),
  ];

  /// 演示详情直接由首页 mock 列表推导，保证「列表说是什么，详情就是什么」，
  /// 不另造一套假数据，否则站点名 / 处理人 / 状态会对不上。
  static TaskDetail _seed(String id) {
    final List<TaskItem> samples = MockHomeRepository.abnormalSamples;
    TaskItem? item;
    for (final TaskItem candidate in samples) {
      if (candidate.id == id) {
        item = candidate;
        break;
      }
    }

    final String tag = item?.tags.isNotEmpty == true ? item!.tags.first : '处理中';
    final TaskState state = switch (tag) {
      '待处理' => TaskState.todo,
      '已完成' || '已修复' || '非异常' => TaskState.fixed,
      '已关闭' => TaskState.confirmed,
      '已终止' => TaskState.terminated,
      _ => TaskState.doing,
    };
    final bool submitted =
        state.isSubmitted || state == TaskState.terminated;

    final String digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    final int numericId =
        int.tryParse(id) ?? (int.tryParse(digits) ?? id.hashCode.abs() % 9000);

    final String creator = _people[numericId % _people.length].nickname;
    final String executor = item?.executor.isNotEmpty == true
        ? item!.executor
        : _people[(numericId + 1) % _people.length].nickname;

    return TaskDetail(
      id: numericId,
      jobNumber: 'YC0120261105${digits.padLeft(5, '0')}',
      state: state,
      content: item?.content ?? '演示异常记录',
      stationName: item?.stationName ?? '演示站点',
      regionText: '浙江省 嘉兴市 南湖区',
      creator: TaskPerson(nickname: creator),
      executor: TaskPerson(nickname: executor),
      stationManager: TaskPerson(nickname: creator),
      gmtCreate: item?.timeText.replaceFirst(' ', 'T').isEmpty == false
          ? '${item!.timeText.replaceFirst(' ', 'T')}:00.000+0800'
          : '2026-11-04T09:12:00.000+0800',
      gmtHappen: '2026-11-04T08:40:00.000+0800',
      deadline: '2026-11-06T20:00:00.000+0800',
      gmtSolved: submitted ? '2026-11-04T11:20:00.000+0800' : null,
      overtime: state == TaskState.todo,
      timeUsageSolved: submitted ? '2小时8分钟' : '38分钟',
      remind: 4,
      errorUnit: submitted ? 'CODcr分析仪GR-2116、采水单元' : '',
      reason: submitted ? '标液过期导致核查偏差' : '',
      solution: submitted ? '重新配置标液并连续观察三个周期，数据恢复正常' : '',
      contentPictures: <TaskPhoto>[
        for (final String url in item?.images ?? const <String>[])
          TaskPhoto(url: url.replaceFirst('/600', '/900'), title: '异常描述'),
      ],
      submitPictures: submitted
          ? <TaskPhoto>[
              const TaskPhoto(
                url: 'https://picsum.photos/seed/gc-fix1/900',
                title: '处理前',
              ),
              const TaskPhoto(
                url: 'https://picsum.photos/seed/gc-fix2/900',
                title: '处理后',
              ),
            ]
          : const <TaskPhoto>[],
      auth: TaskAuth(
        enableToSubmit: state.isOpen,
        enableToTerminate: state.isOpen,
        enableToConfirm: state.isSubmitted,
        enableToEdit: state == TaskState.todo,
      ),
    );
  }

  static TaskDetail _of(String id) =>
      _store.putIfAbsent(id, () => _seed(id));

  /// 处理提交只带得到数字 id，演示数据的主键却是列表里的字符串 id，
  /// 这里反查一次，避免提交后凭空多出一条新记录。
  static String _keyFor(int taskId) {
    for (final String key in _store.keys) {
      if (_of(key).id == taskId) return key;
    }
    return '$taskId';
  }

  static List<TaskLogEntry> _logOf(String id) => _logs.putIfAbsent(
    id,
    () => <TaskLogEntry>[
      TaskLogEntry(
        id: 1,
        content: '创建了故障',
        stateLabel: '待处理',
        time: _of(id).gmtCreate,
        user: _of(id).creator,
      ),
      TaskLogEntry(
        id: 2,
        content: '分派给 ${_of(id).executor?.nickname ?? '运维'}',
        stateLabel: '待处理',
        time: _of(id).gmtCreate,
        user: _of(id).creator,
      ),
    ],
  );

  void _appendLog(String id, String content, TaskState state) {
    final List<TaskLogEntry> logs = _logOf(id);
    logs.insert(
      0,
      TaskLogEntry(
        id: logs.length + 10,
        content: content,
        stateLabel: state.label,
        time: DateTime.now().toIso8601String(),
        user: _of(id).executor,
      ),
    );
  }

  @override
  Future<TaskDetail> fetchDetail(String id) async {
    await Future<void>.delayed(delay);
    return _of(id);
  }

  @override
  Future<List<TaskLogEntry>> fetchLog(String id) async {
    await Future<void>.delayed(delay);
    return List<TaskLogEntry>.unmodifiable(_logOf(id));
  }

  @override
  Future<List<TaskReader>> fetchReaders(String id) async {
    await Future<void>.delayed(delay);
    return <TaskReader>[
      TaskReader(
        userId: 1,
        time: _of(id).gmtCreate,
        person: _people[0],
      ),
      TaskReader(userId: 2, time: _of(id).gmtCreate, person: _people[1]),
      TaskReader(userId: 3, time: _of(id).gmtCreate, person: _people[2]),
    ];
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) async {
    await Future<void>.delayed(delay);
    return _comments.putIfAbsent(
      id,
      () => <TaskComment>[
        TaskComment(
          id: 1,
          content: '已联系厂家，预计下午到场处理。',
          time: '2026-11-04T10:20:00.000+0800',
          person: _people[1],
          creatorId: 2,
        ),
      ],
    );
  }

  @override
  Future<void> addComment(String id, String content) async {
    await Future<void>.delayed(delay);
    final List<TaskComment> list = await fetchComments(id);
    list.insert(
      0,
      TaskComment(
        id: list.length + 1,
        content: content.trim(),
        time: DateTime.now().toIso8601String(),
        person: const TaskPerson(id: 99, nickname: '我'),
        creatorId: 99,
      ),
    );
  }

  @override
  Future<List<TaskComment>> fetchLikes(String id) async {
    await Future<void>.delayed(delay);
    if (!_liked.contains(id)) return const <TaskComment>[];
    return <TaskComment>[
      TaskComment(id: 1, content: '', person: const TaskPerson(nickname: '我')),
    ];
  }

  @override
  Future<void> toggleLike(String id) async {
    await Future<void>.delayed(delay);
    if (!_liked.remove(id)) _liked.add(id);
  }

  @override
  Future<ErrorUnitCatalog> fetchErrorUnits(String id) async {
    await Future<void>.delayed(delay);
    return const ErrorUnitCatalog(
      instruments: <ErrorUnitOption>[
        ErrorUnitOption(value: 27, label: '五参数分析仪GR-6600（自研）'),
        ErrorUnitOption(value: 37, label: 'CODcr分析仪GR-2116'),
        ErrorUnitOption(value: 67, label: '氨氮分析仪GR-3411-12通阀版'),
      ],
      controls: <ErrorUnitOption>[
        ErrorUnitOption(value: 1, label: '采水单元'),
        ErrorUnitOption(value: 2, label: '配水单元'),
        ErrorUnitOption(value: 3, label: '控制单元'),
      ],
      others: <ErrorUnitOption>[
        ErrorUnitOption(value: 11, label: '站房'),
        ErrorUnitOption(value: 12, label: '供电'),
        ErrorUnitOption(value: 13, label: '网络'),
      ],
    );
  }

  @override
  Future<void> submitProcess(ProcessDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 480));
    final String id = _keyFor(draft.taskId);
    final TaskDetail current = _of(id);
    _store[id] = current.copyWith(
      state: draft.outcome == ProcessOutcome.fixed
          ? TaskState.fixed
          : TaskState.notError,
      reason: draft.reason,
      solution: draft.solution,
      gmtSolved: DateTime.now().toIso8601String(),
      auth: const TaskAuth(enableToConfirm: true),
    );
    _appendLog(id, draft.outcome.label, _store[id]!.state);
  }

  @override
  Future<void> saveDraft(ProcessDraft draft) async {
    await Future<void>.delayed(delay);
    final String id = _keyFor(draft.taskId);
    _store[id] = _of(id).copyWith(
      state: TaskState.doing,
      reason: draft.reason,
      solution: draft.solution,
    );
    _appendLog(id, '保存了处理草稿', TaskState.doing);
  }

  @override
  Future<void> confirm(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    _store[id] = _of(id).copyWith(
      state: TaskState.confirmed,
      auth: const TaskAuth(),
    );
    _appendLog(id, '确认关闭', TaskState.confirmed);
  }

  @override
  Future<void> reject(String id, String description) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    _store[id] = _of(id).copyWith(
      state: TaskState.doing,
      auth: const TaskAuth(enableToSubmit: true, enableToTerminate: true),
    );
    _appendLog(id, '拒绝修复：$description', TaskState.doing);
  }

  @override
  Future<void> terminate(String id, String description) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    _store[id] = _of(id).copyWith(
      state: TaskState.terminated,
      auth: const TaskAuth(),
    );
    _appendLog(id, '终止任务：$description', TaskState.terminated);
  }

  @override
  Future<void> transfer(String id, int toUserId, {bool force = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final TaskDetail current = _of(id);
    if (current.state != TaskState.todo) {
      throw const AppException(
        '仅待处理的任务可以转交',
        kind: ApiErrorKind.business,
        code: 'FIELD_ERROR',
      );
    }
    String toName = '运维同事';
    for (final OpsUser user in MockOpsUserRepository.mockOpsUsers) {
      if (user.id == toUserId) toName = user.nickname;
    }
    // 对齐服务端：非强转时接收人还没接受，任务进入「转交冻结」，
    // 当前账号不能再提交处理结果（enableToSubmit = false）。
    _store[id] = current.copyWith(auth: const TaskAuth());
    _appendLog(id, '转交任务给$toName，待接受', current.state);
  }
}

final Provider<TaskDetailRepository> taskDetailRepositoryProvider =
    Provider<TaskDetailRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockTaskDetailRepository();
      return RemoteTaskDetailRepository(ref.watch(apiClientProvider));
    });
