/// 处理异常（M3-04）所需的模型：异常单元目录、六类处理照片、提交草稿。
///
/// 契约来自后端 `TaskSubmitValidator`：`reason` / `solution` 必填，
/// 「异常单元」与「异常仪器」至少要选一个，`picturesBefore` / `picturesAfter`
/// 必传；当 `isArrived=true` 时还要 `processing` / `cleaning` /
/// `waterIntake` / `opsRecord` 四类站点照片。缺一项都会被服务端拒绝，
/// 所以客户端在提交前先做同样的校验，避免白跑一趟。
library;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/widgets.dart';

/// 后端 `TaskErrorUnitItemVO`。
class ErrorUnitOption {
  const ErrorUnitOption({
    required this.value,
    required this.label,
    this.selected = false,
  });

  final int value;
  final String label;
  final bool selected;

  static ErrorUnitOption fromJson(Object? raw) {
    final Map<Object?, Object?> map = raw is Map
        ? raw
        : const <Object?, Object?>{};
    return ErrorUnitOption(
      value: map['value'] is int
          ? map['value']! as int
          : int.tryParse('${map['value'] ?? 0}') ?? 0,
      label: (map['label'] ?? '').toString(),
      selected: map['selected'] == true,
    );
  }

  static List<ErrorUnitOption> listFrom(Object? raw) {
    if (raw is! List) return const <ErrorUnitOption>[];
    return raw.map(ErrorUnitOption.fromJson).toList(growable: false);
  }
}

/// 后端 `TaskErrorUnitVO`：异常仪器 + 控制单元 + 其他单元。
class ErrorUnitCatalog {
  const ErrorUnitCatalog({
    this.instruments = const <ErrorUnitOption>[],
    this.controls = const <ErrorUnitOption>[],
    this.others = const <ErrorUnitOption>[],
  });

  final List<ErrorUnitOption> instruments;
  final List<ErrorUnitOption> controls;
  final List<ErrorUnitOption> others;

  factory ErrorUnitCatalog.fromJson(Map<String, Object?> json) =>
      ErrorUnitCatalog(
        instruments: ErrorUnitOption.listFrom(json['unitInstrument']),
        controls: ErrorUnitOption.listFrom(json['unitControl']),
        others: ErrorUnitOption.listFrom(json['unitOther']),
      );

  bool get isEmpty => instruments.isEmpty && controls.isEmpty && others.isEmpty;
}

/// 六类处理照片，顺序与后端字段一一对应。
///
/// [requiredWhenArrived] 为 false 的（处理前 / 处理后）无论是否到站都必须传。
enum ProcessPhotoSlot {
  before('处理前', 'picturesBefore', true),
  processing('处理中', 'picturesProcessing', false),
  after('处理后', 'picturesAfter', true),
  cleaning('站房卫生', 'picturesCleaning', false),
  waterIntake('取水口', 'picturesWaterIntake', false),
  opsRecord('运维记录', 'picturesOpsRecord', false);

  const ProcessPhotoSlot(this.label, this.field, this.alwaysRequired);

  final String label;
  final String field;

  /// 到站提交时必传；离站提交时仅 [alwaysRequired] 为 true 的必传。
  final bool alwaysRequired;

  bool isRequired({required bool arrived}) => alwaysRequired || arrived;

  IconData get icon => switch (this) {
    ProcessPhotoSlot.before => LucideIcons.camera,
    ProcessPhotoSlot.processing => LucideIcons.wrench,
    ProcessPhotoSlot.after => LucideIcons.circleCheck,
    ProcessPhotoSlot.cleaning => LucideIcons.sparkles,
    ProcessPhotoSlot.waterIntake => LucideIcons.waves,
    ProcessPhotoSlot.opsRecord => LucideIcons.clipboardList,
  };
}

/// 处理结果：已修复 / 非异常。对应 `task/submit/fixed` 与
/// `task/submit/noterror` 两个接口，状态码 3 / 4。
enum ProcessOutcome {
  fixed('已修复', 3, 'task/submit/fixed'),
  notError('非异常', 4, 'task/submit/noterror');

  const ProcessOutcome(this.label, this.stateCode, this.endpoint);

  final String label;
  final int stateCode;
  final String endpoint;

  String get hint => switch (this) {
    ProcessOutcome.fixed => '设备或数据已恢复正常，提交后等待数据管理员确认关闭',
    ProcessOutcome.notError => '现场核查未发现异常，提交后由数据管理员确认',
  };
}

/// 处理表单的提交载荷。
class ProcessDraft {
  const ProcessDraft({
    required this.taskId,
    required this.outcome,
    required this.reason,
    required this.solution,
    this.instrumentIds = const <int>[],
    this.unitIds = const <int>[],
    this.photos = const <ProcessPhotoSlot, List<String>>{},
    this.isArrived = true,
    this.causedByProduct,
    this.description = '',
  });

  final int taskId;
  final ProcessOutcome outcome;
  final String reason;
  final String solution;
  final List<int> instrumentIds;
  final List<int> unitIds;
  final Map<ProcessPhotoSlot, List<String>> photos;
  final bool isArrived;
  final bool? causedByProduct;
  final String description;

  List<String> photosOf(ProcessPhotoSlot slot) =>
      photos[slot] ?? const <String>[];

  Map<String, Object?> toJson() {
    final Map<String, Object?> json = <String, Object?>{
      'id': taskId,
      'reason': reason.trim(),
      'solution': solution.trim(),
      'instrumentList': instrumentIds,
      'errorUnitList': unitIds,
      'isArrived': isArrived,
      if (description.trim().isNotEmpty) 'description': description.trim(),
      if (causedByProduct != null) 'causedByProduct': causedByProduct,
    };
    // 只传已选照片；后端对空列表与 null 一视同仁，都判为「未上传」。
    for (final ProcessPhotoSlot slot in ProcessPhotoSlot.values) {
      final List<String> keys = photosOf(slot);
      if (keys.isNotEmpty) json[slot.field] = keys;
    }
    return json;
  }

  /// 与后端 `TaskSubmitValidator` 等价的前端校验，返回第一条错误。
  String? validate() {
    if (reason.trim().isEmpty) return '请填写故障原因';
    if (solution.trim().isEmpty) return '请填写解决办法';
    if (instrumentIds.isEmpty && unitIds.isEmpty) {
      return '请至少选择一个异常单元或异常仪器';
    }
    for (final ProcessPhotoSlot slot in ProcessPhotoSlot.values) {
      if (!slot.isRequired(arrived: isArrived)) continue;
      if (photosOf(slot).isEmpty) return '请上传「${slot.label}」照片';
    }
    return null;
  }
}
