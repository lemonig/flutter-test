import 'task_detail.dart';

/// 异常任务的「可做什么 / 为什么不能做」，集中一处，避免三处 UI 各判一套。
///
/// 优先级：**服务端 `auth` 说了算**。这里只做两件事：
/// 1. 把 `auth` 的布尔开关翻译成带原因的条目，便于置灰并给出说明；
/// 2. 当 `auth` 全为 false 时，按 `state` 补一句人话，解释为什么不能操作。
///
/// 不要在页面里再写 `if (state == xxx)` 的散装判断 —— 后端状态机调整
/// （例如新增「待复核」）时，只有这里需要改。
class TaskAction {
  const TaskAction({
    required this.key,
    required this.label,
    required this.enabled,
    this.reason = '',
    this.danger = false,
  });

  final String key;
  final String label;

  /// 服务端是否放行。
  final bool enabled;

  /// 不可用时的原因，直接展示给用户；可用时为「操作说明」。
  final String reason;

  final bool danger;

  bool get disabled => !enabled;
}

/// 详情页可执行的动作清单（顺序即展示顺序）。
///
/// `transfer` 已接入人员选择弹层（C7）；`edit` 至今没有实现入口
/// （需要编辑表单），这里仍标记为「待接入」。
List<TaskAction> taskActionsFor(TaskDetail task) {
  final TaskAuth auth = task.auth;
  return <TaskAction>[
    TaskAction(
      key: 'submit',
      label: '处理任务',
      enabled: auth.enableToSubmit,
      reason: _processReason(task),
    ),
    TaskAction(
      key: 'confirm',
      label: '审核处理结果',
      enabled: auth.enableToConfirm,
      reason: _reviewReason(task),
    ),
    TaskAction(
      key: 'terminate',
      label: '终止任务',
      enabled: auth.enableToTerminate,
      danger: true,
      reason: auth.enableToTerminate
          ? '任务不再需要处理，终止后不可恢复'
          : _terminateReason(task),
    ),
    TaskAction(
      key: 'transfer',
      label: '转交任务',
      enabled: auth.enableToTransfer,
      reason: auth.enableToTransfer
          ? '选择一位在职运维人员接收该任务'
          : _transferReason(task),
    ),
    TaskAction(
      key: 'edit',
      label: '编辑任务',
      enabled: false,
      reason: auth.enableToEdit ? '创建 1 小时内可编辑，待接入' : '仅创建 1 小时内可编辑',
    ),
  ];
}

/// 主按钮要展示的动作：能处理就处理，能审核就审核，都不行就是 null。
TaskAction? primaryTaskAction(TaskDetail task) {
  for (final TaskAction action in taskActionsFor(task)) {
    if (action.key != 'submit' && action.key != 'confirm') continue;
    if (action.enabled) return action;
  }
  return null;
}

/// 主按钮不可用时的一句话说明，对齐原工程的状态文案。
String blockedReasonOf(TaskDetail task) => switch (task.state) {
  TaskState.confirmed => '已关闭，无需操作',
  TaskState.terminated => '已终止，无需操作',
  TaskState.fixed || TaskState.notError => '等待数据管理员确认',
  TaskState.rejected => '已被拒绝，等待处理人重新提交',
  _ => '当前账号无处理权限',
};

String _processReason(TaskDetail task) {
  if (task.auth.enableToSubmit) return '填写处理措施并提交';
  return switch (task.state) {
    TaskState.fixed || TaskState.notError => '已提交处理结果，等待确认',
    TaskState.confirmed => '任务已关闭',
    TaskState.terminated => '任务已终止',
    TaskState.rejected => '处理结果被拒绝，可重新提交',
    _ => '当前账号不是该任务的执行人',
  };
}

String _reviewReason(TaskDetail task) {
  if (task.auth.enableToConfirm) return '确认或驳回处理结果';
  if (task.state.isOpen) return '尚未提交处理结果';
  if (task.state.isTerminal) return '任务已结束，无需确认';
  return '仅数据管理员可确认';
}

String _terminateReason(TaskDetail task) {
  if (task.state.isTerminal) return '任务已结束';
  return '仅任务相关管理员可终止';
}

String _transferReason(TaskDetail task) {
  if (task.state.isTerminal) return '任务已结束';
  // 服务端只允许「待处理 + 最初执行人 + 未转交过」三个条件同时成立。
  if (task.state != TaskState.todo) return '仅待处理的任务可转交';
  return '仅任务的最初执行人可转交，且只能转交一次';
}
