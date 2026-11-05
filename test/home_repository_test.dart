import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/home_repository.dart';

void main() {
  group('MockHomeRepository', () {
    final MockHomeRepository repository = MockHomeRepository(
      delay: Duration.zero,
    );

    test('按页返回固定条数', () async {
      final List<TaskItem> page1 = await repository.fetchTasks(
        category: TaskCategory.abnormal,
        page: 1,
        pageSize: 10,
      );
      final List<TaskItem> page2 = await repository.fetchTasks(
        category: TaskCategory.abnormal,
        page: 2,
        pageSize: 10,
      );

      expect(page1, hasLength(10));
      expect(page2, hasLength(10));
      expect(page1.first.id, isNot(page2.first.id));
    });

    test('超出范围返回空列表', () async {
      final List<TaskItem> page = await repository.fetchTasks(
        category: TaskCategory.inspection,
        page: 99,
        pageSize: 10,
      );
      expect(page, isEmpty);
    });

    test('状态筛选生效', () async {
      final List<TaskItem> items = await repository.fetchTasks(
        category: TaskCategory.abnormal,
        page: 1,
        pageSize: 10,
        filters: const <String, String>{'状态': '已修复'},
      );
      expect(items, isNotEmpty);
      expect(items.every((TaskItem item) => item.tags.contains('已修复')), isTrue);
    });

    test('三类任务各自返回对应数据', () async {
      for (final TaskCategory category in TaskCategory.values) {
        final List<TaskItem> items = await repository.fetchTasks(
          category: category,
          page: 1,
          pageSize: 10,
        );
        expect(items, isNotEmpty, reason: '${category.label} 应有 mock 数据');
      }
    });
  });
}
