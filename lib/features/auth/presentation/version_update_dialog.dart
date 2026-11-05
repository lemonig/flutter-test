import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/repositories/auth_repository.dart';

/// M1-06：版本更新弹窗。强制更新不可关闭、不可点遮罩取消。
Future<bool> showVersionUpdateDialog(
  BuildContext context,
  AppVersionInfo info,
) async {
  final bool confirmed =
      await showDialog<bool>(
        context: context,
        barrierDismissible: !info.force,
        builder: (BuildContext context) => PopScope(
          canPop: !info.force,
          child: AlertDialog(
            icon: const Icon(LucideIcons.sparkles),
            title: Text(info.force ? '必须更新后继续使用' : '发现新版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('新版本 v${info.version} 已发布'),
                if (info.notes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(info.notes),
                ],
              ],
            ),
            actions: <Widget>[
              if (!info.force)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('稍后提醒'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('去更新'),
              ),
            ],
          ),
        ),
      ) ??
      false;
  return confirmed;
}
