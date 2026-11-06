import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/workbench_models.dart';

/// 申请与审批（M7-05 ~ M7-10）。
///
/// 接口形态（2026-11-06 实测）：
/// - 四类申请共用 `ApplyForm` 结构，分别提交到
///   `POST apply/part|reagent|fee|tool`；审批人可传 `approve_user_id`，
///   不传时服务端按合同找区域经理，工具申请则强制为保管人；
/// - 记录：`POST apply/list`（我的申请，`type` 按类型筛选），
///   审批中心 `POST approve/list/todo|done|copy`；
/// - 详情 `GET apply/{type}/{id}`（type 为数字编码）；
/// - 动作：`POST apply/{id}/withdraw|approve`，`POST apply/{id}/reject`
///   （body `{"reason": ...}` 必填）。
abstract class ApplyRepository {
  Future<List<ApplyRecord>> fetchMyApplies({ApplyType? type, int page = 1});

  Future<List<ApplyRecord>> fetchApprovalBox(
    ApplyBox box, {
    int page = 1,
  });

  Future<ApplyRecord> fetchApplyDetail(ApplyType type, int id);

  /// 配件 / 工具目录（`part/list`、`tool/list`）。
  Future<List<ShopItem>> fetchShopItems(ApplyType kind, {String keyword = ''});

  /// 试剂目录：按站点拉取，返回按适用仪器分组的列表。
  Future<List<ReagentGroup>> fetchReagentGroups(
    int stationId, {
    String keyword = '',
  });

  /// 审批人候选（`GET user/list/apply`，返回全部在职用户）。
  Future<List<TaskPerson>> fetchApprovers({String keyword = ''});

  /// 抄送人候选（`GET user/list/copy`），与审批人同源不同口。
  Future<List<TaskPerson>> fetchCcUsers({String keyword = ''});

  /// 申请单评论（`POST comment/list`，itemType=5，与 iOS postType 5 同源）。
  Future<List<ApplyComment>> fetchApplyComments(int applyId);

  /// 发表申请单评论（`POST comment`）。
  Future<void> postApplyComment(int applyId, String content);

  Future<void> submit(ApplyDraft draft);

  Future<void> withdraw(int id);

  Future<void> approve(int id);

  Future<void> reject(int id, String reason);
}

class RemoteApplyRepository implements ApplyRepository {
  const RemoteApplyRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ApplyRecord>> fetchMyApplies({
    ApplyType? type,
    int page = 1,
  }) async {
    final ApiResponse response = await _api.postRaw(
      'apply/list',
      data: <String, Object?>{
        'startPage': page,
        'limit': 15,
        if (type != null) 'type': type.code,
      },
    );
    return _records(response);
  }

  @override
  Future<List<ApplyRecord>> fetchApprovalBox(ApplyBox box, {int page = 1}) async {
    final ApiResponse response = await _api.postRaw(
      box.path,
      data: <String, Object?>{'startPage': page, 'limit': 15},
    );
    return _records(response);
  }

  @override
  Future<ApplyRecord> fetchApplyDetail(ApplyType type, int id) async {
    final ApiResponse response = await _api.getRaw('apply/${type.pathSegment}/$id');
    return ApplyRecord.fromJson(response.mapData);
  }

