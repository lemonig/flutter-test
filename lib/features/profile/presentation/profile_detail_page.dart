import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/profile_repository.dart';

/// 个人资料（M9-01）。
///
/// 能改的只有**头像**：后端 `UserController` 只提供 `user/update_avatar`，
/// 昵称 / 职务 / 公司都没有更新接口。所以这里把它们做成只读信息 + 一句
/// 「联系管理员修改」的说明，而不是放个输入框让用户白填一遍。
///
/// 头像换完要顺手做两件事：
/// 1. `ref.invalidate(userProfileProvider(widget.userId?.toString() ?? ''))` 刷新本页；
/// 2. `authProvider.notifier.refreshProfile()` 重新拉 `meta/auth`，
///    否则「我的」页头部头像还是旧的（两处数据源不同）。
class ProfileDetailPage extends ConsumerStatefulWidget {
  const ProfileDetailPage({super.key, this.userId});

  /// 传了就看别人（只读，来自用户资料库）；不传看自己（可改头像）。
  final int? userId;

  @override
  ConsumerState<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends ConsumerState<ProfileDetailPage> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<UserProfile> async = ref.watch(userProfileProvider(widget.userId?.toString() ?? ''));

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: Text(widget.userId == null ? '个人资料' : '用户资料'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: async.when(
        loading: () => const SkeletonList(count: 3),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.cloudOff,
          title: '资料加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重新加载',
          onAction: () => ref.invalidate(userProfileProvider(widget.userId?.toString() ?? '')),
        ),
        data: (UserProfile profile) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userProfileProvider(widget.userId?.toString() ?? ''));
            await ref.read(userProfileProvider(widget.userId?.toString() ?? '').future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _AvatarCard(
                profile: profile,
                uploading: _uploading && widget.userId == null,
                onPick: widget.userId == null ? _pickAvatar : null,
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: '基本信息'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Column(
                    children: <Widget>[
                      _InfoRow(label: '姓名', value: profile.displayName),
                      _InfoRow(
                        label: '职务',
                        value: profile.title.isEmpty ? '—' : profile.title,
                      ),
                      _InfoRow(
                        label: '所属公司',
                        value: profile.company.isEmpty ? '—' : profile.company,
                      ),
                      _InfoRow(label: '工号', value: '${profile.id}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const _ReadOnlyNotice(),
              const SizedBox(height: 16),
              const SectionHeader(title: '工作量'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: <Widget>[
                      _Stat(value: '${profile.taskCount}', label: '处理异常'),
                      _divider(theme),
                      _Stat(value: '${profile.opsRecordCount}', label: '巡检'),
                      _divider(theme),
                      _Stat(value: '${profile.attendCount}', label: '签到'),
                      _divider(theme),
                      _Stat(value: '${profile.mileageCount}', label: '里程'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) =>
      Container(width: 1, height: 28, color: theme.colorScheme.outlineVariant);

  Future<void> _pickAvatar() async {
    final ImageSourceChoice? choice = await showModalBottomSheet<ImageSourceChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(LucideIcons.camera, size: 20),
              title: const Text('拍照'),
              subtitle: const Text('现场拍摄一张头像'),
              onTap: () => Navigator.of(context).pop(ImageSourceChoice.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.images, size: 20),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(context).pop(ImageSourceChoice.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final ImagePickerService picker = ref.read(imagePickerServiceProvider);
    PickedImage? image;
    try {
      if (choice == ImageSourceChoice.camera) {
        image = await picker.pickFromCamera();
      } else {
        final List<PickedImage> picked = await picker.pickFromGallery(limit: 1);
        image = picked.isEmpty ? null : picked.first;
      }
    } catch (error) {
      if (mounted) showToast(context, '无法打开${choice == ImageSourceChoice.camera ? '相机' : '相册'}：$error');
      return;
    }
    if (image == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      await ref.read(profileRepositoryProvider).updateAvatar(image);
      ref.invalidate(userProfileProvider(widget.userId?.toString() ?? ''));
      // 同步登录态里的头像，「我的」页头部与其它用到头像的地方才会更新
      await ref.read(authProvider.notifier).refreshProfile();
      if (mounted) showToast(context, '头像已更新');
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (mounted) showToast(context, '头像更新失败：$error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.profile,
    required this.uploading,
    required this.onPick,
  });

  final UserProfile profile;
  final bool uploading;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: <Widget>[
            GestureDetector(
              onTap: (uploading || onPick == null) ? null : onPick,
              child: Stack(
                children: <Widget>[
                  ProfileAvatar(
                    url: profile.avatar,
                    label: profile.displayName,
                    size: 84,
                  ),
                  if (onPick != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: uploading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              LucideIcons.camera,
                              size: 14,
                              color: theme.colorScheme.onPrimary,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              profile.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              uploading
              ? '正在上传…'
              : onPick == null
              ? '只可查看'
              : '点击头像更换',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头像：支持网络地址（真实环境）、本地文件路径（演示包）与首字母兜底。
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.url,
    required this.label,
    this.size = 48,
  });

  final String url;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: theme.colorScheme.primaryContainer,
      child: Text(
        label.isEmpty ? '?' : label.substring(0, 1),
        style: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    Widget content;
    if (url.isEmpty) {
      content = fallback;
    } else if (url.startsWith('http')) {
      content = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      content = Image.file(
        File(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return ClipOval(
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Tone.neutral.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(LucideIcons.info, size: 16, color: Tone.neutral.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '姓名、职务与公司由管理员维护，如需修改请联系站点管理员。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Tone.neutral.onBackground,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
