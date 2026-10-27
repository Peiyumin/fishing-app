// 风的口径（v2.1.36）：界面只说「几级 + 什么风」，不再出现 km/h / m/s。
//
// 为什么要有这条测试：
//   ① 这个换算以前散落在三处 —— 天气页私有 `_beaufort`（只到 8 级）、
//      首页直接写 km/h、详情页写 m/s。同一个 18km/h 在三页是三种写法，
//      用户拿首页卡对照天气页就会以为「数据不一样」。
//   ② 现在统一走 beaufortLevel / windLevelText，边界值一旦被改错
//      （比如 12km/h 到底算 2 级还是 3 级），三页会一起错，很难靠肉眼发现。
//
// 蒲福风级（km/h 档）：0:<1 1:1-5 2:6-11 3:12-19 4:20-28 5:29-38
//                     6:39-49 7:50-61 8:62-74 9:75-88 10:89-102 11:103-117 12:>=118
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/weather_forecast.dart';

void main() {
  group('beaufortLevel 按蒲福标准换算', () {
    test('每一档的下边界恰好进位、上边界还留在原级', () {
      const cases = <(double, int)>[
        (0.0, 0), (0.9, 0),
        (1.0, 1), (5.9, 1),
        (6.0, 2), (11.9, 2),
        (12.0, 3), (19.9, 3), // 3 级区间 12~19
        (20.0, 4), (28.9, 4),
        (29.0, 5), (38.9, 5),
        (39.0, 6), (49.9, 6),
        (50.0, 7), (61.9, 7),
        (62.0, 8), (74.9, 8),
        (75.0, 9), (88.9, 9),
        (89.0, 10), (102.9, 10),
        (103.0, 11), (117.9, 11),
        (118.0, 12), (200.0, 12), // 12 级以上统一记 12，不能溢出
      ];
      for (final c in cases) {
        expect(beaufortLevel(c.$1), c.$2,
            reason: '${c.$1}km/h 应记为 ${c.$2} 级');
      }
    });

    test('负值 / NaN 不抛异常，按 0 级处理', () {
      expect(beaufortLevel(-5), 0);
      expect(beaufortLevel(double.nan), 0);
    });

    test('旧实现只到 8 级，现在 9~12 级要能区分（海钓大风场景）', () {
      // 回归点：旧 _beaufort 把 62 以上一律返回 8，
      // 台风外围 100km/h 也显示「8级」，与实际差 2 级
      expect(beaufortLevel(100), greaterThan(8));
      expect(beaufortLevel(120), 12);
    });
  });

  group('windLevelText：几级 + 什么风', () {
    test('有风向 → 「东南风 3级」这种写法，不带风速数字', () {
      expect(windLevelText(18, 90), '东风 3级');
      expect(windLevelText(18, 135), '东南风 3级');
      expect(windLevelText(20, 225), '西南风 4级');
      expect(windLevelText(5, 0), '北风 1级');
      // 359° 属于北风区间（±22.5° 容差）
      expect(windLevelText(5, 359), '北风 1级');
    });

    test('风向缺失（旧缓存没有这个字段）→ 只说风力，不硬套「北风」', () {
      expect(windLevelText(18, null), '3级');
    });

    test('文案里不能出现 km/h、m/s 之类的速度单位', () {
      for (final s in [
        windLevelText(0, 0),
        windLevelText(18, 135),
        windLevelText(120, 270),
        windLevelText(18, null),
      ]) {
        expect(s.contains('km'), false, reason: '「$s」不该带 km/h');
        expect(s.contains('m/s'), false, reason: '「$s」不该带 m/s');
      }
    });
  });
}
