import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/ops_detail.dart';
import '../models/task_activity.dart';
import '../models/task_detail.dart';

/// 巡检详情、互动与填报（M4-01 ~ M4-03）。
///
/// 详情走 `GET opsrecord/{id}`；评论点赞复用任务那套接口，`itemType` 必须是
/// `CommentTypeEnum.OpsRecord(3)` —— 传 1 会挂到异常上、传 2 会挂到签到上，
/// 都不会报错，只是巡检详情里永远读不到。
abstract class OpsDetailRepository {
  Future<OpsDetail> fetchDetail(String id);

  Future<List<TaskComment>> fetchComments(String id);

  Future<void> addComment(String id, String content);

  Future<List<TaskComment>> fetchLikes(String id);

  Future<void> toggleLike(String id);

  /// 提交前校验：当前位置是否在站点范围内（服务端 20 km 判定）。
  Future<OpsSiteCheck> checkBeforeSubmit(
    String id, {
    required double longitude,
    required double latitude,
  });

  Future<void> submit(String id, OpsSubmitDraft draft);

  Future<void> terminate(String id, String reason);
}

/// 对齐后端 `CommentTypeEnum.OpsRecord(3)`。
const int kOpsItemType = 3;

/// 提交前校验结果。
///
/// 注意后端返回 `{success: true, data: false, message: '请在站房内提交巡检任务'}`，
/// **`success` 为真不代表能提交**，必须再看 `data`。
class OpsSiteCheck {
  const OpsSiteCheck({required this.onSite, this.message = ''});

  final bool onSite;
  final String message;
}

/// 单个巡检项的提交内容。
class OpsSubmitItem {
  const OpsSubmitItem({
    required this.id,
    this.description = '',
    this.pictures = const <String>[],
  });

  final int id;
  final String description;

  /// 上传接口返回的 objectKey（`ops/...`），不是 OSS 直链。
  final List<String> pictures;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'description': description.trim(),
    'pictures': pictures,
  };
}

/// 巡检提交载荷（`POST opsrecord/submit`）。
class OpsSubmitDraft {
  const OpsSubmitDraft({
    required this.items,
    this.description = '',
    this.pictures = const <String>[],
  });

  final List<OpsSubmitItem> items;

  /// 整体备注。
  final String description;

  /// 整体备注配图。
  final List<String> pictures;

  Map<String, Object?> toJson(String recordId) {
    final int? parsed = int.tryParse(recordId);
    return <String, Object?>{
      'id': parsed ?? recordId,
      'itemList': <Map<String, Object?>>[
        for (final OpsSubmitItem item in items) item.toJson(),
      ],
      'description': description.trim(),
      'pictures': pictures,
    };
  }
}

class RemoteOpsDetailRepository implements OpsDetailRepository {
  const RemoteOpsDetailRepository(this._api);

  final ApiClient _api;

  static int _parseId(String id) {
    final int? parsed = int.tryParse(id);
    if (parsed == null) {
      throw const AppException(
        '巡检任务编号无效',
        kind: ApiErrorKind.parse,
        code: 'BAD_OPS_ID',
      );
    }
    return parsed;
  }

  @override
  Future<OpsDetail> fetchDetail(String id) async {
    final ApiResponse response = await _api.getRaw('opsrecord/${_parseId(id)}');
    return OpsDetail.fromJson(response.data);
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) =>
      _comments('comment/list', _parseId(id));

  @override
  Future<List<TaskComment>> fetchLikes(String id) =>
      _comments('like/list', _parseId(id));

  Future<List<TaskComment>> _comments(String path, int itemId) async {
    final ApiResponse response = await _api.postRaw(
      path,
      data: <String, Object?>{'itemType': kOpsItemType, 'itemId': itemId},
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
      'itemType': kOpsItemType,
      'itemId': _parseId(id),
      'content': content.trim(),
    },
  );

  @override
  Future<void> toggleLike(String id) => _api.postRaw(
    'like',
    data: <String, Object?>{'itemType': kOpsItemType, 'itemId': _parseId(id)},
  );

  @override
  Future<OpsSiteCheck> checkBeforeSubmit(
    String id, {
    required double longitude,
    required double latitude,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'opsrecord/submit/check',
      data: <String, Object?>{
        'id': _parseId(id),
        'coordinate1': longitude,
        'coordinate2': latitude,
      },
    );
    return OpsSiteCheck(
      onSite: response.data == true,
      message: (response.message ?? '').trim(),
    );
  }

  @override
  Future<void> submit(String id, OpsSubmitDraft draft) =>
      _api.postRaw('opsrecord/submit', data: draft.toJson(id));

  @override
  Future<void> terminate(String id, String reason) => _api.postRaw(
    'opsrecord/${_parseId(id)}/terminate',
    data: <String, Object?>{'description': reason.trim()},
  );
}

