import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/api_response.dart';
import '../data/models/workbench_models.dart';
import '../data/repositories/apply_repository.dart';
import '../data/repositories/directory_repository.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/stats_repository.dart';

/// 工作台数据家族（M7）。
///
/// 列表沿用 home 的模式：`AsyncNotifier` + 构造参数 + family 切换缓存，
/// 动作完成后由 `ApplyActionService` 统一 `invalidate`，不做手工状态同步。

/// 上报表单元数据（合同 / 阶段 / 费用类型）。
final reportMetaProvider = FutureProvider<ReportMeta>(
  (Ref ref) => ref.watch(reportRepositoryProvider).fetchMeta(),
);

/// 车牌候选（里程与车辆费用共用），key = keyword。
final carOptionsProvider = FutureProvider.family<List<Car>, String>(
  (Ref ref, String keyword) =>
      ref.watch(reportRepositoryProvider).fetchCars(keyword: keyword),
);

/// 工作台 Banner（`GET meta/banner`）。失败按空列表兜底，不阻塞工作台；
/// 演示模式给一张占位图，保证 demo 包版面完整且不发真实网络请求。
final workBannersProvider = FutureProvider<List<WorkBanner>>((Ref ref) async {
  if (ref.watch(useMockProvider)) {
    return const <WorkBanner>[
      WorkBanner(id: 1, imageUrl: 'https://picsum.photos/seed/gc-banner/900/240'),
    ];
  }
  final ApiClient api = ref.watch(apiClientProvider);
  try {
    final ApiResponse response = await api.getRaw('meta/banner');
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(WorkBanner.fromJson)
        .where((WorkBanner banner) => banner.imageUrl.isNotEmpty)
        .toList(growable: false);
  } on Exception {
    return const <WorkBanner>[];
  }
});

/// 上报列表分页状态。
class ReportPageState {
  const ReportPageState({
    this.items = const <ReportRecord>[],
    this.hasMore = false,
  });

  final List<ReportRecord> items;
  final bool hasMore;
}

class ReportListNotifier extends AsyncNotifier<ReportPageState> {
  ReportListNotifier(this.kind);

  final ReportKind kind;

  static const int pageSize = 15;

  int _page = 1;

  ReportRepository get _repo => ref.read(reportRepositoryProvider);

  @override
  Future<ReportPageState> build() async {
    _page = 1;
    final ReportPage page = await _repo.fetchReports(kind, page: 1);
    return ReportPageState(items: page.items, hasMore: page.hasMore);
  }

  /// 下拉刷新回第一页；已有数据在刷新期间保持可见。
  Future<void> refresh() async {
    try {
      _page = 1;
      final ReportPage page = await _repo.fetchReports(kind, page: 1);
      state = AsyncValue<ReportPageState>.data(
        ReportPageState(items: page.items, hasMore: page.hasMore),
      );
    } on Exception catch (error, stackTrace) {
      state = AsyncError<ReportPageState>(error, stackTrace);
    }
  }

