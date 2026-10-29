import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全屏看完整渔获图（v2.1.54）
///
/// 详情页封面按「顶对齐只露 2/3」显示，一定会裁掉下半张；
/// 用户要求「点图片能看完整的」，所以这里给一个黑底全屏查看器：
///   · 整张图按 contain 显示，一个字都不裁；
///   · 双指缩放 / 双击放大 2.5 倍 / 放大后拖动；
///   · 多图可左右翻页，右上角显示 x/n；
///   · 点右上角关闭，或点上方空白处返回。
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.providerBuilder,
  });

  final List<String> urls;
  final int initialIndex;

  /// 仅供测试注入
  final ImageProvider Function(String url)? providerBuilder;

  /// 打开全屏查看（index 越界会自动夹到合法范围）
  static Future<void> open(
    BuildContext context,
    List<String> urls, {
    int index = 0,
    ImageProvider Function(String url)? providerBuilder,
  }) {
    if (urls.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          urls: urls,
          initialIndex: index,
          providerBuilder: providerBuilder,
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pc;
  late int _index;

  @override
  void initState() {
    super.initState();
    final n = widget.urls.length;
    _index = widget.initialIndex.clamp(0, n <= 0 ? 0 : n - 1);
    _pc = PageController(initialPage: _index);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _ZoomablePhoto(
              key: ValueKey(urls[i]),
              url: urls[i],
              providerBuilder: widget.providerBuilder,
            ),
          ),
          // 顶部渐变 + 关闭 + 计数
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: Container(
                height: top + 64,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: top + 6,
            child: _roundBtn(Icons.close_rounded, () => Navigator.of(context).pop()),
          ),
          if (urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              top: top + 14,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1} / ${urls.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: const IgnorePointer(
              child: Center(
                child: Text(
                  '双指缩放 · 双击放大 · 左右滑动看其他照片',
                  style: TextStyle(fontSize: 11.5, color: Color(0x99FFFFFF)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// 单张图：contain 完整显示 + 缩放
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.url,
    this.providerBuilder,
  });

  final String url;
  final ImageProvider Function(String url)? providerBuilder;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _tc = TransformationController();
  TapDownDetails? _lastTap;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// 双击：放大 2.5 倍 / 复原（在双击点附近放大，手感自然）
  void _onDoubleTap() {
    if (_tc.value.getMaxScaleOnAxis() > 1.05) {
      _tc.value = Matrix4.identity();
      return;
    }
    final p = _lastTap?.localPosition;
    if (p == null) {
      _tc.value = Matrix4.identity()..scale(2.5);
      return;
    }
    const s = 2.5;
    _tc.value = Matrix4.identity()
      ..translate(-p.dx * (s - 1), -p.dy * (s - 1))
      ..scale(s);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.providerBuilder;
    final ImageProvider provider =
        b != null ? b(widget.url) : CachedNetworkImageProvider(widget.url);
    return GestureDetector(
      onDoubleTapDown: (d) => _lastTap = d,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 5,
        panEnabled: true,
        child: SizedBox.expand(
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0x66FFFFFF)),
                ),
              );
            },
            errorBuilder: (_, __, ___) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined,
                      size: 34, color: Color(0x88FFFFFF)),
                  SizedBox(height: 8),
                  Text('图片加载失败',
                      style: TextStyle(fontSize: 12.5, color: Color(0x88FFFFFF))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
