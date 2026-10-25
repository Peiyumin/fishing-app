import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// App 内置的鱼形绘制器（零网络素材）
///
/// 为什么要自己画：
/// ① 图鉴原来的鱼图走后端图片，弱网/首次进页面就是一片灰块，用户要等；
/// ② 池塘里鱼要**不停地游**、还要甩尾、跃出水面，用位图既糊又不能变形；
/// ③ 后端只有 100 种鱼的图，鱼缸里同种鱼多条，位图会显得完全一样。
///
/// 这里用「鱼种名 → 稳定伪随机参数」把同一套矢量骨架染成不同体型 / 配色 /
/// 花纹：同一条鱼每次进页面长得一样（用名字的哈希，不用 Random），
/// 不同鱼种之间又能明显区分。整套素材就是几十行 Path，包体不增加。
///
/// 视觉分层（从下往上）：身体渐变 → 花纹 → 鳞片 → 侧线 / 鳃盖 → 鳍 →
/// 眼睛 → 背部高光。锁定态直接画成深色剪影，只保留轮廓与鳍。
class FishArt extends StatelessWidget {
  /// 鱼种名（决定体型、配色、花纹）
  final String name;

  /// 稀有度：common / rare / legend —— 只影响光泽与高光强度
  final String rarity;

  /// 水域：fresh 淡水 / salt 海水
  final String waterType;

  /// 绘制高度（宽高按体型比例自动算）
  final double size;

  /// 未点亮：画成深色剪影
  final bool locked;

  /// 动画相位（0~1 循环）：驱动尾鳍摆动与身体行波
  final double phase;

  /// 朝向：true 朝右（默认），false 朝左
  final bool facingRight;

  /// 是否画在水里（水下环境加一层青蓝色滤镜，和池塘色调融合）
  final bool underwater;

  const FishArt({
    super.key,
    required this.name,
    this.rarity = 'common',
    this.waterType = 'fresh',
    this.size = 72,
    this.locked = false,
    this.phase = 0,
    this.facingRight = true,
    this.underwater = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = FishStyle.from(name, rarity: rarity, waterType: waterType);
    // 按体型算宽度（带鱼会长很多），但容器放不下时按宽度等比收缩 ——
    // 图鉴格子只有 60 多宽，硬塞会溢出成黄黑条
    return LayoutBuilder(builder: (ctx, c) {
      var w = size * s.bodyLength;
      var h = size;
      final maxW = c.maxWidth;
      final maxH = c.maxHeight;
      if (maxW.isFinite && w > maxW) {
        h = h * maxW / w;
        w = maxW;
      }
      if (maxH.isFinite && h > maxH) {
        w = w * maxH / h;
        h = maxH;
      }
      return RepaintBoundary(
        child: SizedBox(
          width: w,
          height: h,
          child: CustomPaint(
            painter: _FishPainter(FishDraw(
              style: s,
              locked: locked,
              phase: phase,
              facingRight: facingRight,
              underwater: underwater,
            )),
          ),
        ),
      );
    });
  }
}

/// 由鱼种名派生出的外观参数（同名字恒定）
class FishStyle {
  /// 体型：长 / 高（含鳍的整体外框比例，宽度 = size * bodyLength）
  final double bodyLength;

  /// 身体厚度（占整个高度比例，越大越「高背」）
  final double bodyDepth;

  /// 主色（背部）
  final Color back;

  /// 侧面色
  final Color flank;

  /// 腹色
  final Color belly;

  /// 鳍色
  final Color fin;

  /// 花纹：0 无 / 1 竖带 / 2 斑点 / 3 横带 / 4 网纹
  final int pattern;

  /// 花纹强度 0~1
  final double patternAlpha;

  /// 稀有度光泽 0~1
  final double sheen;

  /// 是否需要画胡须（鲶类）
  final bool whiskers;

  const FishStyle({
    required this.bodyLength,
    required this.bodyDepth,
    required this.back,
    required this.flank,
    required this.belly,
    required this.fin,
    required this.pattern,
    required this.patternAlpha,
    required this.sheen,
    required this.whiskers,
  });

