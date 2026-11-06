import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/task_activity.dart';
import '../data/models/task_detail.dart';
import '../data/models/task_process.dart';
import '../data/repositories/ops_user_repository.dart';
import '../data/repositories/task_detail_repository.dart';

/// 异常详情及其附属数据（M3-02 ~ M3-05）。
///
/// 全部按任务 id 分家族缓存；动作完成后由调用方 `invalidate` 对应家族，
/// 不做手工状态同步 —— 服务端算的 `auth`、`timeUsageSolved`、`errorUnit`
/// 只有重新拉取才准确。

final taskDetailProvider = FutureProvider.family<TaskDetail, String>(
  (Ref ref, String id) =>
      ref.watch(taskDetailRepositoryProvider).fetchDetail(id),
);

final taskLogProvider = FutureProvider.family<List<TaskLogEntry>, String>(
  (Ref ref, String id) => ref.watch(taskDetailRepositoryProvider).fetchLog(id),
);

final taskReadersProvider = FutureProvider.family<List<TaskReader>, String>(
  (Ref ref, String id) =>
      ref.watch(taskDetailRepositoryProvider).fetchReaders(id),
);

final taskCommentsProvider = FutureProvider.family<List<TaskComment>, String>(
  (Ref ref, String id) =>
      ref.watch(taskDetailRepositoryProvider).fetchComments(id),
);

final taskLikesProvider = FutureProvider.family<List<TaskComment>, String>(
  (Ref ref, String id) =>
      ref.watch(taskDetailRepositoryProvider).fetchLikes(id),
);

final taskErrorUnitsProvider =
    FutureProvider.family<ErrorUnitCatalog, String>(
      (Ref ref, String id) =>
          ref.watch(taskDetailRepositoryProvider).fetchErrorUnits(id),
    );

/// 转交候选处理人（C7）。keyword 进 family：输入变化即得到新条目，
/// 天然丢弃旧请求结果，无需手工防抖。
final transferCandidatesProvider =
    FutureProvider.family<List<OpsUser>, String>(
      (Ref ref, String keyword) => ref
          .watch(opsUserRepositoryProvider)
          .fetchOpsUsers(keyword: keyword),
    );

/// 详情页动作的统一出口：执行后同时失效详情与首页列表，
/// 保证「处理完返回首页，列表状态已更新」。
class TaskActionService {
  const TaskActionService(this._ref);

  final Ref _ref;

  TaskDetailRepository get _repo => _ref.read(taskDetailRepositoryProvider);

  Future<void> submitProcess(ProcessDraft draft) =>
      _repo.submitProcess(draft);

  Future<void> saveDraft(ProcessDraft draft) => _repo.saveDraft(draft);

  Future<void> confirm(String id) => _repo.confirm(id);

  Future<void> reject(String id, String description) =>
      _repo.reject(id, description);

  Future<void> terminate(String id, String description) =>
      _repo.terminate(id, description);

  Future<void> transfer(String id, int toUserId) =>
      _repo.transfer(id, toUserId);

  Future<void> addComment(String id, String content) =>
      _repo.addComment(id, content);

  Future<void> toggleLike(String id) => _repo.toggleLike(id);

  /// 详情相关的所有家族一次性失效。
  void invalidateTask(String id) {
    _ref.invalidate(taskDetailProvider(id));
    _ref.invalidate(taskLogProvider(id));
    _ref.invalidate(taskReadersProvider(id));
    _ref.invalidate(taskLikesProvider(id));
  }
}

final Provider<TaskActionService> taskActionServiceProvider =
    Provider<TaskActionService>((Ref ref) => TaskActionService(ref));
