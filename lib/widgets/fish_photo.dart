import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/fish_assets.dart';

/// App 内置真实鱼图（透明 PNG）的展示组件
///
/// 图鉴格子、钓鱼档案、池塘放鱼面板都用它。素材在安装包里，
/// 不需要网络，也不会出现「图还没加载出来」的空档。
class FishPhoto extends StatelessWidget {
  final String name;

  /// fresh / salt，仅用于查不到该鱼时的兜底选择
  final String waterType;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// 未点亮的鱼：压成灰色剪影
  final bool locked;

  /// 略微加深色描边阴影，让白底上的银色鱼不至于「糊成一团」
  final bool shadow;

  const FishPhoto({
    super.key,
    required this.name,
    this.waterType = 'fresh',
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.locked = false,
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      FishAssets.pathOrFallback(name, waterType: waterType),
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Icon(Icons.set_meal, color: Color(0xFFB9C4BF)),
        ),
      ),
    );

    Widget child = img;
    if (locked) {
      // 未点亮：灰度 + 降透明，保留真实鱼形，不像卡通图那样「换了个东西」
      child = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.30, 0.59, 0.11, 0, 20, //
          0.30, 0.59, 0.11, 0, 20, //
          0.30, 0.59, 0.11, 0, 20, //
          0, 0, 0, 0.34, 0, //
        ]),
        child: img,
      );
    }
    if (!shadow) return child;
    // 浅色底（图鉴白卡）上，银白色鱼容易糊进背景：垫一层很淡的深色晕影
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.16,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                  Color(0xFF14332A), BlendMode.srcIn),
              child: Image.asset(
                FishAssets.pathOrFallback(name, waterType: waterType),
                width: width,
                height: height,
                fit: fit,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 把内置鱼图预加载成 `ui.Image`，供 Canvas 直接绘制（池塘里几十条鱼用）
class FishImageCache {
  FishImageCache._();

  static final Map<String, ui.Image> _images = {};
  static final Map<String, Future<ui.Image?>> _loading = {};

  static ui.Image? get(String key) => _images[key];

  /// 预载一批鱼名（重复调用只加载一次）
  static Future<void> preload(
      Iterable<String> names, BuildContext context) async {
    for (final n in names) {
      await load(n, context);
    }
  }

  static Future<ui.Image?> load(String name, BuildContext context) {
    final path = FishAssets.pathOrFallback(name);
    final cached = _images[path];
    if (cached != null) return Future.value(cached);
    return _loading.putIfAbsent(path, () async {
      try {
        final data = await DefaultAssetBundle.of(context).load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        _images[path] = frame.image;
        return frame.image;
      } catch (_) {
        return null;
      }
    });
  }

  @visibleForTesting
  static void clear() {
    _images.clear();
    _loading.clear();
  }
}
