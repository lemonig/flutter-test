import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/media/upload_service.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/image_picker_grid.dart';
import '../data/models/task_item.dart';
import '../data/repositories/task_write_repository.dart';
import '../providers/home_providers.dart';

/// 新建异常（M3-01）。
///
/// 字段与后端 `TaskCreateValidator` 严格对齐：现象、站点、发生时间、截止时间、
/// 提醒项五项必填，且截止时间必须晚于当前时间。
///
/// 站点列表取自 `station/datamanager`（我是数据管理员的站点），
/// 这是后端 `station.dataManagerId == creatorId` 校验下唯一能创建成功的范围。
class CreateTaskPage extends ConsumerStatefulWidget {
  const CreateTaskPage({super.key});

  @override
  ConsumerState<CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends ConsumerState<CreateTaskPage> {
  final TextEditingController _content = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  StationOption? _station;
  DateTime _happenAt = DateTime.now();
  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  int _remind = 0;
  List<PickedImage> _images = <PickedImage>[];

  bool _submitting = false;
  String? _submitLabel;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickStation(List<StationOption> stations) async {
    final StationOption? picked = await showModalBottomSheet<StationOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          _StationPickerSheet(stations: stations, selected: _station),
    );
    if (picked != null && mounted) {
      setState(() => _station = picked);
    }
  }

