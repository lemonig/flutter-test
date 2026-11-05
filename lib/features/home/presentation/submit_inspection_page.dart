import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/app_env.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/location/location_service.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/media/upload_service.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_picker_grid.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/models/ops_detail.dart';
import '../data/repositories/ops_detail_repository.dart';
import '../providers/ops_detail_providers.dart';

/// 巡检填报（M4-02 / M4-03）。
///
/// 对应原工程 `SubmitInspectionController`，提交链路有三道关：
/// 1. 本地校验：`requirePhoto` 的巡检项必须有照片，否则后端直接报
///    「xxx需要上传照片」；
/// 2. 站内校验：`POST opsrecord/submit/check` 传当前坐标，服务端按站点
///    20 km 判定，返回 `data: false` + 「请在站房内提交巡检任务」；
/// 3. 上传与提交：照片先走 `upload/4/file`（`ops/` 前缀）拿 objectKey，
///    再 `POST opsrecord/submit` 带 `itemList`。
///
/// 注意第 2 步的响应是 `success: true` + `data: false`，只看 `success`
/// 会误判成「可以提交」。
class SubmitInspectionPage extends ConsumerWidget {
  const SubmitInspectionPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<OpsDetail> detail = ref.watch(opsDetailProvider(recordId));

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('巡检填报'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: detail.when(
        loading: () => const SkeletonList(count: 3),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.cloudOff,
          title: '巡检任务加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重新加载',
          onAction: () => ref.invalidate(opsDetailProvider(recordId)),
        ),
        data: (OpsDetail data) =>
            _SubmitForm(recordId: recordId, detail: data),
      ),
    );
  }
}

class _SubmitForm extends ConsumerStatefulWidget {
  const _SubmitForm({required this.recordId, required this.detail});

  final String recordId;
  final OpsDetail detail;

  @override
  ConsumerState<_SubmitForm> createState() => _SubmitFormState();
}

class _SubmitFormState extends ConsumerState<_SubmitForm> {
  final Map<int, TextEditingController> _notes = <int, TextEditingController>{};
  final Map<int, List<PickedImage>> _photos = <int, List<PickedImage>>{};
  final TextEditingController _remark = TextEditingController();
  final List<PickedImage> _remarkPhotos = <PickedImage>[];
  bool _submitting = false;

  /// 开发包才允许「定位不在站点范围时改用调试坐标」兜底，
  /// 生产包不暴露，否则等于让站内校验可被绕过。
  bool get _allowDebugPoint => kDebugMode && AppEnv.flavor == AppFlavor.dev;

