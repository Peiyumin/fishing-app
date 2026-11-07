// 钓点详情页「AI 分析 / 现在去合不合适」的数据口径（v2.1.83）
//
// 这一层不画界面，只保证三件事不出错：
//   ① 推荐指数 = 四项相加（页面上是把四项摊开写的，加不起来就等于自己打脸）；
//   ② 24 小时色条与最佳时段是**同一条逐时序列**算出来的，不能一处有数据一处空；
//   ③ 拿不到天气时不许编数字（返回 null，页面显示占位）。
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/services/spot_conditions.dart';

/// 造一份「当天 0-23 点」的天气
///
/// [hot] 用来控制哪几个小时的条件更好（温度贴近适宜区间、气压平稳），
/// 其余小时给一个明显更差的参数，方便断言「最佳时段确实挑中了 hot」。
WeatherBundle bundleWith({
  Set<int> hot = const {6, 7, 8},
  DateTime? day,
  double baseTemp = 18,
  int windKmh = 10,
}) {
  final d = day ?? DateTime(2026, 11, 7);
  final hours = <HourPoint>[];
  for (var h = 0; h < 24; h++) {
    final good = hot.contains(h);
    hours.add(HourPoint(
      time: DateTime(d.year, d.month, d.day, h),
      temp: good ? baseTemp : baseTemp + 12, // 差时段：过热
      humidity: 60,
      pressure: good ? 1016 : 1002,
      precipProb: good ? 5 : 60,
      precip: good ? 0 : 1.2,
      windSpeed: good ? windKmh.toDouble() : windKmh * 3.2,
      windDir: 90,
      weatherCode: good ? 1 : 61,
      pressureTrend: good ? 'steady' : 'falling_fast',
      dayRange: 10,
    ));
  }
  return WeatherBundle(
    lat: 34.15,
    lng: 113.47,
    curTemp: baseTemp,
    curHumidity: 60,
    curPressure: 1016,
    curWindSpeed: windKmh.toDouble(),
    curWindDir: 90,
    curPrecip: 0,
    curCode: 1,
    curPrecipProb: 5,
    hours: hours,
    days: const [],
  );
}

