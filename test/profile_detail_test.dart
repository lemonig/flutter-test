import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:green_clean_ops/core/media/image_picker_service.dart';
import 'package:green_clean_ops/core/network/api_providers.dart';
import 'package:green_clean_ops/core/network/api_response.dart';
import 'package:green_clean_ops/core/network/retry_policy.dart';
import 'package:green_clean_ops/features/auth/providers/auth_provider.dart';
import 'package:green_clean_ops/features/profile/data/models/user_profile.dart';
import 'package:green_clean_ops/features/profile/data/repositories/profile_repository.dart';
import 'package:green_clean_ops/features/profile/presentation/profile_detail_page.dart';

import 'helpers/test_app.dart';

const UserProfile _demoProfile = UserProfile(
  id: 16,
  nickname: '卜幸杰',
  avatar: 'https://grean-ops.oss-cn-hangzhou.aliyuncs.com/avatar/16.png',
  title: '主管',
  company: '浙江绿洁环境科技有限公司',
  taskCount: 18,
  opsRecordCount: 7,
  attendCount: 26,
  mileageCount: 12,
);

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.fail = false});

  UserProfile profile = _demoProfile;
  bool fail;
  int updateCalls = 0;

  @override
  Future<UserProfile> fetchProfile({int? userId}) async {
    if (fail) {
      throw const AppException('资料服务不可用', kind: ApiErrorKind.network);
    }
    return profile;
  }

  @override
  Future<UserProfile> updateAvatar(PickedImage image) async {
    updateCalls++;
    profile = profile.copyWith(avatar: image.path);
    return profile;
  }
}

class _FakePicker extends ImagePickerService {
  _FakePicker();

  @override
  Future<PickedImage> pickFromCamera() async =>
      const PickedImage(path: '/tmp/camera.jpg', name: 'camera.jpg');

  @override
  Future<List<PickedImage>> pickFromGallery({int limit = 9}) async =>
      <PickedImage>[
        const PickedImage(path: '/tmp/gallery.jpg', name: 'gallery.jpg'),
      ];
}

Widget _wrap(
  _FakeProfileRepository repo, {
  ImagePickerService? picker,
}) => ProviderScope(
  retry: noAutoRetry,
  overrides: [
    useMockProvider.overrideWithValue(true),
    authProvider.overrideWith(FakeAuthenticatedAuthNotifier.new),
    profileRepositoryProvider.overrideWithValue(repo),
    if (picker != null) imagePickerServiceProvider.overrideWithValue(picker),
  ],
  child: const MaterialApp(home: ProfileDetailPage()),
);

void main() {
  group('UserProfile', () {
    test('解析 user/profile 响应', () {
      final UserProfile profile = UserProfile.fromJson(<String, Object?>{
        'id': 16,
        'nickname': '卜幸杰',
        'avatar': 'https://grean-ops.oss-cn-hangzhou.aliyuncs.com/avatar/16.png',
        'title': '主管',
        'company': '浙江绿洁环境科技有限公司',
        'taskCount': 18,
        'opsRecordCount': 7,
        'attendCount': 26,
        'mileageCount': 12,
      });

      expect(profile.id, 16);
      expect(profile.displayName, '卜幸杰');
      expect(profile.taskCount, 18);
      // 我的事件 = 异常 + 巡检 + 签到
      expect(profile.myEventsCount, 51);
    });

    test('空响应不炸，计数回落 0', () {
      final UserProfile profile = UserProfile.fromJson(null);
      expect(profile.myEventsCount, 0);
      expect(profile.displayName, '未命名用户');
    });
  });

  group('个人资料页', () {
    testWidgets('展示资料与工作量统计', (WidgetTester tester) async {
      final _FakeProfileRepository repo = _FakeProfileRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('个人资料'), findsOneWidget);
      expect(find.text('卜幸杰'), findsWidgets);
      expect(find.text('主管'), findsOneWidget);
      expect(find.text('浙江绿洁环境科技有限公司'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);

      // 工作量卡片在首屏之外，先滚到可见再断言
      await tester.scrollUntilVisible(
        find.text('处理异常'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('处理异常'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('巡检'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('签到'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      expect(find.text('里程'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('昵称等信息是只读的，并说明由管理员维护', (WidgetTester tester) async {
      final _FakeProfileRepository repo = _FakeProfileRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('由管理员维护'),
        findsOneWidget,
      );
      // 后端只有改头像接口，页面上不应该出现任何输入框
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('从相册选图后会上传并提示', (WidgetTester tester) async {
      final _FakeProfileRepository repo = _FakeProfileRepository();
      await tester.pumpWidget(
        _wrap(repo, picker: _FakePicker()),
      );
      await tester.pumpAndSettle();

      // 点击区域是头像本身，下面那行只是说明文字
      await tester.tap(find.byType(ProfileAvatar));
      await tester.pumpAndSettle();

      expect(find.text('从相册选择'), findsOneWidget);
      await tester.tap(find.text('从相册选择'));
      await tester.pumpAndSettle();

      expect(repo.updateCalls, 1);
      expect(find.text('头像已更新'), findsOneWidget);
    });

    testWidgets('加载失败给出重试入口', (WidgetTester tester) async {
      final _FakeProfileRepository repo = _FakeProfileRepository(fail: true);
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('资料加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
      expect(repo.updateCalls, 0);
    });
  });
}
