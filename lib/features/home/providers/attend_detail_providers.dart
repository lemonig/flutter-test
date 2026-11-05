import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/attend_detail.dart';
import '../data/models/task_activity.dart';
import '../data/repositories/attend_detail_repository.dart';

/// 签到详情及其互动数据（M5-03）。
///
/// 与异常详情一样按 id 分家族缓存；评论/点赞动作完成后由调用方
/// `invalidate` 对应家族重新拉取，不做手工状态同步。
final attendDetailProvider = FutureProvider.family<AttendDetail, String>(
  (Ref ref, String id) =>
      ref.watch(attendDetailRepositoryProvider).fetchDetail(id),
);

final attendCommentsProvider =
    FutureProvider.family<List<TaskComment>, String>(
      (Ref ref, String id) =>
          ref.watch(attendDetailRepositoryProvider).fetchComments(id),
    );

final attendLikesProvider = FutureProvider.family<List<TaskComment>, String>(
  (Ref ref, String id) =>
      ref.watch(attendDetailRepositoryProvider).fetchLikes(id),
);
