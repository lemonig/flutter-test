import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/cache/app_cache_service.dart';
import '../../../core/config/app_env.dart';
import '../../../core/config/app_info.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/storage/app_storage.dart';
import '../../auth/data/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/profile_repository.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/section_header.dart';

/// 我的 Tab：真实登录用户资料 / 工作数据 / 账号设置 / 退出登录。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _pushEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotifyPreference();
  }

  Future<void> _loadNotifyPreference() async {
    final bool enabled = await ref.read(appStorageProvider).isNotifyEnabled();
    if (mounted) setState(() => _pushEnabled = enabled);
  }

  /// 缓存大小是异步算的，这里把三态压成一行副标题，
  /// 避免「清除缓存」一行在加载时突然消失或跳高度。
  String _cacheSubtitle() {
    final AsyncValue<int> size = ref.watch(appCacheSizeProvider);
    return size.when(
      data: (int bytes) => bytes <= 0 ? '暂无可清理的缓存' : formatBytes(bytes),
      loading: () => '正在计算…',
      error: (Object error, StackTrace stack) => '点击清理',
    );
  }

  Future<void> _clearCache() async {
    final int bytes = ref.read(appCacheSizeProvider).value ?? 0;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(LucideIcons.trash2),
        title: const Text('清除缓存'),
        content: Text(
          bytes <= 0
              ? '当前没有可清理的缓存。登录状态、未提交的草稿与已上传的记录都不会被删除。'
              : '将清理约 ${formatBytes(bytes)} 的临时文件与图片缓存。\n\n'
                    '登录状态、未提交的草稿、已上传的记录都不受影响。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(appCacheServiceProvider).clear();
      ref.invalidate(appCacheSizeProvider);
      if (mounted) {
        showToast(context, bytes <= 0 ? '缓存已是空的' : '已清理 ${formatBytes(bytes)}');
      }
    } catch (error) {
      if (mounted) showToast(context, '清除失败：$error');
    }
  }

  Future<void> _confirmLogout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(LucideIcons.logOut),
        title: const Text('退出登录'),
        content: const Text('退出后需要重新输入账号密码，确定继续吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(authProvider.notifier).logout();
    // 路由守卫会自动把未登录态重定向到登录页。
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth =
        ref.watch(authProvider).value ??
        const AuthState(status: AuthStatus.unauthenticated);
    final AppUser? user = auth.user;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _ProfileHeader(
            user: user,
            onRefresh: () => ref.read(authProvider.notifier).refreshProfile(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _WorkStatsCard(),
                const SectionHeader(title: '账号与设置'),
                Card(
                  child: Column(
                    children: <Widget>[
                      _SettingTile(
                        icon: LucideIcons.userRound,
                        title: '个人信息',
                        subtitle: user == null
                            ? '未登录'
                            : '${user.displayName} · ${user.role.label}',
                        onTap: () => context.push('/profile-info'),
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      _SettingTile(
                        icon: LucideIcons.clipboardList,
                        title: '我的事件',
                        subtitle: '上报、处置与巡检记录',
                        onTap: () => context.push('/my-events'),
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      _SettingTile(
                        icon: LucideIcons.mapPin,
                        title: '收货地址',
                        subtitle: '申请试剂 / 配件的收货信息',
                        onTap: () => context.push('/addresses'),
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      _SettingTile(
                        icon: LucideIcons.keyRound,
                        title: '修改密码',
                        subtitle: '修改后需要重新登录',
                        onTap: () => context.push('/change-password'),
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      SwitchListTile(
                        value: _pushEnabled,
                        onChanged: (bool value) async {
                          setState(() => _pushEnabled = value);
                          await ref
                              .read(appStorageProvider)
                              .setNotifyEnabled(value);
                          if (context.mounted) {
                            showToast(context, value ? '已开启任务推送' : '已关闭任务推送');
                          }
                        },
                        secondary: const _TileIcon(
                          icon: LucideIcons.bell,
                          tone: Tone.warning,
                        ),
                        title: Text('消息通知', style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          _pushEnabled ? '异常告警与任务派发实时推送' : '已关闭，仅应用内提示',
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      _SettingTile(
                        icon: LucideIcons.circleHelp,
                        title: '帮助与反馈',
                        subtitle: '常见问题与诊断信息',
                        onTap: () => context.push('/help-feedback'),
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      _SettingTile(
                        icon: LucideIcons.trash2,
                        title: '清除缓存',
                        subtitle: _cacheSubtitle(),
                        onTap: _clearCache,
                      ),
                      const Divider(indent: 60, endIndent: 16),
                      _SettingTile(
                        icon: LucideIcons.info,
                        title: '关于',
                        subtitle:
                            '${AppInfo.versionLabel} · ${AppEnv.label}环境'
                            '${ref.watch(useMockProvider) ? ' · 演示数据' : ''}',
                        onTap: () => context.push('/about'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(LucideIcons.logOut, size: 18),
                  label: const Text('退出登录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.onRefresh});

  final AppUser? user;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = user?.displayName ?? '未登录';
    final String initial = name.isEmpty ? '?' : name.substring(0, 1);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 22),
          child: Row(
            children: <Widget>[
              // 头像加一层表面色描边，与渐变头部拉开层次
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: AppAvatar(
                  label: initial,
                  size: 56,
                  radius: 20,
                  tone: Tone.brand,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.8,
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            user?.title.isNotEmpty == true
                                ? user!.title
                                : (user?.role.label ?? '未登录'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          user == null ? '请先登录' : '工号 ${user!.id}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '刷新资料',
                onPressed: onRefresh,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工作量统计来自 `GET user/profile` 的四个计数字段。
///
/// 之前这里是写死的 18 / 3 / 26，纯占位。后端只给「累计处理数」，
/// 没有「待处理」「本月完成」的口径，所以改成能对得上的三项。
class _WorkStatsCard extends ConsumerWidget {
  const _WorkStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final UserProfile? profile = ref
        .watch(userProfileProvider)
        .asData
        ?.value;
    String value(int? count) => count == null ? '—' : '$count';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: <Widget>[
            _Stat(value: value(profile?.myEventsCount), label: '我的事件', theme: theme),
            _divider(theme),
            _Stat(value: value(profile?.opsRecordCount), label: '巡检记录', theme: theme),
            _divider(theme),
            _Stat(value: value(profile?.attendCount), label: '签到记录', theme: theme),
          ],
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) =>
      Container(width: 1, height: 28, color: theme.colorScheme.outlineVariant);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.theme});

  final String value;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      leading: _TileIcon(icon: icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.chevronRight, size: 18),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, this.tone = Tone.brand});

  final IconData icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 19, color: tone.foreground),
    );
  }
}
