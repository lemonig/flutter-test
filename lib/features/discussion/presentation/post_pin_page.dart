import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/media/image_picker_service.dart';
import '../../../core/media/upload_service.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/toast.dart';
import '../data/models/pin_post.dart';
import '../providers/pin_providers.dart';

/// 发帖（M8-02，对照 iOS DiscussionReleaseController）：
/// 选频道 + 正文（必填）+ 多图（upload/5/file → pin/ 前缀 objectKey）。
/// iOS 还有标题字段，后端 Pin.title 可空，这里保留选填一行。
class PostPinPage extends ConsumerStatefulWidget {
  const PostPinPage({super.key});

  @override
  ConsumerState<PostPinPage> createState() => _PostPinPageState();
}

class _PostPinPageState extends ConsumerState<PostPinPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final List<PickedImage> _photos = <PickedImage>[];
  PinChannel? _channel;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickChannel() async {
    final List<PinChannel> channels =
        await ref.read(pinChannelsProvider.future);
    if (!mounted) return;
    final PinChannel? picked = await showModalBottomSheet<PinChannel>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            for (final PinChannel channel in channels)
              ListTile(
                title: Text(channel.name),
                trailing: channel.id == _channel?.id
                    ? const Icon(LucideIcons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(channel),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _channel = picked);
  }

  Future<void> _pickPhotos() async {
    final List<PickedImage> picked = await ref
        .read(imagePickerServiceProvider)
        .pickFromGallery(limit: UploadService.maxImages - _photos.length);
    if (picked.isNotEmpty) setState(() => _photos.addAll(picked));
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_content.text.trim().isEmpty) {
      showToast(context, '请填写帖子内容');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _busyLabel = _photos.isEmpty ? '发布中…' : '上传图片…';
    });
    try {
      final List<String> keys = _photos.isEmpty
          ? const <String>[]
          : await ref
                .read(uploadServiceProvider)
                .uploadAll(_photos, kind: UploadKind.pin);
      if (!mounted) return;
      setState(() => _busyLabel = '发布中…');

      await ref
          .read(pinActionServiceProvider)
          .createPost(
            channelId: _channel?.id ?? 0,
            content: _content.text,
            pictures: keys,
          );
      if (!mounted) return;
      showToast(context, '发布成功');
      Navigator.of(context).pop();
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '发布失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _busyLabel = '发布中…';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('发帖')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Card(
              child: ListTile(
                leading: const Icon(LucideIcons.hash, size: 20),
                title: const Text('频道'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _channel?.name ?? '选择频道',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _channel == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevronRight, size: 16),
                  ],
                ),
                onTap: _pickChannel,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _title,
                      maxLines: 1,
                      decoration: const InputDecoration(
                        hintText: '标题（选填）',
                        border: InputBorder.none,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 1),
                    TextField(
                      controller: _content,
                      minLines: 6,
                      maxLines: 12,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '分享反馈、问题或经验…（必填）',
                        border: InputBorder.none,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(LucideIcons.imagePlus, size: 20),
                        const SizedBox(width: 16),
                        Text('图片', style: theme.textTheme.bodyMedium),
                        const Spacer(),
                        Text(
                          '${_photos.length}/${UploadService.maxImages}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          onPressed:
                              _photos.length >= UploadService.maxImages
                              ? null
                              : _pickPhotos,
                          icon: const Icon(LucideIcons.plus, size: 20),
                          tooltip: '从相册选择',
                        ),
                      ],
                    ),
                    if (_photos.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (int i = 0; i < _photos.length; i++)
                            Stack(
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _photos[i].file,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _photos.removeAt(i)),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(8),
                                          topRight: Radius.circular(8),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(3),
                                      child: const Icon(
                                        LucideIcons.x,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(_busyLabel),
                      ],
                    )
                  : const Text('发布'),
            ),
          ],
        ),
      ),
    );
  }
}
