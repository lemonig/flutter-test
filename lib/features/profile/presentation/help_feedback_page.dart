import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/app_env.dart';
import '../../../core/config/app_info.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/push/push_service.dart';
import '../../../shared/utils/toast.dart';
import '../../auth/data/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';

/// 帮助与反馈（M9-04 附带项）。
///
/// 后端没有反馈提交接口（`web/` 下无 feedback/suggest 控制器），
/// 所以这里不做假表单，而是：**常见问题自助排查 + 一键复制诊断信息**。
/// 后者才是运维场景真正省事的 —— 用户找管理员时直接贴一段带环境与版本的信息。
class HelpFeedbackPage extends ConsumerWidget {
  const HelpFeedbackPage({super.key});

  static const List<({String question, String answer})> _faqs =
      <({String question, String answer})>[
        (
          question: '定位失败 / 一直显示「正在定位」怎么办',
          answer: '先确认手机的定位服务已开启，并给应用授予了定位权限。'
              '室内或地下车库信号弱时容易超时，可以到窗边重试。'
              '若提示「已永久拒绝」，需要到系统设置 - 应用 - 绿洁运维 - 权限中手动打开。',
        ),
        (
          question: '签到提示「当前位置未处在签到站点」',
          answer: '签到站点在地图上有一个有效范围，当前坐标不在范围内就会被拦下。'
              '请走到站点范围内再签到；如果确实在站内却仍被拒，'
              '多半是站点坐标配置有偏差，把诊断信息发给管理员核对。',
        ),
        (
          question: '提交巡检提示「请在站房内提交巡检任务」',
          answer: '巡检要求到站房现场提交，服务端会校验当前位置与站点的距离。'
              '请确认定位权限已开、并未使用模拟位置，然后到站房内重新提交。',
        ),
        (
          question: '照片上传失败或一直转圈',
          answer: '先确认网络可用（切换 Wi-Fi / 移动网络重试）。'
              '单张照片不要过大，拍摄后应用会自动压缩；'
              '弱网下建议一次少传几张，分批提交。',
        ),
        (
          question: '看不到某条异常 / 巡检任务',
          answer: '列表按账号的可见范围返回：普通账号只能看到自己上报、自己处理，'
              '以及被授权站点的记录。确实应该看到却看不到，请联系管理员确认站点授权。',
        ),
        (
          question: '按钮是灰的，写着「当前账号无处理权限」',
          answer: '任务的处理、审核、终止都需要对应角色：处理人是本人才能提交处理结果，'
              '数据管理员才能审核。状态已结束（已确认 / 已终止）的任务也不再提供操作。',
        ),
        (
          question: '如何修改密码',
          answer: '「我的 - 修改密码」输入原密码与新密码即可，修改后需要重新登录。'
              '忘记密码只能由管理员在后台重置。',
        ),
        (
          question: '离线能用吗',
          answer: '不能。列表、详情、提交都需要连服务器，'
              '断网时会显示「数据加载失败」并提供重新加载。',
        ),
      ];

  Future<void> _copyDiagnostics(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final AppUser? user = ref.read(authProvider).value?.user;
    final bool useMock = ref.read(useMockProvider);
    final String now = DateTime.now().toString().split('.').first;
    // 推送收不到时，「有没有拿到 CID、别名绑没绑」是最关键的两个信息，
    // 比让用户描述「我没收到通知」有用得多。
    final PushService push = ref.read(pushServiceProvider);
    final String cid = push.clientId.value?.trim() ?? '';
    final StringBuffer buffer = StringBuffer()
      ..writeln('【${AppInfo.name} 诊断信息】')
      ..writeln('版本：${AppInfo.versionLabel}')
      ..writeln('环境：${AppEnv.label}（${AppEnv.flavorName}）')
      ..writeln('数据源：${useMock ? '演示数据' : '真实接口'}')
      ..writeln('接口地址：${AppEnv.baseUrl}')
      ..writeln('账号：${user == null ? '未登录' : '${user.displayName} (id=${user.id})'}')
      ..writeln('推送 CID：${cid.isEmpty ? '未获取' : cid}')
      ..writeln(
        '推送别名：${user == null ? '未绑定' : pushAliasFor(user.id)}',
      )
      ..writeln('时间：$now');

    try {
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (context.mounted) showToast(context, '诊断信息已复制，可直接粘贴给管理员');
    } catch (_) {
      if (context.mounted) showToast(context, '复制失败，请手动截图本页信息');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('帮助与反馈'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(LucideIcons.lifeBuoy, size: 20, color: AppColors.brand),
                    const SizedBox(width: 8),
                    Text(
                      '遇到问题先看这里',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '下面是最常见的 8 个问题。如果都没解决，把「诊断信息」复制后'
                  '发给所属站点的系统管理员，能省掉反复询问版本和环境的时间。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.6,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _copyDiagnostics(context, ref),
                  icon: const Icon(LucideIcons.copy, size: 17),
                  label: const Text('复制诊断信息'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '常见问题',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // 同关于页：ExpansionTile 内部是 ListTile，必须挂在 Material 上。
          Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _faqs.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ExpansionTile(
                    title: Text(
                      _faqs[i].question,
                      style: theme.textTheme.bodyLarge,
                    ),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    iconColor: theme.colorScheme.onSurfaceVariant,
                    collapsedIconColor: theme.colorScheme.onSurfaceVariant,
                    children: <Widget>[
                      Text(
                        _faqs[i].answer,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.65,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  LucideIcons.megaphone,
                  size: 18,
                  color: AppColors.brandOnContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '意见与需求',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.brandOnContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '应用内暂不支持直接提交工单。功能建议、数据错误、'
                        '账号权限问题，请统一反馈给所属站点的系统管理员，'
                        '由管理员汇总后处理。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.6,
                          color: AppColors.brandOnContainer,
                        ),
                      ),
                    ],
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
