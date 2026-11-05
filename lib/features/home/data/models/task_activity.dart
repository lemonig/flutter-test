/// 异常详情的三类附属数据：操作日志、已读列表、评论。
library;

import 'task_detail.dart';

/// 后端 `TaskLog`：`POST task/{id}/log`。
///
/// `content` 是服务端拼好的动作文案（`创建了故障` / `编辑了任务` /
/// `已修复`），客户端不再二次翻译，避免与后端文案打架。
class TaskLogEntry {
  const TaskLogEntry({
    required this.id,
    required this.content,
    this.stateLabel = '',
    this.time,
    this.user,
    this.photo,
  });

  final int id;
  final String content;
  final String stateLabel;
  final String? time;
  final TaskPerson? user;
  final String? photo;

  static TaskLogEntry fromJson(Map<Object?, Object?> json) => TaskLogEntry(
    id: json['id'] is int
        ? json['id']! as int
        : int.tryParse('${json['id'] ?? 0}') ?? 0,
    content: (json['content'] ?? '').toString(),
    stateLabel: TaskState.fromCode(json['taskState']).label,
    time: json['gmt_create']?.toString(),
    user: TaskPerson.fromJson(json['user']),
    photo: json['photo']?.toString(),
  );
}

/// 后端 `task/{id}/read`：谁在什么时候读过这条异常。
class TaskReader {
  const TaskReader({required this.userId, this.time, this.person});

  final int userId;
  final String? time;
  final TaskPerson? person;

  String get name => person?.nickname.isNotEmpty == true
      ? person!.nickname
      : '用户 $userId';

  static TaskReader fromJson(Map<Object?, Object?> json) => TaskReader(
    userId: json['user_id'] is int
        ? json['user_id']! as int
        : int.tryParse('${json['user_id'] ?? 0}') ?? 0,
    time: json['gmt_create']?.toString(),
    person: TaskPerson.fromJson(json['user']),
  );
}

/// 后端 `CommentVo`：`POST comment/list`，`itemType=1` 表示异常任务。
class TaskComment {
  const TaskComment({
    required this.id,
    required this.content,
    this.time,
    this.person,
    this.creatorId,
    this.pictures = const <TaskPhoto>[],
  });

  final int id;
  final String content;
  final String? time;
  final TaskPerson? person;
  final int? creatorId;
  final List<TaskPhoto> pictures;

  static TaskComment fromJson(Map<Object?, Object?> json) => TaskComment(
    id: json['id'] is int
        ? json['id']! as int
        : int.tryParse('${json['id'] ?? 0}') ?? 0,
    content: (json['content'] ?? '').toString(),
    time: json['gmt_create']?.toString() ?? json['gmtCreate']?.toString(),
    person: TaskPerson.fromJson(json['userCreator']),
    creatorId: json['creatorId'] is int
        ? json['creatorId'] as int
        : int.tryParse('${json['creatorId'] ?? ''}'),
    pictures: TaskPhoto.listFrom(json['pictures']),
  );
}
