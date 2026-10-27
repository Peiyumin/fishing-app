import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/screens/pond_screen.dart';

/// 池塘「可拉近观看」（360 环视）的边界数学
///
/// 用户要求：池塘画面能像全景一样双指放大、拖动看鱼，但**不能拖出白边**。
/// 这里把 `PondView.clampPan` 的约束锁住；手势本身靠真机手感验收。
void main() {
  const size = Size(390, 844);

  test('1 倍时只能停在原点（不然画面会跑偏）', () {
    expect(PondView.clampPan(const Offset(50, -30), 1, size), Offset.zero);
  });

  test('放大后平移被夹在「刚好铺满」的范围里', () {
    const zoom = 2.0;
    // 想往右拖过头 → 夹到 0
    expect(PondView.clampPan(const Offset(120, 0), zoom, size).dx, 0);
    // 想往左拖过头 → 夹到 -(w*(zoom-1))
    expect(PondView.clampPan(const Offset(-9999, -9999), zoom, size),
        Offset(-390, -844));
    // 范围内的值原样保留
    expect(PondView.clampPan(const Offset(-100, -200), zoom, size),
        const Offset(-100, -200));
  });

  test('任何缩放/平移下，可见区域都不会露出画面外', () {
    for (final zoom in [1.0, 1.3, 2.0, 2.6, 3.0]) {
      for (final raw in const [
        Offset(0, 0),
        Offset(-500, -500),
        Offset(500, 500),
        Offset(-77, 33),
      ]) {
        final p = PondView.clampPan(raw, zoom, size);
        // 场景映射到屏幕： [p, p + zoom*size] 必须覆盖 [0, size]
        expect(p.dx, lessThanOrEqualTo(0.01));
        expect(p.dy, lessThanOrEqualTo(0.01));
        expect(p.dx + zoom * size.width,
            greaterThanOrEqualTo(size.width - 0.01));
        expect(p.dy + zoom * size.height,
            greaterThanOrEqualTo(size.height - 0.01));
      }
    }
  });

  test('最大倍数不超过 3 倍（底图 1024px，再放就成马赛克）', () {
    expect(PondScreen.maxZoom, 3.0);
  });
}
