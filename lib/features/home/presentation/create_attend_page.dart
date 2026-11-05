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
import '../../../core/network/server_time.dart';
import '../../../shared/utils/toast.dart';
import '../../../shared/widgets/image_picker_grid.dart';
import '../data/models/attend_meta.dart';
import '../data/models/task_item.dart';
import '../data/repositories/attend_write_repository.dart';
import '../providers/home_providers.dart';

/// 新建签到（M5-01 / M5-02）。
///
/// 对应原工程 `ReleaseSignInLocationController` + `ReleaseSignInController`：
/// 原工程先在地图页确认定位，再进表单填「站点 / 位置 / 备注 / 照片」。
/// 地图可视化要等 M0-07（D3 已定高德，需申请 Key），这里先用系统定位拿到
/// 坐标，再用 `attend/meta` 换附近站点，把「定位 → 站点匹配 → 提交」跑通。
///
/// 后端硬约束（`AttendCreateValidator`）：
/// - 经纬度必填；
/// - 传了站点就必须在站点附近（20 公里内），否则报「当前位置未处在签到站点」；
/// - 地址为空时服务端兜底成「未获取到地址」，所以这里允许用户手填。
class CreateAttendPage extends ConsumerStatefulWidget {
  const CreateAttendPage({super.key});

  @override
  ConsumerState<CreateAttendPage> createState() => _CreateAttendPageState();
}

