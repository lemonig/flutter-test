import '../../../../shared/utils/backend_time.dart';
import '../../../../shared/utils/oss_url.dart';
import 'task_detail.dart';

/// 巡检详情（`GET opsrecord/{id}` → 后端 `OpsRecord` 详情 VO）。
///
/// 与异常最大的差别：巡检没有「状态流转」，只有「做完 / 没做完 / 过期 / 终止」；
/// 巡检项（`opsDetailList`）本身没有「正常 / 异常」枚举，**完成度靠备注与照片表达** ——
/// 这两点都以后端模型为准，规划文档里写的三态取值在接口里并不存在。
class OpsDetail {
  const OpsDetail({
    required this.id,
    this.jobNumber = '',
    this.stationId,
    this.stationName = '',
    this.stationAddress = '',
    this.longitude,
    this.latitude,
    this.executor,
    this.stationManager,
    this.gmtCreate,
    this.deadline,
    this.gmtFirstSubmit,
    this.description = '',
    this.pictures = const <TaskPhoto>[],
    this.pictureKeys = const <String>[],
    this.itemSize = 0,
    this.done = false,
    this.overtime = false,
    this.terminated = false,
    this.auth = const OpsAuth(),
    this.items = const <OpsItemDetail>[],
  });

  final String id;
  final String jobNumber;

  final int? stationId;
  final String stationName;
  final String stationAddress;

  /// 站点经度（`coordinate1`）。
  final double? longitude;

  /// 站点纬度（`coordinate2`）。
  final double? latitude;

  final TaskPerson? executor;
  final TaskPerson? stationManager;

  final String? gmtCreate;
  final String? deadline;
  final String? gmtFirstSubmit;

  final String description;
  final List<TaskPhoto> pictures;

  /// 与 [pictures] 同序的 OSS objectKey。
  ///
  /// 提交巡检时后端是**整体覆盖** `pictures`，所以重新提交必须把原有图片的
  /// key 一起带上，否则用户只是补了一张图，旧图就被清空了。
  final List<String> pictureKeys;

  final int itemSize;
  final bool done;
  final bool overtime;
  final bool terminated;

  final OpsAuth auth;
  final List<OpsItemDetail> items;

  /// 展示状态。优先级对齐后端 `auth` 的判定顺序：
  /// 终止 > 过期 > 完成 > 未完成（终止和过期的任务即便填过也不再算「已完成」）。
  String get statusText {
    if (terminated) return '已终止';
    if (overtime) return '已过期';
    return done ? '已完成' : '未完成';
  }

  bool get editable => auth.canSubmit;

  int get doneCount => items.where((OpsItemDetail item) => item.done).length;

  /// 按单元分组，`其他` 固定排最后（原工程 `lx_items_sectionss` 的顺序）。
  List<OpsGroup> get groups {
    final Map<String, List<OpsItemDetail>> buckets =
        <String, List<OpsItemDetail>>{};
    for (final OpsItemDetail item in items) {
      final String key = item.category.trim().isEmpty ? '其他' : item.category;
      buckets.putIfAbsent(key, () => <OpsItemDetail>[]).add(item);
    }
    final List<String> keys = buckets.keys
        .where((String key) => key != '其他')
        .toList();
    if (buckets.containsKey('其他')) keys.add('其他');
    return <OpsGroup>[
      for (final String key in keys) OpsGroup(category: key, items: buckets[key]!),
    ];
  }

  String get createText => formatBackendTime(gmtCreate);
  String get deadlineText => formatBackendTime(deadline);
  String get finishText => done ? formatBackendTime(gmtFirstSubmit) : '—';
  String get executorName => _nameOf(executor);
  String get stationManagerName => _nameOf(stationManager);

  String get coordinateLabel =>
      longitude != null && latitude != null
      ? '${longitude!.toStringAsFixed(6)}, ${latitude!.toStringAsFixed(6)}'
      : '未记录';

  static String _nameOf(TaskPerson? person) {
    final String nickname = person?.nickname ?? '';
    return nickname.isEmpty ? '—' : nickname;
  }

  static OpsDetail fromJson(Object? raw) {
    final Map<Object?, Object?> json = _asMap(raw);
    final Map<Object?, Object?> station = _asMap(json['station']);
    final List<OpsItemDetail> items = <OpsItemDetail>[];
    for (final Object? element in (json['opsDetailList'] as List?) ?? const <Object?>[]) {
      final OpsItemDetail? item = OpsItemDetail.fromJson(element);
      if (item != null) items.add(item);
    }
    final ParsedPhotos recordPhotos = parsePhotos(json['pictures']);
    return OpsDetail(
      id: '${json['id'] ?? ''}',
      jobNumber: '${json['jobNumber'] ?? ''}',
      stationId: _asInt(station['id']),
      stationName: '${station['name'] ?? ''}',
      stationAddress: '${station['address'] ?? ''}',
      longitude: _asDouble(station['coordinate1']),
      latitude: _asDouble(station['coordinate2']),
      executor: TaskPerson.fromJson(json['executor']),
      stationManager: TaskPerson.fromJson(json['stationManager']),
      gmtCreate: json['gmt_create']?.toString(),
      deadline: json['deadline']?.toString(),
      gmtFirstSubmit: json['gmt_first_submit']?.toString(),
      description: '${json['description'] ?? ''}',
      pictures: recordPhotos.photos,
      pictureKeys: recordPhotos.keys,
      itemSize: _asInt(json['itemSize']) ?? items.length,
      done: json['opsTaskDone'] == true,
      overtime: json['overtime'] == true,
      terminated: json['terminated'] == true,
      auth: OpsAuth.fromJson(json['auth']),
      items: items,
    );
  }

