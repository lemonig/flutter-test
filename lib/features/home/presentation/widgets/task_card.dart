import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../data/models/task_item.dart';

/// 首页任务卡片：站点信息 + 状态 + 正文（执行人高亮）+ 现场照片 + 互动数据。
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.item, required this.onTap});

  final TaskItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final Color muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const AppAvatar(
                    label: '站',
                    icon: LucideIcons.mapPin,
                    size: 40,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.stationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Icon(LucideIcons.clock3, size: 12, color: muted),
                            const SizedBox(width: 3),
                            Text(
                              item.timeText,
                              style: text.labelSmall?.copyWith(color: muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (item.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    StatusPill(status: item.tags.first),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: item.content),
                    TextSpan(
                      text: '  @${item.executor}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
              if (item.images.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _ImageStrip(images: item.images),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _Metric(
                    icon: LucideIcons.eye,
                    label: '${item.readCount}',
                    color: muted,
                  ),
                  const SizedBox(width: 16),
                  _Metric(
                    icon: LucideIcons.messageCircle,
                    label: '${item.commentCount}',
                    color: muted,
                  ),
                  const SizedBox(width: 16),
                  _Metric(
                    icon: LucideIcons.thumbsUp,
                    label: '${item.likeCount}',
                    color: muted,
                  ),
                  const Spacer(),
                  Text(
                    '详情',
                    style: text.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final int count = images.length.clamp(0, 3);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _Thumb(url: images[i], seed: i),
                  if (i == 2 && images.length > 3)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: Text(
                          '+${images.length - 3}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 现场照片：网络图加载中/失败时降级为渐变占位块。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.seed});

  final String url;
  final int seed;

  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFF7FB0F5), Color(0xFF4C8BE0)],
    <Color>[Color(0xFF63C7A6), Color(0xFF3FAE8C)],
    <Color>[Color(0xFFF0B468), Color(0xFFD9964A)],
    <Color>[Color(0xFFA79BE3), Color(0xFF8A7CD4)],
  ];

  Widget _placeholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradients[seed % _gradients.length],
        ),
      ),
      child: const Center(
        child: Icon(LucideIcons.image, size: 22, color: Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? progress) {
            if (progress == null) return child;
            return _placeholder();
          },
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return _placeholder();
      },
    );
  }
}
