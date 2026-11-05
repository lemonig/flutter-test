import 'package:flutter/material.dart';

import '../data/models/task_item.dart';
import 'abnormal_detail_page.dart';
import 'attend_detail_page.dart';
import 'inspection_detail_page.dart';

/// 详情入口。
///
/// 三类任务各自有独立详情页，这里只按分类分发：
/// - 异常 → [AbnormalDetailPage]（M3-02，含处理与确认流转）
/// - 巡检 → [InspectionDetailPage]（M4-01，含填报入口）
/// - 签到 → [AttendDetailPage]（M5-03）
///
/// 之前巡检走的是占位骨架，M4 落地后已删除 —— 保留占位反而会让人以为
/// 某个分类没做，排查问题时容易走错方向。
class TaskDetailPage extends StatelessWidget {
  const TaskDetailPage({
    super.key,
    required this.category,
    required this.id,
    this.item,
  });

  final TaskCategory category;
  final String id;

  /// 列表点击时带过来的行数据，详情页当前只依赖 id 拉全量，保留参数
  /// 是为了后续做「先渲染首屏、再补详情」的优化。
  final TaskItem? item;

  @override
  Widget build(BuildContext context) => switch (category) {
    TaskCategory.abnormal => AbnormalDetailPage(taskId: id),
    TaskCategory.inspection => InspectionDetailPage(recordId: id),
    TaskCategory.signIn => AttendDetailPage(attendId: id),
  };
}
