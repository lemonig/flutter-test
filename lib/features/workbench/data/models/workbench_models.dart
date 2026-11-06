/// 工作台（M7）数据模型。
///
/// 后端契约见 `ops-mobile` 的 `ReportController`（上报三件套）、
/// `ApplyController`（申请与审批）、`ReagentController` / `PartController` /
/// `ToolController`（商品目录）与 `CarController`（车辆）。
/// 实测记录与字段说明见 `docs/接口契约.md` §19。
library;

/// 通用下拉选项，对齐后端 `ItemSelect`（`report/meta` 的合同与工程阶段、
/// 元数据里的费用类型都是这个结构）。
class Option {
  const Option({required this.label, required this.value, this.name = ''});

  final String label;
  final int value;

  /// 合同选项用它存项目全名（`report/meta` 的 `contractList.name`）。
  final String name;

  static Option fromJson(Object? raw) {
    if (raw is! Map) return const Option(label: '', value: 0);
    return Option(
      label: (raw['label'] ?? '').toString(),
      value: raw['value'] is int
          ? raw['value']! as int
          : int.tryParse('${raw['value'] ?? ''}') ?? 0,
      name: (raw['name'] ?? '').toString(),
    );
  }

  static List<Option> listFrom(Object? raw) => raw is List
      ? raw.map(Option.fromJson).toList(growable: false)
      : const <Option>[];
}

/// 工作台 Banner（`GET meta/banner`）。
class WorkBanner {
  const WorkBanner({required this.id, required this.imageUrl, this.name = ''});

  final int id;
  final String imageUrl;
  final String name;

  static WorkBanner fromJson(Object? raw) {
    if (raw is! Map) return const WorkBanner(id: 0, imageUrl: '');
    return WorkBanner(
      id: raw['id'] is int ? raw['id']! as int : 0,
      imageUrl: (raw['filePath'] ?? '').toString(),
      name: (raw['name'] ?? '').toString().trim(),
    );
  }
}

/// 车辆（`GET car`），车牌选择的数据源。
class Car {
  const Car({
    required this.id,
    required this.carNum,
    this.region = '',
    this.city = '',
    this.company = '',
    this.description = '',
  });

  final int id;
  final String carNum;
  final String region;
  final String city;
  final String company;
  final String description;

  static Car fromJson(Object? raw) {
    if (raw is! Map) return const Car(id: 0, carNum: '');
    return Car(
      id: raw['id'] is int ? raw['id']! as int : 0,
      carNum: (raw['car_num'] ?? '').toString(),
      region: (raw['region'] ?? '').toString(),
      city: (raw['city'] ?? '').toString(),
      company: (raw['company'] ?? '').toString(),
      description: (raw['description'] ?? '').toString(),
    );
  }
}

/// 上报三件套：里程 / 车辆费用 / 站点（水电网）费用。
///
/// 三者共享 `AbstractReportForm` 基类（描述 + 照片 + 提交人 + 时间），
/// 差异字段见 [ReportRecord] 的可空成员，UI 按 kind 取用。
enum ReportKind { mileage, carFee, stationFee }

extension ReportKindX on ReportKind {
  String get label => switch (this) {
    ReportKind.mileage => '里程上报',
    ReportKind.carFee => '车辆费用',
    ReportKind.stationFee => '水电网费',
  };

  /// 后端路径段：`report/mileage` / `report/carfee` / `report/stationfee`。
  String get path => switch (this) {
    ReportKind.mileage => 'report/mileage',
    ReportKind.carFee => 'report/carfee',
    ReportKind.stationFee => 'report/stationfee',
  };
}

