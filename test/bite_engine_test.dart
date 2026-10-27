import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_app/models/fishing_species.dart';
import 'package:fishing_app/models/weather_forecast.dart';

/// 构造一天的逐时数据（14 点最高、5 点最低的正弦温度曲线）
List<HourPoint> synthDay({
  required double minT,
  required double maxT,
  double pressure = 1013,
  double windKmh = 8,
  int code = 3,
  int precipProb = 10,
  String trend = 'steady',
}) {
  final out = <HourPoint>[];
  for (var h = 0; h < 24; h++) {
    final phase = (h - 14) / 24 * 2 * math.pi;
    final t = (minT + maxT) / 2 + (maxT - minT) / 2 * math.cos(phase);
    out.add(HourPoint(
      time: DateTime(2026, 10, 23, h),
      temp: double.parse(t.toStringAsFixed(1)),
      humidity: 70,
      pressure: pressure,
      precipProb: precipProb,
      precip: 0,
      windSpeed: windKmh,
      windDir: 90,
      weatherCode: code,
      pressureTrend: trend,
      dayRange: maxT - minT,
    ));
  }
  return out;
}

FishingSpecies sp(String name) =>
    FishingSpecies.all.firstWhere((s) => s.name == name);

const mode = FishingMode('台钓');

void main() {
  test('引擎标定：同一天不同小时应拉开差距，且不会全天爆护', () {
    // 用户截图那天的近似条件：阴天 13.4~20.4℃、1005hPa、风 6km/h、鲫鱼
    final hours = synthDay(
        minT: 13.4, maxT: 20.4, pressure: 1005, windKmh: 6, code: 3);
    final w = WaterMetrics.derive(hours);
    final s = sp('鲫鱼');

    final rows = <String>[];
    final scores = <int>[];
    for (var h = 0; h < 24; h++) {
      final v = Bite.score(h: hours[h], w: w[h], sp: s, mode: mode);
      scores.add(v);
      final r = Bite.compute(h: hours[h], w: w[h], sp: s, mode: mode);
      rows.add('${h.toString().padLeft(2, '0')}:00 temp=${hours[h].temp.toStringAsFixed(1)} '
          'P=${hours[h].pressure} W=${w[h].temp} 水氧=${w[h].oxygen} '
          'score=$v ${Bite.label(v)} dim=${r.dim}');
    }
    // ignore: avoid_print
    print(rows.join('\n'));

    final maxScore = scores.reduce(math.max);
    final baoHuCount = scores.where((v) => v >= 90).length;
    final kouRuoCount = scores.where((v) => v < 80).length;

    // 这种低压阴天：不可能大面积爆护，至少一半时间应当是口弱
    expect(baoHuCount, lessThanOrEqualTo(2),
        reason: '1005hPa 低压阴天不应大面积爆护（实际 $baoHuCount 个小时 ≥90）');
    expect(kouRuoCount, greaterThanOrEqualTo(8),
        reason: '应有明显口弱时段（实际 $kouRuoCount 个小时 <80）');
    expect(maxScore, lessThanOrEqualTo(92));
  });

  test('理想条件：1018hPa 稳定、微风、温差小、清晨应当爆护', () {
    final hours = synthDay(
        minT: 16, maxT: 22, pressure: 1018, windKmh: 9, code: 2);
    final w = WaterMetrics.derive(hours);
    final s = sp('鲫鱼');
    final dawn = Bite.score(h: hours[7], w: w[7], sp: s, mode: mode);
    final noon = Bite.score(h: hours[13], w: w[13], sp: s, mode: mode);
    // ignore: avoid_print
    print('理想条件 清晨7点=$dawn(${Bite.label(dawn)}) 正午13点=$noon(${Bite.label(noon)})');
    expect(dawn, greaterThanOrEqualTo(85), reason: '理想条件清晨应高分');
    expect(noon, lessThan(dawn), reason: '正午应低于清晨');
  });

  test('雷暴必须压到极低分', () {
    final hours = synthDay(
        minT: 24, maxT: 31, pressure: 1002, windKmh: 20, code: 95,
        precipProb: 90);
    final w = WaterMetrics.derive(hours);
    final v = Bite.score(h: hours[14], w: w[14], sp: sp('草鱼'), mode: mode);
    // ignore: avoid_print
    print('雷暴午后=$v(${Bite.label(v)})');
    expect(v, lessThan(30));
  });

  test('盛夏高温低压午后（28~36℃）应为口弱或更差', () {
    final hours = synthDay(
        minT: 28, maxT: 36, pressure: 1000, windKmh: 4, code: 0);
    final w = WaterMetrics.derive(hours);
    final v = Bite.score(h: hours[14], w: w[14], sp: sp('鲫鱼'), mode: mode);
    // ignore: avoid_print
    print('盛夏午后=$v(${Bite.label(v)}) 水温=${w[14].temp} 水氧=${w[14].oxygen}');
    expect(v, lessThan(70));
  });

  test('冷锋过境（骤升 + 大风 + 降温）应压口', () {
    final hours = synthDay(
        minT: 5, maxT: 12, pressure: 1030, windKmh: 30, code: 2,
        trend: 'rising_fast');
    final w = WaterMetrics.derive(hours);
    final v = Bite.score(h: hours[9], w: w[9], sp: sp('鲫鱼'), mode: mode);
    // ignore: avoid_print
    print('冷锋过境=$v(${Bite.label(v)}) 水温=${w[9].temp}');
    expect(v, lessThanOrEqualTo(72));
  });

  test('档位映射：80 以下口弱、80~89 有口、90 以上爆护', () {
    expect(Bite.label(95), '爆护');
    expect(Bite.label(90), '爆护');
    expect(Bite.label(89), '有口');
    expect(Bite.label(80), '有口');
    expect(Bite.label(79), '口弱');
    expect(Bite.label(50), '口弱');
    expect(Bite.label(20), '无口');
    expect(Bite.fishCount(90), 3);
    expect(Bite.fishCount(80), 2);
    expect(Bite.fishCount(79), 1);
  });
}
