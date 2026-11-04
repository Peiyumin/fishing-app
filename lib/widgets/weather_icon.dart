import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/weather_forecast.dart';

/// ============================================================
/// 天气图标（手绘矢量）· v2.1.70
///
/// 为什么不用 Material Icons：
///   · `Icons.grain` / `Icons.opacity` 画的是**点阵**——毛毛雨是一排小点，
///     小雨、中雨也是同一排小点，用户根本分不出强弱；
///   · Material 没有「雷电 + 雨丝」这种组合，`thunderstorm` 自带一朵云，
///     在 18px 的逐时表里糊成一团；
///   · 晴天的月亮 `nightlight_round` 是灰白色（图标本身的形状），
///     用户要的是**黄色月牙**；阴天夜里也没有「灰月亮」的表达。
///
/// 所以这套图标全部自己画，统一规则：
///   雨   = 斜向雨丝，**不分云**（毛毛雨/小雨最细，中雨/大雨/暴雨靠
///          粗细 + 根数逐级加密，一眼能比出大小）
///   雷雨 = 闪电符号 + 雨丝
///   晴   = 日间太阳；夜间**黄色月牙**
///   少云 = 太阳/月牙 + 小云
///   多云 = 云 + 后面露头的太阳/月牙
///   阴   = 厚云；**夜间改成灰色月亮**（用户口径）
///   雪   = 雪花；雾 = 三条雾线
///
/// 画法全部在 0~1 的单位正方形里，再按 size 缩放，
/// 因此 18px（逐时表）到 38px（主卡）都是同一份形状，不会糊。
/// ============================================================
class WeatherGlyph extends StatelessWidget {
  /// WMO 天气代码
  final int? code;

  /// 白天 / 夜间（影响晴、少云、多云、阴的画法）
  final bool day;

  /// 边长（正方形）
  final double size;

  /// 强制指定颜色；不传则用 [Wmo.color] 的通用口径
  final Color? color;

  const WeatherGlyph({
    super.key,
    required this.code,
    this.day = true,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: WeatherGlyphPainter(
          code: code,
          day: day,
          color: color ?? Wmo.color(code, day: day),
        ),
      ),
    );
  }
}

/// 雨的等级规格：根数 / 雨丝长度 / 粗细（单位正方形内的比例）
///
/// 三个值必须**同时**随等级递增，否则「小雨两滴大雨三滴」还是分不清。
class RainSpec {
  final int lines;
  final double length;
  final double width;
  const RainSpec(this.lines, this.length, this.width);
}

/// WMO 代码 → 雨的强度。返回 null 表示这不是雨（雷雨单独走闪电那套）
RainSpec? rainSpecOf(int? code) {
  switch (code) {
    // 毛毛雨：3 根细丝，最短
    case 51:
      return const RainSpec(3, 0.20, 0.045);
    // 小雨（含 53/55 的毛毛雨偏强、61 一般小雨、80 阵雨）
    case 53:
    case 55:
    case 61:
      return const RainSpec(4, 0.26, 0.058);
    case 80:
      return const RainSpec(4, 0.26, 0.065);
    // 冻雨：形态与小雨一致（不用点，避免又变成「小雪粒」的观感）
    case 56:
    case 57:
    case 66:
    case 67:
      return const RainSpec(4, 0.27, 0.06);
    // 中雨
    case 63:
      return const RainSpec(5, 0.31, 0.078);
    // 大雨 / 强阵雨
    case 65:
    case 81:
      return const RainSpec(6, 0.34, 0.086);
    // 暴雨：最多最粗
    case 82:
      return const RainSpec(7, 0.40, 0.094);
    default:
      return null;
  }
}

/// 雷（95/96/99）：闪电 + 雨丝
bool isThunderCode(int? code) =>
    code == 95 || code == 96 || code == 99;

/// 雪（71~77 纯雪 / 85~86 阵雪）
bool isSnowCode(int? code) =>
    code == 71 || code == 73 || code == 75 || code == 77 ||
    code == 85 || code == 86;

