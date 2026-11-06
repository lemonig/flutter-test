import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/media/upload_service.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/photo_viewer_page.dart';
import '../../../shared/widgets/section_header.dart';
import '../../home/data/repositories/task_write_repository.dart';
import '../data/models/workbench_models.dart';
import '../data/repositories/report_repository.dart';
import '../providers/workbench_providers.dart';

/// 上报三件套（M7-02 ~ M7-04）：里程 / 车辆费用 / 水电网费。
///
/// 三个页面共用一个文件：列表、表单与详情的字段高度重叠，
/// 差异只在「车辆 vs 站点」和金额语义，kind 参数决定展示分支。
/// 表单校验在客户端先拦一遍（对齐 ReportCarMileageValidator 等），
/// 但服务端仍是权威 —— 客户端只负责给出可读的失败原因。

// ───────────────────────────── 列表 ─────────────────────────────

class ReportListPage extends ConsumerWidget {
  const ReportListPage({super.key, required this.kind});

  final ReportKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<ReportPageState> page = ref.watch(reportPageProvider(kind));

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(kind.label),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => ReportFormPage(kind: kind),
                ),
              );
              ref.invalidate(reportPageProvider(kind));
            },
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('新建'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: page.when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.triangleAlert,
          title: '加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重试',
          onAction: () => ref.invalidate(reportPageProvider(kind)),
        ),
        data: (ReportPageState state) {
          if (state.items.isEmpty) {
            return EmptyState(
              icon: LucideIcons.filePlus2,
              title: '还没有${kind.label}',
              message: '点右上角「新建」提交第一笔记录',
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification.metrics.pixels >
                  notification.metrics.maxScrollExtent - 200) {
                ref.read(reportPageProvider(kind).notifier).loadMore();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(reportPageProvider(kind).notifier).refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: state.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) =>
                    _ReportCard(record: state.items[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.record});

  final ReportRecord record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String headline = switch (record.kind) {
      ReportKind.mileage =>
        '${record.mileage?.toStringAsFixed(0) ?? '-'} km · 油费过路 ¥${record.cost?.toStringAsFixed(1) ?? '-'}',
      ReportKind.carFee =>
        '¥${record.money?.toStringAsFixed(2) ?? '-'}${record.feeTypeStr.isEmpty ? '' : ' · ${record.feeTypeStr}'}',
      ReportKind.stationFee =>
        '¥${record.money?.toStringAsFixed(2) ?? '-'}${record.feeTypeStr.isEmpty ? '' : ' · ${record.feeTypeStr}'}',
    };
    final String subject = record.kind == ReportKind.stationFee
        ? record.station
        : record.carNum;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                ReportDetailPage(kind: record.kind, id: record.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      subject.isEmpty ? record.reportNumber : subject,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    formatBackendFriendly(record.gmtCreate, empty: ''),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      headline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (record.checkStateStr.isNotEmpty)
                    Text(
                      record.checkStateStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (record.pictures.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(
                      LucideIcons.image,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${record.pictures.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── 表单 ─────────────────────────────

class ReportFormPage extends ConsumerStatefulWidget {
  const ReportFormPage({super.key, required this.kind});

  final ReportKind kind;

  @override
  ConsumerState<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends ConsumerState<ReportFormPage> {
  final TextEditingController _mileage = TextEditingController();
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _money = TextEditingController();
  final TextEditingController _description = TextEditingController();

  Car? _car;
  StationOption? _station;
  Option? _feeType;
  Option? _contract;
  Option? _stage;
  DateTime? _payDate;
  DateTime? _nextPayDate;
  double? _previousMileage;
  final List<PickedImage> _photos = <PickedImage>[];
  bool _busy = false;
  String _busyLabel = '';

  @override
  void dispose() {
    _mileage.dispose();
    _cost.dispose();
    _money.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _isMileage => widget.kind == ReportKind.mileage;

  String? _validate() {
    if (_isMileage) {
      if (_car == null) return '请选择车辆';
      final double? value = double.tryParse(_mileage.text.trim());
      if (value == null || value <= 0) return '请填写正确的里程表读数';
      if (_previousMileage != null && value <= _previousMileage!) {
        return '里程读数必须大于上次（$_previousMileage km）';
      }
    } else {
      if (widget.kind == ReportKind.stationFee && _station == null) {
        return '请选择站点';
      }
      if (widget.kind == ReportKind.carFee && _car == null) return '请选择车辆';
      final double? amount = double.tryParse(_money.text.trim());
      if (amount == null || amount <= 0) return '请输入正确的金额';
      if (amount > 100000000) return '数值异常！请勿填写过大金额！';
      if (widget.kind == ReportKind.stationFee && _payDate == null) {
        return '请选择缴费日期';
      }
    }
    // 2026-11-06 实测：三类上报服务端都强制 contract_id（用于核算归属）。
    if (_contract == null) return '请选择合同';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String? error = _validate();
    if (error != null) {
      showToast(context, error);
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _busyLabel = _photos.isNotEmpty ? '上传照片…' : '提交中…';
    });
    try {
      final List<String> keys = _photos.isEmpty
          ? const <String>[]
          : await ref
                .read(uploadServiceProvider)
                .uploadAll(_photos, kind: UploadKind.form);
      if (!mounted) return;
      setState(() => _busyLabel = '提交中…');

      await ref
          .read(reportRepositoryProvider)
          .submit(_buildDraft(pictureKeys: keys));
      if (!mounted) return;
      showToast(context, '${widget.kind.label}已提交');
      Navigator.of(context).pop();
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '提交失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ReportDraft _buildDraft({required List<String> pictureKeys}) =>
      ReportDraft(
        kind: widget.kind,
        carId: _car?.id,
        carNum: _car?.carNum ?? '',
        mileage: _isMileage ? double.tryParse(_mileage.text.trim()) : null,
        cost: _isMileage ? double.tryParse(_cost.text.trim()) : null,
        feeType: _isMileage ? null : _feeType?.value,
        money: _isMileage ? null : double.tryParse(_money.text.trim()),
        stationId: _station?.id,
        station: _station?.name ?? '',
        payDate: _payDate == null
            ? ''
            : '${_payDate!.year}-${_payDate!.month.toString().padLeft(2, '0')}-${_payDate!.day.toString().padLeft(2, '0')}',
        nextPayDate: _nextPayDate == null
            ? ''
            : '${_nextPayDate!.year}-${_nextPayDate!.month.toString().padLeft(2, '0')}-${_nextPayDate!.day.toString().padLeft(2, '0')}',
        contractId: _contract?.value,
        stage: _stage?.value,
        description: _description.text,
        pictures: pictureKeys,
      );

  Future<void> _pickCar() async {
    final Car? picked = await showModalBottomSheet<Car>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CarPickerSheet(keyword: ''),
    );
    if (picked == null) return;
    setState(() => _car = picked);
    if (_isMileage) {
      final double previous = await ref
          .read(reportRepositoryProvider)
          .fetchPreviousMileage(picked.id);
      if (mounted) setState(() => _previousMileage = previous);
    }
  }

  Future<void> _pickStation() async {
    final List<StationOption> stations = await ref.read(
      managedStationsProvider.future,
    );
    if (!mounted) return;
    final StationOption? picked = await showModalBottomSheet<StationOption>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _StationPickerSheet(
        stations: stations,
      ),
    );
    if (picked != null) setState(() => _station = picked);
  }

  Future<void> _pickOption(List<Option> options, void Function(Option) onPick) async {
    final Option? picked = await showModalBottomSheet<Option>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            for (final Option option in options)
              ListTile(
                title: Text(option.label),
                subtitle: option.name.isEmpty ? null : Text(option.name),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }

  Future<void> _pickDate({required bool isNext}) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() => isNext ? _nextPayDate = picked : _payDate = picked);
  }

  Future<void> _pickPhotos() async {
    final List<PickedImage> picked = await ref
        .read(imagePickerServiceProvider)
        .pickFromGallery(limit: UploadService.maxImages - _photos.length);
    if (picked.isNotEmpty) setState(() => _photos.addAll(picked));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<ReportMeta> meta = ref.watch(reportMetaProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text('新建${widget.kind.label}')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            const SectionHeader(title: '基础信息'),
            Card(
              child: Column(
                children: <Widget>[
                  if (_isMileage || widget.kind == ReportKind.carFee)
                    _PickerTile(
                      icon: LucideIcons.car,
                      title: '车辆',
                      value: _car?.carNum ?? '',
                      hint: '选择车牌',
                      onTap: _pickCar,
                    ),
                  if (widget.kind == ReportKind.stationFee)
                    _PickerTile(
                      icon: LucideIcons.mapPin,
                      title: '站点',
                      value: _station?.name ?? '',
                      hint: '选择我管理的站点',
                      onTap: _pickStation,
                    ),
                  if (!_isMileage)
                    _PickerTile(
                      icon: LucideIcons.receiptText,
                      title: '费用类型',
                      value: _feeType?.label ?? '',
                      hint: '选择费用类型',
                      onTap: () => _pickOption(
                        widget.kind == ReportKind.carFee
                            ? meta.value?.carFeeTypes ?? const <Option>[]
                            : meta.value?.stationFeeTypes ?? const <Option>[],
                        (Option option) => setState(() => _feeType = option),
                      ),
                    ),
                  if (_isMileage)
                    _InputTile(
                      icon: LucideIcons.gauge,
                      title: '里程表读数',
                      hint: _previousMileage != null
                          ? '上次读数 ${_previousMileage!.toStringAsFixed(0)} km'
                          : 'km',
                      controller: _mileage,
                      keyboardType: TextInputType.number,
                    ),
                  if (_isMileage)
                    _InputTile(
                      icon: LucideIcons.fuel,
                      title: '油费 / 过路费',
                      hint: '元（选填）',
                      controller: _cost,
                      keyboardType: TextInputType.number,
                    ),
                  if (!_isMileage)
                    _InputTile(
                      icon: LucideIcons.banknote,
                      title: '金额',
                      hint: '元',
                      controller: _money,
                      keyboardType: TextInputType.number,
                    ),
                  if (widget.kind == ReportKind.stationFee)
                    _PickerTile(
                      icon: LucideIcons.calendarDays,
                      title: '缴费日期',
                      value: _payDate == null ? '' : _dateLabel(_payDate!),
                      hint: '选择日期',
                      onTap: () => _pickDate(isNext: false),
                    ),
                  if (widget.kind == ReportKind.stationFee)
                    _PickerTile(
                      icon: LucideIcons.calendarClock,
                      title: '下次缴费',
                      value: _nextPayDate == null ? '' : _dateLabel(_nextPayDate!),
                      hint: '选填',
                      onTap: () => _pickDate(isNext: true),
                    ),
                ],
              ),
            ),
            const SectionHeader(title: '项目归属'),
            Card(
              child: Column(
                children: <Widget>[
                  _PickerTile(
                    icon: LucideIcons.fileSignature,
                    title: '合同',
                    value: _contract?.label ?? '',
                    hint: '选择合同（必填）',
                    onTap: () => _pickOption(
                      meta.value?.contracts ?? const <Option>[],
                      (Option option) => setState(() => _contract = option),
                    ),
                  ),
                  _PickerTile(
                    icon: LucideIcons.workflow,
                    title: '工程阶段',
                    value: _stage?.label ?? '',
                    hint: '选择阶段（选填）',
                    onTap: () => _pickOption(
                      meta.value?.stages ?? const <Option>[],
                      (Option option) => setState(() => _stage = option),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader(title: '备注与凭证'),
            Card(
              child: Column(
                children: <Widget>[
                  _InputTile(
                    icon: LucideIcons.penLine,
                    title: '备注',
                    hint: '补充说明（选填）',
                    controller: _description,
                    maxLines: 3,
                  ),
                  _PhotoTile(
                    photos: _photos,
                    onAdd: _pickPhotos,
                    onRemove: (int index) =>
                        setState(() => _photos.removeAt(index)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
                  : const Text('提交上报'),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

// ───────────────────────────── 详情 ─────────────────────────────

class ReportDetailPage extends ConsumerWidget {
  const ReportDetailPage({super.key, required this.kind, required this.id});

  final ReportKind kind;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<ReportRecord> detail = ref.watch(
      reportDetailFutureProvider((kind, id)),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text('${kind.label}详情')),
      body: detail.when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (Object error, StackTrace stack) => EmptyState(
          icon: LucideIcons.triangleAlert,
          title: '加载失败',
          message: error is AppException ? error.userMessage : '请稍后重试',
          actionLabel: '重试',
          onAction: () => ref.invalidate(reportDetailFutureProvider((kind, id))),
        ),
        data: (ReportRecord record) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      record.reportNumber.isEmpty ? '#${record.id}' : record.reportNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatBackendFriendly(record.gmtCreate, empty: ''),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader(title: '上报内容'),
            Card(
              child: Column(
                children: <Widget>[
                  if (record.kind == ReportKind.stationFee)
                    _DetailRow(label: '站点', value: record.station),
                  if (record.kind != ReportKind.stationFee)
                    _DetailRow(label: '车辆', value: record.carNum),
                  if (record.mileage != null)
                    _DetailRow(
                      label: '里程读数',
                      value: '${record.mileage!.toStringAsFixed(0)} km',
                    ),
                  if (record.cost != null)
                    _DetailRow(
                      label: '油费 / 过路费',
                      value: '¥${record.cost!.toStringAsFixed(2)}',
                    ),
                  if (record.money != null)
                    _DetailRow(
                      label: '金额',
                      value: '¥${record.money!.toStringAsFixed(2)}',
                    ),
                  if (record.feeTypeStr.isNotEmpty)
                    _DetailRow(label: '费用类型', value: record.feeTypeStr),
                  if (record.kind == ReportKind.stationFee &&
                      record.payDate.isNotEmpty)
                    _DetailRow(
                      label: '缴费日期',
                      value: formatBackendFriendly(record.payDate, empty: ''),
                    ),
                  if (record.kind == ReportKind.stationFee &&
                      record.nextPayDate.isNotEmpty)
                    _DetailRow(
                      label: '下次缴费',
                      value: formatBackendFriendly(record.nextPayDate, empty: ''),
                    ),
                  if (record.contractNum.isNotEmpty)
                    _DetailRow(label: '合同', value: record.contractNum),
                  if (record.stageStr.isNotEmpty)
                    _DetailRow(label: '工程阶段', value: record.stageStr),
                  if (record.checkStateStr.isNotEmpty)
                    _DetailRow(label: '审核状态', value: record.checkStateStr),
                  if (record.description.isNotEmpty)
                    _DetailRow(label: '备注', value: record.description),
                ],
              ),
            ),
            if (record.pictures.isNotEmpty) ...<Widget>[
              const SectionHeader(title: '凭证照片'),
              _PhotoGrid(urls: record.pictures),
            ],
          ],
        ),
      ),
    );
  }
}

/// 详情不在分页缓存里，单独按 id 拉取（Mock 下同一数据源，字段一致）。
final reportDetailFutureProvider = FutureProvider.family<ReportRecord,
    (ReportKind, int)>((Ref ref, (ReportKind, int) args) {
  return ref.watch(reportRepositoryProvider).fetchReportDetail(args.$1, args.$2);
});

// ───────────────────────────── 共享组件 ─────────────────────────────

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      shape: const Border(),
      leading: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      title: Text(title, style: theme.textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value.isEmpty ? hint : value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevronRight, size: 16),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _InputTile extends StatelessWidget {
  const _InputTile({
    required this.icon,
    required this.title,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
  });

  final IconData icon;
  final String title;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          SizedBox(
            width: 92,
            child: Text(title, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PickedImage> photos;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                LucideIcons.imagePlus,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Text('凭证照片', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${photos.length}/${UploadService.maxImages}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                onPressed: photos.length >= UploadService.maxImages ? null : onAdd,
                icon: const Icon(LucideIcons.plus, size: 20),
                tooltip: '从相册选择',
              ),
            ],
          ),
          if (photos.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int i = 0; i < photos.length; i++)
                  Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          photos[i].file,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => onRemove(i),
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
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < urls.length; i++)
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => PhotoViewerPage(
                      images: urls,
                      initialIndex: i,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    urls[i],
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 96,
                      height: 96,
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: const Icon(LucideIcons.imageOff, size: 20),
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

// ───────────────────────────── 选择弹层 ─────────────────────────────

class _CarPickerSheet extends ConsumerStatefulWidget {
  const _CarPickerSheet({required this.keyword});

  final String keyword;

  @override
  ConsumerState<_CarPickerSheet> createState() => _CarPickerSheetState();
}

class _CarPickerSheetState extends ConsumerState<_CarPickerSheet> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Car>> cars = ref.watch(carOptionsProvider(_keyword));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (String value) => setState(() => _keyword = value),
              decoration: const InputDecoration(
                hintText: '搜索车牌',
                isDense: true,
                prefixIcon: Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                ),
              ),
            ),
          ),
          Expanded(
            child: cars.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object e, StackTrace s) =>
                  const Center(child: Text('车辆加载失败')),
              data: (List<Car> list) => ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: <Widget>[
                  for (final Car car in list)
                    ListTile(
                      title: Text(car.carNum),
                      subtitle: Text(
                        <String>[car.region, car.city, car.company]
                            .where((String s) => s.isNotEmpty)
                            .join(' · '),
                      ),
                      onTap: () => Navigator.of(context).pop(car),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationPickerSheet extends StatelessWidget {
  const _StationPickerSheet({required this.stations});

  final List<StationOption> stations;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: <Widget>[
          for (final StationOption station in stations)
            ListTile(
              title: Text(station.name),
              subtitle: station.subtitle.isEmpty ? null : Text(station.subtitle),
              onTap: () => Navigator.of(context).pop(station),
            ),
        ],
      ),
    );
  }
}