  @override
  Future<List<ShopItem>> fetchShopItems(
    ApplyType kind, {
    String keyword = '',
  }) async {
    final ApiResponse response = await _api.postRaw(
      '${kind.pathSegment}/list',
      data: <String, Object?>{'keyword': keyword.trim()},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(ShopItem.fromJson)
        .toList();
  }

  @override
  Future<List<ReagentGroup>> fetchReagentGroups(
    int stationId, {
    String keyword = '',
  }) async {
    final ApiResponse response = await _api.postRaw(
      'reagent/list',
      data: <String, Object?>{
        'stationId': stationId,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(ReagentGroup.fromJson)
        .toList();
  }

  @override
  Future<List<TaskPerson>> fetchApprovers({String keyword = ''}) async {
    final ApiResponse response = await _api.getRaw('user/list/apply');
    final List<TaskPerson> users = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(_person)
        .toList();
    final String query = keyword.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users
        .where((TaskPerson user) => user.nickname.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Future<List<TaskPerson>> fetchCcUsers({String keyword = ''}) async {
    final ApiResponse response = await _api.getRaw('user/list/copy');
    final List<TaskPerson> users = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(_person)
        .toList();
    final String query = keyword.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users
        .where((TaskPerson user) => user.nickname.toLowerCase().contains(query))
        .toList(growable: false);
  }

  /// 申请单的评论 itemType 固定 5（对照 iOS `ApplyPostRepliesController`
  /// 的 `postType = 5`，2026-11-06 实测 `comment/list` 可用）。
  static const int _kItemTypeApply = 5;

  @override
  Future<List<ApplyComment>> fetchApplyComments(int applyId) async {
    final ApiResponse response = await _api.postRaw(
      'comment/list',
      data: <String, Object?>{'itemType': _kItemTypeApply, 'itemId': applyId},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(ApplyComment.fromJson)
        .toList();
  }

  @override
  Future<void> postApplyComment(int applyId, String content) => _api.postRaw(
    'comment',
    data: <String, Object?>{
      'itemType': _kItemTypeApply,
      'itemId': applyId,
      'content': content.trim(),
    },
  );

  @override
  Future<void> submit(ApplyDraft draft) =>
      _api.postRaw('apply/${draft.type.pathSegment}', data: draft.toJson());

  @override
  Future<void> withdraw(int id) =>
      _api.postRaw('apply/$id/withdraw', data: const <String, Object?>{});

  @override
  Future<void> approve(int id) =>
      _api.postRaw('apply/$id/approve', data: const <String, Object?>{});

  @override
  Future<void> reject(int id, String reason) => _api.postRaw(
    'apply/$id/reject',
    data: <String, Object?>{'reason': reason.trim()},
  );

  static List<ApplyRecord> _records(ApiResponse response) => response.listData
      .whereType<Map<Object?, Object?>>()
      .map(ApplyRecord.fromJson)
      .toList();

  static TaskPerson _person(Object? raw) {
    if (raw is! Map) return const TaskPerson();
    return TaskPerson(
      id: raw['id'] is int ? raw['id']! as int : null,
      nickname: (raw['nickname'] ?? '').toString(),
      avatar: (raw['avatar'] ?? '').toString(),
    );
  }
}

/// 演示实现：申请单在进程内流转 —— 提交即出现在「我的申请」与
/// （当选了自己做审批人时）待审批箱里，撤回 / 通过 / 驳回都会改变状态，
/// 与 MockTaskDetailRepository 的副作用约定一致。
class MockApplyRepository implements ApplyRepository {
  MockApplyRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  /// 演示登录账号（与 test helpers 的 demoTestUser 一致）。
  static const int demoUserId = 1001;

  static final List<ApplyRecord> _store = _seed();

  static List<ApplyRecord> _seed() {
    final List<ApplyRecord> records = <ApplyRecord>[
      ApplyRecord(
        id: 901,
        type: ApplyType.reagent,
        state: ApplyState.processing,
        applyNumber: 'SJ2026110501',
        applyDate: '2026-11-05T09:30:00.000+0800',
        requireDate: '2026-11-12',
        description: '氨氮仪试剂补货',
        approveUserId: demoUserId,
        items: const <ApplyItem>[
          ApplyItem(
            itemId: 337,
            itemName: '氨氮试剂D',
            quantity: 2,
            materialCode: '700203000053',
            recipeCode: 'GM81101',
            instrument: '氨氮分析仪',
          ),
        ],
        applicant: const TaskPerson(id: 593, nickname: '张子龙'),
      ),
      ApplyRecord(
        id: 283,
        type: ApplyType.fee,
        state: ApplyState.approved,
        applyNumber: 'LSC2026102801',
        applyDate: '2026-10-28T16:49:08.000+0800',
        approveUserId: 177,
        approveDate: '2026-10-29T09:00:00.000+0800',
        isApproved: true,
        isApprovedStr: '已通过',
        feeType: 2,
        money: 200,
        approveDescription1: '情况属实，同意报销',
      ),
      ApplyRecord(
        id: 276,
        type: ApplyType.tool,
        state: ApplyState.processing,
        applyNumber: 'GJ2026110201',
        applyDate: '2026-11-02T14:00:00.000+0800',
        description: '便携式 pH 计申领',
        approveUserId: demoUserId,
        items: const <ApplyItem>[
          ApplyItem(itemId: 3, itemName: '便携式pH计', quantity: 1),
        ],
        applicant: const TaskPerson(id: 594, nickname: '李娜'),
      ),
      ApplyRecord(
        id: 254,
        type: ApplyType.part,
        state: ApplyState.rejected,
        applyNumber: 'PJ2026102001',
        applyDate: '2026-10-20T11:00:00.000+0800',
        description: '蠕动泵泵管 20 根',
        approveUserId: 177,
        approveDate: '2026-10-21T10:00:00.000+0800',
        isApproved: false,
        isApprovedStr: '已驳回',
        rejectReason: '库存充足，先用完现有备件',
        items: const <ApplyItem>[
          ApplyItem(itemId: 11, itemName: '蠕动泵泵管', quantity: 20),
        ],
      ),
    ];
    return records;
  }

  static final List<ShopItem> _tools = const <ShopItem>[
    ShopItem(
      id: 1,
      name: '总磷分析仪',
      version: 'GR-3210',
      unit: '台',
      count: '1',
      location: '湖州市安吉县凤凰库房',
    ),
    ShopItem(id: 2, name: '便携式COD测定仪', version: 'GR-50', unit: '台', count: '3', location: '嘉兴中心库房'),
    ShopItem(id: 3, name: '便携式pH计', version: 'PH-110', unit: '台', count: '5', location: '嘉兴中心库房'),
    ShopItem(id: 4, name: '红外测温枪', version: 'IR-9', unit: '把', count: '8', location: '连云港库房'),
  ];

  static final List<ShopItem> _parts = const <ShopItem>[
    ShopItem(id: 11, name: '蠕动泵泵管', materialCode: '700203000101', unit: '根', count: '36'),
    ShopItem(id: 12, name: '采水蠕动泵管', materialCode: '700203000102', unit: '根', count: '24'),
    ShopItem(id: 13, name: '电极导线', materialCode: '700203000310', unit: '根', count: '9'),
    ShopItem(id: 14, name: '空气过滤器', materialCode: '700203000415', unit: '只', count: '15'),
  ];

  static final List<ReagentGroup> _reagentGroups = const <ReagentGroup>[
    ReagentGroup(
      instrumentName: '氨氮分析仪',
      items: <ShopItem>[
        ShopItem(
          id: 337,
          name: '氨氮试剂D',
          materialCode: '700203000053',
          recipeCode: 'GM81101',
          company: '绿洁',
          model: 'ADSJD-2126-1901；含试剂及母液',
          bottling: '500ml',
        ),
        ShopItem(id: 338, name: '氨氮标液', materialCode: '700203000054', recipeCode: 'GM81102', bottling: '250ml'),
      ],
    ),
    ReagentGroup(
      instrumentName: 'CODcr分析仪',
      items: <ShopItem>[
        ShopItem(id: 303, name: '总磷试剂', materialCode: '700203000357', recipeCode: 'GM80301'),
        ShopItem(id: 305, name: 'COD试剂套装', materialCode: '700203000360', bottling: '100套'),
      ],
    ),
  ];

  static final List<TaskPerson> _approvers = const <TaskPerson>[
    TaskPerson(id: 177, nickname: '胡华鑫'),
    TaskPerson(id: 16, nickname: '卜幸杰'),
    TaskPerson(id: 25, nickname: '赵亮'),
    TaskPerson(id: 1001, nickname: '张伟'),
  ];

  static int _nextId = 990000;

  /// static store 会跨用例共享（进程内演示数据本就如此），
  /// 测试入口调用它恢复种子数据，避免用例间污染。
  static void resetForTest() {
    _store
      ..clear()
      ..addAll(_seed());
  }

  @override
  Future<List<ApplyRecord>> fetchMyApplies({
    ApplyType? type,
    int page = 1,
  }) async {
    await Future<void>.delayed(delay);
    final Iterable<ApplyRecord> matched = type == null
        ? _store
        : _store.where((ApplyRecord record) => record.type == type);
    return List<ApplyRecord>.unmodifiable(matched);
  }

  @override
  Future<List<ApplyRecord>> fetchApprovalBox(ApplyBox box, {int page = 1}) async {
    await Future<void>.delayed(delay);
    switch (box) {
      case ApplyBox.todo:
        return List<ApplyRecord>.unmodifiable(
          _store.where(
            (ApplyRecord r) =>
                r.approveUserId == demoUserId && r.canApprove,
          ),
        );
      case ApplyBox.done:
        return List<ApplyRecord>.unmodifiable(
          _store.where(
            (ApplyRecord r) =>
                r.approveUserId == demoUserId &&
                (r.state == ApplyState.approved || r.state == ApplyState.rejected),
          ),
        );
      case ApplyBox.copy:
        return const <ApplyRecord>[];
    }
  }

  @override
  Future<ApplyRecord> fetchApplyDetail(ApplyType type, int id) async {
    await Future<void>.delayed(delay);
    for (final ApplyRecord record in _store) {
      if (record.id == id) return record;
    }
    throw AppException(
      '申请单不存在',
      kind: ApiErrorKind.business,
      code: 'NOT_FOUND',
    );
  }

  @override
  Future<List<ShopItem>> fetchShopItems(
    ApplyType kind, {
    String keyword = '',
  }) async {
    await Future<void>.delayed(delay);
    final List<ShopItem> source = kind == ApplyType.tool ? _tools : _parts;
    final String query = keyword.trim();
    if (query.isEmpty) return List<ShopItem>.unmodifiable(source);
    return source
        .where((ShopItem item) => item.name.contains(query))
        .toList(growable: false);
  }

  @override
  Future<List<ReagentGroup>> fetchReagentGroups(
    int stationId, {
    String keyword = '',
  }) async {
    await Future<void>.delayed(delay);
    final String query = keyword.trim();
    if (query.isEmpty) return List<ReagentGroup>.unmodifiable(_reagentGroups);
    return _reagentGroups
        .map(
          (ReagentGroup group) => ReagentGroup(
            instrumentName: group.instrumentName,
            items: group.items
                .where((ShopItem item) => item.name.contains(query))
                .toList(),
          ),
        )
        .where((ReagentGroup group) => group.items.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<TaskPerson>> fetchApprovers({String keyword = ''}) async {
    await Future<void>.delayed(delay);
    final String query = keyword.trim().toLowerCase();
    if (query.isEmpty) return List<TaskPerson>.unmodifiable(_approvers);
    return _approvers
        .where((TaskPerson user) => user.nickname.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Future<List<TaskPerson>> fetchCcUsers({String keyword = ''}) =>
      fetchApprovers(keyword: keyword);

  /// 演示评论：按申请单 id 存进程内，「取列表 + 发表」与真实后端一致。
  static final Map<int, List<ApplyComment>> _commentStore = <int, List<ApplyComment>>{};

  @override
  Future<List<ApplyComment>> fetchApplyComments(int applyId) async {
    await Future<void>.delayed(delay);
    return List<ApplyComment>.unmodifiable(
      _commentStore.putIfAbsent(applyId, () => <ApplyComment>[]),
    );
  }

  @override
  Future<void> postApplyComment(int applyId, String content) async {
    await Future<void>.delayed(delay);
    final List<ApplyComment> list = _commentStore.putIfAbsent(
      applyId,
      () => <ApplyComment>[],
    );
    list.insert(
      0,
      ApplyComment(
        id: list.length + 1,
        content: content.trim(),
        time: DateTime.now().toIso8601String(),
        person: const TaskPerson(id: demoUserId, nickname: '张伟'),
      ),
    );
  }

  @override
  Future<void> submit(ApplyDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (draft.type == ApplyType.fee) {
      if (draft.money == null) {
        throw const AppException('请输入金额！', kind: ApiErrorKind.business);
      }
      if (draft.money! <= 0 || draft.money! > 100000000) {
        throw const AppException(
          '数值异常！上报金额为非零正数！',
          kind: ApiErrorKind.business,
        );
      }
    }
    final ApplyRecord record = ApplyRecord(
      id: ++_nextId,
      type: draft.type,
      state: ApplyState.processing,
      applyNumber: '${draft.type.code}$_nextId',
      applyDate: DateTime.now().toIso8601String(),
      requireDate: draft.requireDate,
      description: draft.description,
      approveUserId: draft.approveUserId ?? demoUserId,
      isApprovedStr: '审批中',
      feeType: draft.feeType,
      money: draft.money,
      pictures: List<String>.of(draft.pictures),
      items: List<ApplyItem>.of(draft.items),
      deliveryName: draft.deliveryName,
      deliveryAddress: draft.deliveryAddress,
      deliveryPhone: draft.deliveryPhone,
      applicant: const TaskPerson(id: demoUserId, nickname: '张伟'),
    );
    _store.insert(0, record);
  }

  @override
  Future<void> withdraw(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ApplyRecord record = _require(id);
    if (!record.canWithdraw) {
      throw const AppException(
        '当前状态不可撤回',
        kind: ApiErrorKind.business,
      );
    }
    _replace(
      record,
      record.copyWith(state: ApplyState.withdrawn, isApprovedStr: '已撤回'),
    );
  }

  @override
  Future<void> approve(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ApplyRecord record = _require(id);
    if (!record.canApprove) {
      throw const AppException(
        '该申请不在待审批状态',
        kind: ApiErrorKind.business,
      );
    }
    _replace(
      record,
      record.copyWith(
        state: ApplyState.approved,
        isApproved: true,
        isApprovedStr: '已通过',
        approveDate: DateTime.now().toIso8601String(),
      ),
    );
  }

  @override
  Future<void> reject(int id, String reason) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (reason.trim().isEmpty) {
      throw const AppException(
        '拒绝原因不能为空！',
        kind: ApiErrorKind.business,
      );
    }
    final ApplyRecord record = _require(id);
    if (!record.canApprove) {
      throw const AppException(
        '该申请不在待审批状态',
        kind: ApiErrorKind.business,
      );
    }
    _replace(
      record,
      record.copyWith(
        state: ApplyState.rejected,
        isApproved: false,
        isApprovedStr: '已驳回',
        rejectReason: reason.trim(),
        approveDate: DateTime.now().toIso8601String(),
      ),
    );
  }

  ApplyRecord _require(int id) {
    for (final ApplyRecord record in _store) {
      if (record.id == id) return record;
    }
    throw AppException('申请单不存在', kind: ApiErrorKind.business);
  }

  void _replace(ApplyRecord old, ApplyRecord next) {
    final int index = _store.indexOf(old);
    _store[index] = next;
  }
}

extension on ApplyType {
  /// 详情路径段与提交路径段一致（`apply/part/{id}`、`apply/part`）。
  String get pathSegment => switch (this) {
    ApplyType.part => 'part',
    ApplyType.reagent => 'reagent',
    ApplyType.fee => 'fee',
    ApplyType.tool => 'tool',
  };
}

final Provider<ApplyRepository> applyRepositoryProvider =
    Provider<ApplyRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockApplyRepository();
      return RemoteApplyRepository(ref.watch(apiClientProvider));
    });
