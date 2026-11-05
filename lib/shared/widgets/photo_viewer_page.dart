import 'dart:io';

import 'package:flutter/material.dart';


/// 图片全屏预览：左右滑动切换、双指/双击缩放、下滑关闭。
///
/// 没有引 photo_view：需求只有「能放大看清水印和数值」，InteractiveViewer
/// 已足够，少一个依赖就少一份升级风险。
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.title,
  });

  /// 本地文件路径或网络 URL。
  final List<String> images;
  final int initialIndex;
  final String? title;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int total = widget.images.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title ?? (total > 1 ? '${_index + 1} / $total' : '查看图片'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: total,
        onPageChanged: (int i) => setState(() => _index = i),
        itemBuilder: (BuildContext context, int i) => _ZoomableImage(
          source: widget.images[i],
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.source});

  final String source;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _transformation = TransformationController();

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformation.value.getMaxScaleOnAxis() > 1.05) {
      _transformation.value = Matrix4.identity();
    } else {
      _transformation.value = Matrix4.diagonal3Values(2.4, 2.4, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRemote =
        widget.source.startsWith('http://') ||
        widget.source.startsWith('https://');
    final ImageProvider provider = isRemote
        ? NetworkImage(widget.source)
        : FileImage(File(widget.source));

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformation,
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext context, Object error, StackTrace? s) =>
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
            loadingBuilder:
                (
                  BuildContext context,
                  Widget child,
                  ImageChunkEvent? progress,
                ) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white70,
                      ),
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }
}
