import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/widgets/env_badge.dart';

/// 首页顶部：标题、环境徽标、消息入口、新建入口与搜索框。
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.unreadCount,
    required this.onNotificationTap,
    required this.onCreateTap,
    required this.onSearchTap,
    this.account,
    this.role,
  });

  final int unreadCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onCreateTap;
  final VoidCallback onSearchTap;

  /// 诊断面板里展示的登录身份，未登录时为 null。
  final String? account;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('运维工作台', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Icon(
                          LucideIcons.mapPin,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '嘉兴市 · 水环境监测',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        EnvBadge(account: account, role: role),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '消息',
                onPressed: onNotificationTap,
                icon: Badge.count(
                  count: unreadCount,
                  maxCount: 99,
                  isLabelVisible: unreadCount > 0,
                  child: const Icon(LucideIcons.bell, size: 19),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '新建',
                onPressed: onCreateTap,
                icon: const Icon(LucideIcons.plus, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SearchBar(
            hintText: '搜索站点、任务、人员',
            leading: Icon(
              LucideIcons.search,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            readOnly: true,
            onTap: onSearchTap,
          ),
        ],
      ),
    );
  }
}
