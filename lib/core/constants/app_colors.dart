import 'package:flutter/material.dart';

/// 设计令牌：品牌基色 + 业务语义色。
///
/// 中性色（背景、分割线、文字灰阶）全部交给 Material 3 的
/// [ColorScheme] 角色（surface / surfaceContainer* / outline / onSurfaceVariant），
/// 这里只保留 M3 未内置的「成功 / 警告 / 危险」三类业务语义色。
class AppColors {
  const AppColors._();

  /// 品牌主色
  static const Color brand = Color(0xFF1677FF);
  static const Color brandContainer = Color(0xFFE5F0FF);
  static const Color brandOnContainer = Color(0xFF0A3A78);

  /// 成功：已完成 / 已巡检 / 已签到
  static const Color success = Color(0xFF0E9F6E);
  static const Color successContainer = Color(0xFFE2F7EE);
  static const Color successOnContainer = Color(0xFF04543A);

  /// 警告：处理中 / 待跟进
  static const Color warning = Color(0xFFC77414);
  static const Color warningContainer = Color(0xFFFFF1DC);
  static const Color warningOnContainer = Color(0xFF6B3D00);

  /// 危险：待处理 / 异常
  static const Color danger = Color(0xFFD92D20);
  static const Color dangerContainer = Color(0xFFFEECEA);
  static const Color dangerOnContainer = Color(0xFF7A1F16);

  /// 中性：默认态 / 次要标签
  static const Color neutral = Color(0xFF52637A);
  static const Color neutralContainer = Color(0xFFEFF3F9);
  static const Color neutralOnContainer = Color(0xFF3B4A5C);
}

/// 业务状态的气质分组，统一决定标签、图标底色与强调色。
enum Tone { brand, success, warning, danger, neutral }

extension ToneX on Tone {
  /// 前景色（文字 / 图标）
  Color get foreground => switch (this) {
    Tone.brand => AppColors.brand,
    Tone.success => AppColors.success,
    Tone.warning => AppColors.warning,
    Tone.danger => AppColors.danger,
    Tone.neutral => AppColors.neutral,
  };

  /// 容器底色（标签背景 / 图标圆角块）
  Color get background => switch (this) {
    Tone.brand => AppColors.brandContainer,
    Tone.success => AppColors.successContainer,
    Tone.warning => AppColors.warningContainer,
    Tone.danger => AppColors.dangerContainer,
    Tone.neutral => AppColors.neutralContainer,
  };

  /// 容器上的文字色
  Color get onBackground => switch (this) {
    Tone.brand => AppColors.brandOnContainer,
    Tone.success => AppColors.successOnContainer,
    Tone.warning => AppColors.warningOnContainer,
    Tone.danger => AppColors.dangerOnContainer,
    Tone.neutral => AppColors.neutralOnContainer,
  };
}
