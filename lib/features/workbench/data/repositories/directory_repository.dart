import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/workbench_models.dart';

/// 资料库（M7-12，对照 iOS `Data(资料)` 模块）：站点 / 驻点 / 用户 / 车辆。
///
/// 接口（2026-11-06 实测）：
/// - 站点 `GET station/list`（全量 SimpleStation）；
/// - 驻点 `GET agency/list`（列表即含 landlord / 租金等详情字段，
///   iOS 的 `agency/{id}` 详情同一份结构，不再单独拉取）；
/// - 用户 `GET user/list`；
/// - 车辆 `GET car/location`（CarLocation 内嵌 Car，定位经纬度一并返回）。
///
/// 车辆定位**只展示数字与文字**（经纬度 / 描述 / 在线状态），
/// 地图展示等高德 Key 改绑后再接（见未完成清单 A1）。
abstract class DirectoryRepository {
  Future<List<DirectoryStation>> fetchStations({String keyword = ''});

  Future<List<Agency>> fetchAgencies({String keyword = ''});

  Future<List<TaskPerson>> fetchUsers({String keyword = ''});

  Future<List<CarLocationItem>> fetchCarsWithLocation({String keyword = ''});
}

class RemoteDirectoryRepository implements DirectoryRepository {
  const RemoteDirectoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<DirectoryStation>> fetchStations({String keyword = ''}) async {
    final ApiResponse response = await _api.getRaw('station/list');
    final List<DirectoryStation> stations = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(DirectoryStation.fromJson)
        .toList();
    return _filter(stations, keyword, (DirectoryStation s) => s.name);
  }

  @override
  Future<List<Agency>> fetchAgencies({String keyword = ''}) async {
    final ApiResponse response = await _api.getRaw('agency/list');
    final List<Agency> agencies = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(Agency.fromJson)
        .toList();
    return _filter(agencies, keyword, (Agency a) => a.name);
  }

  @override
  Future<List<TaskPerson>> fetchUsers({String keyword = ''}) async {
    final ApiResponse response = await _api.getRaw('user/list');
    final List<TaskPerson> users = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(_person)
        .toList();
    return _filter(users, keyword, (TaskPerson u) => u.nickname);
  }

  @override
  Future<List<CarLocationItem>> fetchCarsWithLocation({
    String keyword = '',
  }) async {
    final ApiResponse response = await _api.getRaw(
      'car/location',
      data: const <String, Object?>{},
    );
    final List<CarLocationItem> cars = response.listData
        .whereType<Map<Object?, Object?>>()
        .map(CarLocationItem.fromJson)
        .toList();
    return _filter(cars, keyword, (CarLocationItem c) => c.car.carNum);
  }

  static List<T> _filter<T>(
    List<T> items,
    String keyword,
    String Function(T) label,
  ) {
    final String query = keyword.trim();
    if (query.isEmpty) return items;
    return items.where((T item) => label(item).contains(query)).toList();
  }

  static TaskPerson _person(Object? raw) {
    if (raw is! Map) return const TaskPerson();
    return TaskPerson(
      id: raw['id'] is int ? raw['id']! as int : null,
      nickname: (raw['nickname'] ?? '').toString(),
      avatar: (raw['avatar'] ?? '').toString(),
    );
  }
}

/// 演示实现：与实测响应同构的静态数据，keyword 本地过滤。
class MockDirectoryRepository implements DirectoryRepository {
  MockDirectoryRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static const List<DirectoryStation> _stations = <DirectoryStation>[
    DirectoryStation(
      id: 666,
      name: '北门八平米测试',
      region: '浙江省',
      city: '嘉兴市',
      contractNum: '2021450JS',
      firstChar: 'B',
    ),
    DirectoryStation(
      id: 1919,
      name: '小兴闸',
      region: '江苏省',
      city: '连云港市',
      contractNum: '2023126JS',
      firstChar: 'X',
    ),
    DirectoryStation(
      id: 2001,
      name: '运河三塔断面',
      region: '浙江省',
      city: '嘉兴市',
      contractNum: '2021274NM',
      firstChar: 'Y',
    ),
    DirectoryStation(
      id: 2002,
      name: '南湖水质自动站',
      region: '浙江省',
      city: '嘉兴市',
      contractNum: '2021450JS',
      firstChar: 'N',
    ),
  ];