void main() {
  final at = DateTime(2026, 11, 7, 7); // 早上 7 点，正好落在 hot 里

  group('① 拿不到天气就不编数字', () {
    test('bundle 为 null → 返回 null', () {
      final c = SpotConditions.of(
          bundle: null, kind: 'wild', km: 3, bearingFromMe: 90);
      expect(c, isNull);
    });

    test('当天没有逐时数据 → 返回 null（不拿别的天凑）', () {
      final b = bundleWith(day: DateTime(2026, 11, 8));
      final c = SpotConditions.of(
        bundle: b,
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      );
      expect(c, isNull);
    });
  });

  group('② 推荐指数四项必须加起来等于总分', () {
    test('四项之和 == score', () {
      final c = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      final sum = c.parts.fold<int>(0, (a, p) => a + p.value);
      expect(sum, c.score);
    });

    test('构成项标签固定四项：天气 / 水域 / 风岸 / 距离', () {
      final c = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.parts.map((p) => p.label).toList(),
          ['天气', '水域', '风岸', '距离']);
    });

    test('远处（>40km）要被扣 3 分，近距离不扣', () {
      final near = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      final far = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 60,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(near.parts.last.value, 0);
      expect(far.parts.last.value, -3);
      expect(near.score - far.score, 3);
    });

    test('钓友钓点（wild）比静水湖泊（venue）多 2 分水体加成', () {
      final wild = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      final venue = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'venue',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(wild.parts[1].value, 2);
      expect(venue.parts[1].value, 0);
    });
  });

  group('③ 24 小时色条', () {
    test('长度恒为 24，且按小时对齐（-1 表示没数据）', () {
      final c = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.hourly.length, 24);
      expect(c.hourly.every((v) => v >= 0), isTrue);
    });

    test('「好时段」的分数确实高于差时段', () {
      final c = SpotConditions.of(
        bundle: bundleWith(hot: {6, 7, 8}),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.hourly[7], greaterThan(c.hourly[14]));
    });

    test('nowHour 跟着传入的时间走（红线画在哪）', () {
      final c = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: DateTime(2026, 11, 7, 15),
      )!;
      expect(c.nowHour, 15);
    });
  });

  group('④ 最佳出钓时间', () {
    test('挑中的窗口包含那几个好小时，分数取窗口内最高', () {
      final c = SpotConditions.of(
        bundle: bundleWith(hot: {6, 7, 8}),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.windows, isNotEmpty);
      final best = c.best!;
      expect(best.start, lessThanOrEqualTo(6));
      expect(best.end, greaterThanOrEqualTo(8));
      expect(best.score, c.hourly.sublist(best.start, best.end + 1).reduce(
          (a, b) => a > b ? a : b));
    });

    test('最多两个窗口，且按开始时间排序', () {
      final c = SpotConditions.of(
        bundle: bundleWith(hot: {5, 6, 12, 13, 19}),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.windows.length, lessThanOrEqualTo(2));
      if (c.windows.length == 2) {
        expect(c.windows[0].start, lessThan(c.windows[1].start));
      }
    });

    test('一整天都烂的时候不许硬挑「最佳」（不给窗口）', () {
      // 全天 35℃、大风、气压一路掉：分数应该跌到阈值以下
      final bad = bundleWith(hot: const {}, baseTemp: 36, windKmh: 40);
      final c = SpotConditions.of(
        bundle: bad,
        kind: 'venue',
        km: 50,
        bearingFromMe: 270,
        at: at,
      )!;
      expect(c.score, lessThan(55));
      expect(c.windows, isEmpty);
      expect(c.best, isNull);
    });

    test('窗口文案：单小时写成「7 时」，多小时写成「6-8 时」', () {
      expect(const SpotTimeWindow(7, 7, 80).range, '7 时');
      expect(const SpotTimeWindow(6, 8, 80).range, '6-8 时');
    });
  });

  group('⑤ 温度 / 风力 / 文案', () {
    test('今日气温区间取当天最低与最高', () {
      final c = SpotConditions.of(
        bundle: bundleWith(hot: {7}, baseTemp: 18),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.tempMin, 18);
      expect(c.tempMax, 30); // 差时段 = base + 12
      expect(c.tempMax, greaterThan(c.tempMin));
    });

    test('风力区间用蒲福风级（10km/h ≈ 2 级）', () {
      final c = SpotConditions.of(
        bundle: bundleWith(windKmh: 10),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.windMin, 2);
      expect(c.windMax, 5); // 差时段 32km/h
    });

    test('体感 / 风感文案落在预期档位', () {
      expect(SpotConditions.tempFeel(3), '很冷');
      expect(SpotConditions.tempFeel(10), '冷');
      expect(SpotConditions.tempFeel(18), '凉爽');
      expect(SpotConditions.tempFeel(26), '舒适');
      expect(SpotConditions.tempFeel(34), '很热');
      expect(SpotConditions.windFeel(2), '微风拂面');
      expect(SpotConditions.windFeel(6), '大风，不建议出钓');
    });

    test('AI 正文把真实数字写进去了（不是套话）', () {
      final c = SpotConditions.of(
        bundle: bundleWith(hot: {7}),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      expect(c.aiText, contains('mg/L'));
      expect(c.aiText, contains('hPa'));
      expect(c.aiText, contains('水温'));
      expect(c.aiText.length, greaterThan(40));
    });

    test('分数越低，今日建议越谨慎', () {
      final good = SpotConditions.of(
        bundle: bundleWith(),
        kind: 'wild',
        km: 3,
        bearingFromMe: 90,
        at: at,
      )!;
      final bad = SpotConditions.of(
        bundle: bundleWith(hot: const {}, baseTemp: 36, windKmh: 40),
        kind: 'venue',
        km: 50,
        bearingFromMe: 270,
        at: at,
      )!;
      expect(good.score, greaterThan(bad.score));
      expect('${good.advice}${bad.advice}', isNotEmpty);
      expect(bad.advice, anyOf(contains('改天'), contains('偏弱'), contains('一般')));
    });
  });

  group('⑥ 档位与地理工具', () {
    test('档位边界', () {
      expect(SpotConditions.gradeOf(90), '优秀');
      expect(SpotConditions.gradeOf(85), '优秀');
      expect(SpotConditions.gradeOf(84), '良好');
      expect(SpotConditions.gradeOf(70), '良好');
      expect(SpotConditions.gradeOf(50), '一般');
      expect(SpotConditions.gradeOf(30), '口弱');
      expect(SpotConditions.gradeOf(29), '难钓');
    });

    test('kindKey：野钓点算钓友钓点，钓场算湖泊', () {
      expect(SpotConditions.kindKey('wild'), '钓友钓点');
      expect(SpotConditions.kindKey('venue'), '湖泊');
      expect(SpotConditions.kindKey('shop'), '湖泊');
    });

    test('距离：同一点 0 公里，隔 1 个纬度约 111 公里', () {
      expect(SpotConditions.kmBetween(34, 113, 34, 113), closeTo(0, .001));
      expect(SpotConditions.kmBetween(34, 113, 35, 113), closeTo(111, 2));
    });

    test('方位角：正东约 90 度，正北约 0 度', () {
      expect(SpotConditions.bearingBetween(34, 113, 34, 114), closeTo(90, 1));
      expect(SpotConditions.bearingBetween(34, 113, 35, 113), closeTo(0, 2));
    });
  });
}