  /// 统一解析「图片」字段，同时给出展示用直链和提交用 objectKey。
  ///
  /// 巡检有两种形态：`pictures` 是裸 objectKey 数组，`picturesPreview` 是
  /// `{picture: key, url: 直链}`。两种都必须能取到 key —— 后端提交是整体覆盖，
  /// 拿不到旧 key 就会把用户之前的照片清空。
  static ParsedPhotos parsePhotos(Object? raw) {
    if (raw is! List) return const ParsedPhotos();
    final List<TaskPhoto> photos = <TaskPhoto>[];
    final List<String> keys = <String>[];
    for (final Object? element in raw) {
      String url = '';
      String key = '';
      String? title;
      if (element is String) {
        key = element.trim();
        url = resolveOssUrl(key);
      } else if (element is Map) {
        final Map<Object?, Object?> map = Map<Object?, Object?>.from(element);
        key = '${map['picture'] ?? ''}'.trim();
        url = resolveOssUrl('${map['url'] ?? ''}'.trim());
        final String rawTitle = '${map['title'] ?? ''}';
        title = rawTitle.isEmpty ? null : rawTitle;
        if (url.isEmpty) url = resolveOssUrl(key);
      }
      if (url.isEmpty) continue;
      photos.add(TaskPhoto(url: url, title: title));
      keys.add(key.isEmpty ? _keyFromUrl(url) : key);
    }
    return ParsedPhotos(photos: photos, keys: keys);
  }

  static String _keyFromUrl(String url) =>
      url.startsWith(kOssBaseUrl) ? url.substring(kOssBaseUrl.length) : url;

  static Map<Object?, Object?> _asMap(Object? value) =>
      value is Map ? Map<Object?, Object?>.from(value) : const <Object?, Object?>{};

  static double? _asDouble(Object? value) => switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v),
    _ => null,
  };

  static int? _asInt(Object? value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v),
    _ => null,
  };
}

/// 详情页能做什么，完全由服务端 `OpsRecordService#getOpsAuth` 判定。
///
/// 不要在客户端按「是不是执行人」自行推导，两边一旦不一致就会出现
/// 「按钮能点但请求被拒」。
class OpsAuth {
  const OpsAuth({
    this.canSubmit = false,
    this.canTerminate = false,
    this.canTransfer = false,
    this.canForceTransfer = false,
  });

  final bool canSubmit;
  final bool canTerminate;
  final bool canTransfer;
  final bool canForceTransfer;

  bool get canOperate => canSubmit || canTerminate || canTransfer || canForceTransfer;

  static OpsAuth fromJson(Object? raw) {
    final Map<Object?, Object?> json = OpsDetail._asMap(raw);
    bool read(String key) => json[key] == true;
    return OpsAuth(
      canSubmit: read('enableToSubmit'),
      canTerminate: read('enableToTerminate'),
      canTransfer: read('enableToTransfer'),
      canForceTransfer: read('enableToForceTransfer'),
    );
  }
}

/// 单个巡检项（`opsDetailList[i]`）。
class OpsItemDetail {
  const OpsItemDetail({
    required this.id,
    this.category = '',
    this.name = '',
    this.description = '',
    this.requirePhoto = false,
    this.photos = const <TaskPhoto>[],
    this.pictureKeys = const <String>[],
  });

  /// `ops_record_detail.id`，提交时作为 `itemList[i].id`。
  final int id;

  final String category;
  final String name;

  /// 巡检项备注（`ops_record_detail.description`）。
  ///
  /// 原 iOS 只填照片不填这里，但服务端 `updateOpsRecordDetail` 会写这个字段，
  /// 所以 M4-02 的「逐项备注」是能落库的，不需要改后端。
  final String description;

  final bool requirePhoto;
  final List<TaskPhoto> photos;

  /// 已有照片的 objectKey，与 [photos] 同序，提交时原样带回。
  final List<String> pictureKeys;

  bool get done => description.trim().isNotEmpty || photos.isNotEmpty;

  static OpsItemDetail? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> json = Map<Object?, Object?>.from(raw);
    final int? id = OpsDetail._asInt(json['id']);
    if (id == null) return null;
    final ParsedPhotos parsed = OpsDetail.parsePhotos(
      json['picturesPreview'] ?? json['pictures'],
    );
    return OpsItemDetail(
      id: id,
      category: '${json['category'] ?? ''}',
      name: '${json['opsItemName'] ?? json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      requirePhoto: json['requirePhoto'] == true,
      photos: parsed.photos,
      pictureKeys: parsed.keys,
    );
  }
}

/// 「图片字段」的解析结果：展示用直链 + 提交用 objectKey。
class ParsedPhotos {
  const ParsedPhotos({
    this.photos = const <TaskPhoto>[],
    this.keys = const <String>[],
  });

  final List<TaskPhoto> photos;
  final List<String> keys;

  bool get isEmpty => photos.isEmpty;
}

/// 按单元分好的一组巡检项。
class OpsGroup {
  const OpsGroup({required this.category, required this.items});

  final String category;
  final List<OpsItemDetail> items;

  int get doneCount => items.where((OpsItemDetail item) => item.done).length;
}
