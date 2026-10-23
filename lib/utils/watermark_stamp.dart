import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 水印的一行文字
class WatermarkLine {
  final String text;
  final double size;
  final FontWeight weight;
  final Color color;

  /// 与下一行的间距
  final double gap;

  const WatermarkLine(
    this.text,
    this.size,
    this.weight,
    this.color, [
    this.gap = 0,
  ]);
}

/// 把水印文字直接画进照片像素里，返回 PNG 字节。
///
/// 为什么不用「控件树 + RepaintBoundary 截图」：
///   - 依赖界面尺寸，不同机型出来的水印大小不一样；
///   - 需要先把图片渲染上屏才截得到，多一帧、多一次整屏重绘。
/// 这里直接 Canvas 画：输入输出都是字节，逻辑可单测、可跨端复用。
///
/// [maxSide] 限制长边像素（PNG 无损，原图直出会到 8MB+）。
Future<Uint8List> stampWatermarkPng(
  Uint8List srcBytes,
  List<WatermarkLine> lines, {
  int maxSide = 1440,
}) async {
  final codec = await ui.instantiateImageCodec(srcBytes);
  final frame = await codec.getNextFrame();
  final ui.Image src = frame.image;
  try {
    final int longest = math.max(src.width, src.height);
    final double k = longest > maxSide ? maxSide / longest : 1.0;
    final int w = math.max(1, (src.width * k).round());
    final int h = math.max(1, (src.height * k).round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );

    // 底部渐隐，压住白字
    final double gTop = h * 0.58;
    canvas.drawRect(
      Rect.fromLTWH(0, gTop, w.toDouble(), h - gTop),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, gTop),
          Offset(0, h.toDouble()),
          [const Color(0x00000000), const Color(0xD9000000)],
          [0.0, 1.0],
        ),
    );

    // 以 375 逻辑宽为基准缩放字号
    final double base = w / 375.0;
    final double padding = w * 0.055;

    final painters = <TextPainter>[];
    double blockH = 0;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final tp = TextPainter(
        text: TextSpan(
          text: l.text,
          style: TextStyle(
            fontSize: (l.size * base).clamp(10.0, 120.0),
            fontWeight: l.weight,
            color: l.color,
            height: 1.28,
            shadows: const [
              Shadow(
                  color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: w - padding * 2);
      painters.add(tp);
      blockH += tp.height;
      if (i < lines.length - 1) blockH += l.gap * base;
    }

    double y = h - h * 0.052 - blockH;
    for (var i = 0; i < painters.length; i++) {
      painters[i].paint(canvas, Offset(padding, y));
      y += painters[i].height + lines[i].gap * base;
      painters[i].dispose();
    }

    final pic = recorder.endRecording();
    final out = await pic.toImage(w, h);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (bytes == null) throw Exception('水印合成失败');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    src.dispose();
  }
}
