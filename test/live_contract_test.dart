import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/features/auth/data/models/app_user.dart';
import 'package:green_clean_ops/features/home/data/models/filter_group.dart';
import 'package:green_clean_ops/features/home/data/models/task_item.dart';
import 'package:green_clean_ops/features/home/data/repositories/meta_repository.dart';
import 'package:green_clean_ops/features/home/data/repositories/remote_home_repository.dart';

/// 把 `192.168.188.66:1601` 与 `ops-mobile` 源码中的真实响应结构固化为回归测试。
/// 这些用例不发起网络请求，后端不可达时同样可跑。
void main() {
  Map<String, Object?> decode(String source) =>
      Map<String, Object?>.from(jsonDecode(source) as Map);

  group('后端实测响应（ApiErrorResponse）', () {
    test('登录参数错误 → 业务异常，保留后端原文', () {
      final ApiResponse response = ApiResponse.parse(
        decode(
          '{"success":false,"message":"账户或密码不能为空",'
          '"request_time":"2026-11-04T22:15:37.707+08:00",'
          '"error":"FIELD_ERROR","path":"/api/login"}',
        ),
      );
      expect(response.success, isFalse);
      final AppException failure = response.failure!;
      expect(failure.kind, ApiErrorKind.business);
      expect(failure.code, 'FIELD_ERROR');
      expect(failure.userMessage, '账户或密码不能为空');
    });

    test('未携带 token → UNAUTHENTICATED 触发统一登出', () {
      final ApiResponse response = ApiResponse.parse(
        decode(
          '{"success":false,"message":"用户未认证或token过期，请重新登录后继续",'
          '"error":"UNAUTHENTICATED","path":"/api/task/timeline"}',
        ),
      );
      final AppException failure = response.failure!;
      expect(failure.isUnauthenticated, isTrue);
      expect(failure.userMessage, contains('登录已过期'));
    });

    test('登录成功响应 → SimpleUser 角色派生', () {
      final ApiResponse response = ApiResponse.parse(
        decode(
          '{"success":true,"data":{'
          '"id":1001,"nickname":"张伟","token":"real-token",'
          '"title":"运维工程师","mobile":"13800000000",'
          '"metaAuthVO":{"ops":true,"manager":false,"opsManager":true,'
          '"dataManager":false,"assistant":false,"reginManager":false,'
          '"cityManager":false,"areaManager":false,"projectManager":false}'
          '},"request_time":"2026-11-04T22:15:37.000+08:00"}',
        ),
      );
      final AppUser user = AppUser.fromJson(response.mapData);
      expect(user.token, 'real-token');
      expect(user.displayName, '张伟');
      expect(user.role, UserRole.opsManager);
      expect(user.can(AppPermission.approve), isTrue);
      expect(user.can(AppPermission.statistics), isTrue);
      expect(user.can(AppPermission.manageUser), isFalse);
    });
  });

  group('真实 timeline 数据样本（字段已脱敏）', () {
    test('异常：+0800 时间格式与 TaskStateEnum', () {
      final TaskItem item = RemoteHomeRepository.mapTaskItem(
        TaskCategory.abnormal,
        <Object?, Object?>{
          'id': 68076,
          'content': '出负超下限',
          'state': 1,
          'gmt_create': '2026-11-04T20:08:43.000+0800',
          'station': <Object?, Object?>{'name': '某水质自动监测站'},
          'executor': <Object?, Object?>{'nickname': '某工程师'},
          'pictures': <Object?>[
            <Object?, Object?>{
              'picture': '/portrait/202611/a.jpg',
              'url': 'https://oss.example.com/a.jpg',
            },
          ],
          'countRead': 3,
        },
      );
      expect(item.timeText, '2026-11-04 20:08');
      expect(item.tags, <String>['待处理']);
      expect(item.images, <String>['https://oss.example.com/a.jpg']);
    });

    test('巡检 description 为空时用站点与检查项生成摘要', () {
      final TaskItem item = RemoteHomeRepository.mapTaskItem(
        TaskCategory.inspection,
        <Object?, Object?>{
          'id': 12591626,
          'description': null,
          'itemSize': 12,
          'opsTaskDone': true,
          'station': <Object?, Object?>{'name': '某断面监测站'},
          'gmt_create': '2026-11-01T20:02:10.000+0800',
        },
      );
      expect(item.content, '12 个检查项 · 某断面监测站巡检任务');
      expect(item.tags, <String>['已完成']);
    });

    test('签到 description 为空时用 address 生成摘要', () {
      final TaskItem item = RemoteHomeRepository.mapTaskItem(
        TaskCategory.signIn,
        <Object?, Object?>{
          'id': 54975,
          'description': '',
          'address': '浙江省宁波市某路段',
          'user': <Object?, Object?>{'nickname': '某签到人'},
          'station': <Object?, Object?>{'name': '某站点'},
          'gmt_create': '2026-11-04T19:43:55.000+0800',
        },
      );
      expect(item.content, '现场签到 · 浙江省宁波市某路段');
      expect(item.executor, '某签到人');
    });
  });

  group('后端 meta/basic 条件结构', () {
    test('省级 value 是行政区划码，会原样提交到 condition4', () {
      final ApiResponse response = ApiResponse.parse(
        decode(
          '{"success":true,"data":{"taskConditionList":[{"name":"可见范围",'
          '"list":[{"label":"全部","value":"1"},'
          '{"label":"我处理的","value":"2"}]},'
          '{"name":"所属省份","list":[{"label":"全部","value":"1"},'
          '{"label":"浙江省","value":"330000"},'
          '{"label":"江苏省","value":"320000"}]}]}}',
        ),
      );
      final List<FilterGroup> groups = MetaRepository.parseGroupList(
        response.mapData['taskConditionList'],
      );
      expect(groups, hasLength(2));
      expect(groups.first.valueOf('我处理的'), '2');
      expect(groups.last.valueOf('浙江省'), '330000');

      final Map<String, Object?> body = RemoteHomeRepository.buildTimelineBody(
        category: TaskCategory.abnormal,
        page: 1,
        pageSize: 10,
        filters: const <String, String>{'所属省份': '浙江省'},
        groups: <FilterGroup>[
          ...TaskFilterConfig.of(TaskCategory.abnormal)
              .where((FilterGroup g) => g.title != '所属省份'),
          groups.last,
        ],
      );
      expect(body['condition4'], '330000');
      expect(body['condition1'], '1');
    });
  });
}
