/// 后端时间文本的解析与展示。
///
/// 后端（Spring）把 `Timestamp` 序列化成**已本地化的 GMT+8 字面值**，
/// 形如 `2026-11-05T08:38:32.000+0800`。这类字符串若交给
/// `DateTime.parse().toLocal()`，会先转成 UTC 再转回设备时区，
/// 设备时区不是东八区时就会整体偏移，因此这里优先取字面量的年月日时分。
library;

final RegExp _literal = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?',
);

/// 解析成**设备本地**的 [DateTime]，仅用于比较/计算（不用于显示）。
DateTime? parseBackendTime(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is DateTime) return raw;
  final String source = '$raw'.trim();
  if (source.isEmpty) return null;
  final RegExpMatch? match = _literal.firstMatch(source);
  if (match != null) {
    int part(int index) => int.tryParse(match.group(index) ?? '') ?? 0;
    return DateTime(
      part(1),
      part(2),
      part(3),
      part(4),
      part(5),
      part(6),
    );
  }
  return DateTime.tryParse(source);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// `2026-11-05 08:38`；无法解析时原样返回，空值返回 [empty]。
String formatBackendTime(Object? raw, {String empty = '—'}) {
  if (raw == null) return empty;
  final String source = '$raw'.trim();
  if (source.isEmpty) return empty;
  final DateTime? value = parseBackendTime(raw);
  if (value == null) return source;
  return '${value.year}-${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}';
}

/// `11-05 08:38`，用于时间轴等空间紧张处。
String formatBackendShort(Object? raw, {String empty = '—'}) {
  final DateTime? value = parseBackendTime(raw);
  if (value == null) return raw == null ? empty : '$raw';
  return '${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}';
}

/// 今天 / 昨天 / 本年内省略年份，其余补全。
String formatBackendFriendly(Object? raw, {String empty = '—'}) {
  final DateTime? value = parseBackendTime(raw);
  if (value == null) return raw == null ? empty : '$raw';
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(value.year, value.month, value.day);
  final int diff = today.difference(day).inDays;
  final String clock = '${_two(value.hour)}:${_two(value.minute)}';
  if (diff == 0) return '今天 $clock';
  if (diff == 1) return '昨天 $clock';
  if (value.year == now.year) {
    return '${_two(value.month)}-${_two(value.day)} $clock';
  }
  return '${value.year}-${_two(value.month)}-${_two(value.day)} $clock';
}

/// 评论 / 动态时间戳：`2026-11-05T13:06:00.000+0800` → `11-05 13:06`。
///
/// 评论接口返回的时间不一定能走 [parseBackendTime]（时区后缀写法不统一），
/// 所以这里退化成字面量截取：解析失败就原样返回，避免丢成空串。
String formatCommentTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final String normalized = raw.replaceFirst('T', ' ');
  final RegExpMatch? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ ](\d{2}):(\d{2})',
  ).firstMatch(normalized);
  if (match == null) return normalized;
  return '${match.group(2)}-${match.group(3)} ${match.group(4)}:${match.group(5)}';
}

/// 两个时间的可读间隔，例如 `6分钟` / `3小时20分钟` / `2天4小时`。
String formatDuration(Duration duration) {
  if (duration.isNegative) return '0分钟';
  final int days = duration.inDays;
  final int hours = duration.inHours % 24;
  final int minutes = duration.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days天$hours小时' : '$days天';
  if (hours > 0) return minutes > 0 ? '$hours小时$minutes分钟' : '$hours小时';
  return '$minutes分钟';
}
