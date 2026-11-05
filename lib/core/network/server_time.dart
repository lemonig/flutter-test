import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 服务端时间校准（M0-08，对应原工程 TrueTime）。
///
/// 用响应头 `Date` 或业务返回的服务器时间计算本地时钟偏移，
/// 签到/异常提交等敏感时间统一取 [now]，避免用户改系统时间影响业务。
class ServerTime {
  Duration _offset = Duration.zero;
  bool _calibrated = false;
  DateTime? _lastCalibratedAt;

  bool get isCalibrated => _calibrated;
  Duration get offset => _offset;
  DateTime? get lastCalibratedAt => _lastCalibratedAt;

  /// 用一次请求的服务端时间校准（会补偿单次 RTT 的一半）。
  void calibrate(
    DateTime serverUtc, {
    DateTime? requestSentAt,
    DateTime? responseReceivedAt,
  }) {
    final DateTime received = responseReceivedAt ?? DateTime.now().toUtc();
    final DateTime sent = requestSentAt ?? received;
    final Duration rtt = received.difference(sent);
    final DateTime estimatedServerNow = serverUtc.add(
      Duration(microseconds: rtt.inMicroseconds ~/ 2),
    );
    _offset = estimatedServerNow.difference(DateTime.now().toUtc());
    _calibrated = true;
    _lastCalibratedAt = received;
  }

  /// 从 HTTP `Date` 响应头校准（RFC 1123：`Wed, 04 Nov 2026 11:30:00 GMT`）。
  void calibrateFromHttpDate(String? value) {
    final DateTime? parsed = _parseHttpDate(value);
    if (parsed == null) return;
    calibrate(parsed);
  }

  /// 校准后的当前本地时间；未校准时退化为系统时间。
  DateTime now() => DateTime.now().add(_offset);

  void reset() {
    _offset = Duration.zero;
    _calibrated = false;
    _lastCalibratedAt = null;
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    // 形如 "Wed, 04 Nov 2026 11:30:00 GMT"
    final RegExp pattern = RegExp(
      r'^\w{3},\s*(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    );
    final RegExpMatch? match = pattern.firstMatch(value.trim());
    if (match == null) return null;
    const Map<String, int> months = <String, int>{
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final int? month = months[match.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}

final Provider<ServerTime> serverTimeProvider = Provider<ServerTime>(
  (Ref ref) => ServerTime(),
);
