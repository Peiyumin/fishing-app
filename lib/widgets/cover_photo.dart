import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 渔获详情页封面图（v2.1.54）
///
/// 之前的问题是：`BoxFit.cover` 默认**居中裁切**，竖拍的渔获照比封面框高得多，
/// 上下各被切掉一大块 —— 而水印（时间·天气·钓况·钓点）恰好盖在**左上角**，
/// 于是用户上传的照片里，水印第一行永远看不到。
///
/// 现在的规则（用户原话：「以图片的顶部为准开始显示，显示 2/3」）：
///   1. 图片顶边对齐封面顶边（`alignment: topCenter`），只露上面 2/3；
///   2. 封面框整体加高，顶部额外留出「状态栏 + 工具条」的高度，
///      这段用同一张图模糊压暗铺底（不像套黑框），
///      保证水印落在状态栏下方而不是被 iOS 时钟压住；
///   3. 点一下进全屏查看完整图片（由调用方接）。
class CoverPhoto extends StatefulWidget {
  const CoverPhoto({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.topBarHeight = 0,
    this.onTap,
    this.onAspect,
    this.providerBuilder,
  });

  final String url;

  /// 封面宽度（= 屏宽）
  final double width;

  /// 封面总高度（含 [topBarHeight]），由 [visibleHeight] 算好后传进来
  final double height;

  /// 顶部「状态栏 + 工具条」占的高度，这块只铺模糊底、不放照片
  final double topBarHeight;

  final VoidCallback? onTap;

  /// 解析出原图宽高比（高/宽）后回调，调用方用 [visibleHeight] 重算高度
  final ValueChanged<double>? onAspect;

  /// 仅供测试注入（默认走 CachedNetworkImageProvider）
  final ImageProvider Function(String url)? providerBuilder;

  /// 图片区可视高度：顶对齐，只露上面 [fraction]；横图/方图整张显示
  ///
  /// 纯函数，单测直接调，不用起渲染。
  static double visibleHeight({
    required double width,
    required double aspect, // 原图 高/宽
    required double screenHeight,
    double fraction = 2 / 3,
  }) {
    final full = width * aspect;
    // 横图（高比宽小）整张给出来；竖拍才按 2/3 裁
    final want = aspect < .9 ? full : full * fraction;
    final minH = width * .72;
    final maxH = screenHeight * .62;
    final lo = minH > maxH ? maxH : minH;
    return want.clamp(lo, maxH);
  }

  @override
  State<CoverPhoto> createState() => _CoverPhotoState();
}

class _CoverPhotoState extends State<CoverPhoto> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _provider = _makeProvider();
    _resolve();
  }

  @override
  void didUpdateWidget(CoverPhoto old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _detach();
      _provider = _makeProvider();
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  ImageProvider _makeProvider() {
    final b = widget.providerBuilder;
    return b != null ? b(widget.url) : CachedNetworkImageProvider(widget.url);
  }

  /// 先解一次尺寸：拿到原图宽高比才能算「2/3 有多高」
  void _resolve() {
    final p = _provider;
    if (p == null) return;
    try {
      final s = p.resolve(ImageConfiguration.empty);
      _stream = s;
      final l = ImageStreamListener(
        (info, _) {
          final w = info.image.width;
          final h = info.image.height;
          if (w <= 0 || h <= 0) return;
          widget.onAspect?.call(h / w);
        },
        onError: (_, __) {
          // 图裂了就算了，封面照旧显示占位色块，不往上抛异常
        },
      );
      _listener = l;
      s.addListener(l);
    } catch (_) {
      // 解析失败不影响布局（会一直用父级给的兜底高度）
    }
  }

  void _detach() {
    final s = _stream;
    final l = _listener;
    if (s != null && l != null) {
      try {
        s.removeListener(l);
      } catch (_) {}
    }
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final top = widget.topBarHeight;
    final photoH = (widget.height - top).clamp(120.0, 4000.0);
    final p = _provider;

    return SizedBox(
      width: w,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ① 顶部一条「模糊延续」：让水印落在状态栏下面，又不切出黑边
          if (top > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top,
              child: _topBar(p),
            ),
          // ② 照片本体：顶边对齐，只露上面 2/3
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: photoH,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: _photo(p, photoH),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(ImageProvider? p) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppTheme.inkBg),
          if (p != null)
            // 模糊的同图铺底：像照片向上延伸出去，不是一个黑框
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Image(
                image: p,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xC707080C), Color(0x9907080C)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(ImageProvider? p, double h) {
    if (p == null) {
      return const ColoredBox(
        color: AppTheme.primarySoft,
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 32, color: AppTheme.textSecondary),
        ),
      );
    }
    return Image(
      image: p,
      width: widget.width,
      height: h,
      fit: BoxFit.cover,
      // ★ 顶对齐：宽铺满后**只裁底部**，水印在顶上，永远不会被裁掉
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, syncLoaded) {
        if (syncLoaded || frame != null) return child;
        return const ColoredBox(color: AppTheme.primarySoft);
      },
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: AppTheme.primarySoft,
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 32, color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}