  @override
  void initState() {
    super.initState();
    _remark.text = widget.detail.description;
    for (final OpsItemDetail item in widget.detail.items) {
      _notes[item.id] = TextEditingController(text: item.description);
      _photos[item.id] = <PickedImage>[];
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _notes.values) {
      controller.dispose();
    }
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OpsDetail detail = widget.detail;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              _HintCard(
                done: detail.doneCount,
                total: detail.items.length,
                deadline: detail.deadlineText,
              ),
              const SizedBox(height: 16),
              for (final OpsGroup group in detail.groups) ...<Widget>[
                SectionHeader(
                  title: group.category,
                  actionLabel: '${group.items.length} 项',
                ),
                const SizedBox(height: 8),
                _GroupEditor(
                  group: group,
                  notes: _notes,
                  photos: _photos,
                  enabled: !_submitting,
                  onPhotosChanged: (int id, List<PickedImage> images) =>
                      setState(() => _photos[id] = images),
                ),
                const SizedBox(height: 14),
              ],
              SectionHeader(
                title: '巡检备注',
                actionLabel: '${_remark.text.length}/600',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _remark,
                      enabled: !_submitting,
                      maxLines: 4,
                      maxLength: 600,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: '本次巡检的整体情况、遗留问题等（选填）',
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 4),
                    ImagePickerGrid(
                      images: _remarkPhotos,
                      enabled: !_submitting,
                      maxCount: 9,
                      label: '备注照片',
                      onChanged: (List<PickedImage> images) =>
                          setState(() {
                            _remarkPhotos
                              ..clear()
                              ..addAll(images);
                          }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: Text(_submitting ? '正在提交…' : '提交巡检'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    // 1. 必传照片：先在本地拦，省一次网络往返，报错文案也更具体。
    for (final OpsItemDetail item in widget.detail.items) {
      if (!item.requirePhoto) continue;
      if ((_photos[item.id] ?? const <PickedImage>[]).isEmpty) {
        showToast(context, '「${item.name}」需要上传照片');
        return;
      }
    }

    setState(() => _submitting = true);
    final OpsDetailRepository repo = ref.read(opsDetailRepositoryProvider);
    try {
      // 2. 站内校验
      GeoPoint? point = await _resolvePoint();
      if (point == null) return;
      OpsSiteCheck check = await repo.checkBeforeSubmit(
        widget.recordId,
        longitude: point.longitude,
        latitude: point.latitude,
      );
      if (!check.onSite && _allowDebugPoint) {
        final bool useDebug = await _confirmDebugPoint(check.message);
        if (useDebug) {
          point = LocationService.debugPoint;
          check = await repo.checkBeforeSubmit(
            widget.recordId,
            longitude: point.longitude,
            latitude: point.latitude,
          );
        }
      }
      if (!check.onSite) {
        if (mounted) {
          showToast(
            context,
            check.message.isEmpty ? '请在站房内提交巡检任务' : check.message,
          );
        }
        return;
      }

      // 3. 上传 + 组装载荷
      final List<OpsSubmitItem> items = <OpsSubmitItem>[];
      for (final OpsItemDetail item in widget.detail.items) {
        final List<PickedImage> picked =
            _photos[item.id] ?? const <PickedImage>[];
        final String note = _notes[item.id]?.text.trim() ?? '';
        final bool changed =
            picked.isNotEmpty || note != item.description.trim();
        // 没动过的项不传：后端是整体覆盖，传空值会把已有备注清掉。
        if (!changed) continue;
        List<String> keys = const <String>[];
        if (picked.isNotEmpty) {
          keys = await ref
              .read(uploadServiceProvider)
              .uploadAll(picked, kind: UploadKind.ops);
        }
        items.add(
          OpsSubmitItem(
            id: item.id,
            description: note,
            pictures: <String>[...item.pictureKeys, ...keys],
          ),
        );
      }

      List<String> remarkKeys = widget.detail.pictureKeys;
      if (_remarkPhotos.isNotEmpty) {
        final List<String> uploaded = await ref
            .read(uploadServiceProvider)
            .uploadAll(_remarkPhotos, kind: UploadKind.ops);
        remarkKeys = <String>[...remarkKeys, ...uploaded];
      }

      await repo.submit(
        widget.recordId,
        OpsSubmitDraft(
          items: items,
          description: _remark.text,
          pictures: remarkKeys,
        ),
      );

      ref.invalidate(opsDetailProvider(widget.recordId));
      if (!mounted) return;
      showToast(context, '巡检已提交');
      Navigator.of(context).pop();
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (mounted) showToast(context, '提交失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<GeoPoint?> _resolvePoint() async {
    // 演示包不依赖真实 GPS，固定用调试坐标跑通流程。
    if (ref.read(useMockProvider)) return LocationService.debugPoint;

    final LocationResult result = await ref.read(locationServiceProvider).locate();
    if (result.isSuccess) return result.point;

    if (_allowDebugPoint) {
      final bool useDebug = await _confirmDebugPoint(result.failure!.message);
      if (useDebug) return LocationService.debugPoint;
    }
    if (mounted) showToast(context, result.failure!.message);
    return null;
  }

  Future<bool> _confirmDebugPoint(String message) async {
    if (!mounted) return false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('不在站点范围内'),
        content: Text(
          message.isEmpty ? '当前位置与站点距离超出限制，无法提交巡检。' : message,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('使用调试坐标重试'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.done,
    required this.total,
    required this.deadline,
  });

  final int done;
  final int total;
  final String deadline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tone.brand.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(LucideIcons.info, size: 18, color: Tone.brand.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '已完成 $done/$total 项 · 截止 $deadline',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Tone.brand.onBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '提交时需在站点 20 公里范围内；标注「需拍照」的项目必须上传照片。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Tone.brand.onBackground,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    required this.group,
    required this.notes,
    required this.photos,
    required this.enabled,
    required this.onPhotosChanged,
  });

  final OpsGroup group;
  final Map<int, TextEditingController> notes;
  final Map<int, List<PickedImage>> photos;
  final bool enabled;
  final void Function(int id, List<PickedImage> images) onPhotosChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          for (final OpsItemDetail item in group.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (item.requirePhoto)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 1),
                          child: _Chip(text: '需拍照', tone: Tone.warning),
                        ),
                    ],
                  ),
                  if (item.pictureKeys.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '已有 ${item.pictureKeys.length} 张照片，新增会追加保留',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes[item.id],
                    enabled: enabled,
                    maxLines: 2,
                    minLines: 1,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '本项备注（选填）',
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ImagePickerGrid(
                    images: photos[item.id] ?? const <PickedImage>[],
                    enabled: enabled,
                    maxCount: 3,
                    label: item.requirePhoto ? '现场照片（必传）' : '现场照片',
                    onChanged: (List<PickedImage> images) =>
                        onPhotosChanged(item.id, images),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.tone});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: tone.onBackground),
      ),
    );
  }
}
