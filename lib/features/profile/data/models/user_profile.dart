/// 个人资料（`GET user/profile` → 后端 `UserProfile`）。
///
/// 与 [AppUser] 的区别：`AppUser` 是登录态（含 token、角色权限位），
/// 这里是展示用的资料 + 工作量统计，两者来源不同接口，不要互相替代。
///
/// **后端只有「改头像」一个写入接口**（`user/update_avatar`），昵称 / 职务 /
/// 公司都是只读的，页面上不能做成可编辑输入框，否则用户改完发现保存不了。
class UserProfile {
  const UserProfile({
    required this.id,
    this.nickname = '',
    this.avatar = '',
    this.title = '',
    this.company = '',
    this.taskCount = 0,
    this.opsRecordCount = 0,
    this.attendCount = 0,
    this.mileageCount = 0,
  });

  final int id;
  final String nickname;
  final String avatar;
  final String title;
  final String company;

  /// 处理过的异常任务数。
  final int taskCount;

  /// 处理过的巡检数。
  final int opsRecordCount;

  /// 签到数。
  final int attendCount;

  /// 里程上报数。
  final int mileageCount;

  /// 「我的事件」= 异常 + 巡检 + 签到。
  int get myEventsCount => taskCount + opsRecordCount + attendCount;

  String get displayName => nickname.isEmpty ? '未命名用户' : nickname;

  static UserProfile fromJson(Object? raw) {
    final Map<Object?, Object?> json = raw is Map
        ? Map<Object?, Object?>.from(raw)
        : const <Object?, Object?>{};
    return UserProfile(
      id: _asInt(json['id']) ?? 0,
      nickname: '${json['nickname'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
      title: '${json['title'] ?? ''}',
      company: '${json['company'] ?? ''}',
      taskCount: _asInt(json['taskCount']) ?? 0,
      opsRecordCount: _asInt(json['opsRecordCount']) ?? 0,
      attendCount: _asInt(json['attendCount']) ?? 0,
      mileageCount: _asInt(json['mileageCount']) ?? 0,
    );
  }

  UserProfile copyWith({String? avatar}) => UserProfile(
    id: id,
    nickname: nickname,
    avatar: avatar ?? this.avatar,
    title: title,
    company: company,
    taskCount: taskCount,
    opsRecordCount: opsRecordCount,
    attendCount: attendCount,
    mileageCount: mileageCount,
  );

  static int? _asInt(Object? value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v),
    _ => null,
  };
}
