import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 业务状态 → 语义色调的映射。
///
/// 后端返回的状态文案并不统一（异常/巡检/签到三套），集中在这里归类，
/// 避免状态色散落在各个组件里。
Tone toneOfStatus(String status) => switch (status) {
  '待处理' || '未签到' || '超时' || '紧急' || '已驳回' || '已拒绝' || '已过期' =>
    Tone.danger,
  '处理中' || '待巡检' || '进行中' || '待审批' || '待确认' || '未完成' =>
    Tone.warning,
  // 已修复 / 非异常仍等数据管理员确认，用品牌色表示「进行中但无异常」
  '已修复' || '非异常' => Tone.brand,
  '已完成' || '已巡检' || '已签到' || '已通过' || '已关闭' || '已同意' =>
    Tone.success,
  '已终止' || '已取消' => Tone.neutral,
  _ => Tone.brand,
};

/// 状态标签：浅色容器 + 高对比文字 + 前置圆点。
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Tone tone = toneOfStatus(status);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: tone.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status,
            style: text.labelSmall?.copyWith(
              color: tone.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