  /// 触底加载下一页。
  Future<void> loadMore() async {
    final ReportPageState? current = state.value;
    if (current == null || !current.hasMore) return;
    _page += 1;
    final ReportPage page = await _repo.fetchReports(kind, page: _page);
    state = AsyncValue<ReportPageState>.data(
      ReportPageState(
        items: <ReportRecord>[...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }
}

final reportPageProvider =
    AsyncNotifierProvider.family<ReportListNotifier, ReportPageState, ReportKind>(
      ReportListNotifier.new,
    );

/// 申请列表状态（我的申请 / 审批三箱共用）。
class ApplyPageState {
  const ApplyPageState({this.items = const <ApplyRecord>[], this.hasMore = false});

  final List<ApplyRecord> items;
  final bool hasMore;
}

/// 申请列表 key 的约定（family 缓存按 key 隔离）：
/// `my` / `my:{typeCode}`（我的申请，type 可空）/ `todo` / `done` / `copy`。
class ApplyListKey {
  const ApplyListKey.my([this.type]) : box = null;

  const ApplyListKey.box(this.box) : type = null;

  final ApplyBox? box;
  final ApplyType? type;

  String get value {
    if (box != null) return box!.name;
    return type == null ? 'my' : 'my:${type!.code}';
  }

  static ApplyListKey parse(String key) {
    final List<String> parts = key.split(':');
    if (parts.first == 'my') {
      return ApplyListKey.my(
        parts.length > 1 ? ApplyType.fromCode(int.tryParse(parts[1])) : null,
      );
    }
    return ApplyListKey.box(
      ApplyBox.values.firstWhere(
        (ApplyBox box) => box.name == parts.first,
        orElse: () => ApplyBox.todo,
      ),
    );
  }
}

class ApplyListNotifier extends AsyncNotifier<ApplyPageState> {
  ApplyListNotifier(this.key);

  final String key;

  static const int pageSize = 15;

  ApplyRepository get _repo => ref.read(applyRepositoryProvider);

  @override
  Future<ApplyPageState> build() async {
    final ApplyListKey parsed = ApplyListKey.parse(key);
    final List<ApplyRecord> items = parsed.box == null
        ? await _repo.fetchMyApplies(type: parsed.type, page: 1)
        : await _repo.fetchApprovalBox(parsed.box!, page: 1);
    return ApplyPageState(items: items, hasMore: items.length >= pageSize);
  }
}

/// 「我的申请」列表，参数为 ApplyListKey.my 的 value。
final myAppliesProvider =
    AsyncNotifierProvider.family<ApplyListNotifier, ApplyPageState, String>(
      ApplyListNotifier.new,
    );

/// 审批中心三箱列表，参数为 box.name。
final approvalBoxProvider =
    AsyncNotifierProvider.family<ApplyListNotifier, ApplyPageState, String>(
      ApplyListNotifier.new,
    );

/// 商品目录（配件 / 工具），key = `{typeCode}` 或 `{typeCode}:{keyword}`。
final shopItemsProvider = FutureProvider.family<List<ShopItem>, String>((
  Ref ref,
  String key,
) {
  final List<String> parts = key.split(':');
  final ApplyType kind =
      ApplyType.fromCode(int.tryParse(parts.first)) ?? ApplyType.tool;
  final String keyword = parts.length > 1 ? parts.sublist(1).join(':') : '';
  return ref.watch(applyRepositoryProvider).fetchShopItems(kind, keyword: keyword);
});

/// 试剂分组目录，key = `{stationId}` 或 `{stationId}:{keyword}`。
final reagentGroupsProvider = FutureProvider.family<List<ReagentGroup>, String>((
  Ref ref,
  String key,
) {
  final List<String> parts = key.split(':');
  final int stationId = int.tryParse(parts.first) ?? 0;
  final String keyword = parts.length > 1 ? parts.sublist(1).join(':') : '';
  return ref
      .watch(applyRepositoryProvider)
      .fetchReagentGroups(stationId, keyword: keyword);
});

/// 审批人候选，key = keyword。
final approversProvider = FutureProvider.family<List<TaskPerson>, String>((
  Ref ref,
  String keyword,
) => ref.watch(applyRepositoryProvider).fetchApprovers(keyword: keyword));

/// 申请单详情，key = `{typeCode}:{id}`。
final applyDetailProvider = FutureProvider.family<ApplyRecord, String>((
  Ref ref,
  String key,
) {
  final List<String> parts = key.split(':');
  final ApplyType type =
      ApplyType.fromCode(int.tryParse(parts.first)) ?? ApplyType.fee;
  final int id = int.tryParse(parts.elementAt(1)) ?? 0;
  return ref.watch(applyRepositoryProvider).fetchApplyDetail(type, id);
});

/// ── 统计（M7-11）── key = `kind:period`（period 变化即换 family 条目）。
enum StatsKind { abnormal, inspection, mileage }

/// 统计页数据：为了三种 stat 类型共用一个 family，返回原始 Object 列表，
/// 由页面按 kind 强类型消费（解析已在仓库完成，这里是三种结果类型的联合）。
final statsProvider = FutureProvider.family<List<Object>, String>((
  Ref ref,
  String key,
) {
  final List<String> parts = key.split(':');
  final StatsKind kind = StatsKind.values.firstWhere(
    (StatsKind k) => k.name == parts.first,
    orElse: () => StatsKind.abnormal,
  );
  final StatPeriod period = StatPeriod.values.firstWhere(
    (StatPeriod p) => p.name == parts.elementAt(1),
    orElse: () => StatPeriod.day,
  );
  final DateTime now = DateTime.now();
  final (String, String) range = period.range(now);
  final DateTimeRange dateTimeRange = DateTimeRange(
    start: DateTime.parse(range.$1),
    end: DateTime.parse(range.$2),
  );
  final StatsRepository repo = ref.watch(statsRepositoryProvider);
  return switch (kind) {
    StatsKind.abnormal => repo
        .fetchAbnormalStats(range: dateTimeRange)
        .then((List<AbnormalStat> v) => v),
    StatsKind.inspection => repo
        .fetchInspectionStats(range: dateTimeRange)
        .then((List<InspectionStat> v) => v),
    StatsKind.mileage => repo
        .fetchMileageStats(range: dateTimeRange)
        .then((List<MileageStat> v) => v),
  };
});

/// ── 资料库（M7-12）── key = `{kind}:{keyword}`。
enum DirectoryKind { station, agency, user, car }

extension DirectoryKindX on DirectoryKind {
  String get label => switch (this) {
    DirectoryKind.station => '站点资料',
    DirectoryKind.agency => '驻点资料',
    DirectoryKind.user => '用户资料',
    DirectoryKind.car => '车辆资料',
  };
}

final directoryProvider = FutureProvider.family<List<Object>, String>((
  Ref ref,
  String key,
) {
  final List<String> parts = key.split(':');
  final DirectoryKind kind = DirectoryKind.values.firstWhere(
    (DirectoryKind k) => k.name == parts.first,
    orElse: () => DirectoryKind.station,
  );
  final String keyword = parts.length > 1 ? parts.sublist(1).join(':') : '';
  final DirectoryRepository repo = ref.watch(directoryRepositoryProvider);
  return switch (kind) {
    DirectoryKind.station =>
      repo.fetchStations(keyword: keyword).then((List<DirectoryStation> v) => v),
    DirectoryKind.agency =>
      repo.fetchAgencies(keyword: keyword).then((List<Agency> v) => v),
    DirectoryKind.user =>
      repo.fetchUsers(keyword: keyword).then((List<TaskPerson> v) => v),
    DirectoryKind.car => repo
        .fetchCarsWithLocation(keyword: keyword)
        .then((List<CarLocationItem> v) => v),
  };
});

/// 抄送人候选，key = keyword（复用申请仓库的 user/list/copy）。
final ccUsersProvider = FutureProvider.family<List<TaskPerson>, String>((
  Ref ref,
  String keyword,
) => ref.watch(applyRepositoryProvider).fetchCcUsers(keyword: keyword));

/// 申请单评论，key = 申请单 id。
final applyCommentsProvider = FutureProvider.family<List<ApplyComment>, String>((
  Ref ref,
  String applyId,
) => ref.watch(applyRepositoryProvider).fetchApplyComments(
      int.tryParse(applyId) ?? 0,
    ));

/// 申请动作出口：执行后失效列表与详情，三处视图同步。
class ApplyActionService {
  ApplyActionService(this._ref);

  final Ref _ref;

  ApplyRepository get _repo => _ref.read(applyRepositoryProvider);

  Future<void> submit(ApplyDraft draft) async {
    await _repo.submit(draft);
    _ref.invalidate(myAppliesProvider);
    _ref.invalidate(approvalBoxProvider);
  }

  Future<void> withdraw(int id, ApplyType type) async {
    await _repo.withdraw(id);
    _invalidate(type, id);
  }

  Future<void> approve(int id, ApplyType type) async {
    await _repo.approve(id);
    _invalidate(type, id);
  }

  Future<void> reject(int id, ApplyType type, String reason) async {
    await _repo.reject(id, reason);
    _invalidate(type, id);
  }

  void _invalidate(ApplyType type, int id) {
    _ref.invalidate(myAppliesProvider);
    _ref.invalidate(approvalBoxProvider);
    _ref.invalidate(applyDetailProvider('${type.code}:$id'));
  }
}

final Provider<ApplyActionService> applyActionServiceProvider =
    Provider<ApplyActionService>((Ref ref) => ApplyActionService(ref));
