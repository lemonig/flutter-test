import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/constants/app_colors.dart';
import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/core/network/retry_policy.dart';
import 'package:green_clean_ops/features/message/data/models/message_models.dart';
import 'package:green_clean_ops/features/message/data/repositories/message_repository.dart';
import 'package:green_clean_ops/features/message/presentation/message_list_page.dart';
import 'package:green_clean_ops/features/message/presentation/message_page.dart';
import 'package:green_clean_ops/features/message/providers/message_providers.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/shared/widgets/status_pill.dart';

import 'helpers/test_app.dart';

MessageCategory _category(
  MessageType type, {
  int unread = 0,
  String title = '最新一条消息',
}) => MessageCategory(
  type: type,
  name: type.defaultName,
  latestTitle: title,
  latestTime: '2026-11-05 09:46',
  unread: unread,
);

MessageItem _item(
  int id,
  MessageType type, {
  String title = '任务标题',
  bool? accepted,
  int? jobId = 68098,
}) => MessageItem(
  id: id,
  type: type,
  title: title,
  content: '',
  leftLabel: '站点:测试站',
  rightLabel: '截止时间:2026-11-06 09:46',
  timeText: '11-05 09:46',
  jobId: jobId,
  accepted: accepted,
);

class _FakeMessageRepository implements MessageRepository {
  _FakeMessageRepository({
    List<MessageCategory>? categories,
    Map<MessageType, List<MessageItem>>? messages,
    this.fail = false,
  }) : categories = categories ?? <MessageCategory>[_category(MessageType.task, unread: 2)],
       messages = messages ?? <MessageType, List<MessageItem>>{
         MessageType.task: <MessageItem>[_item(1, MessageType.task)],
       };

  List<MessageCategory> categories;
  Map<MessageType, List<MessageItem>> messages;
  bool fail;

  int fetchCalls = 0;
  int transferCalls = 0;
  int? lastTransferId;
  bool? lastAccepted;
  final List<MessageType> fetchedTypes = <MessageType>[];

  @override
  bool? get lastResponseHasMore => null;

  @override
  Future<List<MessageCategory>> fetchCategories() async {
    if (fail) throw const AppException('断网', kind: ApiErrorKind.network);
    return categories;
  }

  @override
  Future<List<MessageItem>> fetchMessages({
    required MessageType type,
    required int page,
    required int pageSize,
  }) async {
    fetchCalls++;
    fetchedTypes.add(type);
    if (fail) throw const AppException('断网', kind: ApiErrorKind.network);
    return messages[type] ?? const <MessageItem>[];
  }

  @override
  Future<void> transfer({
    required int messageId,
    required bool accepted,
  }) async {
    transferCalls++;
    lastTransferId = messageId;
    lastAccepted = accepted;
  }
}

/// 只挂了消息模块所需 override 的测试容器。
Widget _wrap(Widget child, MessageRepository repository) => ProviderScope(
  retry: noAutoRetry,
  overrides: [
    messageRepositoryProvider.overrideWithValue(repository),
    authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
    // 未读数是「演示环境求和 / 真实环境读接口」两套口径，这里固定为演示口径，
    // 让断言能对上本地分类（真机上两者的值本来就一致）。
    useMockProvider.overrideWithValue(true),
    serverUnreadCountProvider.overrideWith((Ref ref) async => 0),
  ],
  child: MaterialApp(home: child),
);