  /// 稳定的字符串哈希（FNV-1a，不受 Dart 版本 hashCode 随机化影响）
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  /// 淡水常见配色（背深、侧亮、腹白）——不同鱼种在这几组里游走 + 微调色相
  static const List<List<int>> _freshPalettes = [
    [0xFF6B5A34, 0xFFB49A5E, 0xFFF0E4C8], // 黄褐（鲫 / 鲤）
    [0xFF4A5A3A, 0xFF8B9B67, 0xFFE8EDD6], // 橄榄（草鱼）
    [0xFF3B4A55, 0xFF7A8B96, 0xFFE3E9EC], // 青灰（鲈 / 鳜）
    [0xFF33302B, 0xFF6E675C, 0xFFD8D2C6], // 墨黑（鲶 / 黑鱼）
    [0xFF7A4B2A, 0xFFC2824A, 0xFFF2DCC0], // 橙褐（鲤变种）
    [0xFF5C6670, 0xFF9AA8B4, 0xFFEDF2F6], // 银灰（白条 / 翘嘴）
    [0xFF4E4136, 0xFF9C8468, 0xFFEADFCB], // 泥褐（黄颡）
  ];

  /// 海水常见配色
  static const List<List<int>> _saltPalettes = [
    [0xFF1F3A5F, 0xFF3F7EA6, 0xFFE6F2F8], // 深蓝（鲷）
    [0xFF3A2C4E, 0xFF7B5E9B, 0xFFEDE6F6], // 紫（石斑）
    [0xFF123C46, 0xFF2E8A93, 0xFFE0F5F6], // 孔雀青（青衣）
    [0xFF4A3520, 0xFFA87C3E, 0xFFF5E7C9], // 金褐（黄鱼）
    [0xFF5A1F26, 0xFFB84B4F, 0xFFF8E1E1], // 朱红（红友）
    [0xFF2A2F36, 0xFF6F7986, 0xFFE7EBEF], // 铁灰（鲅鱼）
  ];

  factory FishStyle.from(
    String name, {
    String rarity = 'common',
    String waterType = 'fresh',
  }) {
    final h = _hash(name);
    final salt = waterType == 'salt';

    // ---- 体型：长身 / 高背 / 细长 三类，再加一点个体差 ----
    // 关键词优先（鲤鱼高背、带鱼细长、鲶鱼头大尾长…）
    // 真实淡水鱼体长:体高约 2.6~3.2，这里 bodyDepth 是半高占比，
    // 0.33 → 全高 0.66，配 bodyLength 1.85 就是约 2.8:1，不再像「圆盘鱼」
    double bodyLength = salt ? 1.95 : 1.85;
    double bodyDepth = salt ? 0.30 : 0.33;

    if (_hasAny(name, const ['带', '鳗', '鳝', '针', '颌针'])) {
      bodyLength = 2.70;
      bodyDepth = 0.15;
    } else if (_hasAny(name, const ['鲶', '鮰', '黄颡', '泥鳅', '胡子'])) {
      bodyLength = 2.15;
      bodyDepth = 0.25;
    } else if (_hasAny(name, const ['鲤', '鲫', '鳊', '鲂', '鳑鲏'])) {
      bodyLength = 1.58;
      bodyDepth = 0.41;
    } else if (_hasAny(name, const ['鲀', '河豚', '翻车'])) {
      bodyLength = 1.20;
      bodyDepth = 0.50;
    } else if (_hasAny(name, const ['鲈', '鳜', '鲅', '鲳'])) {
      bodyLength = 1.72;
      bodyDepth = 0.36;
    } else if (_hasAny(name, const ['鲨', '鳐', '魟'])) {
      bodyLength = 2.40;
      bodyDepth = 0.24;
    }
    // ±6% 的个体差，让同体型的不同鱼不完全一样
    bodyLength *= 0.94 + (h % 13) / 100.0;
    bodyDepth *= 0.94 + ((h >> 5) % 13) / 100.0;

    // ---- 配色 ----
    final palettes = salt ? _saltPalettes : _freshPalettes;
    final p = palettes[(h >> 3) % palettes.length];
    // 色相 ±6° 微调，避免同组配色的鱼看起来一模一样
    final hueShift = ((h >> 11) % 13 - 6).toDouble();
    final back = _shift(Color(p[0]), hueShift);
    final flank = _shift(Color(p[1]), hueShift);
    final belly = _shift(Color(p[2]), hueShift);
    final fin = Color.lerp(flank, back, 0.35)!.withOpacity(0.82);

    // ---- 花纹 ----
    final pattern = (h >> 17) % 5;
    final patternAlpha = 0.16 + ((h >> 19) % 16) / 100.0;

    // ---- 稀有度光泽 ----
    final sheen = switch (rarity) {
      'legend' => 0.95,
      'rare' => 0.62,
      _ => 0.28,
    };

    final whiskers = _hasAny(name, const ['鲶', '鮰', '黄颡', '胡子', '泥鳅']);

    return FishStyle(
      bodyLength: bodyLength,
      bodyDepth: bodyDepth,
      back: back,
      flank: flank,
      belly: belly,
      fin: fin,
      pattern: pattern,
      patternAlpha: patternAlpha,
      sheen: sheen,
      whiskers: whiskers,
    );
  }

