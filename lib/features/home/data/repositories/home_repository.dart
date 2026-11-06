import '../models/filter_group.dart';
import '../models/task_item.dart';

/// 首页任务列表数据源抽象。
///
/// 真实后端接入时新增 `RemoteHomeRepository implements HomeRepository`，
/// 复用 [TaskCategoryX.endpoint] 与 `ApiClient` 即可，UI 层无需改动。
abstract class HomeRepository {
  Future<List<TaskItem>> fetchTasks({
    required TaskCategory category,
    required int page,
    required int pageSize,
    Map<String, String> filters = const {},
  });

  /// 全局搜索（M2-04）：后端按 search_text（内容/站名/处理人等）
  /// like 匹配，不按当前账号过滤，三类结果同构 timeline VO。
  Future<List<TaskItem>> search({
    required TaskCategory category,
    required String keyword,
    required int page,
    int pageSize = 10,
  });

  /// 按省 + 时间区间的 timeline（统计详情页用）：
  /// 省份直接传 region_key（不走 label 翻译），
  /// 异常在 condition4、巡检在 condition3（对齐后端 conditionOrder）。
  Future<List<TaskItem>> fetchTasksByRegion({
    required TaskCategory category,
    required String regionKey,
    required String startDate,
    required String endDate,
    required int page,
    int pageSize = 10,
  });

  /// 上一次请求后服务端报告的「是否还有下一页」。
  /// 真实后端在 `additional_data.more_items_in_collection` 返回精确值；
  /// 返回 null 的数据源（如 Mock）由调用方按返回条数推断。
  bool? get lastResponseHasMore => null;
}

/// 本地 mock 数据源：保证在未接后端时首页可完整演示（分页 / 刷新 / 筛选）。
class MockHomeRepository implements HomeRepository {
  MockHomeRepository({this.delay = const Duration(milliseconds: 450)});

  final Duration delay;

  /// 演示详情页复用这批样例，避免列表与详情出现两套不一致的假数据。
  static List<TaskItem> get abnormalSamples => _abnormalTasks;

  @override
  bool? get lastResponseHasMore => null;

  @override
  Future<List<TaskItem>> search({
    required TaskCategory category,
    required String keyword,
    required int page,
    int pageSize = 10,
  }) async {
    await Future<void>.delayed(delay);
    final List<TaskItem> all = switch (category) {
      TaskCategory.abnormal => _abnormalTasks,
      TaskCategory.inspection => _inspectionTasks,
      TaskCategory.signIn => _signInTasks,
    };
    final String query = keyword.trim();
    if (query.isEmpty) return const [];
    final List<TaskItem> matched = all
        .where(
          (TaskItem item) =>
              item.content.contains(query) ||
              item.stationName.contains(query) ||
              item.executor.contains(query),
        )
        .toList();
    // 数据不足时循环补足，与 fetchTasks 的演示口径一致。
    final int total = matched.isEmpty
        ? 0
        : (matched.length * 3).clamp(pageSize, pageSize * 3);
    final List<TaskItem> expanded = List<TaskItem>.generate(
      total,
      (int i) => matched[i % matched.length],
    );
    final int start = (page - 1) * pageSize;
    if (start >= expanded.length) return const [];
    final int end = (start + pageSize).clamp(0, expanded.length);
    return expanded.sublist(start, end);
  }