/// 演示实现：内存记录完成状态，提交后在本次运行内能立刻看到「已完成」。
class MockOpsDetailRepository implements OpsDetailRepository {
  MockOpsDetailRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static final Set<String> _doneIds = <String>{};
  static final Map<String, List<TaskComment>> _comments =
      <String, List<TaskComment>>{};
  static final Set<String> _liked = <String>{};

  static const TaskPerson _demoPerson = TaskPerson(
    id: 1001,
    nickname: '张伟',
    avatar: '',
  );

  static OpsDetail demoDetail(String id) {
    final bool done = _doneIds.contains(id);
    return OpsDetail(
      id: id,
      jobNumber: 'XJ20261104003',
      stationId: 9001,
      stationName: '嘉兴市南湖水质自动监测站',
      stationAddress: '浙江省嘉兴市南湖区南湖景区东侧',
      longitude: 120.7628,
      latitude: 30.7489,
      executor: _demoPerson,
      stationManager: const TaskPerson(id: 1002, nickname: '李建国'),
      gmtCreate: '2026-11-04T08:00:00.000+0800',
      deadline: '2026-11-08T19:00:00.000+0800',
      gmtFirstSubmit: done ? '2026-11-04T15:20:00.000+0800' : null,
      description: done ? '已完成本周例行巡检，两台仪表读数正常。' : '',
      pictures: done
          ? const <TaskPhoto>[
              TaskPhoto(url: 'https://picsum.photos/seed/gc-ops-note/900'),
            ]
          : const <TaskPhoto>[],
      itemSize: 6,
      done: done,
      auth: OpsAuth(
        canSubmit: !done,
        canTerminate: !done,
        canTransfer: !done,
        canForceTransfer: false,
      ),
      items: <OpsItemDetail>[
        OpsItemDetail(
          id: 1,
          category: '采配水单元',
          name: '沉淀池清洗',
          requirePhoto: true,
          description: done ? '已清洗，池底无明显沉积。' : '',
          photos: done
              ? const <TaskPhoto>[
                  TaskPhoto(url: 'https://picsum.photos/seed/gc-ops-1/900'),
                ]
              : const <TaskPhoto>[],
        ),
        OpsItemDetail(
          id: 2,
          category: '分析单元',
          name: '仪器校准（拍摄仪器校准记录或台账填写记录）',
          requirePhoto: true,
          description: done ? 'CODcr 与氨氮均完成单点核查。' : '',
          photos: done
              ? const <TaskPhoto>[
                  TaskPhoto(url: 'https://picsum.photos/seed/gc-ops-2/900'),
                ]
              : const <TaskPhoto>[],
        ),
        OpsItemDetail(
          id: 3,
          category: '分析单元',
          name: '更换试剂（拍摄台账填写更换记录）',
          requirePhoto: true,
        ),
        OpsItemDetail(id: 4, category: '辅助设备', name: '运维记录填写'),
        OpsItemDetail(id: 5, category: '其他', name: '站房卫生'),
      ],
    );
  }

  @override
  Future<OpsDetail> fetchDetail(String id) async {
    await Future<void>.delayed(delay);
    return demoDetail(id);
  }

  @override
  Future<List<TaskComment>> fetchComments(String id) async {
    await Future<void>.delayed(delay);
    return _comments[id] ?? const <TaskComment>[];
  }

  @override
  Future<List<TaskComment>> fetchLikes(String id) async {
    await Future<void>.delayed(delay);
    return _liked.contains(id) ? demoLikes : const <TaskComment>[];
  }

  @override
  Future<void> addComment(String id, String content) async {
    await Future<void>.delayed(delay);
    _comments
        .putIfAbsent(id, () => <TaskComment>[])
        .insert(
          0,
          TaskComment(
            id: DateTime.now().millisecondsSinceEpoch,
            content: content,
            time: DateTime.now().toIso8601String(),
            person: _demoPerson,
            creatorId: _demoPerson.id,
          ),
        );
  }

  @override
  Future<void> toggleLike(String id) async {
    await Future<void>.delayed(delay);
    if (!_liked.remove(id)) _liked.add(id);
  }

  @override
  Future<OpsSiteCheck> checkBeforeSubmit(
    String id, {
    required double longitude,
    required double latitude,
  }) async {
    await Future<void>.delayed(delay);
    return const OpsSiteCheck(onSite: true);
  }

  @override
  Future<void> submit(String id, OpsSubmitDraft draft) async {
    await Future<void>.delayed(delay);
    _doneIds.add(id);
  }

  @override
  Future<void> terminate(String id, String reason) async {
    await Future<void>.delayed(delay);
    throw const AppException('演示数据不支持终止任务', kind: ApiErrorKind.business);
  }

  static const List<TaskComment> demoLikes = <TaskComment>[
    TaskComment(id: 1, content: '', person: _demoPerson, creatorId: 1001),
  ];
}

final Provider<OpsDetailRepository> opsDetailRepositoryProvider =
    Provider<OpsDetailRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockOpsDetailRepository();
      return RemoteOpsDetailRepository(ref.watch(apiClientProvider));
    });
