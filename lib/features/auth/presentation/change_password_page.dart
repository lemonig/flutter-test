import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_response.dart';
import '../../../shared/utils/toast.dart';
import '../providers/auth_provider.dart';

/// 修改密码（M1-04）：成功后强制重新登录，由路由守卫接管跳转。
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _busy = false;
  bool _obscureNew = true;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authProvider.notifier)
          .changePassword(
            oldPassword: _oldController.text,
            newPassword: _newController.text,
          );
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } on Object {
      if (mounted) showToast(context, '修改失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(LucideIcons.keyRound, size: 40, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  '修改后需要重新登录',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _oldController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '原密码',
                    prefixIcon: Icon(LucideIcons.lock),
                  ),
                  validator: (String? value) =>
                      (value == null || value.isEmpty) ? '请输入原密码' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newController,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: '新密码',
                    prefixIcon: const Icon(LucideIcons.lockKeyhole),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew ? LucideIcons.eyeOff : LucideIcons.eye,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (String? value) {
                    if (value == null || value.isEmpty) return '请输入新密码';
                    if (value.length < 6) return '密码长度不少于 6 位';
                    if (value == _oldController.text) {
                      return '新密码不能与原密码相同';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认新密码',
                    prefixIcon: Icon(LucideIcons.circleCheck),
                  ),
                  validator: (String? value) =>
                      value != _newController.text ? '两次输入的密码不一致' : null,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确认修改'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
