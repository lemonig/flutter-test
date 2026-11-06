import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';

/// 快递收货地址（M9-03 变体，C3）。
///
/// 后端 `ApplyController#address` 家族，是**申请单的收货地址簿**
/// （试剂 / 配件申请的 delivery 信息来源），不是签到地址。
///
/// ⚠️ 方法语义与 REST 惯例相反（源码确认过，2026-11-06 实测 GET 可用）：
/// - `GET address`：我的地址列表；
/// - `PUT address`：**新增**（服务端补 user_id）；
/// - `POST address`：**修改**；
/// - `DELETE address/{id}`：删除。
class ExpressAddress {
  const ExpressAddress({
    required this.id,
    this.name = '',
    this.address = '',
    this.phone = '',
    this.tag = '',
  });

  final int id;
  final String name;
  final String address;
  final String phone;
  final String tag;

  /// 列表卡主行（姓名 电话）。
  String get title => phone.isEmpty ? name : '$name $phone';

  static ExpressAddress fromJson(Object? raw) {
    if (raw is! Map) return const ExpressAddress(id: 0);
    String t(Object? v) => (v ?? '').toString();
    return ExpressAddress(
      id: raw['id'] is int ? raw['id']! as int : int.tryParse('${raw['id'] ?? 0}') ?? 0,
      name: t(raw['name']),
      address: t(raw['address']),
      phone: t(raw['phone']),
      tag: t(raw['tag']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (id > 0) 'id': id,
    'name': name.trim(),
    'address': address.trim(),
    'phone': phone.trim(),
    if (tag.isNotEmpty) 'tag': tag.trim(),
  };
}

abstract class AddressRepository {
  Future<List<ExpressAddress>> fetchAddresses();

  Future<void> add(ExpressAddress address);

  Future<void> update(ExpressAddress address);

  Future<void> remove(int id);
}

class RemoteAddressRepository implements AddressRepository {
  const RemoteAddressRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ExpressAddress>> fetchAddresses() async {
    final ApiResponse response = await _api.getRaw('address');
    return response.listData
        .whereType<Map<Object?, Object?>>()
        .map(ExpressAddress.fromJson)
        .toList();
  }

  @override
  Future<void> add(ExpressAddress address) =>
      _api.putRaw('address', data: address.toJson());

  @override
  Future<void> update(ExpressAddress address) =>
      _api.postRaw('address', data: address.toJson());

  @override
  Future<void> remove(int id) => _api.deleteRaw('address/$id');
}

/// 演示实现：进程内留存，增删改与真实后端同语义（PUT 加 POST 改）。
class MockAddressRepository implements AddressRepository {
  MockAddressRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static final List<ExpressAddress> _store = <ExpressAddress>[
    const ExpressAddress(
      id: 19,
      name: '邵钰恒',
      address: '浙江省嘉兴市南湖区XX路XX号站房',
      phone: '13385114893',
      tag: '站房',
    ),
    const ExpressAddress(
      id: 20,
      name: '张伟',
      address: '浙江省嘉兴市南湖区绿洁科技园 3 号楼',
      phone: '13800000000',
      tag: '公司',
    ),
  ];

  static int _nextId = 21;

  /// 供测试重置种子数据（static store 跨用例共享）。
  static void resetForTest() {
    _store
      ..clear()
      ..addAll(<ExpressAddress>[
        const ExpressAddress(
          id: 19,
          name: '邵钰恒',
          address: '浙江省嘉兴市南湖区XX路XX号站房',
          phone: '13385114893',
          tag: '站房',
        ),
      ]);
    _nextId = 21;
  }

  @override
  Future<List<ExpressAddress>> fetchAddresses() async {
    await Future<void>.delayed(delay);
    return List<ExpressAddress>.unmodifiable(_store);
  }

  @override
  Future<void> add(ExpressAddress address) async {
    await Future<void>.delayed(delay);
    _store.insert(0, ExpressAddress(id: ++_nextId, name: address.name, address: address.address, phone: address.phone, tag: address.tag));
  }

  @override
  Future<void> update(ExpressAddress address) async {
    await Future<void>.delayed(delay);
    final int index = _store.indexWhere((ExpressAddress a) => a.id == address.id);
    if (index < 0) {
      throw const AppException('地址不存在', kind: ApiErrorKind.business);
    }
    _store[index] = address;
  }

  @override
  Future<void> remove(int id) async {
    await Future<void>.delayed(delay);
    _store.removeWhere((ExpressAddress a) => a.id == id);
  }
}

final Provider<AddressRepository> addressRepositoryProvider =
    Provider<AddressRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockAddressRepository();
      return RemoteAddressRepository(ref.watch(apiClientProvider));
    });
