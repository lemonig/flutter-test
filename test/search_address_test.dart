import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/features/home/data/models/filter_group.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/address_repository.dart';
import 'package:green_clean_ops/features/home/data/repositories/remote_home_repository.dart';

/// 批次① 轻量回归（完整测试由人工验收覆盖）：
/// 只钉住最容易悄悄回归的两个纯函数——timeline 请求体的日期区间
/// 与地址簿的 PUT/POST 语义。
void main() {
  group('timeline 请求体日期区间（C5）', () {
    test('日期区间拼顶层 startDate/endDate，不占 condition 编码', () {
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.abnormal,
        page: 1,
        pageSize: 10,
        filters: <String, String>{
          TaskFilterConfig.dateRangeKey: '2026-11-01|2026-11-06',
        },
      );
      expect(body['startDate'], '2026-11-01');
      expect(body['endDate'], '2026-11-06');
      expect(body['condition1'], '1');
    });

    test('无日期时不带 startDate/endDate', () {
      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.signIn,
        page: 1,
        pageSize: 10,
      );
      expect(body.containsKey('startDate'), isFalse);
    });
  });

  group('地址簿（C3，PUT=新增 POST=修改）', () {
    test('toJson 携带全部字段，id>0 才带 id', () {
      final Map<String, Object?> draft = const ExpressAddress(
        id: 0,
        name: '张三',
        address: '小兴闸站房',
        phone: '13800000000',
        tag: '站房',
      ).toJson();
      expect(draft.containsKey('id'), isFalse);
      expect(draft['name'], '张三');

      final Map<String, Object?> update = const ExpressAddress(
        id: 19,
        name: '李四',
        address: '公司',
        phone: '',
      ).toJson();
      expect(update['id'], 19);
      expect(update.containsKey('tag'), isFalse);
    });

    test('Mock 增删改语义对齐后端', () async {
      MockAddressRepository.resetForTest();
      final MockAddressRepository repo = MockAddressRepository(delay: Duration.zero);

      final List<ExpressAddress> before = await repo.fetchAddresses();
      expect(before, hasLength(1));

      await repo.add(const ExpressAddress(id: 0, name: '王五', address: '连云港驻点'));
      expect((await repo.fetchAddresses()).first.name, '王五');

      final ExpressAddress added = (await repo.fetchAddresses()).first;
      await repo.update(ExpressAddress(id: added.id, name: '王五改', address: '新地址'));
      expect((await repo.fetchAddresses()).first.name, '王五改');

      await repo.remove(added.id);
      expect((await repo.fetchAddresses()).first.id, 19);
    });
  });
}