/// 上报记录，合并后端 `CarMileageForm` / `CarFeeForm` / `StationFeeForm`。
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.kind,
    this.description = '',
    this.pictures = const <String>[],
    this.submitter,
    this.gmtCreate = '',
    this.reportNumber = '',
    this.carId,
    this.carNum = '',
    this.mileage,
    this.cost,
    this.feeType,
    this.feeTypeStr = '',
    this.money,
    this.stationId,
    this.station = '',
    this.payDate = '',
    this.nextPayDate = '',
    this.contractId,
    this.contractNum = '',
    this.stage,
    this.stageStr = '',
    this.checkStateStr = '',
  });

  final int id;
  final ReportKind kind;
  final String description;
  final List<String> pictures;

  /// 提交人（`UserAvatar`：id + nickname + avatar）。
  final TaskPerson? submitter;
  final String gmtCreate;
  final String reportNumber;

  final int? carId;
  final String carNum;

  /// 里程表读数（km）与油费 / 过路费（元）。
  final double? mileage;
  final double? cost;

  final int? feeType;
  final String feeTypeStr;

  /// 车辆费用 / 水电网费金额（元）。
  final double? money;

  final int? stationId;
  final String station;
  final String payDate;
  final String nextPayDate;

  final int? contractId;
  final String contractNum;
  final int? stage;
  final String stageStr;

  /// 里程上报的审核状态文案（后端已拼好）。
  final String checkStateStr;

  static ReportRecord fromJson(Object? raw, ReportKind kind) {
    if (raw is! Map) {
      return ReportRecord(id: 0, kind: kind);
    }
    double? toDouble(Object? value) => value is num ? value.toDouble() : null;
    return ReportRecord(
      id: raw['id'] is int ? raw['id']! as int : 0,
      kind: kind,
      description: (raw['description'] ?? '').toString(),
      pictures: _strings(raw['pictures']),
      submitter: _person(raw['user']),
      gmtCreate: (raw['gmt_create'] ?? '').toString(),
      reportNumber: (raw['report_number'] ?? '').toString(),
      carId: raw['car_id'] is int ? raw['car_id']! as int : null,
      carNum: (raw['car_num'] ?? '').toString(),
      mileage: toDouble(raw['mileage']),
      cost: toDouble(raw['cost']),
      feeType: raw['fee_type'] is int ? raw['fee_type']! as int : null,
      feeTypeStr: (raw['fee_type_str'] ?? '').toString(),
      money: toDouble(raw['money']),
      stationId: raw['station_id'] is int ? raw['station_id']! as int : null,
      station: (raw['station'] ?? '').toString(),
      payDate: (raw['pay_date'] ?? '').toString(),
      nextPayDate: (raw['next_pay_date'] ?? '').toString(),
      contractId: raw['contract_id'] is int
          ? raw['contract_id']! as int
          : null,
      contractNum: (raw['contract_num'] ?? '').toString(),
      stage: raw['stage'] is int ? raw['stage']! as int : null,
      stageStr: (raw['stage_str'] ?? '').toString(),
      checkStateStr: (raw['check_state_str'] ?? '').toString(),
    );
  }

  static List<String> _strings(Object? raw) => raw is List
      ? raw.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList()
      : const <String>[];

  static TaskPerson? _person(Object? raw) {
    if (raw is! Map) return null;
    final String nickname = (raw['nickname'] ?? '').toString();
    return TaskPerson(
      id: raw['id'] is int ? raw['id']! as int : null,
      nickname: nickname,
      avatar: (raw['avatar'] ?? '').toString(),
    );
  }
}

/// 上报表单提交体（对应 `PUT report/mileage|carfee|stationfee`）。
class ReportDraft {
  const ReportDraft({
    required this.kind,
    required this.carId,
    required this.carNum,
    required this.mileage,
    required this.cost,
    required this.feeType,
    required this.money,
    required this.stationId,
    required this.station,
    required this.payDate,
    required this.nextPayDate,
    required this.contractId,
    required this.stage,
    required this.description,
    required this.pictures,
  });

  final ReportKind kind;
  final int? carId;
  final String carNum;
  final double? mileage;
  final double? cost;
  final int? feeType;
  final double? money;
  final int? stationId;
  final String station;
  final String payDate;
  final String nextPayDate;
  final int? contractId;
  final int? stage;
  final String description;
  final List<String> pictures;

