import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/image_picker_service.dart';
import '../../../../core/media/upload_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/api_response.dart';
import '../models/user_profile.dart';

/// 个人资料与头像（M9-01）。
///
/// 读取走 `GET user/profile`；写入**只有头像**一条路径：
/// 先 `upload/3/file` 传图拿 objectKey，再 `POST user/update_avatar {avatar: key}`。
/// 昵称、职务、公司后端没有更新接口，页面按只读处理。
abstract class ProfileRepository {
  /// [userId] 为空读自己（`user/profile`），
  /// 否则读他人资料（`user/{id}/profile`，用户资料库详情用）。
  Future<UserProfile> fetchProfile({int? userId});

  /// 上传并设置头像，成功后返回最新资料。
  Future<UserProfile> updateAvatar(PickedImage image);
}

class RemoteProfileRepository implements ProfileRepository {
  const RemoteProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<UserProfile> fetchProfile({int? userId}) async {
    final ApiResponse response = await _api.getRaw(
      userId == null ? 'user/profile' : 'user/$userId/profile',
    );
    return UserProfile.fromJson(response.data);
  }

  @override
  Future<UserProfile> updateAvatar(PickedImage image) async {
    // 头像单独一套前缀（`avatar/`），与业务图片（`task/`、`ops/`）分开归档。
    final String key = await UploadService(
      _api,
    ).uploadImage(image, kind: UploadKind.avatar);
    await _api.postRaw('user/update_avatar', data: <String, Object?>{'avatar': key});
    return fetchProfile();
  }
}

/// 演示实现：头像改完在本次运行内可见。
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  static UserProfile _profile = const UserProfile(
    id: 1001,
    nickname: '张伟',
    avatar: '',
    title: '运维工程师',
    company: '浙江绿洁环境科技有限公司',
    taskCount: 18,
    opsRecordCount: 7,
    attendCount: 26,
    mileageCount: 12,
  );

  @override
  Future<UserProfile> fetchProfile({int? userId}) async {
    await Future<void>.delayed(delay);
    return _profile;
  }

  @override
  Future<UserProfile> updateAvatar(PickedImage image) async {
    await Future<void>.delayed(delay);
    // 演示环境没有 OSS，直接用本地文件路径当「头像地址」，
    // 页面用 `Image.file` 也能正常显示，不需要真的上传。
    _profile = _profile.copyWith(avatar: image.path);
    return _profile;
  }
}

final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>((Ref ref) {
      if (ref.watch(useMockProvider)) return MockProfileRepository();
      return RemoteProfileRepository(ref.watch(apiClientProvider));
    });

/// key = 用户 id 字符串；空串代表当前登录用户自己（`user/profile`）。
/// 其他用户走 `user/{id}/profile`（用户资料库详情）。
final userProfileProvider = FutureProvider.family<UserProfile, String>((
  Ref ref,
  String userId,
) => ref.watch(profileRepositoryProvider).fetchProfile(
      userId: userId.isEmpty ? null : int.tryParse(userId),
    ));
