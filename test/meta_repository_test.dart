import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/features/home/data/models/filter_group.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/meta_repository.dart';

void main() {
  group('M2-02 meta/basic 条件解析', () {
    test('三类条件列表按后端结构解析 label/value', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'taskConditionList': <Object?>[
            <String, Object?>{
              'name': '可见范围',
              'list': <Object?>[
                <String, Object?>{'label': '全部', 'value': '1'},
                <String, Object?>{'label': '我处理的', 'value': '2'},
              ],
            },
            <String, Object?>{
              'name': '任务状态',
              'list': <Object?>[
                <String, Object?>{'label': '全部', 'value': '1'},
                <String, Object?>{'label': '待处理', 'value': '2'},
              ],
            },
          ],
          'opsConditionList': <Object?>[
            <String, Object?>{
              'name': '所属省份',
              'list': <Object?>[
                <String, Object?>{'label': '全部', 'value': '1'},
                <String, Object?>{'label': '浙江省', 'value': 'org-zj'},
              ],
            },
          ],
          'attendConditionList': <Object?>[],
        },
      });

      final Map<TaskCategory, List<FilterGroup>> parsed = MetaRepository.parse(
        response,
      );
      final List<FilterGroup> task = parsed[TaskCategory.abnormal]!;
      expect(task, hasLength(2));
      expect(task.first.title, '可见范围');
      expect(task.first.valueOf('我处理的'), '2');
      expect(task.last.valueOf('待处理'), '2');

      final FilterGroup region = parsed[TaskCategory.inspection]!.single;
      expect(region.valueOf('浙江省'), 'org-zj');
      expect(parsed[TaskCategory.signIn], isEmpty);
    });

    test('空条件列表安全返回空数组', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': <String, Object?>{},
      });
      final Map<TaskCategory, List<FilterGroup>> parsed = MetaRepository.parse(
        response,
      );
      for (final TaskCategory category in TaskCategory.values) {
        expect(parsed[category], isEmpty);
      }
    });
  });

  group('本地 fallback 与后端分组一致', () {
    test('三类的 condition 顺序与分组数正确', () {
      expect(TaskFilterConfig.conditionOrder[TaskCategory.abnormal], <String>[
        '可见范围',
        '任务状态',
        '其他',
        '所属省份',
      ]);
      expect(TaskFilterConfig.conditionOrder[TaskCategory.inspection], <String>[
        '可见范围',
        '任务状态',
        '所属省份',
      ]);
      expect(TaskFilterConfig.conditionOrder[TaskCategory.signIn], <String>[
        '可见范围',
        '所属省份',
      ]);
    });

    test('异常「任务状态」label 映射到后端 1~8', () {
      final FilterGroup status = TaskFilterConfig.of(TaskCategory.abnormal)
          .firstWhere((FilterGroup g) => g.title == '任务状态');
      expect(status.valueOf('全部'), '1');
      expect(status.valueOf('待处理'), '2');
      expect(status.valueOf('超时'), '8');
    });
  });

  group('M0-01 additional_data 分页', () {
    test('more_items_in_collection 可读取', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': <Object?>[],
        'additional_data': <String, Object?>{
          'total': 37,
          'totalPage': 4,
          'startPage': 1,
          'limit': 10,
          'more_items_in_collection': true,
        },
      });
      expect(response.hasMoreItems, isTrue);
      expect((response.additionalData! as Map)['total'], 37);
    });

    test('无分页字段时返回 null', () {
      final ApiResponse response = ApiResponse.parse(<String, Object?>{
        'success': true,
        'data': <Object?>[],
      });
      expect(response.hasMoreItems, isNull);
    });
  });
}
