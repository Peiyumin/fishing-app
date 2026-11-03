import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 标记里的白色图形
///
/// v2.1.69 用户口径：**只把渔具店换成小房子**，野钓点 / 收费钓场仍是原来的
/// 小鱼，只是换了颜色 —— 不要整张图统一换图标。
enum SpotPinGlyph { fish, house }

/// 钓点标记：定位针 + 白色图形（小鱼 / 小房子）
///
/// 两套地图内核共用同一份画法：
///   · 原生 MapLibre 内核 —— 画进 PNG 交给原生层当 symbol icon（`addImage`）；
///   · flutter_map 兜底内核 —— 直接当 Widget 用。
///
/// 颜色按钓点身份区分（见 `utils/spot_marker_style.dart`）：
///   绿 = 野钓点 / 红 = 黑坑·鱼塘·收费 / 蓝 = 渔具店；
/// 图形只有渔具店用小房子，其余保持原小鱼。
class SpotPinPainter extends CustomPainter {
  const SpotPinPainter({
    this.color = AppTheme.danger,
    this.glyph = SpotPinGlyph.fish,
  });

  /// 定稿尺寸：所有坐标都按这个「单位画布」写，绘制时等比缩放
  static const double unitW = 120;
  static const double unitH = 156;

  final Color color;
  final SpotPinGlyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / unitW);
    _paintUnit(canvas);
    canvas.restore();
  }

  void _paintUnit(Canvas canvas) {
    const double cx = 60; // 圆头中心 x
    const double cy = 56; // 圆头中心 y
    const double r = 40; // 圆头半径
    const double tipY = 148; // 针尖 y

    // 水滴形：圆头 + 下方收成尖
    final head = Path()
      ..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: r));
    final tail = Path()
      ..moveTo(cx - r * 0.62, cy + r * 0.62)
      ..quadraticBezierTo(cx - r * 0.32, cy + r * 1.28, cx, tipY)
      ..quadraticBezierTo(cx + r * 0.32, cy + r * 1.28, cx + r * 0.62, cy + r * 0.62)
      ..close();
    final pin = Path.combine(PathOperation.union, head, tail);

    // 白色描边：卫星影像背景很花，没有白边会糊成一团
    canvas.drawPath(
        pin,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(pin, Paint()..color = color);

    if (glyph == SpotPinGlyph.house) {
      _paintHouse(canvas, cx, cy);
    } else {
      _paintFish(canvas, cx, cy);
    }
  }

  /// 白色鱼形：椭圆鱼身 + 三角尾鳍（野钓点 / 收费钓场的原图标）
  void _paintFish(Canvas canvas, double cx, double cy) {
    final body = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(cx + 3, cy - 2), width: 42, height: 26));
    final fin = Path()
      ..moveTo(cx - 16, cy - 2)
      ..lineTo(cx - 30, cy - 14)
      ..lineTo(cx - 30, cy + 10)
      ..close();
    canvas.drawPath(
        Path.combine(PathOperation.union, body, fin),
        Paint()..color = Colors.white);
    // 鱼眼（挖回底色）
    canvas.drawCircle(
        Offset(cx + 16, cy - 7), 3.4, Paint()..color = color);
  }

  /// 白色小房子：屋顶 + 墙体一体，门挖回底色（渔具店专用）
  void _paintHouse(Canvas canvas, double cx, double cy) {
    const double roofHalf = 26; // 屋檐半宽
    const double wallHalf = 17; // 墙半宽
    final double roofTop = cy - 25;
    final double eaveY = cy + 1;
    final double baseY = cy + 23;

    final house = Path()
      ..moveTo(cx, roofTop) // 屋脊
      ..lineTo(cx + roofHalf, eaveY)
      ..lineTo(cx + wallHalf, eaveY)
      ..lineTo(cx + wallHalf, baseY)
      ..lineTo(cx - wallHalf, baseY)
      ..lineTo(cx - wallHalf, eaveY)
      ..lineTo(cx - roofHalf, eaveY)
      ..close();
    canvas.drawPath(
      house,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );

    // 门：用底色挖出来，小房子才有「可辨认的门」
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 13), width: 11, height: 20),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant SpotPinPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glyph != glyph;
}

/// 钓点标记 Widget（flutter_map 兜底内核用）
class SpotPin extends StatelessWidget {
  const SpotPin({
    super.key,
    this.width = 30,
    this.height = 39,
    this.color = AppTheme.danger,
    this.glyph = SpotPinGlyph.fish,
  });

  final double width;
  final double height;
  final Color color;
  final SpotPinGlyph glyph;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: SpotPinPainter(color: color, glyph: glyph)),
    );
  }
}