/// 雾
bool isFogCode(int? code) => code == 45 || code == 48;

class WeatherGlyphPainter extends CustomPainter {
  final int? code;
  final bool day;
  final Color color;

  const WeatherGlyphPainter({
    required this.code,
    required this.day,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 0) return;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s); // 之后一律用 0~1 坐标

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    _draw(canvas, fill, line);
    canvas.restore();
  }

  void _draw(Canvas cv, Paint fill, Paint line) {
    final c = code;

    // ---------- 雷阵雨：闪电 + 雨丝 ----------
    if (isThunderCode(c)) {
      _thunder(cv, fill);
      return;
    }

    // ---------- 雨：只有雨丝，等级靠粗细/密度 ----------
    final spec = rainSpecOf(c);
    if (spec != null) {
      _rain(cv, spec);
      return;
    }

    // ---------- 雪 ----------
    if (isSnowCode(c)) {
      _snow(cv, line, 0.5, 0.5, 0.34);
      return;
    }

    // ---------- 雾 ----------
    if (isFogCode(c)) {
      _fog(cv, line);
      return;
    }

    switch (c) {
      case 0: // 晴：太阳 / 黄色月牙
        if (day) {
          _sun(cv, fill, line, const Offset(0.5, 0.5), 0.22, 0.10);
        } else {
          _moon(cv, fill, const Offset(0.48, 0.5), 0.34);
        }
        return;
      case 1: // 少云：太阳/月牙 + 小云
        if (day) {
          _sun(cv, fill, line, const Offset(0.40, 0.40), 0.19, 0.085);
        } else {
          _moon(cv, fill, const Offset(0.40, 0.40), 0.27);
        }
        cv.drawPath(_cloud(0.80, const Offset(0.14, 0.16)), fill);
        return;
      case 2: // 多云：云 + 后面露头的太阳/月牙
        if (day) {
          _sun(cv, fill, line, const Offset(0.70, 0.28), 0.145, 0.075);
        } else {
          _moon(cv, fill, const Offset(0.73, 0.25), 0.21);
        }
        cv.drawPath(_cloud(0.92, const Offset(0.0, 0.06)), fill);
        return;
      case 3: // 阴：日间一朵厚云；夜间灰色月亮（用户口径）
        if (day) {
          cv.drawPath(_cloud(1.0, const Offset(0.0, 0.02)), fill);
        } else {
          _moon(cv, fill, const Offset(0.5, 0.5), 0.34);
        }
        return;
      default:
        // 未知：空心圆 + 中心点（比问号更耐看，也不会被系统字体吞掉）
        cv.drawCircle(const Offset(0.5, 0.5), 0.30, line..strokeWidth = 0.075);
        cv.drawCircle(const Offset(0.5, 0.5), 0.055, fill);
        return;
    }
  }

  // ─────────────────────────── 雨丝 ───────────────────────────

  /// 斜向雨丝：从右上到左下（风把雨吹斜的观感），奇偶交错避免像栅栏
  void _rain(Canvas cv, RainSpec spec) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = spec.width
      ..isAntiAlias = true;

    const span = 0.60; // 横向铺开范围
    final gap = spec.lines > 1 ? span / (spec.lines - 1) : 0.0;
    const x0 = 0.5 - span / 2;
    final y0 = 0.5 - spec.length / 2 - 0.02;

    for (var i = 0; i < spec.lines; i++) {
      final x = x0 + gap * i;
      // 交错 4%：密的时候不会连成一片
      final dy = i.isEven ? 0.0 : 0.075;
      cv.drawLine(
        Offset(x, y0 + dy),
        Offset(x - spec.length * 0.26, y0 + dy + spec.length),
        p,
      );
    }
  }

  // ─────────────────────────── 闪电 + 雨丝 ───────────────────────────

  void _thunder(Canvas cv, Paint fill) {
    // 闪电偏左，右侧留出雨丝的位置 —— 18px 下两者都不至于被挤掉
    final bolt = Path()
      ..moveTo(0.44, 0.05)
      ..lineTo(0.09, 0.53)
      ..lineTo(0.28, 0.53)
      ..lineTo(0.18, 0.95)
      ..lineTo(0.56, 0.41)
      ..lineTo(0.36, 0.41)
      ..close();
    cv.drawPath(bolt, fill);

    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.062
      ..isAntiAlias = true;
    for (var i = 0; i < 3; i++) {
      final x = 0.74 + i * 0.085;
      final y0 = 0.24 + (i.isEven ? 0.0 : 0.07);
      cv.drawLine(Offset(x, y0), Offset(x - 0.05, y0 + 0.25), p);
    }
  }

  // ─────────────────────────── 太阳 / 月亮 / 云 ───────────────────────────

  void _sun(Canvas cv, Paint fill, Paint line, Offset c, double r,
      double ray) {
    cv.drawCircle(c, r, fill);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.065
      ..isAntiAlias = true;
    const gap = 0.055;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final dir = Offset(math.cos(a), math.sin(a));
      cv.drawLine(c + dir * (r + gap), c + dir * (r + gap + ray), p);
    }
  }

  /// 月牙：大圆减去偏右上的小圆（Path.combine difference）
  void _moon(Canvas cv, Paint fill, Offset c, double r) {
    final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final inner = Path()
      ..addOval(Rect.fromCircle(
        center: c + Offset(r * 1.18, -r * 0.79),
        radius: r * 0.97,
      ));
    cv.drawPath(Path.combine(PathOperation.difference, outer, inner), fill);
  }

  /// 云：三个圆 + 一个圆角矩形，同色填充自然连成一片
  Path _cloud(double scale, Offset shift) {
    final p = Path();
    p.addRRect(RRect.fromLTRBR(
        0.10, 0.50, 0.90, 0.74, const Radius.circular(0.12)));
    p.addOval(Rect.fromCircle(center: const Offset(0.34, 0.52), radius: 0.15));
    p.addOval(Rect.fromCircle(center: const Offset(0.55, 0.44), radius: 0.19));
    p.addOval(Rect.fromCircle(center: const Offset(0.75, 0.54), radius: 0.13));
    final m = Matrix4.identity()
      ..translate(shift.dx, shift.dy)
      ..scale(scale, scale);
    return p.transform(m.storage);
  }

  // ─────────────────────────── 雪花 / 雾 ───────────────────────────

  void _snow(Canvas cv, Paint line, double cx, double cy, double r) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.065
      ..isAntiAlias = true;
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi / 3;
      final dir = Offset(math.cos(a), math.sin(a));
      cv.drawLine(Offset(cx, cy) - dir * r, Offset(cx, cy) + dir * r, p);
    }
    // 每个主枝上挑两个小分叉（18px 下会糊成小毛刺，但整体仍读作雪花）
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi / 3;
      final dir = Offset(math.cos(a), math.sin(a));
      final back = Offset(cx, cy) + dir * (r * 0.62);
      for (final sign in [-1.0, 1.0]) {
        final b = a + sign * 0.9;
        final bd = Offset(math.cos(b), math.sin(b));
        cv.drawLine(back, back + bd * (r * 0.30), p);
      }
    }
  }

  void _fog(Canvas cv, Paint line) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.075
      ..isAntiAlias = true;
    cv.drawLine(const Offset(0.10, 0.34), const Offset(0.90, 0.34), p);
    cv.drawLine(const Offset(0.18, 0.52), const Offset(0.82, 0.52), p);
    cv.drawLine(const Offset(0.08, 0.70), const Offset(0.72, 0.70), p);
  }

  @override
  bool shouldRepaint(WeatherGlyphPainter oldDelegate) =>
      oldDelegate.code != code ||
      oldDelegate.day != day ||
      oldDelegate.color != color;
}
