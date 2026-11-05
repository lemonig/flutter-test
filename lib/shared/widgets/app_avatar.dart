import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 头像 / 图标块：优先展示图标，否则取名称首字。
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.label,
    this.icon,
    this.tone = Tone.brand,
    this.size = 44,
    this.radius = 14,
  });

  final String label;
  final IconData? icon;
  final Tone tone;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.46, color: tone.foreground)
          : Text(
              label.isEmpty ? '?' : label.substring(0, 1),
              style: text.titleSmall?.copyWith(
                color: tone.foreground,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
