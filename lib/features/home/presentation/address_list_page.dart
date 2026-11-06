import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_response.dart';
import '../../../core/storage/app_storage.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/repositories/address_repository.dart';

/// 快递收货地址簿（C3 / M9-03）。
///
/// 地址用于试剂 / 配件申请的收货信息；「默认地址」后端无字段，
/// 记在本地（`AppStorage`），提交申请时可一键带出。
/// 返回值：选择模式（`select`）下 pop 回选中的地址，供申请页回填。
class AddressListPage extends ConsumerStatefulWidget {
  const AddressListPage({super.key, this.selectMode = false});

  final bool selectMode;

  @override
  ConsumerState<AddressListPage> createState() => _AddressListPageState();
}

class _AddressListPageState extends ConsumerState<AddressListPage> {
  List<ExpressAddress> _items = const <ExpressAddress>[];
  bool _loading = true;
  String? _error;
  int _defaultId = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadDefault();
  }

  Future<void> _loadDefault() async {
    final int id = await ref.read(appStorageProvider).readDefaultAddress();
    if (mounted) setState(() => _defaultId = id);
  }

  Future<void> _reload() async {
    try {
      final List<ExpressAddress> items =
          await ref.read(addressRepositoryProvider).fetchAddresses();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _error = null;
        });
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.userMessage;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setDefault(ExpressAddress address) async {
    await ref.read(appStorageProvider).saveDefaultAddress(address.id);
    if (!mounted) return;
    setState(() => _defaultId = address.id);
    showToast(context, '已设为默认地址');
  }

  Future<void> _remove(ExpressAddress address) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除这个地址？'),
        content: Text('${address.name}：${address.address}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(addressRepositoryProvider).remove(address.id);
      if (!mounted) return;
      showToast(context, '已删除');
      _reload();
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    }
  }

  /// 新增 / 编辑共用底部面板；提交成功后刷新列表。
  Future<void> _edit([ExpressAddress? initial]) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _AddressForm(initial: initial),
      ),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget.selectMode ? '选择收货地址' : '收货地址')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('新增地址'),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _error != null
          ? EmptyState(
              icon: LucideIcons.triangleAlert,
              title: '加载失败',
              message: _error!,
              actionLabel: '重试',
              onAction: () {
                setState(() => _loading = true);
                _reload();
              },
            )
          : _items.isEmpty
          ? const EmptyState(
              icon: LucideIcons.mapPinPlus,
              title: '还没有收货地址',
              message: '新增地址后，申请试剂 / 配件时可以直接选用',
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final ExpressAddress address = _items[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              address.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (address.tag.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                address.tag,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(address.address),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (String action) {
                          if (action == 'edit') _edit(address);
                          if (action == 'default') _setDefault(address);
                          if (action == 'delete') _remove(address);
                        },
                        itemBuilder: (BuildContext menuContext) =>
                            <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('编辑'),
                              ),
                              PopupMenuItem<String>(
                                value: 'default',
                                enabled: _defaultId != address.id,
                                child: const Text('设为默认'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'delete',
                                child: Text('删除'),
                              ),
                            ],
                      ),
                      onTap: widget.selectMode
                          ? () => Navigator.of(context).pop(address)
                          : () => _edit(address),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// 新增 / 编辑表单。pop(true) 表示已保存，由列表页刷新。
class _AddressForm extends ConsumerStatefulWidget {
  const _AddressForm({this.initial});

  final ExpressAddress? initial;

  @override
  ConsumerState<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<_AddressForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.initial?.phone ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.address ?? '',
  );
  late final TextEditingController _tag = TextEditingController(
    text: widget.initial?.tag ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      showToast(context, '请填写收货人');
      return;
    }
    if (_address.text.trim().isEmpty) {
      showToast(context, '请填写详细地址');
      return;
    }
    final ExpressAddress draft = ExpressAddress(
      id: widget.initial?.id ?? 0,
      name: _name.text,
      phone: _phone.text,
      address: _address.text,
      tag: _tag.text,
    );
    setState(() => _saving = true);
    try {
      final AddressRepository repo = ref.read(addressRepositoryProvider);
      if (widget.initial == null) {
        await repo.add(draft);
      } else {
        await repo.update(draft);
      }
      if (!mounted) return;
      showToast(context, widget.initial == null ? '已新增' : '已保存');
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.initial == null ? '新增地址' : '编辑地址',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '收货人',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '联系电话',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '详细地址',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tag,
              decoration: const InputDecoration(
                labelText: '标签（选填，如：公司 / 站房）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
