import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/features/home/data/models/filter_group.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/remote_home_repository.dart';

void main() {
  group('M2-01 timeline 请求参数（后端 condition 为数字编码）', () {
    test('异常为 condition1~4，携带分页与翻译后的编码', () {
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.abnormal,
        page: 2,
        pageSize: 10,
        filters: const <String, String>{
          '可见范围': '我处理的',
          '任务状态': '处理中',
          '其他': '产品缺陷导致',
          '所属省份': '全部',
        },
      );
      expect(body['startPage'], 2);
      expect(body['limit'], 10);
      expect(body['condition1'], '2'); // 可见范围 → 我处理的
      expect(body['condition2'], '3'); // 任务状态 → 处理中
      expect(body['condition3'], '2'); // 其他 → 产品缺陷导致
      expect(body['condition4'], '1'); // 省份 → 全部
    });

    test('无筛选时所有 condition 显式传 "1"', () {
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.abnormal,
        page: 1,
        pageSize: 10,
      );
      for (int i = 1; i <= 4; i++) {
        expect(body['condition$i'], '1');
      }
    });

    test('巡检为 condition1~3', () {
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.inspection,
        page: 1,
        pageSize: 10,
        filters: const <String, String>{'任务状态': '已完成', '可见范围': '未读'},
      );
      expect(body['condition1'], '4'); // 可见范围 → 未读
      expect(body['condition2'], '3'); // 任务状态 → 已完成
      expect(body['condition3'], '1');
      expect(body.containsKey('condition4'), isFalse);
    });

    test('签到为 condition1~2', () {
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.signIn,
        page: 1,
        pageSize: 10,
        filters: const <String, String>{'可见范围': '我的签到'},
      );
      expect(body['condition1'], '2');
      expect(body['condition2'], '1');
      expect(body.containsKey('condition3'), isFalse);
    });

    test('动态分组里的省份 key 会原样提交（M2-02）', () {
      final List<FilterGroup> dynamicGroups = <FilterGroup>[
        const FilterGroup(
          title: '可见范围',
          options: <String>['全部', '我处理的'],
          values: <String, String>{'全部': '1', '我处理的': '2'},
        ),
        const FilterGroup(
          title: '任务状态',
          options: <String>['全部', '待处理'],
          values: <String, String>{'全部': '1', '待处理': '2'},
        ),
        const FilterGroup(
          title: '其他',
          options: <String>['全部'],
          values: <String, String>{'全部': '1'},
        ),
        const FilterGroup(
          title: '所属省份',
          options: <String>['全部', '浙江省', '江苏省'],
          values: <String, String>{'全部': '1', '浙江省': 'org-zj', '江苏省': 'org-js'},
        ),
      ];
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.abnormal,
        page: 1,
        pageSize: 10,
        filters: const <String, String>{'所属省份': '浙江省'},
        groups: dynamicGroups,
      );
      expect(body['condition4'], 'org-zj');
      expect(body['condition1'], '1');
    });
  });

  group('M2-01 三类响应字段映射', () {
    test('异常：content + 图片对象数组 + TaskStateEnum', () {
      final TaskItem item = RemoteHomeRepository.mapTaskItem(
        TaskCategory.abnormal,
        <Object?, Object?>{
          'id': 101,
          'content': '采水单元压力异常',
          'state': 1,
          'gmt_create': '2026-11-04T09:12:00.000+08:00',
          'executor': <Object?, Object?>{'nickname': '张伟'},
          'station': <Object?, Object?>{'name': '南湖站'},
          'pictures': <Object?>[
            <Object?, Object?>{'url': 'https://img/1.jpg'},
            <Object?, Object?>{'picture': 'https://img/2.jpg'},
          ],
          'countRead': 12,
          'countComment': 3,
          'countLike': 5,
        },
      );
      expect(item.id, '101');
      expect(item.content, '采水单元压力异常');
      expect(item.tags, <String>['待处理']);
      expect(item.executor, '张伟');
      expect(item.stationName, '南湖站');
      expect(item.timeText, '2026-11-04 09:12');
      expect(item.images, hasLength(2));
      expect(item.readCount, 12);
    });

    test('巡检：description + 图片字符串数组 + 完成状态', () {
      final TaskItem item = RemoteHomeRepository.mapTaskItem(
        TaskCategory.inspection,
        <Object?, Object?>{
          'id': 201,
          'description': '日常巡检',
          'opsTaskDone': true,
          'pictures': <Object?>['https://img/a.jpg'],
          'station': <Object?, Object?>{'name': '三塔站'},
        },
      );
      expect(item.content, '日常巡检');
      expect(item.tags, <String>['已完成']);
      expect(item.images, <String>['https://img/a.jpg']);
      expect(item.executor, '未指派');
    });

    test('签到：user / address 兜底', () {
      final TaskItem item = RemoteHomeRepository.mapTaskItem(
        TaskCategory.signIn,
        <Object?, Object?>{
          'id': 301,
          'description': '现场签到',
          'address': '嘉兴市南湖区',
          'user': <Object?, Object?>{'nickname': '陈晨'},
          'jobNumber': 'J-003',
        },
      );
      expect(item.stationName, '嘉兴市南湖区');
      expect(item.executor, '陈晨');
      expect(item.tags, <String>['已签到']);
    });

    test('异常状态枚举完整映射（后端 TaskStateEnum 1~7）', () {
      expect(RemoteHomeRepository.abnormalStateLabel(1), '待处理');
      expect(RemoteHomeRepository.abnormalStateLabel(2), '处理中');
      expect(RemoteHomeRepository.abnormalStateLabel(3), '已修复');
      expect(RemoteHomeRepository.abnormalStateLabel(4), '非异常');
      expect(RemoteHomeRepository.abnormalStateLabel(5), '已关闭');
      expect(RemoteHomeRepository.abnormalStateLabel(6), '已拒绝');
      expect(RemoteHomeRepository.abnormalStateLabel(7), '已终止');
      expect(RemoteHomeRepository.abnormalStateLabel(99), '状态 99');
    });
  });
}
