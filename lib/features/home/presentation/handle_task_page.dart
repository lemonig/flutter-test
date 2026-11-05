import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/media/upload_service.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/image_picker_grid.dart';
import '../../../shared/widgets/status_pill.dart';
import '../data/models/task_detail.dart';
import '../data/models/task_item.dart';
import '../data/models/task_process.dart';
import '../providers/home_providers.dart';
import '../providers/task_detail_providers.dart';

/// 处理异常（M3-04）。
///
/// 表单结构与后端 `TaskSubmitValidator` 的必填项一一对应：
/// 处理结果 → 异常定位（单元/仪器多选）→ 故障原因 → 解决办法 → 现场照片。
/// 少一项服务端都会拒绝，所以本地先做同样的校验并给出定位到字段的提示。
class HandleTaskPage extends ConsumerStatefulWidget {
  const HandleTaskPage({super.key, required this.task});

  final TaskDetail task;

  @override
  ConsumerState<HandleTaskPage> createState() => _HandleTaskPageState();
}

class _HandleTaskPageState extends ConsumerState<HandleTaskPage> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _solution = TextEditingController();
  final TextEditingController _description = TextEditingController();

  final Set<int> _instruments = <int>{};
  final Set<int> _units = <int>{};
  final Map<ProcessPhotoSlot, List<PickedImage>> _photos =
      <ProcessPhotoSlot, List<PickedImage>>{};

  ProcessOutcome _outcome = ProcessOutcome.fixed;
  bool _arrived = true;
  bool _busy = false;
  String? _busyLabel;

  @override
  void initState() {
    super.initState();
    // 上次存过草稿时把已填内容带出来，避免运维重填一遍。
    _reason.text = widget.task.reason;
    _solution.text = widget.task.solution;
    _description.text = widget.task.description;
  }

  @override
  void dispose() {
    _reason.dispose();
    _solution.dispose();
    _description.dispose();
    super.dispose();
  }

  int get _photoCount => _photos.values.fold<int>(
    0,
    (int sum, List<PickedImage> list) => sum + list.length,
  );

  ProcessDraft _buildDraft({bool withPhotos = true}) => ProcessDraft(
    taskId: widget.task.id,
    outcome: _outcome,
    reason: _reason.text,
    solution: _solution.text,
    description: _description.text,
    instrumentIds: _instruments.toList(),
    unitIds: _units.toList(),
    photos: <ProcessPhotoSlot, List<String>>{
      if (withPhotos)
        for (final MapEntry<ProcessPhotoSlot, List<PickedImage>> entry
            in _photos.entries)
          entry.key: entry.value.map((PickedImage i) => i.path).toList(),
    },
    isArrived: _arrived,
  );

  /// 上传所有照片，把本地路径换成后端 objectKey。
  Future<Map<ProcessPhotoSlot, List<String>>> _uploadAll() async {
    final Map<ProcessPhotoSlot, List<String>> keys =
        <ProcessPhotoSlot, List<String>>{};
    final int total = _photoCount;
    int done = 0;
    for (final ProcessPhotoSlot slot in ProcessPhotoSlot.values) {
      final List<PickedImage> images = _photos[slot] ?? const <PickedImage>[];
      if (images.isEmpty) continue;
      final List<String> uploaded = <String>[];
      for (final PickedImage image in images) {
        final int index = done;
        if (mounted) {
          setState(() => _busyLabel = '上传照片 ${index + 1}/$total');
        }
        uploaded.addAll(
          await ref
              .read(uploadServiceProvider)
              .uploadAll(<PickedImage>[image], kind: UploadKind.task),
        );
        done++;
      }
      keys[slot] = uploaded;
    }
    return keys;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ProcessDraft draft = _buildDraft();
    final String? error = draft.validate();
    if (error != null) {
      showToast(context, error);
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _busyLabel = _photoCount > 0 ? '上传照片 0/$_photoCount' : '提交中…';
    });

    try {
      final Map<ProcessPhotoSlot, List<String>> keys = await _uploadAll();
      if (!mounted) return;
      setState(() => _busyLabel = '提交中…');

      await ref.read(taskActionServiceProvider).submitProcess(
        ProcessDraft(
          taskId: widget.task.id,
          outcome: _outcome,
          reason: _reason.text,
          solution: _solution.text,
          description: _description.text,
          instrumentIds: _instruments.toList(),
          unitIds: _units.toList(),
          photos: keys,
          isArrived: _arrived,
        ),
      );

      if (!mounted) return;
      await ref
          .read(taskListProvider(TaskCategory.abnormal).notifier)
          .refresh();
      if (!mounted) return;
      showToast(context, '已提交「${_outcome.label}」，等待数据管理员确认');
      Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (mounted) showToast(context, '提交失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _saveDraft() async {
    if (_busy) return;
    if (_reason.text.trim().isEmpty && _solution.text.trim().isEmpty) {
      showToast(context, '至少填写故障原因或解决办法后再存草稿');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _busyLabel = '保存草稿…';
    });
    try {
      await ref
          .read(taskActionServiceProvider)
          .saveDraft(_buildDraft(withPhotos: false));
      if (!mounted) return;
      showToast(context, '草稿已保存');
      Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (mounted) showToast(context, error.userMessage);
    } catch (error) {
      if (mounted) showToast(context, '保存失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<ErrorUnitCatalog> catalog = ref.watch(
      taskErrorUnitsProvider('${widget.task.id}'),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('处理异常'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _saveDraft,
            child: const Text('存草稿'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.send, size: 18),
            label: Text(_busyLabel ?? '提交处理'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          _TaskSummaryCard(task: widget.task),
          const SizedBox(height: 12),
          _SectionCard(
            icon: LucideIcons.clipboardCheck,
            title: '处理结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<ProcessOutcome>(
                  segments: <ButtonSegment<ProcessOutcome>>[
                    for (final ProcessOutcome outcome in ProcessOutcome.values)
                      ButtonSegment<ProcessOutcome>(
                        value: outcome,
                        label: Text(outcome.label),
                      ),
                  ],
                  selected: <ProcessOutcome>{_outcome},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy
                      ? null
                      : (Set<ProcessOutcome> value) =>
                            setState(() => _outcome = value.first),
                ),
                const SizedBox(height: 10),
                Text(
                  _outcome.hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: LucideIcons.cpu,
            title: '异常定位',
            subtitle: '异常单元与异常仪器至少选一项',
            trailing: Text(
              '${_instruments.length + _units.length} 已选',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            child: catalog.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (Object error, StackTrace stack) => Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      error is AppException ? error.userMessage : '加载失败',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      taskErrorUnitsProvider('${widget.task.id}'),
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (ErrorUnitCatalog data) => data.isEmpty
                  ? Text(
                      '该站点未配置异常单元，可先上传照片并在解决办法中说明',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (data.instruments.isNotEmpty)
                          _ChipGroup(
                            label: '异常仪器',
                            options: data.instruments,
                            selected: _instruments,
                            onToggle: _toggleInstrument,
                          ),
                        if (data.controls.isNotEmpty)
                          _ChipGroup(
                            label: '控制单元',
                            options: data.controls,
                            selected: _units,
                            onToggle: _toggleUnit,
                          ),
                        if (data.others.isNotEmpty)
                          _ChipGroup(
                            label: '其他单元',
                            options: data.others,
                            selected: _units,
                            onToggle: _toggleUnit,
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: LucideIcons.search,
            title: '故障原因',
            subtitle: '必填，写清判断依据',
            child: TextField(
              controller: _reason,
              minLines: 3,
              maxLines: 5,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: '例如：蠕动泵泵管老化导致采水量不足',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: LucideIcons.wrench,
            title: '解决办法',
            subtitle: '必填，写清处理动作与结果',
            child: TextField(
              controller: _solution,
              minLines: 4,
              maxLines: 7,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: '例如：更换泵管并复测流量，连续观察三个周期数据正常',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: LucideIcons.camera,
            title: '现场照片',
            subtitle: _arrived
                ? '到站提交需上传全部 6 类照片'
                : '离站提交只需处理前与处理后',
            trailing: Switch.adaptive(
              value: _arrived,
              onChanged: _busy
                  ? null
                  : (bool value) => setState(() => _arrived = value),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _arrived ? LucideIcons.mapPinCheck : LucideIcons.mapPinOff,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _arrived ? '已到站' : '未到站（远程处理）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final ProcessPhotoSlot slot in ProcessPhotoSlot.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              slot.icon,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              slot.label,
                              style: theme.textTheme.labelLarge,
                            ),
                            if (slot.isRequired(arrived: _arrived)) ...<Widget>[
                              const SizedBox(width: 6),
                              Text(
                                '必传',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        ImagePickerGrid(
                          label: slot.label,
                          images: _photos[slot] ?? const <PickedImage>[],
                          maxCount: 3,
                          enabled: !_busy,
                          onChanged: (List<PickedImage> images) =>
                              setState(() => _photos[slot] = images),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: LucideIcons.messageSquareText,
            title: '处理备注',
            subtitle: '选填，补充说明会进入操作日志',
            child: TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: '例如：已同步厂家备件库存，下次巡检带回旧泵管',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleInstrument(int value) => setState(() {
    if (!_instruments.remove(value)) _instruments.add(value);
  });

  void _toggleUnit(int value) => setState(() {
    if (!_units.remove(value)) _units.add(value);
  });
}

class _TaskSummaryCard extends StatelessWidget {
  const _TaskSummaryCard({required this.task});

  final TaskDetail task;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                StatusPill(status: task.state.label),
                const SizedBox(width: 8),
                if (task.overtime) const StatusPill(status: '超时'),
                const Spacer(),
                Text(
                  '截止 ${formatBackendShort(task.deadline)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: task.overtime
                        ? AppColors.danger
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              task.stationName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              task.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 17, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final List<ErrorUnitOption> options;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ErrorUnitOption option in options)
                FilterChip(
                  label: Text(option.label),
                  selected: selected.contains(option.value),
                  onSelected: (_) => onToggle(option.value),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
