import 'dart:convert';

/// 功能权限点（M1-03）。工作台入口、审批按钮等按此过滤。
enum AppPermission {
  viewWorkbench,
  reportMileage,
  reportCarFee,
  reportStationFee,
  applyReagent,
  applyPart,
  applyTool,
  applyFee,
  approve,
  statistics,
  stationData,
  vehicleLocation,
  handleAbnormal,
  assignTask,
  manageUser,
}

enum UserRole {
  operator,
  dataManager,
  opsManager,
  projectManager,
  areaManager,
  cityManager,
  regionManager,
  admin,
  unknown,
}

extension UserRoleX on UserRole {
  String get label => switch (this) {
    UserRole.operator => '运维工程师',
    UserRole.dataManager => '数据管理员',
    UserRole.opsManager => '运维主管',
    UserRole.projectManager => '项目经理',
    UserRole.areaManager => '区域经理',
    UserRole.cityManager => '城市经理',
    UserRole.regionManager => '大区经理',
    UserRole.admin => '系统管理员',
    UserRole.unknown => '未分配角色',
  };
}

/// 当前登录用户。字段对齐原 iOS `UserTool.swift` 的 `User` 模型：
/// `token / id / nickname / avatar / title` 以及一组角色布尔标志。
class AppUser {
  const AppUser({
    required this.id,
    required this.token,
    required this.nickname,
    this.username = '',
    this.avatar = '',
    this.title = '',
    this.mobile = '',
    this.role = UserRole.unknown,
    this.permissions = const <AppPermission>{},
    this.rawJson = '',
  });

  final String id;
  final String token;
  final String nickname;
  final String username;
  final String avatar;
  final String title;
  final String mobile;
  final UserRole role;
  final Set<AppPermission> permissions;
  final String rawJson;

  bool can(AppPermission permission) => permissions.contains(permission);

  String get displayName => nickname.isEmpty ? username : nickname;

  factory AppUser.fromJson(Map<Object?, Object?> json) {
    String text(Object? value) => value == null ? '' : '$value';

    final Map<Object?, Object?> meta = json['metaAuthVO'] is Map
        ? Map<Object?, Object?>.from(json['metaAuthVO']! as Map)
        : const <Object?, Object?>{};

    bool flag(String key) =>
        json[key] == true ||
        json[key] == 1 ||
        json[key] == '1' ||
        meta[key] == true ||
        meta[key] == 1;

    final UserRole role = flag('manager')
        ? UserRole.admin
        : flag('projectManager')
        ? UserRole.projectManager
        : flag('opsManager')
        ? UserRole.opsManager
        : flag('reginManager')
        ? UserRole.regionManager
        : flag('areaManager')
        ? UserRole.areaManager
        : flag('cityManager')
        ? UserRole.cityManager
        : flag('dataManager')
        ? UserRole.dataManager
        : flag('ops') || flag('op')
        ? UserRole.operator
        : UserRole.unknown;

    return AppUser(
      id: text(json['id']),
      token: text(json['token']),
      nickname: text(json['nickname']),
      username: text(json['username'] ?? json['account']),
      avatar: text(json['avatar']),
      title: text(json['title']),
      mobile: text(json['mobile']),
      role: role,
      permissions: _permissionsFor(role, flag),
      rawJson: jsonEncode(json),
    );
  }

  static AppUser? tryFromJsonString(String value) {
    try {
      final Object? decoded = jsonDecode(value);
      return decoded is Map ? AppUser.fromJson(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  /// 角色 → 权限。基础运维员可上报/申请/处理异常；
  /// 管理岗逐级叠加审批、统计、资料与用户管理能力。
  static Set<AppPermission> _permissionsFor(
    UserRole role,
    bool Function(String key) flag,
  ) {
    final Set<AppPermission> result = <AppPermission>{
      AppPermission.viewWorkbench,
      AppPermission.reportMileage,
      AppPermission.reportCarFee,
      AppPermission.reportStationFee,
      AppPermission.applyReagent,
      AppPermission.applyPart,
      AppPermission.applyTool,
      AppPermission.applyFee,
      AppPermission.handleAbnormal,
    };

    if (flag('dataManager')) {
      result.addAll(<AppPermission>{
        AppPermission.stationData,
        AppPermission.statistics,
      });
    }
    if (role == UserRole.opsManager ||
        role == UserRole.projectManager ||
        role == UserRole.admin) {
      result.addAll(<AppPermission>{
        AppPermission.approve,
        AppPermission.assignTask,
        AppPermission.statistics,
      });
    }
    if (role == UserRole.areaManager ||
        role == UserRole.cityManager ||
        role == UserRole.regionManager) {
      result.addAll(<AppPermission>{
        AppPermission.approve,
        AppPermission.statistics,
        AppPermission.vehicleLocation,
      });
    }
    if (role == UserRole.projectManager || role == UserRole.admin) {
      result.addAll(<AppPermission>{
        AppPermission.stationData,
        AppPermission.vehicleLocation,
        AppPermission.manageUser,
      });
    }
    return result;
  }

  AppUser copyWith({
    String? token,
    String? nickname,
    String? avatar,
    String? title,
    String? mobile,
  }) => AppUser(
    id: id,
    token: token ?? this.token,
    nickname: nickname ?? this.nickname,
    username: username,
    avatar: avatar ?? this.avatar,
    title: title ?? this.title,
    mobile: mobile ?? this.mobile,
    role: role,
    permissions: permissions,
    rawJson: rawJson,
  );
}