class _CreateAttendPageState extends ConsumerState<CreateAttendPage> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _locating = true;
  GeoPoint? _point;
  LocationFailure? _failure;

  AttendMeta _meta = AttendMeta.empty;
  bool _metaLoading = false;
  String? _metaError;

  StationDistance? _station;

  /// 用户是否已就「站点」做出选择 —— 选了站点或显式选了「不选择站点」。
  /// 原工程也是选完才亮提交按钮，避免漏关联站点。
  bool _stationDecided = false;

  List<PickedImage> _images = <PickedImage>[];
  bool _submitting = false;
  String? _submitLabel;

  @override
  void initState() {
    super.initState();
    // 首帧之后再弹定位权限，initState 里弹窗会被打断。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locate();
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _failure = null;
    });

    // 演示包不依赖真实 GPS，固定用调试坐标跑通流程。
    if (ref.read(useMockProvider)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() {
        _point = LocationService.debugPoint;
        _locating = false;
      });
      await _loadMeta();
      return;
    }

    final LocationResult result = await ref
        .read(locationServiceProvider)
        .locate();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _point = result.point;
      _failure = result.failure;
    });
    if (result.isSuccess) await _loadMeta();
  }

  /// 调试坐标兜底：与原工程 iOS DEBUG 分支写死坐标同理，
  /// 模拟器没有 GPS 时也要能验证完整签到流程。
  Future<void> _useDebugPoint() async {
    setState(() {
      _point = LocationService.debugPoint;
      _failure = null;
      _locating = false;
    });
    await _loadMeta();
  }

  Future<void> _loadMeta() async {
    final GeoPoint? point = _point;
    if (point == null) return;

    setState(() {
      _metaLoading = true;
      _metaError = null;
    });
    try {
      final AttendMeta meta = await ref
          .read(attendWriteRepositoryProvider)
          .fetchMeta(longitude: point.longitude, latitude: point.latitude);
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _metaLoading = false;
        // 重新定位坐标变了，之前选的站点可能已不在附近，
        // 留着会让后端报「当前位置未处在签到站点」，直接失效。
        final bool stillNearby = _station == null ||
            meta.stationsNearBy.any(
              (StationDistance s) => s.id == _station!.id,
            );
        if (!stillNearby) {
          _station = null;
          _stationDecided = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _metaLoading = false;
        _metaError = error is AppException ? error.userMessage : '$error';
      });
    }
  }

  Future<void> _pickStation() async {
    if (_meta.stationsNearBy.isEmpty) {
      await _loadMeta();
      if (!mounted) return;
      if (_meta.stationsNearBy.isEmpty) {
        showToast(context, '当前位置附近没有站点，可先重试定位');
        return;
      }
    }

    final _StationChoice? choice = await showModalBottomSheet<_StationChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _StationSheet(
        stations: _meta.stationsNearBy,
        selectedId: _station?.id,
        decidedNone: _stationDecided && _station == null,
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _station = choice.station;
      _stationDecided = true;
    });
  }

  Future<void> _submit() async {
    final GeoPoint? point = _point;
    if (point == null) {
      showToast(context, '尚未获取到定位，请先重新定位');
      return;
    }
    if (!_stationDecided) {
      showToast(context, '请选择附近站点，或选择「不选择站点」');
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
              kind: UploadKind.checkIn,
              onProgress: (int index, int total, double progress) {
                if (!mounted) return;
                setState(() => _submitLabel = '上传图片 ${index + 1}/$total');
              },
            );
      }
      if (!mounted) return;
      setState(() => _submitLabel = '提交中…');

      await ref
          .read(attendWriteRepositoryProvider)
          .createAttend(
            AttendDraft(
              stationId: _station?.id,
              coordinate1: point.longitude,
              coordinate2: point.latitude,
              address: _address.text,
              description: _note.text,
              pictureKeys: keys,
            ),
          );

      if (!mounted) return;
      await ref
          .read(taskListProvider(TaskCategory.signIn).notifier)
          .refresh();
      if (!mounted) return;
      showToast(context, '签到成功');
      Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      showToast(context, error.userMessage);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '签到失败：$error');
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
    final bool canSubmit = _point != null && _stationDecided && !_submitting;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('新建签到'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: <Widget>[
                  _locationCard(theme),
                  const SizedBox(height: 12),
                  _stationCard(theme),
                  const SizedBox(height: 12),
                  _noteCard(theme),
                  const SizedBox(height: 12),
                  _photoCard(theme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: canSubmit ? _submit : null,
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
                      : const Text('提交签到'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 定位区块 ──────────────────────────────────────────────────────────

  Widget _locationCard(ThemeData theme) {
    final GeoPoint? point = _point;

    return _SectionCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: Row(
            children: <Widget>[
              Icon(
                LucideIcons.mapPinCheckInside,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('当前位置', style: theme.textTheme.labelLarge),
              const Spacer(),
              if (_locating)
                Text(
                  '定位中…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else if (point != null)
                _Tag(text: '已定位', tone: Tone.success)
              else
                _Tag(text: '定位失败', tone: Tone.danger),
            ],
          ),
        ),
        if (_locating)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 8, 14, 16),
            child: LinearProgressIndicator(minHeight: 3),
          )
        else if (point == null)
          _failureNotice(theme)
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(
              children: <Widget>[
                Icon(
                  LucideIcons.crosshair,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '经度 ${point.longitude.toStringAsFixed(6)}　'
                    '纬度 ${point.latitude.toStringAsFixed(6)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _locating ? null : _locate,
                  child: const Text('重新定位'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: TextField(
              controller: _address,
              enabled: !_submitting,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '位置',
                hintText: '未获取到地址，可手动填写',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _failureNotice(ThemeData theme) {
    // 与原工程 iOS `#if DEBUG` 写死坐标一致：只有开发环境给兜底入口，
    // 生产包不暴露「伪造坐标」，否则等于让签到可被绕过。
    final bool allowDebugPoint =
        kDebugMode && AppEnv.flavor == AppFlavor.dev;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: _NoticeCard(
        tone: Tone.warning,
        icon: LucideIcons.mapPinOff,
        title: '无法获取当前位置',
        message: _failure?.message ?? LocationFailure.unknown.message,
        actions: <Widget>[
          FilledButton.tonal(
            onPressed: _locate,
            child: const Text('重试定位'),
          ),
          if (allowDebugPoint) ...<Widget>[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _useDebugPoint,
              child: const Text('使用调试坐标'),
            ),
          ],
        ],
      ),
    );
  }

  // ── 站点区块 ──────────────────────────────────────────────────────────

  Widget _stationCard(ThemeData theme) {
    final String? value = _station != null
        ? '${_station!.name} · 距 ${_station!.distanceLabel}'
        : (_stationDecided ? '不选择站点' : null);

    return _SectionCard(
      children: <Widget>[
        _FieldRow(
          icon: LucideIcons.building2,
          label: '签到站点',
          value: value,
          placeholder: _metaLoading ? '加载附近站点…' : '请选择',
          enabled: !_submitting && _point != null,
          onTap: _pickStation,
        ),
        if (_metaError != null) ...<Widget>[
          const _FieldDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: <Widget>[
                Icon(
                  LucideIcons.cloudOff,
                  size: 14,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '附近站点加载失败：$_metaError',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _submitting ? null : _loadMeta,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ],
        const _FieldDivider(),
        _FieldRow(
          icon: LucideIcons.clock3,
          label: '签到时间',
          value: _formatNow(),
        ),
        const _FieldDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: <Widget>[
              Icon(
                LucideIcons.calendarCheck,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _meta.countToday > 0
                      ? '今日已签到 ${_meta.countToday} 次'
                      : '今日还未签到',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_meta.stationsNearBy.isNotEmpty)
                Text(
                  '附近 ${_meta.stationsNearBy.length} 个站点',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 备注 / 照片 ───────────────────────────────────────────────────────

  Widget _noteCard(ThemeData theme) => _SectionCard(
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
                Text('备注', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _note,
              enabled: !_submitting,
              minLines: 3,
              maxLines: 6,
              maxLength: 600,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '现场情况、同行人员等（选填）',
                counterText: '',
                border: InputBorder.none,
                isDense: true,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _photoCard(ThemeData theme) => _SectionCard(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: ImagePickerGrid(
          images: _images,
          enabled: !_submitting,
          label: '现场照片',
          hint: '支持拍照或相册，最多 9 张；签到照片存到 check/ 目录',
          onChanged: (List<PickedImage> next) => setState(() => _images = next),
        ),
      ),
    ],
  );

  /// 时间取服务端校准值（M0-08），避免用户改系统时间影响签到时间观感。
  /// 服务端落库用的是自己的 `gmt_create`，这里只负责展示。
  String _formatNow() {
    final DateTime now = ref.read(serverTimeProvider).now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}

/// 站点选择结果：`station == null` 表示用户显式选了「不选择站点」。
class _StationChoice {
  const _StationChoice.station(StationDistance this.station) : decided = true;

  const _StationChoice.none() : station = null, decided = true;

  final StationDistance? station;
  final bool decided;
}

class _StationSheet extends StatelessWidget {
  const _StationSheet({
    required this.stations,
    this.selectedId,
    this.decidedNone = false,
  });

  final List<StationDistance> stations;
  final int? selectedId;
  final bool decidedNone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text('选择签到站点', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '按与当前位置的直线距离排序，超过 20 公里的站点不会出现在这里',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final StationDistance station in stations)
                  ListTile(
                    leading: Icon(
                      LucideIcons.mapPin,
                      size: 20,
                      color: station.id == selectedId
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(station.name),
                    subtitle: Text('距当前位置 ${station.distanceLabel}'),
                    trailing: station.id == selectedId
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () =>
                        Navigator.of(context).pop(_StationChoice.station(station)),
                  ),
                ListTile(
                  leading: Icon(
                    LucideIcons.mapPinOff,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('不选择站点'),
                  subtitle: const Text('只记录位置与时间，不关联站点'),
                  trailing: decidedNone
                      ? Icon(
                          LucideIcons.check,
                          size: 18,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () =>
                      Navigator.of(context).pop(const _StationChoice.none()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── 与新建异常页一致的表单基础件 ─────────────────────────────────────────

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
            if (onTap != null)
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
    this.actions = const <Widget>[],
  });

  final Tone tone;
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: tone.foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tone.onBackground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tone.onBackground,
              height: 1.5,
            ),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: actions),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: tone.onBackground),
      ),
    );
  }
}
