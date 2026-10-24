import 'package:flutter/material.dart';

/// 钓点标记：红色定位针 + 白色鱼形
///
/// 两套地图内核共用同一份画法：
///   · 原生 MapLibre 内核 —— 画进 PNG 交给原生层当 symbol icon（`addImage`）；
///   · flutter_map 兜底内核 —— 直接当 Widget 用。
/// 之前两边的钓点样式是各写各的（一个是 5.5px 红圆点，一个是
/// `Icons.location_on`），既不一致也不好认，统一到这里。
class SpotPinPainter extends CustomPainter {
  const SpotPinPainter();

  /// 定稿尺寸：所有坐标都按这个「单位画布」写，绘制时等比缩放
  static const double unitW = 120;
  static const double unitH = 156;

  static const Color pinColor = Color(0xFFE53935);

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
      ..quadraticBezierTo(
          cx - r * 0.32, cy + r * 1.28, cx, tipY)
      ..quadraticBezierTo(
          cx + r * 0.32, cy + r * 1.28, cx + r * 0.62, cy + r * 0.62)
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
    canvas.drawPath(pin, Paint()..color = pinColor);

    // 白色鱼形：椭圆鱼身 + 三角尾鳍
    final body = Path()
      ..addOval(Rect.fromCenter(
          center: const Offset(cx + 3, cy - 2), width: 42, height: 26));
    final fin = Path()
      ..moveTo(cx - 16, cy - 2)
      ..lineTo(cx - 30, cy - 14)
      ..lineTo(cx - 30, cy + 10)
      ..close();
    canvas.drawPath(
        Path.combine(PathOperation.union, body, fin),
        Paint()..color = Colors.white);
    // 鱼眼（挖回红色）
    canvas.drawCircle(
        const Offset(cx + 16, cy - 7), 3.4, Paint()..color = pinColor);
  }

  @override
  bool shouldRepaint(covariant SpotPinPainter oldDelegate) => false;
}

/// 钓点标记 Widget（flutter_map 兜底内核用）
class SpotPin extends StatelessWidget {
  const SpotPin({super.key, this.width = 30, this.height = 39});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const CustomPaint(painter: SpotPinPainter()),
    );
  }
}
