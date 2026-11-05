/// 异常详情模型（M3-02），字段对齐后端 `TaskDetailItemVO`。
///
/// 后端契约见 `ops-mobile` 的 `TaskService#getTaskDetail`：
/// 详情接口是 `GET task/{id}`，且**读取即已读**（服务端顺手写 read 记录），
/// 所以页面每次刷新都会让已读人数 +1，这是服务端行为，不是重复请求。
library;

/// 后端 `TaskStateEnum`：1 待处理 / 2 处理中 / 3 已修复 / 4 非异常
/// / 5 已关闭 / 6 已拒绝 / 7 已终止。
enum TaskState {
  todo(1, '待处理'),
  doing(2, '处理中'),
  fixed(3, '已修复'),
  notError(4, '非异常'),
  confirmed(5, '已关闭'),
  rejected(6, '已拒绝'),
  terminated(7, '已终止'),
  unknown(0, '未知');

  const TaskState(this.code, this.label);

  final int code;
  final String label;

  static TaskState fromCode(Object? raw) {
    final int? code = raw is int ? raw : int.tryParse('$raw');
    for (final TaskState state in values) {
      if (state.code == code) return state;
    }
    return TaskState.unknown;
  }

  /// 待处理 / 处理中：运维还能提交处理结果。
  bool get isOpen => this == todo || this == doing;

  /// 已修复 / 非异常：等待数据管理员确认或拒绝。
  bool get isSubmitted => this == fixed || this == notError;

  /// 已关闭 / 已终止：流程终结。
  bool get isTerminal => this == confirmed || this == terminated;
}

/// 用户精简信息（`UserAvatar`）。
class TaskPerson {
  const TaskPerson({this.id, this.nickname = '', this.avatar = ''});

  final int? id;
  final String nickname;
  final String avatar;

  static TaskPerson? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> map = raw;
    final String nickname = (map['nickname'] ?? map['name'] ?? '').toString();
    if (nickname.isEmpty && map['id'] == null) return null;
    return TaskPerson(
      id: map['id'] is int
          ? map['id'] as int
          : int.tryParse('${map['id'] ?? ''}'),
      nickname: nickname,
      avatar: (map['avatar'] ?? '').toString(),
    );
  }
}

/// `PictureBO`：OSS 直链 + 分类标题（异常描述 / 处理前 / 处理中 …）。
class TaskPhoto {
  const TaskPhoto({required this.url, this.title});

  final String url;
  final String? title;

  static List<TaskPhoto> listFrom(Object? raw) {
    if (raw is! List) return const <TaskPhoto>[];
    final List<TaskPhoto> result = <TaskPhoto>[];
    for (final Object? element in raw) {
      if (element is String && element.isNotEmpty) {
        result.add(TaskPhoto(url: element));
      } else if (element is Map) {
        final String url = (element['url'] ?? element['picture'] ?? '')
            .toString();
        if (url.isEmpty) continue;
        final String? title = element['title']?.toString();
        result.add(
          TaskPhoto(url: url, title: title == null || title.isEmpty ? null : title),
        );
      }
    }
    return result;
  }
}

/// 后端 `MetaProcessAuthVO`：详情页能做什么，完全由服务端判定。
///
/// 不要在客户端自行推导状态与角色的组合，规则集中在
/// `TaskService#getTaskAuth`，两边不一致就会出现「按钮能点但请求被拒」。
class TaskAuth {
  const TaskAuth({
    this.enableToTransfer = false,
    this.enableToTerminate = false,
    this.enableToSubmit = false,
    this.enableToEdit = false,
    this.enableToConfirm = false,
    this.enableToForceTransfer = false,
  });

  final bool enableToTransfer;
  final bool enableToTerminate;
  final bool enableToSubmit;
  final bool enableToEdit;
  final bool enableToConfirm;
  final bool enableToForceTransfer;

  static TaskAuth fromJson(Object? raw) {
    if (raw is! Map) return const TaskAuth();
    bool read(String key) => raw[key] == true;
    return TaskAuth(
      enableToTransfer: read('enableToTransfer'),
      enableToTerminate: read('enableToTerminate'),
      enableToSubmit: read('enableToSubmit'),
      enableToEdit: read('enableToEdit'),
      enableToConfirm: read('enableToConfirm'),
      enableToForceTransfer: read('enableToForceTransfer'),
    );
  }

  bool get hasAny =>
      enableToTransfer ||
      enableToTerminate ||
      enableToSubmit ||
      enableToEdit ||
      enableToConfirm ||
      enableToForceTransfer;
}

class TaskDetail {
  const TaskDetail({
    required this.id,
    required this.state,
    required this.content,
    this.jobNumber = '',
    this.stationName = '',
    this.regionText = '',
    this.address = '',
    this.creator,
    this.executor,
    this.stationManager,
    this.gmtCreate,
    this.gmtHappen,
    this.deadline,
    this.gmtSolved,
    this.overtime = false,
    this.timeUsageSolved = '',
    this.remind = 0,
    this.errorUnit = '',
    this.reason = '',
    this.solution = '',
    this.description = '',
    this.hadArrivedStationStr = '',
    this.causedByProduct,
    this.contentPictures = const <TaskPhoto>[],
    this.submitPictures = const <TaskPhoto>[],
    this.auth = const TaskAuth(),
    this.isArrived = false,
  });