  /// 对齐 `AbstractReportForm` 及其子类的 JSON 字段（下划线命名）。
  Map<String, Object?> toJson() => <String, Object?>{
    ...switch (kind) {
      ReportKind.mileage => <String, Object?>{
        'car_id': carId,
        'car_num': carNum,
        'mileage': mileage,
        'cost': cost,
      },
      ReportKind.carFee => <String, Object?>{
        'car_id': carId,
        'car_num': carNum,
        'fee_type': feeType,
        'money': money,
      },
      ReportKind.stationFee => <String, Object?>{
        'station_id': stationId,
        'station': station,
        'fee_type': feeType,
        'money': money,
        'pay_date': payDate.isEmpty ? null : payDate,
        'next_pay_date': nextPayDate.isEmpty ? null : nextPayDate,
      },
    },
    if (contractId != null) 'contract_id': contractId,
    if (stage != null) 'stage': stage,
    'description': description.trim(),
    'pictures': pictures,
  }..removeWhere((String key, Object? value) => value == null);
}

/// 商品条目：试剂 / 配件 / 工具共用（`reagent/list`、`part/list`、`tool/list`）。
class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    this.materialCode = '',
    this.version = '',
    this.model = '',
    this.unit = '',
    this.count = '',
    this.location = '',
    this.consistency = '',
    this.bottling = '',
    this.instrument = '',
    this.recipeCode = '',
    this.company = '',
  });

  final int id;
  final String name;
  final String materialCode;
  final String version;
  final String model;
  final String unit;

  /// 工具的库存数量（后端给的是字符串）。
  final String count;
  final String location;

  /// 试剂专属：浓度 / 规格 / 适用仪器 / 配方号。
  final String consistency;
  final String bottling;
  final String instrument;
  final String recipeCode;
  final String company;

  static ShopItem fromJson(Object? raw) {
    if (raw is! Map) return const ShopItem(id: 0, name: '');
    String text(Object? v) => (v ?? '').toString();
    return ShopItem(
      id: raw['id'] is int ? raw['id']! as int : 0,
      name: text(raw['name']),
      materialCode: text(raw['material_code']),
      version: text(raw['version']),
      model: text(raw['model']),
      unit: text(raw['unit']),
      count: text(raw['count']),
      location: text(raw['location']),
      consistency: text(raw['consistency']),
      bottling: text(raw['bottling']),
      instrument: text(raw['instrument'] ?? raw['instrumentName']),
      recipeCode: text(raw['recipe_code']),
      company: text(raw['company']),
    );
  }
}

/// 试剂按适用仪器分组（`POST reagent/list` 带 `stationId` 时的响应结构）。
class ReagentGroup {
  const ReagentGroup({required this.instrumentName, required this.items});

  final String instrumentName;
  final List<ShopItem> items;

  static ReagentGroup fromJson(Object? raw) {
    if (raw is! Map) return const ReagentGroup(instrumentName: '', items: <ShopItem>[]);
    return ReagentGroup(
      instrumentName: (raw['instrumentName'] ?? '').toString(),
      items: raw['reagentList'] is List
          ? (raw['reagentList']! as List).map(ShopItem.fromJson).toList()
          : const <ShopItem>[],
    );
  }
}

/// 申请类型，对齐后端 `ApplyTypeEnum`。
enum ApplyType {
  part(1, '配件申请'),
  reagent(2, '试剂申请'),
  fee(3, '临时费用'),
  tool(4, '运维工具');

  const ApplyType(this.code, this.label);

  final int code;
  final String label;

