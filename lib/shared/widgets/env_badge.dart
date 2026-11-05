import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/app_env.dart';
import '../../core/config/env_probe.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_providers.dart';
import '../../core/network/auth_bridge.dart';

/// 当前构建指向的环境。演示包与真实包必须一眼可辨，
/// 否则「装了包但看不到真实数据」会被误判成接口故障。
class EnvDescriptor {
  const EnvDescriptor({
    required this.title,
    required this.badge,
    required this.tone,
    required this.icon,
    required this.dataSource,
  });

  final String title;
  final String badge;
  final Tone tone;
  final IconData icon;
  final String dataSource;

  static EnvDescriptor of({required bool demo}) {
    if (demo) {
      return const EnvDescriptor(
        title: '演示模式',
        badge: '演示',
        tone: Tone.warning,
        icon: LucideIcons.flaskConical,
        dataSource: '内置演示数据（不发起任何网络请求）',
      );
    }
    return switch (AppEnv.flavor) {
      AppFlavor.prod => const EnvDescriptor(
        title: '生产环境',
        badge: '生产',
        tone: Tone.danger,
        icon: LucideIcons.shieldAlert,
        dataSource: '正式服务器接口',
      ),
      AppFlavor.staging => const EnvDescriptor(
        title: '测试环境',
        badge: '测试',
        tone: Tone.neutral,
        icon: LucideIcons.server,
        dataSource: 'UAT 服务器接口',
      ),
      AppFlavor.dev => const EnvDescriptor(
        title: '开发环境',
        badge: '开发',
        tone: Tone.brand,
        icon: LucideIcons.codeXml,
        dataSource: '局域网后端接口',
      ),
    };
  }
}

/// 环境徽标：首页标题旁常驻，点开即环境诊断面板。
class EnvBadge extends ConsumerWidget {
  const EnvBadge({super.key, this.account, this.role});

  final String? account;
  final String? role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool demo = ref.watch(useMockProvider);
    final EnvDescriptor env = EnvDescriptor.of(demo: demo);
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showEnvDiagnostics(
          context,
          demo: demo,
          token: ref.read(tokenHolderProvider).token,
          account: account,
          role: role,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: env.tone.background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: env.tone.foreground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                env.badge,
                style: text.labelSmall?.copyWith(
                  color: env.tone.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                LucideIcons.chevronDown,
                size: 12,
                color: env.tone.foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开环境诊断面板。
Future<void> showEnvDiagnostics(
  BuildContext context, {
  required bool demo,
  String? token,
  String? account,
  String? role,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _EnvDiagnosticsSheet(
      demo: demo,
      token: token,
      account: account,
      role: role,
    ),
  );
}

class _EnvDiagnosticsSheet extends StatefulWidget {
  const _EnvDiagnosticsSheet({
    required this.demo,
    this.token,
    this.account,
    this.role,
  });

  final bool demo;
  final String? token;
  final String? account;
  final String? role;

  @override
  State<_EnvDiagnosticsSheet> createState() => _EnvDiagnosticsSheetState();
}

class _EnvDiagnosticsSheetState extends State<_EnvDiagnosticsSheet> {
  EnvProbeResult? _result;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    if (!widget.demo) _probe();
  }

  Future<void> _probe() async {
    setState(() => _probing = true);
    final EnvProbeResult result = await EnvProbe.run(token: widget.token);
    if (!mounted) return;
    setState(() {
      _result = result;
      _probing = false;
    });
  }

  String get _diagnosticsText {
    final EnvDescriptor env = EnvDescriptor.of(demo: widget.demo);
    return <String>[
      '环境：${env.title}（FLAVOR=${AppEnv.flavor.name}）',
      'baseUrl：${AppEnv.baseUrl}',
      '数据源：${env.dataSource}',
      '连通性：${_result == null ? '未检测' : '${_result!.label} · ${_result!.summary}'}',
      '账号：${widget.account ?? '未登录'}${widget.role == null ? '' : '（${widget.role}）'}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EnvDescriptor env = EnvDescriptor.of(demo: widget.demo);
    final TextTheme text = theme.textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: env.tone.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(env.icon, size: 19, color: env.tone.foreground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(env.title, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        env.dataSource,
                        style: text.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _UrlRow(url: widget.demo ? '未启用网络层' : AppEnv.baseUrl),
            const SizedBox(height: 8),
            _InfoRow(
              icon: LucideIcons.activity,
              label: '连通性',
              value: _probing
                  ? '检测中…'
                  : (_result == null ? '未检测' : _result!.summary),
              valueColor: _probing
                  ? theme.colorScheme.onSurfaceVariant
                  : (_result == null
                        ? theme.colorScheme.onSurfaceVariant
                        : (_result!.isHealthy
                              ? (_result!.unauthenticated && _result!.hasToken
                                    ? AppColors.warning
                                    : AppColors.success)
                              : AppColors.danger)),
              trailing: _probing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            _InfoRow(
              icon: LucideIcons.userRound,
              label: '登录账号',
              value: widget.account ?? '未登录',
              subtitle: widget.role,
            ),
            _InfoRow(
              icon: LucideIcons.timer,
              label: '请求超时',
              value:
                  '${AppEnv.connectTimeout.inSeconds}s 连接 / ${AppEnv.receiveTimeout.inSeconds}s 读取',
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _probing || widget.demo ? null : _probe,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('重新检测'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _diagnosticsText),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('诊断信息已复制')),
                      );
                    },
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('复制诊断'),
                  ),
                ),
              ],
            ),
            if (widget.demo) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      LucideIcons.info,
                      size: 15,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前包是演示构建，所有数据来自本地 Mock。\n'
                        '要连真实后端，请用 --dart-define=USE_MOCK=false 重新构建。',
                        style: text.bodySmall?.copyWith(
                          color: AppColors.warningOnContainer,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            LucideIcons.link,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '复制地址',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('地址已复制')));
            },
            icon: const Icon(LucideIcons.copy, size: 15),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 9),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