  final int id;
  final String jobNumber;
  final TaskState state;
  final String content;

  final String stationName;

  /// `江苏省 连云港市 灌云县`
  final String regionText;
  final String address;

  final TaskPerson? creator;
  final TaskPerson? executor;
  final TaskPerson? stationManager;

  final String? gmtCreate;
  final String? gmtHappen;
  final String? deadline;
  final String? gmtSolved;

  final bool overtime;

  /// 服务端算好的耗时文案（`6分钟`），避免客户端跨时区算错。
  final String timeUsageSolved;
  final int remind;

  /// 异常单元 / 仪器，服务端已拼成 `A、B、C`。
  final String errorUnit;
  final String reason;
  final String solution;
  final String description;
  final String hadArrivedStationStr;
  final bool? causedByProduct;

  final List<TaskPhoto> contentPictures;
  final List<TaskPhoto> submitPictures;

  final TaskAuth auth;
  final bool isArrived;

  /// 处理照片按 `title` 分组（处理前 / 处理中 / 处理后 / 站房卫生 …）。
  Map<String, List<TaskPhoto>> get submitPicturesByTitle {
    final Map<String, List<TaskPhoto>> grouped = <String, List<TaskPhoto>>{};
    for (final TaskPhoto photo in submitPictures) {
      final String key = photo.title ?? '处理照片';
      grouped.putIfAbsent(key, () => <TaskPhoto>[]).add(photo);
    }
    return grouped;
  }

  bool get hasProcessResult =>
      reason.isNotEmpty ||
      solution.isNotEmpty ||
      submitPictures.isNotEmpty;

  /// 动作完成后本地先行更新，避免整页重新请求导致的闪烁。
  TaskDetail copyWith({
    TaskState? state,
    String? reason,
    String? solution,
    String? gmtSolved,
    String? timeUsageSolved,
    String? errorUnit,
    List<TaskPhoto>? submitPictures,
    TaskAuth? auth,
  }) => TaskDetail(
    id: id,
    jobNumber: jobNumber,
    state: state ?? this.state,
    content: content,
    stationName: stationName,
    regionText: regionText,
    address: address,
    creator: creator,
    executor: executor,
    stationManager: stationManager,
    gmtCreate: gmtCreate,
    gmtHappen: gmtHappen,
    deadline: deadline,
    gmtSolved: gmtSolved ?? this.gmtSolved,
    overtime: overtime,
    timeUsageSolved: timeUsageSolved ?? this.timeUsageSolved,
    remind: remind,
    errorUnit: errorUnit ?? this.errorUnit,
    reason: reason ?? this.reason,
    solution: solution ?? this.solution,
    description: description,
    hadArrivedStationStr: hadArrivedStationStr,
    causedByProduct: causedByProduct,
    contentPictures: contentPictures,
    submitPictures: submitPictures ?? this.submitPictures,
    auth: auth ?? this.auth,
    isArrived: isArrived,
  );

  factory TaskDetail.fromJson(Map<String, Object?> json) {
    final Map<Object?, Object?> station = json['station'] is Map
        ? json['station']! as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final List<String> regions = <String>[
      if ((station['regionTitle'] ?? '').toString().isNotEmpty)
        '${station['regionTitle']}',
      if ((station['cityTitle'] ?? '').toString().isNotEmpty)
        '${station['cityTitle']}',
      if ((station['districtTitle'] ?? '').toString().isNotEmpty)
        '${station['districtTitle']}',
    ];

    final String? rawGmtCreate = json['gmt_create']?.toString();
    final String? rawGmtHappen = json['gmt_happen']?.toString();
    final String? rawDeadline = json['deadline']?.toString();
    final String? rawGmtSolved = json['gmt_solved']?.toString();

    return TaskDetail(
      id: json['id'] is int
          ? json['id']! as int
          : int.tryParse('${json['id'] ?? 0}') ?? 0,
      jobNumber: (json['jobNumber'] ?? '').toString(),
      state: TaskState.fromCode(json['state']),
      content: (json['content'] ?? '').toString(),
      stationName: (station['name'] ?? '').toString(),
      regionText: regions.join(' '),
      address: (station['address'] ?? '').toString(),
      creator: TaskPerson.fromJson(json['creator']),
      executor: TaskPerson.fromJson(json['executor']),
      stationManager: TaskPerson.fromJson(json['stationManager']),
      gmtCreate: rawGmtCreate,
      gmtHappen: rawGmtHappen,
      deadline: rawDeadline,
      gmtSolved: rawGmtSolved,
      overtime: json['overtime'] == true,
      timeUsageSolved: (json['timeUsageSolved'] ?? '').toString(),
      remind: json['remind'] is int
          ? json['remind']! as int
          : int.tryParse('${json['remind'] ?? 0}') ?? 0,
      errorUnit: (json['errorUnit'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      solution: (json['solution'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      hadArrivedStationStr: (json['hadArrivedStationStr'] ?? '').toString(),
      causedByProduct: json['causedByProduct'] is bool
          ? json['causedByProduct'] as bool
          : null,
      contentPictures: TaskPhoto.listFrom(json['contentPictures']),
      submitPictures: TaskPhoto.listFrom(json['submitPictures']),
      auth: TaskAuth.fromJson(json['auth']),
      isArrived: json['isArrived'] == true,
    );
  }
}
