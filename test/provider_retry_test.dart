import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/retry_policy.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/home_repository.dart';
import 'package:green_clean_ops/features/home/providers/home_providers.dart';
import 'package:green_clean_ops/features/home/presentation/widgets/task_list_view.dart';

class _FailingRepo implements HomeRepository {

  @override
  Future<List<TaskItem>> search({
    required TaskCategory category,
    required String keyword,
    required int page,
    int pageSize = 10,
  }) async => const <TaskItem>[];


  int calls = 0;

  @override
  bool? get lastResponseHasMore => null;

  @override
  Future<List<TaskItem>> fetchTasks({
    required TaskCategory category,
    required int page,
    required int pageSize,
    Map<String, String> filters = const <String, String>{},
  }) async {
    calls++;
    throw Exception('后端不可达');
  }
}

void main() {
  testWidgets('关闭隐式重试后，列表失败只请求一次并展示错误态', (WidgetTester tester) async {
    final _FailingRepo repo = _FailingRepo();

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutoRetry,
        overrides: [
          useMockProvider.overrideWithValue(false),
          homeRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TaskListView(category: TaskCategory.abnormal)),
        ),
      ),
    );
    // 跑够默认指数退避的窗口（200/400/800/1600ms），确认没有二次请求
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    expect(repo.calls, 1);
    expect(find.text('数据加载失败'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  test('noAutoRetry 对任何错误都返回 null（不重试）', () {
    expect(noAutoRetry(0, Exception('x')), isNull);
    expect(noAutoRetry(3, Exception('x')), isNull);
  });
}