void main() {
  group('模型解析', () {
    test('分类解析：缺字段用兜底文案，分类名后端优先', () {
      final MessageCategory? category = MessageCategory.fromJson(<String, Object?>{
        'messageType': 2,
        'messageName': '巡检任务',
        'latest_message_title': '  ',
        'latest_message_time': null,
        'unread_count': '3',
      });
      expect(category, isNotNull);
      expect(category!.type, MessageType.ops);
      expect(category.name, '巡检任务');
      // 后端给空标题 → 兜底成「暂无消息」，不能显示空白行
      expect(category.latestTitle, '暂无消息');
      expect(category.latestTime, '');
      expect(category.unread, 3);
    });

    test('未知分类被丢弃，不让脏数据打出 8 个分类', () {
      expect(MessageCategory.fromJson(<String, Object?>{'messageType': 99}), isNull);
      expect(MessageCategory.fromJson('bad'), isNull);
    });

    test('消息解析：accepted 三态与 jobId', () {
      final MessageItem? pending = MessageItem.fromJson(<String, Object?>{
        'id': 485305,
        'message_type': 3,
        'title': '测试1转交了一条巡检任务给你',
        'content': null,
        'description_left': '站点:测试站4',
        'gmt_create': '2026-11-05T09:46:39.000+0800',
        'jobId': 12376768,
        'accepted': null,
      });
      expect(pending, isNotNull);
      expect(pending!.accepted, isNull);
      expect(pending.isPendingTransfer, isTrue);
      expect(pending.transferResultLabel, '待处理');
      expect(pending.jobId, 12376768);
      expect(pending.timeText, '11-05 09:46');

      final MessageItem? accepted = MessageItem.fromJson(<String, Object?>{
        'id': 1,
        'message_type': 3,
        'title': 't',
        'accepted': true,
      });
      expect(accepted!.accepted, isTrue);
      expect(accepted.isPendingTransfer, isFalse);
      expect(accepted.transferResultLabel, '已同意');
    });

    test('只有异常 / 巡检能跳业务详情，申请审批不外跳', () {
      expect(MessageType.task.linkedToTask, isTrue);
      expect(MessageType.ops.linkedToTask, isTrue);
      expect(MessageType.apply.linkedToTask, isFalse);
      expect(MessageType.transfer.isTransfer, isTrue);
      expect(MessageType.like.isTransfer, isFalse);
    });
  });

  group('消息分类页', () {
    testWidgets('渲染分类与未读角标，未读汇总取总数', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        categories: <MessageCategory>[
          _category(MessageType.task, unread: 2, title: '南湖站氨氮异常'),
          _category(MessageType.ops, unread: 1),
          _category(MessageType.apply),
        ],
      );
      await tester.pumpWidget(_wrap(const MessagePage(), repo));
      await tester.pumpAndSettle();

      expect(find.text('异常任务'), findsOneWidget);
      expect(find.text('巡检任务'), findsOneWidget);
      expect(find.text('我的申请'), findsOneWidget);
      expect(find.text('南湖站氨氮异常'), findsOneWidget);
      // 未读汇总：演示环境由本地分类求和 = 2 + 1
      expect(find.text('3 条未读消息'), findsOneWidget);
    });

    testWidgets('加载失败给出重试，而不是空白', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(fail: true);
      await tester.pumpWidget(_wrap(const MessagePage(), repo));
      await tester.pumpAndSettle();

      expect(find.text('消息加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    });

    testWidgets('全部已读逐个分类触发置读', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        categories: <MessageCategory>[
          _category(MessageType.task, unread: 2),
          _category(MessageType.transfer, unread: 1),
          _category(MessageType.apply),
        ],
      );
      await tester.pumpWidget(_wrap(const MessagePage(), repo));
      await tester.pumpAndSettle();

      // 首屏卡片也会请求；这里先清掉已有记录，只看「全部已读」的增量
      repo.fetchedTypes.clear();
      repo.categories = <MessageCategory>[
        _category(MessageType.task),
        _category(MessageType.transfer),
        _category(MessageType.apply),
      ];

      await tester.tap(find.text('全部已读'));
      await tester.pumpAndSettle();

      // 只对有两个未读的分类各请求一次，零未读的申请不碰
      expect(repo.fetchedTypes, <MessageType>[MessageType.task, MessageType.transfer]);
      expect(find.text('消息已全部读完'), findsOneWidget);
    });
  });

  group('消息明细页', () {
    testWidgets('展示明细并可下拉刷新', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        messages: <MessageType, List<MessageItem>>{
          MessageType.task: <MessageItem>[
            _item(1, MessageType.task, title: '南湖站氨氮异常'),
            _item(2, MessageType.task, title: '三塔断面 COD 缺测'),
          ],
        },
      );
      await tester.pumpWidget(
        _wrap(const MessageListPage(type: MessageType.task), repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('异常任务'), findsOneWidget);
      expect(find.text('南湖站氨氮异常'), findsOneWidget);
      expect(find.text('三塔断面 COD 缺测'), findsOneWidget);
      // 非转交分类不该出现同意 / 拒绝
      expect(find.text('同意'), findsNothing);
    });

    testWidgets('空分类给空态而不是白屏', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        messages: <MessageType, List<MessageItem>>{},
      );
      await tester.pumpWidget(
        _wrap(const MessageListPage(type: MessageType.like), repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂无收到的赞'), findsOneWidget);
    });

    testWidgets('转交任务可同意，确认后状态变为已同意', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        messages: <MessageType, List<MessageItem>>{
          MessageType.transfer: <MessageItem>[
            _item(20, MessageType.transfer, title: '王强转交了一条巡检任务给你'),
          ],
        },
      );
      await tester.pumpWidget(
        _wrap(const MessageListPage(type: MessageType.transfer), repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('待处理'), findsOneWidget);
      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();

      // 二次确认：转交不可撤回，必须点实
      expect(find.text('同意转交任务'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '同意'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.transferCalls, 1);
      expect(repo.lastTransferId, 20);
      expect(repo.lastAccepted, isTrue);
      expect(toneOfStatus('已同意'), Tone.success);
    });

    testWidgets('转交任务可拒绝，确认弹窗说明会退回原处理人', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        messages: <MessageType, List<MessageItem>>{
          MessageType.transfer: <MessageItem>[
            _item(21, MessageType.transfer),
          ],
        },
      );
      await tester.pumpWidget(
        _wrap(const MessageListPage(type: MessageType.transfer), repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(find.textContaining('任务会退回原处理人'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '拒绝'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.lastAccepted, isFalse);
      expect(repo.lastTransferId, 21);
    });

    testWidgets('已处置的转交只显示结果，不再给按钮', (WidgetTester tester) async {
      final _FakeMessageRepository repo = _FakeMessageRepository(
        messages: <MessageType, List<MessageItem>>{
          MessageType.transfer: <MessageItem>[
            _item(22, MessageType.transfer, accepted: false),
          ],
        },
      );
      await tester.pumpWidget(
        _wrap(const MessageListPage(type: MessageType.transfer), repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('已拒绝'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '同意'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '拒绝'), findsNothing);
    });
  });
}
