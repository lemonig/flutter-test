import 'package:flutter/material.dart';

/// 轻量提示：统一 SnackBar 文案与时长，避免每个页面重复拼装。
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
      ),
    );
}
