import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';

/// 运维人员精简信息，来源 `POST user/ops/list`。
///
/// SQL 只查 `id, nickname, pinyin, jianpin, firstchar` 五列并过滤
/// `is_ops = 1 and is_active = 1`，但实测响应是完整 User 序列化
/// （带一堆 null 字段），客户端只取需要的那几个即可。
/// 列表本身就是「可接收转交的人」的权威来源，客户端不再自行判断角色。
class OpsUser {
  const OpsUser({
    required this.id,
    this.nickname = '',
    this.pinyin = '',
    this.jianpin = '',
    this.firstChar = '',
  });

  final int id;
  final String nickname;

  /// 全拼 / 简拼（2026-11-05 实测：全拼为大写，如 `BUXINGJIE`），
  /// 服务端按它们做大小写不敏感的 keyword 模糊匹配，展示用不到。
  final String pinyin;
  final String jianpin;

  /// 昵称首字母，服务端按它排序（A → Z）。
  final String firstChar;

  static OpsUser fromJson(Object? raw) {
    if (raw is! Map) {
      throw const AppException(
        '人员数据格式异常',
        kind: ApiErrorKind.parse,
        code: 'DATA_NOT_MAP',
      );
    }
    return OpsUser(
      id: raw['id'] is int
          ? raw['id']! as int
          : int.tryParse('${raw['id'] ?? ''}') ?? 0,
      nickname: (raw['nickname'] ?? '').toString(),
      pinyin: (raw['pinyin'] ?? '').toString(),
      jianpin: (raw['jianpin'] ?? '').toString(),
      firstChar: (raw['firstchar'] ?? '').toString(),
    );
  }
}

/// 可接收转交任务的运维人员（C7 委派任务）。
abstract class OpsUserRepository {
  /// `POST user/ops/list`，[keyword] 匹配昵称 / 全拼 / 简拼（服务端 like）。
  /// 不传分页参数时返回全量，与原工程一致。
  Future<List<OpsUser>> fetchOpsUsers({String keyword = ''});
}

class RemoteOpsUserRepository implements OpsUserRepository {
  const RemoteOpsUserRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<OpsUser>> fetchOpsUsers({String keyword = ''}) async {
    final ApiResponse response = await _api.postRaw(
      'user/ops/list',
      data: <String, Object?>{'keyword': keyword.trim()},
    );
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(OpsUser.fromJson)
        .toList();
  }
}

/// 演示实现：模拟服务端的过滤（在职运维）与排序（按首字母），
/// keyword 对昵称 / 全拼 / 简拼做不区分大小写的匹配。
/// 第一个人就是演示登录账号本人，供弹层验证「不能转给自己」的排除逻辑。
class MockOpsUserRepository implements OpsUserRepository {
  MockOpsUserRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  /// 演示用在职运维名单；第一个就是演示登录账号本人，
  /// 供弹层验证「不能转给自己」的排除逻辑，公开给 Mock 仓库共用。
  static const List<OpsUser> mockOpsUsers = <OpsUser>[
    OpsUser(
      id: 1001,
      nickname: '张伟',
      pinyin: 'zhangwei',
      jianpin: 'zw',
      firstChar: 'Z',
    ),
    OpsUser(
      id: 2,
      nickname: '李娜',
      pinyin: 'lina',
      jianpin: 'ln',
      firstChar: 'L',
    ),
    OpsUser(
      id: 3,
      nickname: '王强',
      pinyin: 'wangqiang',
      jianpin: 'wq',
      firstChar: 'W',
    ),
    OpsUser(
      id: 4,
      nickname: '赵敏',
      pinyin: 'zhaomin',
      jianpin: 'zm',
      firstChar: 'Z',
    ),
    OpsUser(
      id: 5,
      nickname: '陈刚',
      pinyin: 'chengang',
      jianpin: 'cg',
      firstChar: 'C',
    ),
  ];

  @override
  Future<List<OpsUser>> fetchOpsUsers({String keyword = ''}) async {
    await Future<void>.delayed(delay);
    final String query = keyword.trim().toLowerCase();
    final List<OpsUser> matched = query.isEmpty
        ? List<OpsUser>.of(mockOpsUsers)
        : mockOpsUsers
              .where(
                (OpsUser user) =>
                    user.nickname.toLowerCase().contains(query) ||
                    user.pinyin.toLowerCase().contains(query) ||
                    user.jianpin.contains(query),
              )
              .toList();
    matched.sort(
      (OpsUser a, OpsUser b) => a.firstChar.compareTo(b.firstChar),
    );
    return List<OpsUser>.unmodifiable(matched);
  }
}

final Provider<OpsUserRepository> opsUserRepositoryProvider =
    Provider<OpsUserRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockOpsUserRepository();
      return RemoteOpsUserRepository(ref.watch(apiClientProvider));
    });