  static bool _hasAny(String s, List<String> keys) {
    for (final k in keys) {
      if (s.contains(k)) return true;
    }
    return false;
  }

  /// 在 HSL 空间微调色相（只动 H，避免调出脏色）
  static Color _shift(Color c, double degrees) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withHue((hsl.hue + degrees) % 360).toColor();
  }
}

/// 鱼形绘制器（无状态，可复用）
///
/// 为什么不是直接继承 CustomPainter 画到底：池塘里要同时画十几条鱼，
/// 每条鱼都是独立的角度 / 摆尾相位 / 透明度 / 远近模糊，用 Widget 包十几层
/// CustomPaint 太贵；这里提供「把鱼直接画到任意 Canvas 上」的入口，
/// 池塘那个大画布循环调用即可，一帧只有一次图层合成。
class FishDraw {
  final FishStyle style;
  final bool locked;
  final double phase;
  final bool facingRight;
  final bool underwater;

  FishDraw({
    required this.style,
    this.locked = false,
    this.phase = 0,
    this.facingRight = true,
    this.underwater = false,
  });

  /// 相位换算成弧度（一个周期一趟尾摆）
  double get _t => phase * 2 * math.pi;

  /// 把鱼画进 [box]：鱼身水平居中，尾鳍可能略微超出左边一点
  ///
  /// [opacity] 用于池塘里的远景鱼（半透明更「深」）；
  /// [blur] > 0 时给整条鱼加轻微高斯模糊，模拟水下焦外——这是水下感
  /// 最关键的一层，全清晰的鱼看起来像贴纸。
  void paintInto(
    Canvas canvas,
    Rect box, {
    double opacity = 1.0,
    double blur = 0.0,
  }) {
    final needLayer = opacity < 1.0 || blur > 0;
    if (needLayer) {
      final lp = Paint();
      if (opacity < 1.0) lp.color = Color.fromRGBO(0, 0, 0, opacity);
      if (blur > 0) {
        lp.imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
      }
      canvas.saveLayer(box.inflate(blur * 3), lp);
    }
    canvas.save();
    canvas.translate(box.center.dx, box.center.dy);
    if (!facingRight) canvas.scale(-1, 1);
    // 尾鳍最长到 -0.8，所以整体缩放要留出空间
    canvas.scale(box.width / 1.7, box.height);

    _paintAll(canvas);

    canvas.restore();

    // 水下环境：叠一层青蓝，让鱼和池塘水色融为一体（不是生硬地贴上去）
    if (underwater) {
      canvas.drawRect(
        box,
        Paint()
          ..color = const Color(0xFF1E6B5E).withOpacity(0.09)
          ..blendMode = BlendMode.srcATop,
      );
    }

    if (needLayer) canvas.restore();
  }

