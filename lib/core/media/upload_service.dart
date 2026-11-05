import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/api_providers.dart';
import '../network/api_response.dart';
import 'image_picker_service.dart';

/// 上传类型，对应后端 `com.grean.ops.model.enums.UploadEnum`。
///
/// 服务端用这个值决定 OSS 目录前缀（`task/`、`ops/`、`pin/`…），传错不会报错，
/// 只会把照片存到别的前缀下，后续按业务归档时会找不到。
enum UploadKind {
  task(1, 'task/'),
  helpDoc(2, 'help/'),
  avatar(3, 'avatar/'),
  ops(4, 'ops/'),
  pin(5, 'pin/'),
  checkIn(6, 'check/'),
  setting(7, 'setting/'),
  form(8, 'form/');

  const UploadKind(this.code, this.prefix);

  final int code;
  final String prefix;
}

/// 图片上传（M0-06）。
///
/// 走 **后端代传**：`POST upload/{type}/file`，服务端接收 multipart 后自己写 OSS，
/// 返回 objectKey（如 `task/2026-11-05/xxxx/IMG_0001.jpg`）。
///
/// 为什么不用 iOS 那套 OSS STS 直传：
/// 1. 直传要引 aliyun_oss_flutter，多一份原生依赖和凭证过期处理；
/// 2. 后端接口已经做了同样的落库与前缀归档，直传反而绕过了服务端逻辑；
/// 3. 客户端拿到的 objectKey 与列表接口返回的 `PictureBO.picture` 同构，
///    提交时原样传回即可，展示时用后端给的完整 `url`，客户端不必知道 OSS 域名。
class UploadService {
  const UploadService(this._api);

  final ApiClient _api;

  /// 最大允许上传的图片数量，与后端/原 iOS 保持一致。
  static const int maxImages = 9;

  Future<String> uploadImage(
    PickedImage image, {
    UploadKind kind = UploadKind.task,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final FormData form = FormData.fromMap(<String, Object?>{
      'file': await MultipartFile.fromFile(
        image.path,
        filename: image.name,
        contentType: DioMediaType('image', _extensionOf(image.name)),
      ),
    });

    final ApiResponse response = await _api.postRaw(
      'upload/${kind.code}/file',
      data: form,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
    );

    final Object? data = response.data;
    final String key = data is String ? data.trim() : '';
    if (key.isEmpty) {
      throw const AppException('上传返回为空，请重试', kind: ApiErrorKind.parse);
    }
    return key;
  }

  /// 批量上传，任意一张失败即中断并把已成功的 key 带出去，
  /// 便于页面在重试时只补传失败的那几张。
  Future<List<String>> uploadAll(
    List<PickedImage> images, {
    UploadKind kind = UploadKind.task,
    CancelToken? cancelToken,
    void Function(int index, int total, double progress)? onProgress,
  }) async {
    final List<String> keys = <String>[];
    for (int i = 0; i < images.length; i++) {
      final int index = i;
      final String key = await uploadImage(
        images[index],
        kind: kind,
        cancelToken: cancelToken,
        onProgress: (int sent, int total) => onProgress?.call(
          index,
          images.length,
          total <= 0 ? 0 : sent / total,
        ),
      );
      keys.add(key);
    }
    return keys;
  }

  static String _extensionOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'jpeg';
    final String ext = name.substring(dot + 1).toLowerCase();
    return ext == 'jpg' ? 'jpeg' : ext;
  }
}

final Provider<UploadService> uploadServiceProvider = Provider<UploadService>(
  (Ref ref) => UploadService(ref.watch(apiClientProvider)),
);
