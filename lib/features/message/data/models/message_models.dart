import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/utils/backend_time.dart';
import '../../../home/data/models/task_item.dart';

/// 消息分类编码，与后端 `PushMessageEnum` 一一对应。
///
/// 后端只认 1–7 这七个整型，分类名称也由后端下发的 `messageName` 决定，
/// 这里保留枚举只是为了图标、跳转行为能按分类区分，不能拿来替代后端值。
enum MessageType {
  task(1, '异常任务'),
  ops(2, '巡检任务'),
  transfer(3, '转交任务'),
  comment(4, '收到评论'),
  like(5, '收到的赞'),
  apply(6, '我的申请'),
  approve(7, '我的审批');

  const MessageType(this.code, this.defaultName);

  final int code;
  final String defaultName;

  static MessageType? fromCode(Object? raw) {
    final int? code = raw is int ? raw : int.tryParse('$raw');
    for (final MessageType type in MessageType.values) {
      if (type.code == code) return type;
    }
    return null;
  }

  IconData get icon => switch (this) {
    MessageType.task => LucideIcons.triangleAlert,
    MessageType.ops => LucideIcons.clipboardCheck,
    MessageType.transfer => LucideIcons.arrowRightLeft,
    MessageType.comment => LucideIcons.messageCircle,
    MessageType.like => LucideIcons.thumbsUp,
    MessageType.apply => LucideIcons.fileText,
    MessageType.approve => LucideIcons.badgeCheck,
  };

  Tone get tone => switch (this) {
    MessageType.task => Tone.danger,
    MessageType.ops => Tone.brand,
    MessageType.transfer => Tone.warning,
    MessageType.comment => Tone.brand,
    MessageType.like => Tone.warning,
    MessageType.apply => Tone.neutral,
    MessageType.approve => Tone.brand,
  };

  /// 该分类消息能否点进业务详情。
  ///
  /// 申请 / 审批走的是 `apply` 模块，Flutter 侧还没接，点进去只会白屏，
  /// 所以这里显式返回 null，由页面给出「暂未接入」的提示。
  bool get linkedToTask =>
      this == MessageType.task || this == MessageType.ops;

  /// 只有「转交任务」才有同意 / 拒绝的语义。
  bool get isTransfer => this == MessageType.transfer;
}

/// 消息 Tab 的分类条目：`POST message/list` 的 `data[i]`。
class MessageCategory {
  const MessageCategory({
    required this.type,
    required this.name,
    required this.latestTitle,
    required this.latestTime,
    required this.unread,
  });

  final MessageType type;
  final String name;
  final String latestTitle;

  /// 后端给的是 `yyyy-MM-dd HH:mm`，没有就显示「—」。
  final String latestTime;
  final int unread;

  bool get hasUnread => unread > 0;

  MessageCategory copyWith({int? unread}) => MessageCategory(
    type: type,
    name: name,
    latestTitle: latestTitle,
    latestTime: latestTime,
    unread: unread ?? this.unread,
  );

  static MessageCategory? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> json = Map<Object?, Object?>.from(raw);
    final MessageType? type = MessageType.fromCode(json['messageType']);
    if (type == null) return null;
    final String title = '${json['latest_message_title'] ?? ''}'.trim();
    return MessageCategory(
      type: type,
      // 后端分类名优先，取不到再退回枚举里的默认名
      name: '${json['messageName'] ?? type.defaultName}'.trim().isEmpty
          ? type.defaultName
          : '${json['messageName']}'.trim(),
      latestTitle: title.isEmpty ? '暂无消息' : title,
      latestTime: '${json['latest_message_time'] ?? ''}'.trim(),
      unread: switch (json['unread_count']) {
        final int value => value,
        final Object value => int.tryParse('$value') ?? 0,
        _ => 0,
      },
    );
  }
}

/// 某分类下的一条消息：`POST message/type` 的 `data[i]`。
class MessageItem {
  const MessageItem({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.leftLabel,
    required this.rightLabel,
    required this.timeText,
    required this.jobId,
    this.accepted,
  });

  final int id;
  final MessageType type;
  final String title;

  /// 评论内容 / 转交结果（「已同意」「已拒绝」）等正文，可能为空。
  final String content;

  /// 形如「来源:卜幸杰」「站点:测试站4」，已带前缀，直接展示。
  final String leftLabel;
  final String rightLabel;

  /// 后端 `gmt_create`，按原样转成 `MM-dd HH:mm`。
  final String timeText;

  /// 关联业务主键，点卡片时跳详情用。
  final int? jobId;

  /// 转交消息的处置结果：null = 待处理，true/false = 已同意/已拒绝。
  final bool? accepted;

  bool get isPendingTransfer => type.isTransfer && accepted == null;

  /// 关联的业务分类，用于跳详情；申请 / 审批返回 null。
  TaskCategory? get taskCategory => switch (type) {
    MessageType.task => TaskCategory.abnormal,
    MessageType.ops => TaskCategory.inspection,
    _ => null,
  };

  String get transferResultLabel => switch (accepted) {
    true => '已同意',
    false => '已拒绝',
    null => '待处理',
  };

  static MessageItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> json = Map<Object?, Object?>.from(raw);
    final int? id = switch (json['id']) {
      final int value => value,
      final Object value => int.tryParse('$value'),
      _ => null,
    };
    if (id == null) return null;

    final MessageType? type = MessageType.fromCode(json['message_type']);
    if (type == null) return null;

    String text(Object? value) => '${value ?? ''}'.trim();

    return MessageItem(
      id: id,
      type: type,
      title: text(json['title']),
      content: text(json['content']),
      leftLabel: text(json['description_left']),
      rightLabel: text(json['description_right']),
      timeText: formatBackendShort(json['gmt_create']),
      jobId: switch (json['jobId']) {
        final int value => value,
        final Object value => int.tryParse('$value'),
        _ => null,
      },
      accepted: switch (json['accepted']) {
        final bool value => value,
        _ => null,
      },
    );
  }
}
