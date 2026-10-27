import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/screens/weather_screen.dart';

/// 构造 7 天 × 24 小时的假预报（结构对齐 Open-Meteo 返回）
Map<String, dynamic> _mockForecast() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);

  String d2(int v) => v.toString().padLeft(2, '0');

  final hTime = <String>[];
  final temp = <double>[];
  final hum = <int>[];
  final precip = <double>[];
  final pp = <int>[];
  final code = <int>[];
  final ws = <double>[];
  final wd = <int>[];
  final pres = <double>[];
  final uv = <double>[];
  final cloud = <double>[];

  for (var i = 0; i < 7 * 24; i++) {
    final t = start.add(Duration(hours: i));
    hTime.add('${t.year}-${d2(t.month)}-${d2(t.day)}T${d2(t.hour)}:00');
    temp.add(13.8 + (i % 12) * 0.9);
    hum.add(60 + (i % 30));
    precip.add(0);
    pp.add((i * 7) % 100);
    code.add(i % 5 == 0 ? 0 : (i % 3 == 0 ? 2 : 3));
    ws.add(1.0 + (i % 9) * 2.5);
    wd.add((i * 37) % 360);
    pres.add(1000.0 + (i % 20) * 0.7);
    uv.add((i % 10) * 0.8);
    cloud.add(40.0 + (i % 50));
  }

  final dTime = <String>[];
  for (var i = 0; i < 7; i++) {
    final d = start.add(Duration(days: i));
    dTime.add('${d.year}-${d2(d.month)}-${d2(d.day)}');
  }

  return {
    'current': {
      'temperature_2m': 16.4,
      'relative_humidity_2m': 72,
      'precipitation': 0.0,
      'precipitation_probability': 10,
      'weather_code': 2,
      'wind_speed_10m': 7.2,
      'wind_direction_10m': 315,
      'pressure_msl': 1008.6,
    },
    'hourly': {
      'time': hTime,
      'temperature_2m': temp,
      'relative_humidity_2m': hum,
      'precipitation': precip,
      'precipitation_probability': pp,
      'weather_code': code,
      'wind_speed_10m': ws,
      'wind_direction_10m': wd,
      'pressure_msl': pres,
      'uv_index': uv,
      'cloud_cover': cloud,
    },
    'daily': {
      'time': dTime,
      'weather_code': List.generate(7, (i) => i % 4),
      'temperature_2m_max': List.generate(7, (i) => 22.0 + i),
      'temperature_2m_min': List.generate(7, (i) => 12.0 + i * 0.4),
      'precipitation_sum': List.generate(7, (_) => 0.0),
      'precipitation_probability_max': List.generate(7, (i) => 10 + i * 5),
      'wind_speed_10m_max': List.generate(7, (i) => 12.0 + i),
      'wind_direction_10m_dominant': List.generate(7, (i) => 270 + i * 10),
      'uv_index_max': List.generate(7, (_) => 6.0),
      'sunrise': List.generate(7, (i) => '${dTime[i]}T06:12'),
      'sunset': List.generate(7, (i) => '${dTime[i]}T18:05'),
    },
  };
}

void main() {
  for (final w in [390.0, 360.0, 320.0]) {
    testWidgets('天气页 24 小时表在 ${w.toInt()}dp 宽度下无布局溢出', (tester) async {
      tester.view.physicalSize = Size(w * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'wx_forecast_v1': jsonEncode({
          'lat': 30.2741,
          'lng': 120.1551,
          'ts': DateTime.now().millisecondsSinceEpoch,
          'json': _mockForecast(),
        }),
      });

      await tester.pumpWidget(const MaterialApp(home: WeatherScreen()));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(tester.takeException(), isNull, reason: '首屏渲染异常');

      // 往下滚，强制构建 24 小时表格的每一行
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -560),
            warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull, reason: '滚动第 $i 屏出现布局异常');
      }

      // 回到顶部
      await tester.drag(find.byType(ListView).first, const Offset(0, 6000),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));

      // 打开「AI解析」弹层（多维评分 + 黄金时段 + 建议），确认不溢出
      final ai = find.text('AI解析');
      expect(ai, findsOneWidget);
      await tester.tap(ai);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(tester.takeException(), isNull, reason: 'AI解析弹层渲染异常');
      // 关闭
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 120));

      // 打开「解读」弹层，确认弹层也不溢出
      final explain = find.text('解读');
      expect(explain, findsOneWidget);
      await tester.tap(explain);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(tester.takeException(), isNull, reason: '解读弹层渲染异常');
    });
  }
}
