/// 首页三类任务的统一数据模型。
///
/// 对应 iOS 原工程的 `AbnormalListModel` / `InspectionListModel` /
/// `SignInListModel`，在上层用同一结构承载，差异由 [TaskCategory] 与
/// [TaskItem.tags] 表达。
library;

enum TaskCategory { abnormal, inspection, signIn }

extension TaskCategoryX on TaskCategory {
  /// Tab 展示名，对齐原工程 `titleArr = ["异常","巡检","签到"]`
  String get label => switch (this) {
    TaskCategory.abnormal => '异常',
    TaskCategory.inspection => '巡检',
    TaskCategory.signIn => '签到',
  };

  /// 原工程接口：异常 `task/timeline`，巡检 `opsrecord/timeline`
  String get endpoint => switch (this) {
    TaskCategory.abnormal => 'task/timeline',
    TaskCategory.inspection => 'opsrecord/timeline',
    TaskCategory.signIn => 'attend/timeline',
  };

  /// 详情接口前缀（后端均为 `GET /<prefix>/{id}`）。
  String get detailEndpoint => switch (this) {
    TaskCategory.abnormal => 'task',
    TaskCategory.inspection => 'opsrecord',
    TaskCategory.signIn => 'attend',
  };
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.stationName,
    required this.timeText,
    required this.content,
    required this.executor,
    this.tags = const [],
    this.images = const [],
    this.readCount = 0,
    this.commentCount = 0,
    this.likeCount = 0,
  });

  final String id;
  final String stationName;
  final String timeText;
  final String content;

  /// 发起人 / 执行人昵称，列表中高亮展示
  final String executor;
  final List<String> tags;
  final List<String> images;
  final int readCount;
  final int commentCount;
  final int likeCount;

  TaskItem copyWith({List<String>? tags, int? readCount}) => TaskItem(
    id: id,
    stationName: stationName,
    timeText: timeText,
    content: content,
    executor: executor,
    tags: tags ?? this.tags,
    images: images,
    readCount: readCount ?? this.readCount,
    commentCount: commentCount,
    likeCount: likeCount,
  );
}