  Future<DateTime?> _pickDateTime(
    DateTime initial, {
    DateTime? first,
    DateTime? last,
  }) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2020),
      lastDate: last ?? DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickHappenAt() async {
    final DateTime? value = await _pickDateTime(
      _happenAt,
      last: DateTime.now().add(const Duration(days: 1)),
    );
    if (value != null && mounted) setState(() => _happenAt = value);
  }

  Future<void> _pickDeadline() async {
    final DateTime? value = await _pickDateTime(
      _deadline,
      first: DateTime.now(),
    );
    if (value != null && mounted) setState(() => _deadline = value);
  }

  String? _validate(List<StationOption> stations) {
    if (stations.isEmpty) return '当前账号不是任何站点的数据管理员，无法新建异常';
    if (_station == null) return '请选择发生站点';
    if (_content.text.trim().isEmpty) return '请填写异常现象描述';
    if (!_deadline.isAfter(DateTime.now())) return '截止时间必须晚于当前时间';
    return null;
  }

  Future<void> _submit(List<StationOption> stations) async {
    final String? error = _validate(stations);
    if (error != null) {
      showToast(context, error);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitLabel = _images.isEmpty ? '提交中…' : '上传图片 0/${_images.length}';
    });

    try {
      List<String> keys = const <String>[];
      if (_images.isNotEmpty) {
        keys = await ref
            .read(uploadServiceProvider)
            .uploadAll(
              _images,
              kind: UploadKind.task,
              onProgress: (int index, int total, double progress) {
                if (!mounted) return;
                setState(() {
                  _submitLabel = '上传图片 ${index + 1}/$total';
                });
              },
            );
      }

      if (!mounted) return;
      setState(() => _submitLabel = '提交中…');

      await ref
          .read(taskWriteRepositoryProvider)
          .createTask(
            CreateTaskDraft(
              stationId: _station!.id,
              content: _content.text,
              happenAt: _happenAt,
              deadline: _deadline,
              remind: _remind,
              pictureKeys: keys,
            ),
          );

      if (!mounted) return;
      await ref
          .read(taskListProvider(TaskCategory.abnormal).notifier)
          .refresh();
      if (!mounted) return;
      showToast(context, '异常已提交');
      Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      showToast(context, error.userMessage);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '提交失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<StationOption>> stations = ref.watch(
      managedStationsProvider,
    );
    final List<StationOption> list =
        stations.value ?? const <StationOption>[];

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('新建异常'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: <Widget>[
                    if (stations.isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (stations.hasError)
                      _NoticeCard(
                        tone: Tone.danger,
                        icon: LucideIcons.cloudOff,
                        title: '站点加载失败',
                        message: '${stations.error}',
                        actionLabel: '重试',
                        onAction: () =>
                            ref.invalidate(managedStationsProvider),
                      )
                    else if (list.isEmpty)
                      _NoticeCard(
                        tone: Tone.warning,
                        icon: LucideIcons.shieldAlert,
                        title: '暂无可创建异常的站点',
                        message:
                            '后端要求「站点数据管理员」才能为该站点建单。'
                            '当前账号名下没有站点，请联系管理员分配后再试。',
                        actionLabel: '刷新',
                        onAction: () =>
                            ref.invalidate(managedStationsProvider),
                      ),
                    _SectionCard(
                      children: <Widget>[
                        _FieldRow(
                          icon: LucideIcons.mapPin,
                          label: '发生站点',
                          value: _station?.name,
                          placeholder: '请选择',
                          enabled: list.isNotEmpty,
                          onTap: () => _pickStation(list),
                        ),
                        const _FieldDivider(),
                        _FieldRow(
                          icon: LucideIcons.clock,
                          label: '异常发生时间',
                          value: _formatDateTime(_happenAt),
                          onTap: _pickHappenAt,
                        ),
                        const _FieldDivider(),
                        _FieldRow(
                          icon: LucideIcons.calendarClock,
                          label: '截止时间',
                          value: _formatDateTime(_deadline),
                          onTap: _pickDeadline,
                        ),
                        const _FieldDivider(),
                        _FieldRow(
                          icon: LucideIcons.bellRing,
                          label: '提醒',
                          value: RemindOption.labelOf(_remind),
                          onTap: () => _pickRemind(theme),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(
                                    LucideIcons.penLine,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('异常现象', style: theme.textTheme.labelLarge),
                                  const SizedBox(width: 4),
                                  Text(
                                    '*',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _content,
                                minLines: 4,
                                maxLines: 8,
                                maxLength: 500,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  hintText: '描述站点、仪器、数据异常现象……',
                                  counterText: '',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: ImagePickerGrid(
                            images: _images,
                            enabled: !_submitting,
                            hint: '支持拍照或相册，最多 9 张；上传后自动压缩到 1600px',
                            onChanged: (List<PickedImage> next) =>
                                setState(() => _images = next),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _submitting || list.isEmpty
                      ? null
                      : () => _submit(list),
                  child: _submitting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(_submitLabel ?? '提交中…'),
                          ],
                        )
                      : const Text('提交异常'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRemind(ThemeData theme) async {
    final int? value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('提醒时间', style: theme.textTheme.titleMedium),
            ),
            for (final RemindOption option in RemindOption.all)
              ListTile(
                title: Text(option.label),
                trailing: option.value == _remind
                    ? Icon(
                        LucideIcons.check,
                        size: 18,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => _remind = value);
  }

  static String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 46,
    endIndent: 14,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
  );
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    this.value,
    this.placeholder,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool empty = value == null || value!.isEmpty;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                empty ? (placeholder ?? '请选择') : value!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: empty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                  fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Tone tone;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: tone.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tone.onBackground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tone.onBackground,
                    height: 1.5,
                  ),
                ),
                if (actionLabel != null) ...<Widget>[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: tone.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationPickerSheet extends StatefulWidget {
  const _StationPickerSheet({required this.stations, this.selected});

  final List<StationOption> stations;
  final StationOption? selected;

  @override
  State<_StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<_StationPickerSheet> {
  final TextEditingController _keyword = TextEditingController();
  late List<StationOption> _filtered = widget.stations;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    final String q = value.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.stations
          : widget.stations
                .where(
                  (StationOption s) =>
                      s.name.toLowerCase().contains(q) ||
                      (s.subtitle.toLowerCase().contains(q)),
                )
                .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('选择发生站点', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SearchBar(
              controller: _keyword,
              hintText: '搜索站点名称',
              leading: Icon(
                LucideIcons.search,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onChanged: _onSearch,
              elevation: const WidgetStatePropertyAll<double>(0),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的站点',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 4),
                      itemBuilder: (BuildContext context, int index) {
                        final StationOption station = _filtered[index];
                        final bool active = station.id == widget.selected?.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          title: Text(station.name),
                          subtitle: station.subtitle.isEmpty
                              ? null
                              : Text(station.subtitle),
                          trailing: active
                              ? Icon(
                                  LucideIcons.check,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(station),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