  @override
  Future<List<TaskItem>> fetchTasksByRegion({
    required TaskCategory category,
    required String regionKey,
    required String startDate,
    required String endDate,
    required int page,
    int pageSize = 10,
  }) async {
    await Future<void>.delayed(delay);
    final List<TaskItem> all = switch (category) {
      TaskCategory.abnormal => _abnormalTasks,
      TaskCategory.inspection => _inspectionTasks,
      TaskCategory.signIn => _signInTasks,
    };
    final DateTime start = DateTime.parse(startDate);
    final DateTime end = DateTime.parse(endDate).add(const Duration(days: 1));
    final List<TaskItem> matched = all.where((TaskItem item) {
      final DateTime? created = DateTime.tryParse(
        item.timeText.replaceFirst(' ', 'T'),
      );
      return created != null &&
          !created.isBefore(start) &&
          created.isBefore(end);
    }).toList();
    final int total = matched.isEmpty
        ? 0
        : (matched.length * 3).clamp(pageSize, pageSize * 3);
    final List<TaskItem> expanded = List<TaskItem>.generate(
      total,
      (int i) => matched[i % matched.length],
    );
    final int pos = (page - 1) * pageSize;
    if (pos >= expanded.length) return const [];
    return expanded.sublist(pos, (pos + pageSize).clamp(0, expanded.length));
  }

  @override
  Future<List<TaskItem>> fetchTasks({
    required TaskCategory category,
    required int page,
    required int pageSize,
    Map<String, String> filters = const {},
  }) async {
    await Future<void>.delayed(delay);

    final List<TaskItem> all = switch (category) {
      TaskCategory.abnormal => _abnormalTasks,
      TaskCategory.inspection => _inspectionTasks,
      TaskCategory.signIn => _signInTasks,
    };

    final List<String> active = filters.entries
        .where(
          (MapEntry<String, String> e) =>
              e.key != TaskFilterConfig.dateRangeKey &&
              e.value.isNotEmpty &&
              e.value != '全部',
        )
        .map((MapEntry<String, String> e) => e.value)
        .toList();
    Iterable<TaskItem> filtered = active.isEmpty
        ? all
        : all.where(
            (TaskItem item) =>
                active.any((String label) => item.tags.contains(label)),
          );
    // 演示数据的时间都在 2026-11-01 ~ 11-04，按日期区间过滤出可感知的差异。
    final String? dateRange = filters[TaskFilterConfig.dateRangeKey];
    if (dateRange != null && dateRange.contains('|')) {
      final List<String> parts = dateRange.split('|');
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        final DateTime start = DateTime.parse(parts[0]);
        final DateTime end = DateTime.parse(parts[1]).add(
          const Duration(days: 1),
        );
        filtered = filtered.where((TaskItem item) {
          final DateTime? created = DateTime.tryParse(
            item.timeText.replaceFirst(' ', 'T'),
          );
          return created != null &&
              !created.isBefore(start) &&
              created.isBefore(end);
        });
      }
    }
    final List<TaskItem> hit = filtered.toList(growable: false);

    // 数据不足时循环补足，模拟后端多页数据
    final int total = pageSize * 3;
    final List<TaskItem> source = hit.isEmpty ? all : hit;
    final List<TaskItem> expanded = List<TaskItem>.generate(
      total,
      (int i) => source[i % source.length],
    );

