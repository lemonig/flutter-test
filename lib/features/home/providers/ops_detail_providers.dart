import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/ops_detail.dart';
import '../data/models/task_activity.dart';
import '../data/repositories/ops_detail_repository.dart';

/// 巡检详情及其互动数据（M4-01 ~ M4-04）。
///
/// 与异常/签到详情一致：按 id 分家族缓存，提交或评论后由调用方
/// `invalidate` 重新拉取，不做手工状态同步。
final opsDetailProvider = FutureProvider.family<OpsDetail, String>(
  (Ref ref, String id) => ref.watch(opsDetailRepositoryProvider).fetchDetail(id),
);

final opsCommentsProvider = FutureProvider.family<List<TaskComment>, String>(
  (Ref ref, String id) =>
      ref.watch(opsDetailRepositoryProvider).fetchComments(id),
);

final opsLikesProvider = FutureProvider.family<List<TaskComment>, String>(
  (Ref ref, String id) => ref.watch(opsDetailRepositoryProvider).fetchLikes(id),
);
