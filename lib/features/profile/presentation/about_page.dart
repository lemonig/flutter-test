import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/app_env.dart';
import '../../../core/config/app_info.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_providers.dart';
import '../../../shared/utils/toast.dart';
import '../../auth/data/repositories/auth_repository.dart';
import '../../auth/presentation/version_update_dialog.dart';
import '../../auth/providers/auth_provider.dart';

/// 关于（M9-04 / M9-05 手动检查更新）。
///
/// 版本检查原本只在登录后静默跑一次（`appVersionProvider`），
/// 用户想主动确认「是不是最新版」时没有任何入口，这里补上。
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _checking = false;

  /// 只比主版本号段，避免服务端发布旧版本时反被提示「有新版本」。
  static bool _isNewer(String remote, String local) {
    List<int> parse(String value) => value
        .split(RegExp(r'[.+-]'))
        .map((String part) => int.tryParse(part) ?? 0)
        .toList();

    final List<int> a = parse(remote);
    final List<int> b = parse(local);
    for (int i = 0; i < 3; i++) {
      final int x = i < a.length ? a[i] : 0;
      final int y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    if (AppEnv.versionCheckUrl == null) {
      showToast(
        context,
        '${AppEnv.label}环境不检查线上版本，正式包才会提示更新',
      );
      return;
    }
    setState(() => _checking = true);
    try {
      final AppVersionInfo? info = await ref.refresh(appVersionProvider.future);
      if (!mounted) return;
      if (info == null) {
        showToast(context, '已是最新版本 ${AppInfo.versionLabel}');
        return;
      }
      if (!_isNewer(info.version, AppInfo.version)) {
        showToast(context, '已是最新版本 ${AppInfo.versionLabel}');
        return;
      }
      final bool goUpdate = await showVersionUpdateDialog(context, info);
      if (goUpdate && mounted) {
        showToast(context, '请前往应用市场更新到 v${info.version}');
      }
    } catch (error) {
      if (mounted) showToast(context, '检查更新失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool useMock = ref.watch(useMockProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('关于'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const _AppBadge(),
          const SizedBox(height: 20),
          _InfoCard(
            rows: <({String label, String value})>[
              (label: '版本', value: AppInfo.versionLabel),
              (label: '环境', value: '${AppEnv.label}（${AppEnv.flavorName}）'),
              (label: '数据源', value: useMock ? '演示数据（不连服务器）' : '真实接口'),
              (label: '服务器', value: AppEnv.baseUrl),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: _checking ? null : _checkUpdate,
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw, size: 18),
            label: Text(_checking ? '正在检查…' : '检查更新'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 20),
          // 必须是 Material 而不是带背景色的 Container：
          // ListTile 在非 Material 的背景上会断言「水波纹可能不可见」。
          Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                _LinkTile(
                  icon: LucideIcons.shieldCheck,
                  title: '隐私政策',
                  subtitle: '收集范围、权限用途与你的权利',
                  onTap: () => context.push('/privacy-policy'),
                ),
                const Divider(height: 1, indent: 56, endIndent: 16),
                _LinkTile(
                  icon: LucideIcons.lifeBuoy,
                  title: '帮助与反馈',
                  subtitle: '常见问题与诊断信息',
                  onTap: () => context.push('/help-feedback'),
                ),
                const Divider(height: 1, indent: 56, endIndent: 16),
                _LinkTile(
                  icon: LucideIcons.code,
                  title: '开源许可',
                  subtitle: '第三方组件授权说明',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppInfo.name,
                    applicationVersion: AppInfo.versionLabel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '© 2026 绿洁环境 · 运维移动端',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBadge extends StatelessWidget {
  const _AppBadge();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.brand, Color(0xFF3C9BFF)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            LucideIcons.droplets,
            size: 38,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppInfo.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          AppInfo.versionLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 64,
                    child: Text(
                      rows[i].label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
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
    final ThemeData theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      leading: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: const Icon(LucideIcons.chevronRight, size: 18),
    );
  }
}
