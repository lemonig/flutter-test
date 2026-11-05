import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/utils/toast.dart';

/// 打开「新建」底部面板，返回用户选择的操作名。
Future<void> showQuickCreateSheet(BuildContext context) async {
  final String? action = await showModalBottomSheet<String>(
    context: context,
    builder: (BuildContext sheetContext) => const QuickCreateSheet(),
  );
  if (action == null || !context.mounted) return;

  if (action == '新建异常') {
    context.push('/task/create');
    return;
  }
  if (action == '新建签到') {
    context.push('/attend/create');
    return;
  }
  showToast(context, '「$action」表单开发中');
}

/// 新建入口：异常上报 / 现场签到。
class QuickCreateSheet extends StatelessWidget {
  const QuickCreateSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('新建', style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              '选择要上报或记录的类型',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _ActionTile(
              icon: LucideIcons.triangleAlert,
              tone: Tone.danger,
              title: '新建异常',
              subtitle: '上报站点设备或水质异常',
              onTap: () => Navigator.of(context).pop('新建异常'),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: LucideIcons.mapPinCheckInside,
              tone: Tone.success,
              title: '新建签到',
              subtitle: '记录现场到场位置与时间',
              onTap: () => Navigator.of(context).pop('新建签到'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Tone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.background,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 21, color: tone.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
