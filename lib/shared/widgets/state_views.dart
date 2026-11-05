import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_response.dart';
import 'empty_state.dart';

/// M0-05：列表加载骨架屏。用渐变呼吸动画代替静态转圈，
/// 弱网下能明确告诉用户「内容正在来」而不是白屏。
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key, this.height = 132});

  final double height;

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeInOut.transform(_controller.value);
        final Color base = Color.lerp(
          scheme.surfaceContainerHighest,
          scheme.surfaceContainerLow,
          t,
        )!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _bar(base, 40, 40, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _bar(base, double.infinity, 12),
                          const SizedBox(height: 8),
                          _bar(base, 96, 10),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: widget.height - 92),
                _bar(base, double.infinity, 10),
                const SizedBox(height: 8),
                _bar(base, 180, 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(Color color, double width, double height, {double radius = 6}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) => ListView.separated(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    itemCount: count,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (_, _) => const SkeletonCard(),
  );
}

/// 统一错误态：按领域异常类型给不同文案与重试动作。
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    super.key,
    required this.error,
    required this.onRetry,
    this.title = '数据加载失败',
  });

  final Object error;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final String message = error is AppException
        ? (error as AppException).userMessage
        : '请稍后重试';
    final bool offline =
        error is AppException &&
        ((error as AppException).kind == ApiErrorKind.network ||
            (error as AppException).kind == ApiErrorKind.timeout);
    return EmptyState(
      icon: offline ? LucideIcons.cloudOff : LucideIcons.triangleAlert,
      tone: Tone.danger,
      title: title,
      message: message,
      actionLabel: '重新加载',
      onAction: onRetry,
    );
  }
}

/// 通用 AsyncValue 视图：加载 / 错误 / 数据三态统一，供四个业务模块复用。
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
    this.errorTitle,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;
  final String? errorTitle;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => loading ?? const SkeletonList(),
    error: (Object error, StackTrace stack) => ErrorRetryView(
      error: error,
      title: errorTitle ?? '数据加载失败',
      onRetry: onRetry ?? () {},
    ),
    data: builder,
  );
}