  static ApplyType? fromCode(Object? raw) {
    final int? code = raw is int ? raw : int.tryParse('$raw');
    for (final ApplyType type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// 申请状态，对齐后端 `ApplyStateEnum`。
enum ApplyState {
  processing(1, '审批中'),
  doing(2, '处理中'),
  approved(3, '已通过'),
  rejected(4, '已驳回'),
  withdrawn(5, '已撤回');

  const ApplyState(this.code, this.label);

  final int code;
  final String label;

  static ApplyState? fromCode(Object? raw) {
    final int? code = raw is int ? raw : int.tryParse('$raw');
    for (final ApplyState state in values) {
      if (state.code == code) return state;
    }
    return null;
  }
}

/// 申请单（列表条目与详情共用 `ApplyForm` 结构）。
class ApplyRecord {
  const ApplyRecord({
    required this.id,
    required this.type,
    required this.state,
    this.applyNumber = '',
    this.applyDate = '',
    this.requireDate = '',
    this.description = '',
    this.approveUserId,
    this.approveDate = '',
    this.isApproved,
    this.isApprovedStr = '',
    this.isApproved2Str = '',
    this.approveDescription1 = '',
    this.approveDescription2 = '',
    this.rejectReason = '',
    this.feeType,
    this.money,
    this.pictures = const <String>[],
    this.items = const <ApplyItem>[],
    this.deliveryName = '',
    this.deliveryAddress = '',
    this.deliveryPhone = '',
    this.applicant,
  });

  final int id;
  final ApplyType type;

  /// 状态优先用后端拼好的文案（`is_approved_str`），枚举兜底。
  final ApplyState state;
  final String applyNumber;
  final String applyDate;
  final String requireDate;
  final String description;
  final int? approveUserId;
  final String approveDate;
  final bool? isApproved;
  final String isApprovedStr;
  final String isApproved2Str;
  final String approveDescription1;
  final String approveDescription2;
  final String rejectReason;
  final int? feeType;
  final double? money;
  final List<String> pictures;
  final List<ApplyItem> items;
  final String deliveryName;
  final String deliveryAddress;
  final String deliveryPhone;

  /// 审批中心列表里的申请人。
  final TaskPerson? applicant;

  String get stateLabel =>
      isApprovedStr.isNotEmpty ? isApprovedStr : state.label;

  bool get canWithdraw => state == ApplyState.processing;

  bool get canApprove =>
      state == ApplyState.processing && isApproved == null;

  /// 审批动作后本地先行更新（Mock 副作用也走这里），避免整页重拉。
  ApplyRecord copyWith({
    ApplyState? state,
    bool? isApproved,
    String? isApprovedStr,
    String? approveDate,
    String? rejectReason,
  }) => ApplyRecord(
    id: id,
    type: type,
    state: state ?? this.state,
    applyNumber: applyNumber,
    applyDate: applyDate,
    requireDate: requireDate,
    description: description,
    approveUserId: approveUserId,
    approveDate: approveDate ?? this.approveDate,
    isApproved: isApproved ?? this.isApproved,
    isApprovedStr: isApprovedStr ?? this.isApprovedStr,
    isApproved2Str: isApproved2Str,
    approveDescription1: approveDescription1,
    approveDescription2: approveDescription2,
    rejectReason: rejectReason ?? this.rejectReason,
    feeType: feeType,
    money: money,
    pictures: pictures,
    items: items,
    deliveryName: deliveryName,
    deliveryAddress: deliveryAddress,
    deliveryPhone: deliveryPhone,
    applicant: applicant,
  );

  static ApplyRecord fromJson(Object? raw) {
    if (raw is! Map) {
      return ApplyRecord(id: 0, type: ApplyType.fee, state: ApplyState.processing);
    }
    double? toDouble(Object? value) => value is num ? value.toDouble() : null;
    final ApplyState state =
        ApplyState.fromCode(raw['apply_state']) ?? ApplyState.processing;
    return ApplyRecord(
      id: raw['id'] is int ? raw['id']! as int : 0,
      type: ApplyType.fromCode(raw['apply_type']) ?? ApplyType.fee,
      state: state,
      applyNumber: (raw['apply_number'] ?? '').toString(),
      applyDate: (raw['apply_date'] ?? '').toString(),
      requireDate: (raw['require_date'] ?? '').toString(),
      description: (raw['description'] ?? '').toString(),
      approveUserId: raw['approve_user_id'] is int
          ? raw['approve_user_id']! as int
          : null,
      approveDate: (raw['approve_date'] ?? '').toString(),
      isApproved: raw['is_approved'] is bool
          ? raw['is_approved']! as bool
          : null,
      isApprovedStr: (raw['is_approved_str'] ?? '').toString(),
      isApproved2Str: (raw['is_approved_2_str'] ?? '').toString(),
      approveDescription1: (raw['approve_description_1'] ?? '').toString(),
      approveDescription2: (raw['approve_description_2'] ?? '').toString(),
      rejectReason: (raw['reason'] ?? '').toString(),
      feeType: raw['fee_type'] is int ? raw['fee_type']! as int : null,
      money: toDouble(raw['money']),
      pictures: ReportRecord._strings(raw['pictures']),
      items: raw['itemList'] is List
          ? (raw['itemList']! as List).map(ApplyItem.fromJson).toList()
          : const <ApplyItem>[],
      deliveryName: (raw['delivery_name'] ?? '').toString(),
      deliveryAddress: (raw['delivery_address'] ?? '').toString(),
      deliveryPhone: (raw['delivery_phone'] ?? '').toString(),
      applicant: ReportRecord._person(raw['user']),
    );
  }
}

/// 申请单明细（`PartReagentItem`）。
class ApplyItem {
  const ApplyItem({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    this.materialCode = '',
    this.consistency = '',
    this.bottling = '',
    this.version = '',
    this.instrument = '',
    this.recipeCode = '',
  });

  final int itemId;
  final String itemName;
  final int quantity;
  final String materialCode;
  final String consistency;
  final String bottling;
  final String version;
  final String instrument;
  final String recipeCode;

  static ApplyItem fromJson(Object? raw) {
    if (raw is! Map) return const ApplyItem(itemId: 0, itemName: '', quantity: 0);
    String text(Object? v) => (v ?? '').toString();
    return ApplyItem(
      itemId: raw['item_id'] is int ? raw['item_id']! as int : 0,
      itemName: text(raw['item_name']),
      quantity: raw['quantity'] is int
          ? raw['quantity']! as int
          : int.tryParse('${raw['quantity'] ?? 0}') ?? 0,
      materialCode: text(raw['material_code']),
      consistency: text(raw['consistency']),
      bottling: text(raw['bottling']),
      version: text(raw['version']),
      instrument: text(raw['instrument']),
      recipeCode: text(raw['recipe_code']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'item_id': itemId,
    'item_name': itemName,
    'quantity': quantity,
    if (materialCode.isNotEmpty) 'material_code': materialCode,
    if (consistency.isNotEmpty) 'consistency': consistency,
    if (bottling.isNotEmpty) 'bottling': bottling,
    if (version.isNotEmpty) 'version': version,
    if (instrument.isNotEmpty) 'instrument': instrument,
    if (recipeCode.isNotEmpty) 'recipe_code': recipeCode,
  };
}

/// 申请单提交体（`POST apply/part|reagent|fee|tool`）。
class ApplyDraft {
  const ApplyDraft({
    required this.type,
    this.description = '',
    this.requireDate = '',
    this.approveUserId,
    this.feeType,
    this.money,
    this.pictures = const <String>[],
    this.items = const <ApplyItem>[],
    this.stationId,
    this.contractId,
    this.toolId,
    this.deliveryName = '',
    this.deliveryAddress = '',
    this.deliveryPhone = '',
    this.applyCopy = const <int>[],
  });

  final ApplyType type;

  /// 抄送人 id 列表（`apply_copy`，对齐 iOS 的多选抄送）。
  final List<int> applyCopy;

  final String description;
  final String requireDate;
  final int? approveUserId;
  final int? feeType;
  final double? money;
  final List<String> pictures;
  final List<ApplyItem> items;
  final int? stationId;
  final int? contractId;

  /// 工具申请：后端按 `tool_id` 自动指定保管人为审批人。
  final int? toolId;
  final String deliveryName;
  final String deliveryAddress;
  final String deliveryPhone;

  Map<String, Object?> toJson() => <String, Object?>{
    'apply_type': type.code,
    'description': description.trim(),
    if (requireDate.isNotEmpty) 'require_date': requireDate,
    if (approveUserId != null) 'approve_user_id': approveUserId,
    if (feeType != null) 'fee_type': feeType,
    if (money != null) 'money': money,
    if (pictures.isNotEmpty) 'pictures': pictures,
    if (items.isNotEmpty)
      'itemList': items.map((ApplyItem item) => item.toJson()).toList(),
    if (stationId != null) 'station_id': stationId,
    if (contractId != null) 'contract_id': contractId,
    if (toolId != null) 'tool_id': toolId,
    if (deliveryName.isNotEmpty) 'delivery_name': deliveryName,
    if (deliveryAddress.isNotEmpty) 'delivery_address': deliveryAddress,
    if (deliveryPhone.isNotEmpty) 'delivery_phone': deliveryPhone,
    if (applyCopy.isNotEmpty) 'apply_copy': applyCopy,
  };
}

/// 审批中心三个列表的 key，同时用于 provider family 与路径参数。
enum ApplyBox { todo, done, copy }

extension ApplyBoxX on ApplyBox {
  String get label => switch (this) {
    ApplyBox.todo => '待我审批',
    ApplyBox.done => '已审批',
    ApplyBox.copy => '我的抄送',
  };

  String get path => switch (this) {
    ApplyBox.todo => 'approve/list/todo',
    ApplyBox.done => 'approve/list/done',
    ApplyBox.copy => 'approve/list/copy',
  };
}

/// 共享的用户精简模型（与 home 的 TaskPerson 同构，避免跨 feature 依赖）。
class TaskPerson {
  const TaskPerson({this.id, this.nickname = '', this.avatar = ''});

  final int? id;
  final String nickname;
  final String avatar;
}

// ───────────────────── 统计（M7-11）─────────────────────

/// 异常统计一行（`POST task/statestat`），title 为省份或「全国」。
class AbnormalStat {
  const AbnormalStat({
    required this.title,
    this.regionKey = '',
    this.total = 0,
    this.todo = 0,
    this.doing = 0,
    this.fixed = 0,
    this.notError = 0,
    this.confirmed = 0,
    this.terminated = 0,
    this.overtime = 0,
  });

  final String title;
  final String regionKey;
  final int total;
  final int todo;
  final int doing;
  final int fixed;
  final int notError;
  final int confirmed;
  final int terminated;
  final int overtime;

  static AbnormalStat fromJson(Object? raw) {
    if (raw is! Map) return const AbnormalStat(title: '');
    int n(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return AbnormalStat(
      title: (raw['title'] ?? '').toString(),
      regionKey: (raw['region_key'] ?? '').toString(),
      total: n(raw['total']),
      todo: n(raw['state_todo']),
      doing: n(raw['state_doing']),
      fixed: n(raw['state_fixed']),
      notError: n(raw['state_noterror']),
      confirmed: n(raw['state_confirmed']),
      terminated: n(raw['state_terminated']),
      overtime: n(raw['state_overtime']),
    );
  }
}

/// 巡检统计一行（`POST opsrecord/statestat`）。
class InspectionStat {
  const InspectionStat({
    required this.title,
    this.regionKey = '',
    this.total = 0,
    this.todo = 0,
    this.done = 0,
    this.overtime = 0,
    this.termination = 0,
  });

  final String title;
  final String regionKey;
  final int total;
  final int todo;
  final int done;
  final int overtime;
  final int termination;

  static InspectionStat fromJson(Object? raw) {
    if (raw is! Map) return const InspectionStat(title: '');
    int n(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return InspectionStat(
      title: (raw['title'] ?? '').toString(),
      regionKey: (raw['region_key'] ?? '').toString(),
      total: n(raw['total']),
      todo: n(raw['todo']),
      done: n(raw['done']),
      overtime: n(raw['overtime']),
      termination: n(raw['termination']),
    );
  }
}

/// 里程统计一行（`POST car/state`）：各省车辆与本周期上报情况。
class MileageStat {
  const MileageStat({
    required this.region,
    this.regionKey = '',
    this.carNumber = 0,
    this.reported = 0,
    this.noReported = 0,
  });

  final String region;
  final String regionKey;
  final int carNumber;
  final int reported;
  final int noReported;

  static MileageStat fromJson(Object? raw) {
    if (raw is! Map) return const MileageStat(region: '');
    int n(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return MileageStat(
      region: (raw['region'] ?? '').toString(),
      regionKey: (raw['region_key'] ?? '').toString(),
      carNumber: n(raw['car_number']),
      reported: n(raw['reported']),
      noReported: n(raw['no_reported']),
    );
  }
}

/// 统计的时间维度：对齐 iOS 的「日 / 周 / 月」切换。
enum StatPeriod { day, week, month }

extension StatPeriodX on StatPeriod {
  String get label => switch (this) {
    StatPeriod.day => '日',
    StatPeriod.week => '周',
    StatPeriod.month => '月',
  };

  /// (startDate, endDate)，与 iOS RiZhouYueHeader 的口径一致：
  /// 日 = 当天，周 = 本周一到今天，月 = 本月 1 号到今天。
  (String, String) range(DateTime now) => switch (this) {
    StatPeriod.day => _fmt(now, now),
    StatPeriod.week => _fmt(now.subtract(Duration(days: now.weekday - 1)), now),
    StatPeriod.month => _fmt(DateTime(now.year, now.month, 1), now),
  };

  static (String, String) _fmt(DateTime start, DateTime end) => (
    '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
    '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}',
  );
}

// ───────────────────── 资料库（M7-12）─────────────────────

/// 站点资料（`GET station/list`，SimpleStation）。
class DirectoryStation {
  const DirectoryStation({
    required this.id,
    this.name = '',
    this.region = '',
    this.city = '',
    this.contractNum = '',
    this.firstChar = '',
  });

  final int id;
  final String name;
  final String region;
  final String city;
  final String contractNum;
  final String firstChar;

  static DirectoryStation fromJson(Object? raw) {
    if (raw is! Map) return const DirectoryStation(id: 0);
    String t(Object? v) => (v ?? '').toString();
    return DirectoryStation(
      id: raw['id'] is int ? raw['id']! as int : 0,
      name: t(raw['name']),
      region: t(raw['region']),
      city: t(raw['city']),
      contractNum: t(raw['contract_num']),
      firstChar: t(raw['firstchar']),
    );
  }
}

/// 站点详情（`GET station/{id}/profile`，对照 iOS StationProfileModel）。
///
/// 实测核心字段：站名/地区 + 三类业务计数 + 管理员信息 + 站点属性；
/// 站点属性字符串（类型/状态等）后端给的是数字编码，iOS 端自己翻译，
/// 这里只展示拿得到文本的 subset，编码类字段不进 UI。
class StationProfile {
  const StationProfile({
    required this.id,
    this.name = '',
    this.region = '',
    this.city = '',
    this.district = '',
    this.address = '',
    this.dataManager = '',
    this.assistant = '',
    this.ops = '',
    this.taskCount = 0,
    this.opsRecordCount = 0,
    this.attendCount = 0,
    this.stationTypeStr = '',
    this.buildDate = '',
    this.mn = '',
  });

  final int id;
  final String name;
  final String region;
  final String city;
  final String district;
  final String address;
  final String dataManager;
  final String assistant;
  final String ops;
  final int taskCount;
  final int opsRecordCount;
  final int attendCount;
  final String stationTypeStr;
  final String buildDate;
  final String mn;

  String get regionText => <String>[
    region,
    city,
    district,
  ].where((String s) => s.isNotEmpty).join(' ');

  static StationProfile fromJson(Object? raw) {
    if (raw is! Map) return const StationProfile(id: 0);
    String t(Object? v) => (v ?? '').toString();
    int n(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return StationProfile(
      id: n(raw['id']),
      name: t(raw['name']),
      region: t(raw['region']),
      city: t(raw['city']),
      district: t(raw['district']),
      address: t(raw['address']),
      dataManager: t(raw['dataManager']),
      assistant: t(raw['assistant']),
      ops: t(raw['ops']),
      taskCount: n(raw['taskCount']),
      opsRecordCount: n(raw['opsRecordCount']),
      attendCount: n(raw['attendCount']),
      buildDate: t(raw['buildDate']),
      mn: t(raw['mn']),
    );
  }
}

/// 驻点资料（`GET agency/list`，Agency）。
class Agency {
  const Agency({
    required this.id,
    this.name = '',
    this.agent = '',
    this.agentPhone = '',
    this.landlord = '',
    this.landlordPhone = '',
    this.countRoom = '',
    this.countRoomUsed = '',
    this.startDate = '',
    this.endDate = '',
    this.rentOfYear = '',
    this.feeOfYear = '',
    this.payMethod = '',
  });

  final int id;
  final String name;
  final String agent;
  final String agentPhone;
  final String landlord;
  final String landlordPhone;
  final String countRoom;
  final String countRoomUsed;
  final String startDate;
  final String endDate;
  final String rentOfYear;
  final String feeOfYear;
  final String payMethod;

  static Agency fromJson(Object? raw) {
    if (raw is! Map) return const Agency(id: 0);
    String t(Object? v) => (v ?? '').toString();
    return Agency(
      id: raw['id'] is int ? raw['id']! as int : 0,
      name: t(raw['name']),
      agent: t(raw['agent']),
      agentPhone: t(raw['agent_phone']),
      landlord: t(raw['landlord']),
      landlordPhone: t(raw['landlord_phone']),
      countRoom: t(raw['count_room']),
      countRoomUsed: t(raw['count_room_used']),
      startDate: t(raw['start_date']),
      endDate: t(raw['end_date']),
      rentOfYear: t(raw['rent_of_year']),
      feeOfYear: t(raw['fee_of_year']),
      payMethod: t(raw['pay_method']),
    );
  }
}

/// 带定位的车辆条目（`GET car/location`，CarLocation + Car）。
class CarLocationItem {
  const CarLocationItem({
    required this.car,
    this.lng = '',
    this.lat = '',
    this.gpsTime = '',
    this.speed = 0,
    this.online = false,
    this.imei = '',
    this.locDesc = '',
  });

  final Car car;
  final String lng;
  final String lat;
  final String gpsTime;
  final double speed;
  final bool online;
  final String imei;
  final String locDesc;

  static CarLocationItem fromJson(Object? raw) {
    if (raw is! Map) {
      return const CarLocationItem(car: Car(id: 0, carNum: ''));
    }
    String t(Object? v) => (v ?? '').toString();
    return CarLocationItem(
      car: Car.fromJson(raw['car']),
      lng: t(raw['lng']),
      lat: t(raw['lat']),
      gpsTime: t(raw['gps_time']),
      speed: raw['speed'] is num ? (raw['speed']! as num).toDouble() : 0,
      online: raw['activation_flag'] == true,
      imei: t(raw['imei']),
      locDesc: t(raw['loc_desc']),
    );
  }
}

/// 申请单评论（`comment` 家族，itemType=5，与 iOS postType 5 同源）。
class ApplyComment {
  const ApplyComment({
    required this.id,
    required this.content,
    this.time = '',
    this.person,
  });

  final int id;
  final String content;
  final String time;
  final TaskPerson? person;

  static ApplyComment fromJson(Object? raw) {
    if (raw is! Map) return const ApplyComment(id: 0, content: '');
    final Object? user = raw['user'];
    return ApplyComment(
      id: raw['id'] is int ? raw['id']! as int : 0,
      content: (raw['content'] ?? '').toString(),
      time: (raw['gmt_create'] ?? raw['time'] ?? '').toString(),
      person: TaskPerson(
        id: raw['user_id'] is int ? raw['user_id']! as int : null,
        nickname: (user is Map ? user['nickname'] : user ?? '').toString(),
        avatar: (user is Map ? user['avatar'] : (raw['avatar'] ?? '')).toString(),
      ),
    );
  }
}
