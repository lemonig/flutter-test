import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/media/image_picker_service.dart';
import 'photo_viewer_page.dart';

/// 现场照片选择九宫格（M0-06）。
///
/// 只负责「选 / 删 / 预览」，不在选图时上传 —— 上传时机交给提交动作，
/// 这样用户中途放弃不会在 OSS 上留一堆孤儿文件。
class ImagePickerGrid extends StatefulWidget {
  const ImagePickerGrid({
    super.key,
    required this.images,
    required this.onChanged,
    this.maxCount = 9,
    this.enabled = true,
    this.hint,
    this.picker,
    this.label = '现场照片',
  });

  final List<PickedImage> images;
  final ValueChanged<List<PickedImage>> onChanged;
  final int maxCount;
  final bool enabled;
  final String? hint;

  /// 便于测试注入。
  final ImagePickerService? picker;

  /// 分组标题，处理异常页按「处理前 / 处理中 / 处理后」分块复用。
  final String label;

  @override
  State<ImagePickerGrid> createState() => _ImagePickerGridState();
}

class _ImagePickerGridState extends State<ImagePickerGrid> {
  late final ImagePickerService _picker =
      widget.picker ?? ImagePickerService();
  bool _busy = false;

  int get _remaining => widget.maxCount - widget.images.length;

  Future<void> _openSourceSheet() async {
    if (!widget.enabled || _busy || _remaining <= 0) return;

    final ImageSourceChoice? choice = await showModalBottomSheet<ImageSourceChoice>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(LucideIcons.camera, size: 20),
              title: const Text('拍照'),
              subtitle: const Text('现场即时拍摄'),
              onTap: () => Navigator.of(context).pop(ImageSourceChoice.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.images, size: 20),
              title: const Text('从相册选择'),
              subtitle: Text('最多还可选 $_remaining 张'),
              onTap: () => Navigator.of(context).pop(ImageSourceChoice.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (choice == ImageSourceChoice.camera) {
        final PickedImage? image = await _picker.pickFromCamera();
        if (image != null && mounted) {
          widget.onChanged(<PickedImage>[...widget.images, image]);
        }
      } else {
        final List<PickedImage> picked = await _picker.pickFromGallery(
          limit: _remaining,
        );
        if (picked.isNotEmpty && mounted) {
          final List<PickedImage> merged = <PickedImage>[...widget.images];
          for (final PickedImage image in picked) {
            if (!merged.contains(image) && merged.length < widget.maxCount) {
              merged.add(image);
            }
          }
          widget.onChanged(merged);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开${choice == ImageSourceChoice.camera ? '相机' : '相册'}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(int index) {
    final List<PickedImage> next = <PickedImage>[...widget.images]..removeAt(index);
    widget.onChanged(next);
  }

  void _preview(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PhotoViewerPage(
          images: widget.images.map((PickedImage i) => i.path).toList(),
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool showAddTile =
        widget.enabled && _remaining > 0 && widget.images.length < widget.maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              widget.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.images.length}/${widget.maxCount}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = 8;
            final double tile = (constraints.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (int i = 0; i < widget.images.length; i++)
                  _ImageTile(
                    size: tile,
                    image: widget.images[i],
                    onTap: () => _preview(i),
                    onRemove: widget.enabled ? () => _remove(i) : null,
                  ),
                if (showAddTile)
                  _AddTile(
                    size: tile,
                    busy: _busy,
                    label: '${widget.images.length}/${
                        widget.maxCount
                    }',
                    onTap: _openSourceSheet,
                  ),
              ],
            );
          },
        ),
        if (widget.hint != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.size,
    required this.image,
    required this.onTap,
    this.onRemove,
  });

  final double size;
  final PickedImage image;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: onTap,
                child: Image.file(
                  image.file,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2.4).round(),
                  errorBuilder:
                      (BuildContext context, Object error, StackTrace? s) =>
                          Center(
                            child: Icon(
                              LucideIcons.imageOff,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.size,
    required this.busy,
    required this.label,
    required this.onTap,
  });

  final double size;
  final bool busy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          LucideIcons.plus,
                          size: 22,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