  static const List<Agency> _agencies = <Agency>[
    Agency(
      id: 1,
      name: '湖州办事处',
      agent: '王建国',
      agentPhone: '13905720000',
      landlord: '瞿阿芳',
      landlordPhone: '13587915647',
      countRoom: '2',
      countRoomUsed: '1',
      startDate: '2026-01-15',
      endDate: '2027-01-15',
      rentOfYear: '22320',
      feeOfYear: '0',
      payMethod: '年付',
    ),
    Agency(
      id: 2,
      name: '连云港驻点',
      agent: '赵亮',
      agentPhone: '13851260000',
      landlord: '李守田',
      landlordPhone: '13805180000',
      countRoom: '3',
      countRoomUsed: '2',
      startDate: '2026-03-01',
      endDate: '2028-02-28',
      rentOfYear: '36000',
      feeOfYear: '1200',
      payMethod: '季付',
    ),
  ];

  static const List<TaskPerson> _users = <TaskPerson>[
    TaskPerson(id: 16, nickname: '卜幸杰'),
    TaskPerson(id: 177, nickname: '胡华鑫'),
    TaskPerson(id: 25, nickname: '赵亮'),
    TaskPerson(id: 925, nickname: '张子龙'),
    TaskPerson(id: 1001, nickname: '张伟'),
  ];

  static const List<CarLocationItem> _cars = <CarLocationItem>[
    CarLocationItem(
      car: Car(id: 280, carNum: '藏MJ5592', region: '西藏自治区', city: '林芝', company: '工程服务中心', description: '二手皮卡车'),
      lng: '94.362',
      lat: '29.654',
      gpsTime: '2026-11-06T08:20:00.000+0800',
      speed: 0,
      online: false,
      imei: '868120350206113',
      locDesc: '林芝市巴宜区',
    ),
    CarLocationItem(
      car: Car(id: 66, carNum: '浙B3K207', region: '浙江省', city: '嘉兴', company: '运维四组'),
      lng: '120.755',
      lat: '30.746',
      gpsTime: '2026-11-06T08:40:00.000+0800',
      speed: 42.0,
      online: true,
      imei: '868120350206117',
      locDesc: '嘉兴市南湖区中环南路',
    ),
    CarLocationItem(
      car: Car(id: 41, carNum: '苏G112XF', region: '江苏省', city: '连云港', company: '运维五组'),
      lng: '119.221',
      lat: '34.596',
      gpsTime: '2026-11-06T07:55:00.000+0800',
      speed: 0,
      online: true,
      imei: '868120350206118',
      locDesc: '连云港市海州区',
    ),
  ];

  @override
  Future<List<DirectoryStation>> fetchStations({String keyword = ''}) async {
    await Future<void>.delayed(delay);
    return _filter(_stations, keyword, (DirectoryStation s) => s.name);
  }

  @override
  Future<List<Agency>> fetchAgencies({String keyword = ''}) async {
    await Future<void>.delayed(delay);
    return _filter(_agencies, keyword, (Agency a) => a.name);
  }

  @override
  Future<List<TaskPerson>> fetchUsers({String keyword = ''}) async {
    await Future<void>.delayed(delay);
    return _filter(_users, keyword, (TaskPerson u) => u.nickname);
  }

  @override
  Future<List<CarLocationItem>> fetchCarsWithLocation({
    String keyword = '',
  }) async {
    await Future<void>.delayed(delay);
    return _filter(_cars, keyword, (CarLocationItem c) => c.car.carNum);
  }

  static List<T> _filter<T>(
    List<T> items,
    String keyword,
    String Function(T) label,
  ) {
    final String query = keyword.trim();
    if (query.isEmpty) return List<T>.unmodifiable(items);
    return items
        .where((T item) => label(item).contains(query))
        .toList(growable: false);
  }
}

final Provider<DirectoryRepository> directoryRepositoryProvider =
    Provider<DirectoryRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockDirectoryRepository();
      return RemoteDirectoryRepository(ref.watch(apiClientProvider));
    });
