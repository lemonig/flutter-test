import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 缓存占用统计与清理（M9-04）。
///
/// 只动**可再生的**东西：临时目录、应用缓存目录、网络图的内存缓存。
/// 本地草稿、搜索历史、登录态一律不碰 —— 那些是用户数据，
/// 混进「清除缓存」里会导致「清完缓存，没提交的异常也没了」。
abstract class AppCacheService {
  /// 当前缓存占用的字节数。
  Future<int> computeSize();

  /// 清理缓存。
  Future<void> clear();
}

class LocalAppCacheService implements AppCacheService {
  LocalAppCacheService({List<Directory>? directories})
    : _overrideDirectories = directories;

  /// 测试用：直接指定要统计的目录，避免依赖真实沙箱路径。
  final List<Directory>? _overrideDirectories;

  Future<List<Directory>> _roots() async {
    final List<Directory>? override = _overrideDirectories;
    if (override != null) return override;

    final List<Directory> roots = <Directory>[];
    // 两个目录在不同平台上可能重合，去重避免重复计数。
    final Set<String> seen = <String>{};
    for (final Future<Directory> Function() getter in <Future<Directory> Function()>[
      getTemporaryDirectory,
      getApplicationCacheDirectory,
    ]) {
      try {
        final Directory dir = await getter();
        if (seen.add(dir.path)) roots.add(dir);
      } catch (_) {
        // 取不到就跳过：统计不准好过整页报错。
      }
    }
    return roots;
  }

  @override
  Future<int> computeSize() async {
    int total = 0;
    for (final Directory root in await _roots()) {
      total += await _sizeOf(root);
    }
    return total;
  }

  static Future<int> _sizeOf(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final FileSystemEntity entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // 文件刚好被删掉 / 无权限，跳过。
          }
        }
      }
    } catch (_) {}
    return total;
  }

  @override
  Future<void> clear() async {
    for (final Directory root in await _roots()) {
      if (!await root.exists()) continue;
      await _empty(root);
    }
    // 网络图的内存缓存也清掉，否则用户会觉得「清了没效果」。
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  /// 只删目录里的内容，保留目录本身。
  ///
  /// 直接删掉临时目录本身，某些插件会拿到一个不存在的路径继续写而报错。
  static Future<void> _empty(Directory dir) async {
    try {
      await for (final FileSystemEntity entity in dir.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// 人类可读的字节数：`0 B` / `512 B` / `12.3 MB`。
///
/// 小于 1 KB 时不显示小数，MB 以上保留一位 —— 「0.0 MB」会让用户
/// 以为清理没生效，「12.28 MB」又过于啰嗦。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return kb < 10 ? '${kb.toStringAsFixed(1)} KB' : '${kb.round()} KB';
  }
  final double mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

final Provider<AppCacheService> appCacheServiceProvider =
    Provider<AppCacheService>((Ref ref) => LocalAppCacheService());

/// 当前缓存大小；清理后 `ref.invalidate` 即可刷新。
final FutureProvider<int> appCacheSizeProvider = FutureProvider<int>((
  Ref ref,
) async {
  return ref.watch(appCacheServiceProvider).computeSize();
});
