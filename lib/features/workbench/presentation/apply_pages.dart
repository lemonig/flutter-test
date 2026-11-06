import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/media/image_picker_service.dart';
import '../../../core/media/upload_service.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../home/data/repositories/address_repository.dart';
import '../../home/presentation/address_list_page.dart';
import '../../home/data/repositories/task_write_repository.dart';
import '../data/models/workbench_models.dart';
import '../data/repositories/report_repository.dart';
import '../providers/workbench_providers.dart';

/// 申请流程（M7-05 ~ M7-07）：选品 → 购物车 → 填单提交。
///
/// 试剂按站点拉目录并按仪器分组；配件 / 工具直接关键词搜索；
/// 临时费用没有选品环节，直接填单。四类共用 [ApplySubmitPage]，
/// 由 kind 决定表单字段（对齐 `ApplyController` 的四个提交口）。

// ───────────────────────────── 购物车 ─────────────────────────────

class CartLine {
  const CartLine({required this.item, required this.quantity});

  final ShopItem item;
  final int quantity;
}

/// 购物车按申请类型隔离：切换类型即清空，避免试剂串到配件单里。
class CartState {
  const CartState({this.kind, this.lines = const <int, CartLine>{}});

  final ApplyType? kind;
  final Map<int, CartLine> lines;

  int get totalQuantity =>
      lines.values.fold(0, (int sum, CartLine line) => sum + line.quantity);

  List<CartLine> get list => lines.values.toList(growable: false);
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void ensureKind(ApplyType kind) {
    if (state.kind != kind) {
      state = CartState(kind: kind);
    }
  }

  void add(ShopItem item) {
    final CartLine? existing = state.lines[item.id];
    state = _with(
      item,
      (existing?.quantity ?? 0) + 1,
    );
  }

  void setQuantity(ShopItem item, int quantity) {
    if (quantity <= 0) {
      state = CartState(
        kind: state.kind,
        lines: <int, CartLine>{...state.lines}..remove(item.id),
      );
      return;
    }
    state = _with(item, quantity);
  }

  void clear() => state = CartState(kind: state.kind);

  CartState _with(ShopItem item, int quantity) => CartState(
    kind: state.kind,
    lines: <int, CartLine>{
      ...state.lines,
      item.id: CartLine(item: item, quantity: quantity),
    },
  );
}

final NotifierProvider<CartNotifier, CartState> cartProvider =
    NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

// ───────────────────────────── 选品页 ─────────────────────────────

class ShopPickPage extends ConsumerStatefulWidget {
  const ShopPickPage({super.key, required this.kind});

  final ApplyType kind;

  @override
  ConsumerState<ShopPickPage> createState() => _ShopPickPageState();
}

class _ShopPickPageState extends ConsumerState<ShopPickPage> {
  final TextEditingController _search = TextEditingController();
  String _keyword = '';
  StationOption? _station;

