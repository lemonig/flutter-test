import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 键值存储抽象：生产用 SharedPreferences，测试用内存实现（M0-04）。
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);
}

class SharedPreferencesStore implements KeyValueStore {
  const SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) async => _prefs.remove(key);
}

/// 一次登录会话的持久化内容。
class StoredSession {
  const StoredSession({
    required this.token,
    required this.userJson,
    required this.baseUrl,
    required this.savedAt,
  });

  final String token;
  final String userJson;
  final String baseUrl;
  final DateTime savedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'token': token,
    'userJson': userJson,
    'baseUrl': baseUrl,
    'savedAt': savedAt.toIso8601String(),
  };

  static StoredSession? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final String? token = decoded['token']?.toString();
      final String? userJson = decoded['userJson']?.toString();
      if (token == null || token.isEmpty || userJson == null) return null;
      return StoredSession(
        token: token,
        userJson: userJson,
        baseUrl: decoded['baseUrl']?.toString() ?? '',
        savedAt:
            DateTime.tryParse(decoded['savedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } on FormatException {
      return null;
    }
  }
}

/// 统一存储入口：会话、搜索历史、筛选记忆、草稿。
class AppStorage {
  const AppStorage(this._store);

  final KeyValueStore _store;

  static const String _kSession = 'auth.session';
  static const String _kRememberedUser = 'auth.remembered_username';
  static const String _kRememberEnabled = 'auth.remember_enabled';
  static const String _kSearchHistory = 'pref.search_history';
  static const String _kFilterPrefix = 'pref.filters.';
  static const String _kDraftPrefix = 'pref.draft.';
  static const String _kAgreementAccepted = 'auth.agreement_accepted';
  static const String _kNotifyEnabled = 'pref.notify_enabled';

  // ---- 会话 ----
  Future<void> saveSession(StoredSession session) =>
      _store.write(_kSession, jsonEncode(session.toJson()));

  Future<StoredSession?> readSession() async =>
      StoredSession.tryParse(await _store.read(_kSession));

  Future<void> clearSession() => _store.remove(_kSession);

  // ---- 登录表单记忆 ----
  Future<void> saveRememberedUser(
    String username, {
    required bool enabled,
  }) async {
    await _store.write(_kRememberEnabled, enabled ? '1' : '0');
    await _store.write(_kRememberedUser, enabled ? username : '');
  }

  Future<({String username, bool enabled})> readRememberedUser() async {
    final bool enabled = await _store.read(_kRememberEnabled) == '1';
    final String username = enabled
        ? (await _store.read(_kRememberedUser) ?? '')
        : '';
    return (username: username, enabled: enabled);
  }

  Future<void> setAgreementAccepted(bool value) =>
      _store.write(_kAgreementAccepted, value ? '1' : '0');

  Future<bool> isAgreementAccepted() async =>
      await _store.read(_kAgreementAccepted) == '1';

  // ---- 偏好 ----
  Future<void> saveSearchHistory(List<String> keywords) =>
      _store.write(_kSearchHistory, jsonEncode(keywords.take(10).toList()));

  Future<List<String>> readSearchHistory() async {
    final String? raw = await _store.read(_kSearchHistory);
    if (raw == null) return const <String>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded.map((Object? e) => '$e').toList();
    } on FormatException {
      return const <String>[];
    }
  }

  Future<void> saveFilters(String scope, Map<String, String> filters) =>
      _store.write('$_kFilterPrefix$scope', jsonEncode(filters));

  Future<Map<String, String>> readFilters(String scope) async {
    final String? raw = await _store.read('$_kFilterPrefix$scope');
    if (raw == null) return const <String, String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return decoded.map(
        (Object? k, Object? v) => MapEntry<String, String>('$k', '$v'),
      );
    } on FormatException {
      return const <String, String>{};
    }
  }

  Future<void> saveDraft(String key, String json) =>
      _store.write('$_kDraftPrefix$key', json);

  Future<String?> readDraft(String key) => _store.read('$_kDraftPrefix$key');

  Future<void> clearDraft(String key) => _store.remove('$_kDraftPrefix$key');

  Future<void> setNotifyEnabled(bool value) =>
      _store.write(_kNotifyEnabled, value ? '1' : '0');

  Future<bool> isNotifyEnabled() async =>
      (await _store.read(_kNotifyEnabled)) != '0';
}

/// 默认给内存实现，widget 测试无需初始化插件；
/// `main()` 里会 override 成真实 SharedPreferences。
final Provider<AppStorage> appStorageProvider = Provider<AppStorage>(
  (Ref ref) => AppStorage(InMemoryKeyValueStore()),
);
