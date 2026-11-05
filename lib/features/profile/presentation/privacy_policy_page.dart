import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/app_info.dart';
import '../../../core/constants/app_colors.dart';

/// 隐私政策（M9-04）。
///
/// 文案按 App 的**实际行为**写，不是通用模板：
/// - 定位只用于签到定位与巡检站内校验，不做轨迹追踪；
/// - 相机 / 相册只在上传现场照片时调用；
/// - 不读取通讯录、短信、通话记录。
/// 应用商店审核会因为「声明与实现不符」被拒，所以这里逐条对得上。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('隐私政策'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _MetaCard(
            version: AppInfo.privacyVersion,
            updatedAt: AppInfo.privacyUpdatedAt,
          ),
          const SizedBox(height: 16),
          const _Section(
            icon: LucideIcons.info,
            title: '一、我们收集哪些信息',
            paragraphs: <String>[
              '1. 账号信息：登录账号、密码（服务端加密存储，本机仅保存登录凭证）、'
                  '姓名、职务、所属公司、工号、头像。',
              '2. 业务数据：你上报的异常、处理的工单、填写的巡检记录、签到记录，'
                  '以及随附的现场照片。',
              '3. 位置信息：仅在以下两种场景读取精确位置 —— '
                  '① 新建签到时确定签到坐标；② 提交巡检任务前校验是否位于站点范围内。'
                  // 别在这里用 Markdown 粗体：Text 不解析 `**`，会原样显示星号
                  '位置信息随业务记录一并保存，不做后台持续定位，也不记录移动轨迹。',
              '4. 设备与日志：设备型号、系统版本、应用版本号、接口请求时间与结果，'
                  '用于排查故障与保障服务稳定。',
            ],
          ),
          const _Section(
            icon: LucideIcons.lock,
            title: '二、我们不收集哪些信息',
            paragraphs: <String>[
              '通讯录、短信、通话记录、剪贴板内容、相册中的其他照片、'
                  '其他应用的安装列表与使用情况，均不在收集范围内。',
            ],
          ),
          const _Section(
            icon: LucideIcons.target,
            title: '三、信息用于什么',
            paragraphs: <String>[
              '1. 完成运维业务的派单、处理、审核与统计。',
              '2. 校验签到与巡检的现场真实性（位置与照片）。',
              '3. 故障排查、安全审计与服务质量改进。',
              '不会用于广告投放，也不会用于与上述目的无关的自动化决策。',
            ],
          ),
          const _Section(
            icon: LucideIcons.shieldCheck,
            title: '四、权限说明',
            paragraphs: <String>[
              '定位权限：新建签到、提交巡检时使用；拒绝后这两个功能不可用，'
                  '其他功能不受影响。',
              '相机权限：拍摄现场照片时使用；可改用「从相册选择」绕过。',
              '相册权限：选择已有照片时使用；仅读取你主动勾选的图片。',
              '网络权限：与服务器通信、上传照片。',
            ],
          ),
          const _Section(
            icon: LucideIcons.server,
            title: '五、存储与共享',
            paragraphs: <String>[
              '业务数据与照片存储在运营方（你所属单位）指定的服务器与对象存储中，'
                  '仅有权限的同事与管理员可见。',
              '除法律法规要求或你所在单位的明确授权外，我们不向第三方提供你的个人信息。',
              '照片与记录在业务需要的历史周期内保存；超出周期后按运营方规定归档或删除。',
            ],
          ),
          const _Section(
            icon: LucideIcons.userCheck,
            title: '六、你的权利',
            paragraphs: <String>[
              '你可以在「我的 - 个人信息」查看本账号资料，在「我的事件」查看自己的业务记录。',
              '如需更正资料、注销账号或导出数据，请联系你所属站点的管理员；'
                  '账号由运营方统一创建与停用。',
            ],
          ),
          const _Section(
            icon: LucideIcons.mail,
            title: '七、联系我们',
            paragraphs: <String>[
              '对本政策有疑问，或认为个人信息被不当处理，可通过「我的 - 帮助与反馈」'
                  '查看联系方式，向所属站点的系统管理员反馈。',
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '本政策自 ${AppInfo.privacyUpdatedAt} 起生效。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '继续使用 ${AppInfo.name} 即表示你已阅读并同意本政策。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.version, required this.updatedAt});

  final String version;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            LucideIcons.fileText,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '版本 v$version · 更新于 $updatedAt',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.paragraphs,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Icon(icon, size: 18, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final String text in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