    final int start = (page - 1) * pageSize;
    if (start >= expanded.length) return const [];
    final int end = (start + pageSize).clamp(0, expanded.length);
    return expanded.sublist(start, end);
  }

  static const List<TaskItem> _abnormalTasks = [
    TaskItem(
      id: 'ab-1001',
      stationName: '嘉兴市南湖水质自动监测站',
      timeText: '2026-11-04 09:12',
      content: '采水单元压力异常，蠕动泵运行声音偏大，初步判断为泵管老化，需要现场更换备用泵管并复测流量。',
      executor: '张伟',
      tags: ['处理中'],
      images: [
        'https://picsum.photos/seed/gc-ab1/600',
        'https://picsum.photos/seed/gc-ab2/600',
        'https://picsum.photos/seed/gc-ab3/600',
      ],
      readCount: 12,
      commentCount: 3,
      likeCount: 5,
    ),
    TaskItem(
      id: 'ab-1002',
      stationName: '嘉兴市运河三塔断面监测站',
      timeText: '2026-11-03 16:40',
      content: 'COD 分析仪标液核查结果超出允许范围，已重新配置标液，待观察一个完整测量周期。',
      executor: '李娜',
      tags: ['待处理'],
      images: [
        'https://picsum.photos/seed/gc-ab4/600',
        'https://picsum.photos/seed/gc-ab5/600',
      ],
      readCount: 8,
      commentCount: 1,
      likeCount: 2,
    ),
    TaskItem(
      id: 'ab-1003',
      stationName: '嘉兴市秀洲区北郊河监测站',
      timeText: '2026-11-02 11:05',
      content: '站房空调故障导致机柜温度偏高，已联系厂家上门维修，期间加强远程数据巡检。',
      executor: '王强',
      tags: ['已修复'],
      readCount: 21,
      commentCount: 6,
      likeCount: 9,
    ),
    TaskItem(
      id: 'ab-1004',
      stationName: '嘉兴市海盐县澉浦断面监测站',
      timeText: '2026-11-01 08:30',
      content: '数据缺失超过 2 小时，排查为 4G 模块掉线，重启后恢复上传，需持续关注信号强度。',
      executor: '陈晨',
      tags: ['已修复'],
      images: ['https://picsum.photos/seed/gc-ab6/600'],
      readCount: 15,
      commentCount: 2,
      likeCount: 4,
    ),
  ];

  static const List<TaskItem> _inspectionTasks = [
    TaskItem(
      id: 'in-2001',
      stationName: '嘉兴市南湖水质自动监测站',
      timeText: '2026-11-04 08:00',
      content: '日常巡检：检查采水单元、预处理单元、配水单元运行状态，清洗五参数传感器，记录现场温湿度。',
      executor: '张伟',
      tags: ['待巡检'],
      images: [
        'https://picsum.photos/seed/gc-in1/600',
        'https://picsum.photos/seed/gc-in2/600',
        'https://picsum.photos/seed/gc-in3/600',
      ],
      readCount: 6,
      commentCount: 0,
      likeCount: 1,
    ),
    TaskItem(
      id: 'in-2002',
      stationName: '嘉兴市运河三塔断面监测站',
      timeText: '2026-11-03 14:20',
      content: '专项巡检：核对在线仪表与实验室手工数据，偏差均在 ±5% 以内，试剂余量充足。',
      executor: '李娜',
      tags: ['已巡检'],
      images: ['https://picsum.photos/seed/gc-in4/600'],
      readCount: 11,
      commentCount: 2,
      likeCount: 3,
    ),
    TaskItem(
      id: 'in-2003',
      stationName: '嘉兴市秀洲区北郊河监测站',
      timeText: '2026-11-02 09:45',
      content: '月度巡检：完成站房卫生清理、废液收集与管路密封性检查，未发现渗漏。',
      executor: '王强',
      tags: ['已巡检'],
      readCount: 9,
      commentCount: 1,
      likeCount: 2,
    ),
  ];

  static const List<TaskItem> _signInTasks = [
    TaskItem(
      id: 'si-3001',
      stationName: '嘉兴市南湖水质自动监测站',
      timeText: '2026-11-04 07:58',
      content: '现场签到：到达站点后完成定位签到，今日计划完成异常处置与仪表核查两项工作。',
      executor: '张伟',
      tags: ['已签到'],
      images: ['https://picsum.photos/seed/gc-si1/600'],
      readCount: 4,
      commentCount: 0,
      likeCount: 0,
    ),
    TaskItem(
      id: 'si-3002',
      stationName: '嘉兴市海盐县澉浦断面监测站',
      timeText: '2026-11-03 08:12',
      content: '现场签到：陪同厂家工程师检修 4G 传输模块，签到位置与站点坐标偏差 18 米。',
      executor: '陈晨',
      tags: ['已签到'],
      readCount: 7,
      commentCount: 1,
      likeCount: 1,
    ),
    TaskItem(
      id: 'si-3003',
      stationName: '嘉兴市秀洲区北郊河监测站',
      timeText: '2026-11-02 08:05',
      content: '现场签到：例行到场，完成站房巡检并提交现场照片。',
      executor: '王强',
      tags: ['已签到'],
      readCount: 3,
      commentCount: 0,
      likeCount: 0,
    ),
  ];
}
