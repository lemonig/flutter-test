import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/app_env.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/api_response.dart';
import '../../../core/storage/app_storage.dart';
import '../../../shared/utils/toast.dart';
import '../data/repositories/auth_repository.dart';
import '../providers/auth_provider.dart';

/// 登录页（M1-01）：账号密码、记住账号、协议勾选、错误提示、加载态。
/// 登录成功后由 GoRouter 的鉴权 redirect 自动跳转（含原页面回跳）。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscure = true;
  bool _remember = true;
  bool _agreement = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _restoreForm();
  }

  Future<void> _restoreForm() async {
    final AppStorage storage = ref.read(appStorageProvider);
    final ({String username, bool enabled}) remembered = await storage
        .readRememberedUser();
    final bool accepted = await storage.isAgreementAccepted();
    if (!mounted) return;
    setState(() {
      _remember = remembered.enabled;
      _usernameController.text = remembered.username;
      _agreement = accepted;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);
    try {
      await ref
          .read(authProvider.notifier)
          .login(
            username: _usernameController.text,
            password: _passwordController.text,
            remember: _remember,
            agreementAccepted: _agreement,
          );
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.userMessage);
    } on Object {
      if (!mounted) return;
      setState(() => _errorMessage = '登录失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool busy = ref.watch(authBusyProvider);
    final bool demo = ref.watch(useMockProvider);
    final AuthState auth =
        ref.watch(authProvider).value ??
        const AuthState(status: AuthStatus.unauthenticated);
    final String? expiredMessage = auth.message;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 56,
                  maxWidth: 440,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildBrand(scheme, text),
                      const SizedBox(height: 32),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text('账号登录', style: text.titleLarge),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _usernameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: '账号',
                                    hintText: '请输入账号',
                                    prefixIcon: Icon(LucideIcons.userRound),
                                  ),
                                  validator: (String? value) =>
                                      (value == null || value.trim().isEmpty)
                                      ? '请输入账号'
                                      : null,
                                  onChanged: (_) => _clearError(),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) =>
                                      busy ? null : _submit(),
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    hintText: '请输入密码',
                                    prefixIcon: const Icon(
                                      LucideIcons.lockKeyhole,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscure
                                            ? LucideIcons.eyeOff
                                            : LucideIcons.eye,
                                      ),
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                  validator: (String? value) =>
                                      (value == null || value.isEmpty)
                                      ? '请输入密码'
                                      : null,
                                  onChanged: (_) => _clearError(),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: 40,
                                      child: Checkbox(
                                        value: _remember,
                                        onChanged: (bool? value) => setState(
                                          () => _remember = value ?? false,
                                        ),
                                      ),
                                    ),
                                    Text('记住账号', style: text.bodyMedium),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () =>
                                          showToast(context, '忘记密码请联系管理员重置'),
                                      child: const Text('忘记密码？'),
                                    ),
                                  ],
                                ),
                                _buildAgreement(scheme, text),
                                if (_errorMessage != null ||
                                    expiredMessage != null)
                                  _buildError(
                                    scheme,
                                    text,
                                    _errorMessage ?? expiredMessage!,
                                  ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: busy ? null : _submit,
                                  icon: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(LucideIcons.logIn, size: 18),
                                  label: Text(busy ? '登录中…' : '登 录'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildEnvironmentRow(scheme, text, demo),
                      if (demo) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          '演示账号：${MockAuthRepository.demoUsername} / '
                          '${MockAuthRepository.demoPassword}',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrand(ColorScheme scheme, TextTheme text) => Column(
    children: <Widget>[
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(LucideIcons.droplets, size: 36, color: scheme.primary),
      ),
      const SizedBox(height: 16),
      Text(
        '绿洁运维',
        style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        '水环境智能运维平台',
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _buildAgreement(ColorScheme scheme, TextTheme text) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      SizedBox(
        width: 40,
        child: Checkbox(
          value: _agreement,
          onChanged: (bool? value) {
            setState(() {
              _agreement = value ?? false;
              _errorMessage = null;
            });
          },
        ),
      ),
      Expanded(
        child: GestureDetector(
          onTap: _showAgreement,
          child: Text.rich(
            TextSpan(
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              children: <TextSpan>[
                const TextSpan(text: '我已阅读并同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: '与'),
                TextSpan(
                  text: '《隐私政策》',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildError(ColorScheme scheme, TextTheme text, String message) =>
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              LucideIcons.triangleAlert,
              size: 16,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );

  Widget _buildEnvironmentRow(
    ColorScheme scheme,
    TextTheme text,
    bool demo,
  ) => Center(
    child: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Icon(LucideIcons.info, size: 14, color: scheme.onSurfaceVariant),
        Text(
          '${AppEnv.label}环境 · ${demo ? "演示数据" : AppEnv.baseUrl}',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  void _showAgreement() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(LucideIcons.shieldCheck),
        title: const Text('用户协议与隐私政策'),
        content: const Text(
          '本应用仅用于企业内部的运维业务处理。使用过程中会收集必要的账号信息、'
          '设备标识、定位与现场照片，用于签到、异常上报与巡检记录，'
          '不会用于其他目的，也不会向第三方共享。\n\n'
          '你可以在「我的 - 设置」中管理通知权限与本地缓存。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _agreement = true);
              Navigator.of(context).pop();
            },
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
  }
}
