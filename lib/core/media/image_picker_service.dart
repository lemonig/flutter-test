import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// 一张已选中的本地图片。
///
/// 只持有路径，不预读字节 —— 9 张原图常驻内存会直接把低端机拖崩。
class PickedImage {
  const PickedImage({required this.path, required this.name});

  final String path;
  final String name;

  File get file => File(path);

  bool get exists => File(path).existsSync();

  int get sizeBytes {
    final File f = File(path);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  String get sizeLabel {
    final int bytes = sizeBytes;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  @override
  bool operator ==(Object other) => other is PickedImage && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// 相机 / 相册取图。
///
/// 统一在这里压到 1600px / 质量 82：后端校验不管体积，但现场照片动辄 5MB，
/// 九张就是 45MB，4G 下上传体验不可接受。
class ImagePickerService {
  ImagePickerService({ImagePicker? picker, this.maxWidth = 1600, this.quality = 82})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final double maxWidth;
  final int quality;

  Future<List<PickedImage>> pickFromGallery({int limit = 9}) async {
    if (limit <= 0) return <PickedImage>[];
    final List<XFile> files = await _picker.pickMultiImage(
      imageQuality: quality,
      maxWidth: maxWidth,
      limit: limit,
    );
    return files.take(limit).map(_toPicked).toList(growable: false);
  }

  Future<PickedImage?> pickFromCamera() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: quality,
      maxWidth: maxWidth,
    );
    return file == null ? null : _toPicked(file);
  }

  PickedImage _toPicked(XFile file) => PickedImage(
    path: file.path,
    name: file.name.isEmpty ? 'image.jpg' : file.name,
  );
}

/// 图片来源：拍照 or 相册。
///
/// 定义在服务层，头像（单图）与九宫格（多图）共用同一个枚举，
/// 之前放在 `image_picker_grid.dart` 里，头像页要用就得反向依赖 UI 组件。
enum ImageSourceChoice { camera, gallery }

/// 供页面注入/测试替换；默认实现走系统相册与相机。
final Provider<ImagePickerService> imagePickerServiceProvider =
    Provider<ImagePickerService>((Ref ref) => ImagePickerService());