  @override
  void initState() {
    super.initState();
    // 选品入口可能带着上一次申请的残留，进来先对齐类型。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartProvider.notifier).ensureKind(widget.kind);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _isReagent => widget.kind == ApplyType.reagent;

  Future<void> _pickStation() async {
    final List<StationOption> stations = await ref.read(
      managedStationsProvider.future,
    );
    if (!mounted) return;
    final StationOption? picked = await showModalBottomSheet<StationOption>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            for (final StationOption station in stations)
              ListTile(
                title: Text(station.name),
                subtitle: station.subtitle.isEmpty ? null : Text(station.subtitle),
                onTap: () => Navigator.of(sheetContext).pop(station),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _station = picked);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CartState cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget.kind.label)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_isReagent)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: ListTile(
                leading: const Icon(LucideIcons.mapPin, size: 20),
                title: Text(_station?.name ?? '选择站点'),
                subtitle: Text(
                  _station == null ? '试剂目录按站点备货' : '点击切换站点',
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 16),
                onTap: _pickStation,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (String value) => setState(() => _keyword = value),
                decoration: InputDecoration(
                  hintText: widget.kind == ApplyType.tool ? '搜索工具' : '搜索配件',
                  isDense: true,
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _isReagent
                ? _station == null
                      ? const EmptyState(
                          icon: LucideIcons.mapPin,
                          title: '先选择站点',
                          message: '试剂目录按站点当前配置的仪器备货',
                        )
                      : _ReagentGroups(
                          stationId: _station!.id,
                          keyword: _keyword,
                        )
                : _ShopList(kind: widget.kind, keyword: _keyword),
          ),
          if (cart.lines.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                child: Row(
                  children: <Widget>[
                    Text(
                      '已选 ${cart.totalQuantity} 件',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                ApplySubmitPage(kind: widget.kind),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                      child: const Text('去填申请单'),
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

/// 配件 / 工具目录。
class _ShopList extends ConsumerWidget {
  const _ShopList({required this.kind, required this.keyword});

  final ApplyType kind;
  final String keyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ShopItem>> items = ref.watch(
      shopItemsProvider(
        keyword.isEmpty ? '${kind.code}' : '${kind.code}:$keyword',
      ),
    );
    return items.when(
      loading: () => const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (Object error, StackTrace stack) => EmptyState(
        icon: LucideIcons.triangleAlert,
        title: '目录加载失败',
        message: error is AppException ? error.userMessage : '请稍后重试',
        actionLabel: '重试',
        onAction: () => ref.invalidate(
          shopItemsProvider(
            keyword.isEmpty ? '${kind.code}' : '${kind.code}:$keyword',
          ),
        ),
      ),
      data: (List<ShopItem> list) => list.isEmpty
          ? const EmptyState(
              icon: LucideIcons.packageSearch,
              title: '没有匹配的条目',
              message: '换个关键词试试',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) =>
                  _ShopItemTile(item: list[index]),
            ),
    );
  }
}

/// 试剂分组目录。
class _ReagentGroups extends ConsumerWidget {
  const _ReagentGroups({required this.stationId, required this.keyword});

  final int stationId;
  final String keyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ReagentGroup>> groups = ref.watch(
      reagentGroupsProvider(
        keyword.isEmpty ? '$stationId' : '$stationId:$keyword',
      ),
    );
    return groups.when(
      loading: () => const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (Object error, StackTrace stack) => EmptyState(
        icon: LucideIcons.triangleAlert,
        title: '试剂目录加载失败',
        message: error is AppException ? error.userMessage : '请稍后重试',
        actionLabel: '重试',
        onAction: () => ref.invalidate(
          reagentGroupsProvider(
            keyword.isEmpty ? '$stationId' : '$stationId:$keyword',
          ),
        ),
      ),
      data: (List<ReagentGroup> list) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: <Widget>[
          for (final ReagentGroup group in list) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Row(
                children: <Widget>[
                  const Icon(LucideIcons.flaskConical, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    group.instrumentName,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            for (final ShopItem item in group.items) _ShopItemTile(item: item),
          ],
        ],
      ),
    );
  }
}

class _ShopItemTile extends ConsumerWidget {
  const _ShopItemTile({required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final CartState cart = ref.watch(cartProvider);
    final int quantity = cart.lines[item.id]?.quantity ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      if (item.materialCode.isNotEmpty) item.materialCode,
                      if (item.version.isNotEmpty) item.version,
                      if (item.bottling.isNotEmpty) item.bottling,
                      if (item.unit.isNotEmpty) '单位：${item.unit}',
                      if (item.count.isNotEmpty) '库存 ${item.count}',
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              onPressed: quantity <= 0
                  ? null
                  : () => ref
                        .read(cartProvider.notifier)
                        .setQuantity(item, quantity - 1),
              icon: const Icon(LucideIcons.minus, size: 15),
              visualDensity: VisualDensity.compact,
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => ref.read(cartProvider.notifier).add(item),
              icon: const Icon(LucideIcons.plus, size: 15),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 申请单 ─────────────────────────────

class ApplySubmitPage extends ConsumerStatefulWidget {
  const ApplySubmitPage({super.key, required this.kind});

  final ApplyType kind;

  @override
  ConsumerState<ApplySubmitPage> createState() => _ApplySubmitPageState();
}

class _ApplySubmitPageState extends ConsumerState<ApplySubmitPage> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _money = TextEditingController();
  final TextEditingController _deliveryName = TextEditingController();
  final TextEditingController _deliveryPhone = TextEditingController();
  final TextEditingController _deliveryAddress = TextEditingController();

  TaskPerson? _approver;
  Option? _feeType;
  DateTime? _requireDate;
  final List<TaskPerson> _ccUsers = <TaskPerson>[];
  final List<PickedImage> _photos = <PickedImage>[];
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    _money.dispose();
    _deliveryName.dispose();
    _deliveryPhone.dispose();
    _deliveryAddress.dispose();
    super.dispose();
  }

  bool get _isFee => widget.kind == ApplyType.fee;

  bool get _needsApprover =>
      widget.kind != ApplyType.tool; // 工具申请由保管人审批，不选。

  bool get _needsDelivery =>
      widget.kind == ApplyType.reagent || widget.kind == ApplyType.part;

  String? _validate() {
    final CartState cart = ref.read(cartProvider);
    if (_isFee) {
      final double? amount = double.tryParse(_money.text.trim());
      if (_feeType == null) return '请选择费用类型';
      if (amount == null || amount <= 0) return '请输入正确的金额';
      if (amount > 100000000) return '数值异常！请勿填写过大金额！';
    } else {
      if (cart.lines.isEmpty) return '还没有选择条目';
      if (_needsApprover && _approver == null) return '请选择审批人';
    }
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
      _busyLabelValue = _photos.isEmpty ? '提交中…' : '上传照片…';
    });
    try {
      final List<String> keys = _photos.isEmpty
          ? const <String>[]
          : await ref
                .read(uploadServiceProvider)
                .uploadAll(_photos, kind: UploadKind.form);
      if (!mounted) return;
      setState(() => _busyLabelValue = '提交中…');

      final CartState cart = ref.read(cartProvider);
      await ref.read(applyActionServiceProvider).submit(
        ApplyDraft(
          type: widget.kind,
          description: _description.text,
          requireDate: _requireDate == null
              ? ''
              : _dateOf(_requireDate!),
          approveUserId: _approver?.id,
          feeType: _feeType?.value,
          money: _isFee ? double.tryParse(_money.text.trim()) : null,
          pictures: keys,
          stationId: null,
          items: cart.list
              .map(
                (CartLine line) => ApplyItem(
                  itemId: line.item.id,
                  itemName: line.item.name,
                  quantity: line.quantity,
                  materialCode: line.item.materialCode,
                  consistency: line.item.consistency,
                  bottling: line.item.bottling,
                  version: line.item.version,
                  instrument: line.item.instrument,
                  recipeCode: line.item.recipeCode,
                ),
              )
              .toList(),
          deliveryName: _deliveryName.text,
          deliveryPhone: _deliveryPhone.text,
          deliveryAddress: _deliveryAddress.text,
          applyCopy: _ccUsers
              .where((TaskPerson u) => u.id != null)
              .map((TaskPerson u) => u.id!)
              .toList(),
        ),
      );
      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      showToast(context, '${widget.kind.label}已提交，等待审批');
      // 选品页与提交页一起出栈，回到工作台。
      Navigator.of(context)..pop()..pop();
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '提交失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _busyLabelValue = '提交中…';

  Future<void> _pickApprover() async {
    final TaskPerson? picked = await showModalBottomSheet<TaskPerson>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const _ApproverSheet(),
    );
    if (picked != null && mounted) setState(() => _approver = picked);
  }

  /// 抄送人多选（`GET user/list/copy`，提交体 `apply_copy`，
  /// 对照 iOS SelectApprover 模块）。
  Future<void> _pickCcUsers() async {
    final List<TaskPerson>? picked = await showModalBottomSheet<List<TaskPerson>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CcUserSheet(selected: _ccUsers),
    );
    if (picked != null && mounted) setState(() => _ccUsers..clear()..addAll(picked));
  }

  /// 从地址簿选一条回填收货信息；没有地址时直接进选择页新增也可。
  Future<void> _pickFromAddressBook() async {
    final ExpressAddress? picked = await Navigator.of(context).push(
      MaterialPageRoute<ExpressAddress>(
        builder: (BuildContext context) => const AddressListPage(selectMode: true),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _deliveryName.text = picked.name;
      _deliveryPhone.text = picked.phone;
      _deliveryAddress.text = picked.address;
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _requireDate = picked);
  }

  Future<void> _pickOption(List<Option> options) async {
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
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _feeType = picked);
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
    final CartState cart = ref.watch(cartProvider);
    final AsyncValue<ReportMeta> meta = ref.watch(reportMetaProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text('填写${widget.kind.label}单')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (!_isFee) ...<Widget>[
              const SectionHeader(title: '申请明细'),
              Card(
                child: Column(
                  children: <Widget>[
                    for (final CartLine line in cart.list)
                      ListTile(
                        dense: true,
                        title: Text(line.item.name),
                        subtitle: line.item.materialCode.isEmpty
                            ? null
                            : Text(line.item.materialCode),
                        trailing: Text(
                          '× ${line.quantity}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SectionHeader(title: '审批'),
            Card(
              child: Column(
                children: <Widget>[
                  if (_needsApprover)
                    ListTile(
                      leading: const Icon(LucideIcons.userCheck, size: 20),
                      title: const Text('审批人'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _approver?.nickname ?? '选择审批人',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _approver == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.chevronRight, size: 16),
                        ],
                      ),
                      onTap: _pickApprover,
                    ),
                  if (!_needsApprover)
                    const ListTile(
                      leading: Icon(LucideIcons.userCheck, size: 20),
                      title: Text('审批人'),
                      subtitle: Text('由工具保管人自动审批'),
                    ),
                  ListTile(
                    leading: const Icon(LucideIcons.mailPlus, size: 20),
                    title: const Text('抄送人'),
                    subtitle: _ccUsers.isEmpty
                        ? const Text('选填，结果会同步给被抄送人')
                        : Text(_ccUsers.map((TaskPerson u) => u.nickname).join('、')),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: _pickCcUsers,
                  ),
                  if (!_isFee)
                    ListTile(
                      leading: const Icon(LucideIcons.calendarDays, size: 20),
                      title: const Text('需求日期'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _requireDate == null
                                ? '选填'
                                : _dateOf(_requireDate!),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.chevronRight, size: 16),
                        ],
                      ),
                      onTap: _pickDate,
                    ),
                ],
              ),
            ),
            if (_isFee) ...<Widget>[
              const SectionHeader(title: '费用信息'),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(LucideIcons.receiptText, size: 20),
                      title: const Text('费用类型'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _feeType?.label ?? '选择类型',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _feeType == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.chevronRight, size: 16),
                        ],
                      ),
                      onTap: () => _pickOption(
                        meta.value?.applyFeeTypes ?? const <Option>[],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: TextField(
                        controller: _money,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '金额（元）',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SectionHeader(title: '说明与附件'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: TextField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '申请说明',
                    hintText: '补充说明用途、数量等（选填）',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            if (_isFee)
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
                          Text('发票 / 凭证', style: theme.textTheme.bodyMedium),
                          const Spacer(),
                          IconButton(
                            onPressed: _pickPhotos,
                            icon: const Icon(LucideIcons.plus, size: 20),
                          ),
                        ],
                      ),
                      if (_photos.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            for (int i = 0; i < _photos.length; i++)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _photos[i].file,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_needsDelivery) ...<Widget>[
              SectionHeader(
                title: '收货信息',
                actionLabel: '从地址簿选择',
                onAction: _pickFromAddressBook,
              ),
              Card(
                child: Column(
                  children: <Widget>[
                    _TextFieldRow(label: '收货人', controller: _deliveryName, hint: '姓名'),
                    _TextFieldRow(label: '联系电话', controller: _deliveryPhone, hint: '手机号'),
                    _TextFieldRow(label: '收货地址', controller: _deliveryAddress, hint: '详细地址'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? Text(_busyLabelValue)
                  : const Text('提交申请'),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateOf(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _ApproverSheet extends ConsumerStatefulWidget {
  const _ApproverSheet();

  @override
  ConsumerState<_ApproverSheet> createState() => _ApproverSheetState();
}

class _ApproverSheetState extends ConsumerState<_ApproverSheet> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskPerson>> users = ref.watch(
      approversProvider(_keyword),
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('选择审批人', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              onChanged: (String value) => setState(() => _keyword = value),
              decoration: const InputDecoration(
                hintText: '搜索姓名',
                isDense: true,
                prefixIcon: Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                ),
              ),
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object e, StackTrace s) =>
                  const Center(child: Text('加载失败，请稍后重试')),
              data: (List<TaskPerson> list) => ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: <Widget>[
                  for (final TaskPerson user in list)
                    ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          user.nickname.isEmpty ? '?' : user.nickname[0],
                        ),
                      ),
                      title: Text(user.nickname),
                      onTap: () => Navigator.of(context).pop(user),
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

class _TextFieldRow extends StatelessWidget {
  const _TextFieldRow({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 抄送人多选弹层：搜索 + 已选计数，确认后整体回传。
class _CcUserSheet extends ConsumerStatefulWidget {
  const _CcUserSheet({required this.selected});

  final List<TaskPerson> selected;

  @override
  ConsumerState<_CcUserSheet> createState() => _CcUserSheetState();
}

class _CcUserSheetState extends ConsumerState<_CcUserSheet> {
  String _keyword = '';
  late final Set<int> _picked = <int>{
    for (final TaskPerson user in widget.selected)
      if (user.id != null) user.id!,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TaskPerson>> users = ref.watch(
      ccUsersProvider(_keyword),
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: <Widget>[
                Text('选择抄送人', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '已选 ${_picked.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.brand,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              onChanged: (String value) => setState(() => _keyword = value),
              decoration: const InputDecoration(
                hintText: '搜索姓名',
                isDense: true,
                prefixIcon: Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                ),
              ),
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object e, StackTrace s) =>
                  const Center(child: Text('加载失败，请稍后重试')),
              data: (List<TaskPerson> list) => ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: <Widget>[
                  for (final TaskPerson user in list)
                    CheckboxListTile(
                      value: user.id != null && _picked.contains(user.id),
                      onChanged: (bool? checked) => setState(() {
                        if (user.id == null) return;
                        checked == true
                            ? _picked.add(user.id!)
                            : _picked.remove(user.id);
                      }),
                      secondary: AppAvatar(label: user.nickname, size: 36),
                      title: Text(user.nickname),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: FilledButton(
                onPressed: () {
                  final List<TaskPerson> data =
                      users.asData?.value ?? const <TaskPerson>[];
                  Navigator.of(context).pop(
                    data
                        .where(
                          (TaskPerson user) =>
                              user.id != null && _picked.contains(user.id),
                        )
                        .toList(),
                  );
                },
                child: const Text('确定'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
