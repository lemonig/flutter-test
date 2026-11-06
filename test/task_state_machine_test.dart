import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/features/home/data/models/task_detail.dart';
import 'package:green_clean_ops/features/home/data/models/task_state_machine.dart';

TaskDetail _task({
  TaskState state = TaskState.doing,
  TaskAuth auth = const TaskAuth(),
}) => TaskDetail(id: 1, state: state, content: '现象描述', auth: auth);

TaskAction _actionOf(TaskDetail task, String key) =>
    taskActionsFor(task).firstWhere((TaskAction a) => a.key == key);

void main() {
  group('主按钮选择', () {
    test('可处理时主按钮是「处理任务」', () {
      final TaskDetail task = _task(
        auth: const TaskAuth(enableToSubmit: true),
      );
      expect(primaryTaskAction(task)?.key, 'submit');
      expect(primaryTaskAction(task)?.label, '处理任务');
    });

    test('只能确认时主按钮是「审核处理结果」', () {
      final TaskDetail task = _task(
        state: TaskState.fixed,
        auth: const TaskAuth(enableToConfirm: true),
      );
      expect(primaryTaskAction(task)?.key, 'confirm');
      expect(primaryTaskAction(task)?.label, '审核处理结果');
    });

    test('都不能做时没有主按钮，改为给出原因', () {
      expect(primaryTaskAction(_task()), isNull);
      expect(
        blockedReasonOf(_task(state: TaskState.confirmed)),
        '已关闭，无需操作',
      );
      expect(
        blockedReasonOf(_task(state: TaskState.terminated)),
        '已终止，无需操作',
      );
      expect(blockedReasonOf(_task(state: TaskState.fixed)), '等待数据管理员确认');
      expect(
        blockedReasonOf(_task(state: TaskState.rejected)),
        '已被拒绝，等待处理人重新提交',
      );
    });
  });

  group('非法流转给出可读原因', () {
    test('已关闭任务：处理 / 终止都置灰并说明', () {
      final TaskDetail task = _task(state: TaskState.confirmed);
      expect(_actionOf(task, 'submit').disabled, isTrue);
      expect(_actionOf(task, 'submit').reason, '任务已关闭');
      expect(_actionOf(task, 'terminate').disabled, isTrue);
      expect(_actionOf(task, 'terminate').reason, '任务已结束');
    });

    test('已提交待确认：处理按钮说明「等待确认」', () {
      expect(
        _actionOf(_task(state: TaskState.notError), 'submit').reason,
        '已提交处理结果，等待确认',
      );
      expect(
        _actionOf(_task(state: TaskState.doing), 'confirm').reason,
        '尚未提交处理结果',
      );
    });

    test('被拒绝后仍可重新提交', () {
      final TaskAction submit = _actionOf(
        _task(state: TaskState.rejected),
        'submit',
      );
      expect(submit.reason, '处理结果被拒绝，可重新提交');
    });

    test('服务端放行时动作可用且带操作说明', () {
      final TaskDetail task = _task(
        auth: const TaskAuth(enableToSubmit: true, enableToTerminate: true),
      );
      expect(_actionOf(task, 'submit').enabled, isTrue);
      expect(_actionOf(task, 'submit').reason, '填写处理措施并提交');
      expect(_actionOf(task, 'terminate').enabled, isTrue);
      expect(_actionOf(task, 'terminate').danger, isTrue);
    });

    test('转交跟随服务端 auth，编辑仍待接入', () {
      final TaskDetail task = _task(
        auth: const TaskAuth(enableToTransfer: true, enableToEdit: true),
      );
      final TaskAction transfer = _actionOf(task, 'transfer');
      expect(transfer.enabled, isTrue);
      expect(transfer.reason, '选择一位在职运维人员接收该任务');
      expect(_actionOf(task, 'edit').disabled, isTrue);
      expect(_actionOf(task, 'edit').reason, contains('待接入'));
    });

    test('服务端不放行时转交置灰并按状态给出原因', () {
      expect(_actionOf(_task(), 'transfer').disabled, isTrue);
      expect(
        _actionOf(_task(state: TaskState.confirmed), 'transfer').reason,
        '任务已结束',
      );
      expect(
        _actionOf(_task(state: TaskState.doing), 'transfer').reason,
        '仅待处理的任务可转交',
      );
      // 状态是待处理但 auth 为 false：不是最初执行人或已转交过。
      expect(
        _actionOf(_task(state: TaskState.todo), 'transfer').reason,
        '仅任务的最初执行人可转交，且只能转交一次',
      );
    });
  });
}