  void _paintAll(Canvas canvas) {

    // 身体行波：让整条鱼随相位轻微起伏（不是刚性平移）
    final wave = math.sin(_t) * 0.012;

    final body = _bodyPath(wave);
    final fins = _finPaths(wave);

    // ---------- 1. 鳍（画在身体下面，只露出身体外的部分）----------
    final finPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0.1, -0.1),
        const Offset(-0.6, 0.2),
        locked
            ? [const Color(0xFF9AA6A0), const Color(0xFF7D8A84)]
            : [
                style.fin.withOpacity(0.92),
                style.fin.withOpacity(0.55),
              ],
      );
    for (final f in fins) {
      canvas.drawPath(f, finPaint);
    }
    // 鳍条：细线让鳍不像一块塑料片
    if (!locked) {
      final rayPaint = Paint()
        ..color = style.back.withOpacity(0.18)
        ..strokeWidth = 0.006
        ..style = PaintingStyle.stroke;
      for (final f in fins) {
        canvas.save();
        canvas.clipPath(f);
        for (var i = -3; i <= 3; i++) {
          canvas.drawLine(
            Offset(-0.30, i * 0.012),
            Offset(-0.75, i * 0.055),
            rayPaint,
          );
        }
        canvas.restore();
      }
    }

    // ---------- 2. 身体底色（背深腹浅）----------
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, -0.5),
        const Offset(0, 0.5),
        locked
            ? [const Color(0xFFB7C2BC), const Color(0xFF8C9893)]
            : [style.back, style.flank, style.belly],
        locked ? [0.0, 1.0] : [0.0, 0.55, 1.0],
      );
    canvas.drawPath(body, bodyPaint);

    canvas.save();
    canvas.clipPath(body);

    // ---------- 3. 花纹 ----------
    if (!locked && style.pattern != 0) {
      _paintPattern(canvas, style);
    }

    // ---------- 4. 鳞片 ----------
    if (!locked) _paintScales(canvas, style);

    // ---------- 5. 侧线 ----------
    if (!locked) {
      final lateral = Path()
        ..moveTo(0.40, 0.02)
        ..cubicTo(0.16, -0.02, -0.12, 0.0, -0.44, 0.03);
      canvas.drawPath(
        lateral,
        Paint()
          ..color = style.belly.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.012,
      );
    }

    // ---------- 6. 鳃盖 ----------
    final gill = Path()
      ..moveTo(0.27, -0.30 * style.bodyDepth / 0.5)
      ..cubicTo(0.33, -0.12, 0.33, 0.10, 0.26, 0.28 * style.bodyDepth / 0.5);
    canvas.drawPath(
      gill,
      Paint()
        ..color = (locked ? const Color(0xFF6F7C76) : style.back)
            .withOpacity(0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.010,
    );

    // ---------- 7. 背部高光（水下立体感的关键）----------
    if (!locked) {
      final gloss = Path()
        ..moveTo(0.46, -0.02)
        ..cubicTo(0.38, -0.24 * style.bodyDepth / 0.5, 0.20,
            -0.34 * style.bodyDepth / 0.5, 0.0, -0.33 * style.bodyDepth / 0.5)
        ..cubicTo(-0.18, -0.32 * style.bodyDepth / 0.5, -0.34, -0.18, -0.42,
            -0.10);
      canvas.drawPath(
        gloss,
        Paint()
          ..color = Colors.white.withOpacity(0.10 + style.sheen * 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.028
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.022),
      );
      // 稀有鱼给一层冷光，图鉴里一眼能看出「这条不一般」
      if (style.sheen > 0.5) {
        canvas.drawPath(
          body,
          Paint()
            ..color = const Color(0xFF7FE3D2)
                .withOpacity(0.10 * style.sheen)
            ..blendMode = BlendMode.plus,
        );
      }
    }
    canvas.restore();

    // ---------- 8. 眼睛 ----------
    if (!locked) _paintEye(canvas, style);

    // ---------- 9. 胡须（鲶类）----------
    if (!locked && style.whiskers) {
      final wp = Paint()
        ..color = style.fin.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.012
        ..strokeCap = StrokeCap.round;
      final sway = math.sin(_t + 1.1) * 0.03;
      canvas.drawPath(
        Path()
          ..moveTo(0.48, 0.06)
          ..quadraticBezierTo(0.56, 0.10 + sway, 0.66, 0.20 + sway),
        wp,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0.48, 0.10)
          ..quadraticBezierTo(0.54, 0.18 - sway, 0.62, 0.30 - sway),
        wp,
      );
    }

    // ---------- 10. 嘴 ----------
    canvas.drawPath(
      Path()
        ..moveTo(0.50, 0.045)
        ..quadraticBezierTo(0.44, 0.06, 0.40, 0.045),
      Paint()
        ..color = (locked ? const Color(0xFF5E6B65) : style.back)
            .withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.012
        ..strokeCap = StrokeCap.round,
    );
  }

  /// 身体轮廓：吻部在 (0.5, 0.02)，尾柄在 (-0.5, 0)
  Path _bodyPath(double wave) {
    final d = style.bodyDepth; // 0.20 ~ 0.62
    // 背最高点略靠前，腹最低点略靠后 → 才是鱼的样子，不是椭圆
    final backY = -d * 0.98 + wave;
    final bellyY = d * 0.92 + wave * 0.6;
    return Path()
      ..moveTo(0.50, 0.02)
      ..cubicTo(0.47, -d * 0.52, 0.36, backY, 0.14, backY)
      ..cubicTo(-0.05, backY, -0.20, -d * 0.42, -0.46, -d * 0.20)
      ..lineTo(-0.52, -d * 0.10)
      ..lineTo(-0.52, d * 0.10)
      ..lineTo(-0.46, d * 0.20)
      ..cubicTo(-0.26, d * 0.48, -0.04, bellyY, 0.18, bellyY)
      ..cubicTo(0.38, bellyY, 0.48, d * 0.42, 0.50, 0.02)
      ..close();
  }

  /// 尾鳍 / 背鳍 / 臀鳍 / 胸鳍 / 腹鳍
  List<Path> _finPaths(double wave) {
    final d = style.bodyDepth;
    final swing = math.sin(_t) * 0.10; // 尾摆幅度
    final longTail = style.bodyLength > 2.0;

    // ---- 尾鳍（分叉）----
    final fanW = longTail ? 0.20 : 0.30;
    final fanH = d * (longTail ? 0.55 : 1.05);
    final tail = Path()
      ..moveTo(-0.50, -d * 0.10)
      ..cubicTo(-0.50 - fanW * 0.5, -d * 0.30 + swing * 0.5,
          -0.50 - fanW, -fanH + swing, -0.50 - fanW * 1.05, -fanH * 1.05 + swing)
      ..quadraticBezierTo(-0.50 - fanW * 0.55, swing * 0.6, -0.50 - fanW * 1.05,
          fanH * 1.05 + swing)
      ..cubicTo(-0.50 - fanW, fanH + swing, -0.50 - fanW * 0.5, d * 0.30 + swing * 0.5,
          -0.50, d * 0.10)
      ..close();

    // ---- 背鳍 ----
    final dorsal = Path()
      ..moveTo(0.20, -d * 0.92)
      ..cubicTo(0.06, -d * 1.22, -0.16, -d * 1.16, -0.26, -d * 0.78)
      ..lineTo(-0.26, -d * 0.55)
      ..lineTo(0.20, -d * 0.55)
      ..close();

    // ---- 臀鳍 ----
    final anal = Path()
      ..moveTo(-0.18, d * 0.86)
      ..cubicTo(-0.26, d * 1.30, -0.40, d * 1.20, -0.44, d * 0.72)
      ..close();

    // ---- 胸鳍（随相位前后扒动）----
    final pecSwing = math.sin(_t + math.pi / 2) * 0.03;
    final pectoral = Path()
      ..moveTo(0.22, d * 0.22)
      ..cubicTo(0.12, d * 0.52 + pecSwing, -0.02, d * 0.62 + pecSwing, -0.06,
          d * 0.40 + pecSwing)
      ..cubicTo(0.02, d * 0.24, 0.14, d * 0.18, 0.22, d * 0.22)
      ..close();

    // ---- 腹鳍 ----
    final pelvic = Path()
      ..moveTo(0.06, d * 0.80)
      ..cubicTo(0.00, d * 1.12, -0.12, d * 1.10, -0.14, d * 0.78)
      ..close();

    return [tail, dorsal, anal, pectoral, pelvic];
  }

  /// 花纹：竖带 / 斑点 / 横带 / 网纹
  void _paintPattern(Canvas canvas, FishStyle s) {
    final d = s.bodyDepth;
    final base = s.back.withOpacity(s.patternAlpha);
    final paint = Paint()..color = base;

    switch (s.pattern) {
      case 1: // 竖带（鲈、鳜常见）
        for (var i = 0; i < 5; i++) {
          final x = 0.34 - i * 0.16;
          final band = Path()
            ..moveTo(x, -d)
            ..cubicTo(x - 0.05, -d * 0.4, x - 0.05, d * 0.4, x, d)
            ..lineTo(x - 0.055, d)
            ..cubicTo(x - 0.105, d * 0.4, x - 0.105, -d * 0.4, x - 0.055, -d)
            ..close();
          canvas.drawPath(band, paint);
        }
        break;
      case 2: // 斑点（鳜、石斑）
        final rnd = math.Random(style.bodyLength.hashCode ^ s.pattern);
        for (var i = 0; i < 22; i++) {
          final x = 0.44 - rnd.nextDouble() * 0.86;
          final y = (rnd.nextDouble() - 0.5) * d * 1.7;
          final r = 0.012 + rnd.nextDouble() * 0.022;
          canvas.drawCircle(Offset(x, y), r, paint);
        }
        break;
      case 3: // 横带（侧向亮线）
        for (var i = 0; i < 3; i++) {
          final y = -d * 0.5 + i * d * 0.42;
          canvas.drawRect(
            Rect.fromLTWH(-0.52, y, 1.0, d * 0.10),
            Paint()..color = s.belly.withOpacity(s.patternAlpha * 0.9),
          );
        }
        break;
      case 4: // 网纹（鳞片状交叉）
        final grid = Paint()
          ..color = base.withOpacity(s.patternAlpha * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.008;
        for (var i = -6; i <= 6; i++) {
          canvas.drawLine(
              Offset(-0.5 + i * 0.09, -d), Offset(0.1 + i * 0.09, d), grid);
          canvas.drawLine(
              Offset(0.1 + i * 0.09, -d), Offset(-0.5 + i * 0.09, d), grid);
        }
        break;
    }
  }

  /// 鳞片：沿身体走向画一排排弧线，只在侧腹部显示
  void _paintScales(Canvas canvas, FishStyle s) {
    final d = s.bodyDepth;
    final line = Paint()
      ..color = s.belly.withOpacity(0.11)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.0045;
    // 行：从背到腹（只画侧腹一段，背鳍下方的鳞片本来就看不见）
    for (var row = 0; row < 6; row++) {
      final y = -d * 0.30 + row * d * 0.24;
      // 越靠腹越密（透视上鱼腹鳞片更细）
      final step = 0.085 + row * 0.004;
      for (var x = -0.42; x < 0.34; x += step) {
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(x, y), width: step * 0.95, height: d * 0.30),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          line,
        );
      }
    }
  }

  void _paintEye(Canvas canvas, FishStyle s) {
    final d = s.bodyDepth;
    final c = Offset(0.365, -d * 0.30);
    final r = 0.030 + d * 0.030;
    // 眼白
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF7F4EC));
    // 虹膜
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()..color = Color.lerp(s.back, Colors.black, 0.45)!,
    );
    // 瞳孔（占眼球比例大一些，像真鱼那种「整颗黑」）
    canvas.drawCircle(
        c.translate(0.002, 0), r * 0.62, Paint()..color = const Color(0xFF0B0F0D));
    // 高光（画在左上，光源统一来自上方）
    canvas.drawCircle(
      c.translate(-r * 0.28, -r * 0.32),
      r * 0.20,
      Paint()..color = Colors.white.withOpacity(0.92),
    );
    // 眼眶一圈淡环
    canvas.drawCircle(
      c,
      r * 1.06,
      Paint()
        ..color = s.back.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.008,
    );
  }

}

class _FishPainter extends CustomPainter {
  final FishDraw draw;

  _FishPainter(this.draw);

  @override
  void paint(Canvas canvas, Size size) {
    draw.paintInto(canvas, Rect.fromLTWH(0, 0, size.width, size.height));
  }

  @override
  bool shouldRepaint(_FishPainter old) =>
      old.draw.phase != draw.phase ||
      old.draw.locked != draw.locked ||
      old.draw.facingRight != draw.facingRight ||
      old.draw.style.bodyLength != draw.style.bodyLength ||
      old.draw.style.back != draw.style.back;
}
