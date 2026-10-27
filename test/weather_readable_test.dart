import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/screens/weather_screen.dart';

/// 相对亮度（WCAG）
double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.red / 255) + 0.7152 * f(c.green / 255) + 0.0722 * f(c.blue / 255);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, dynamic> _mockForecast({bool withPressure = true}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  String d2(int v) => v.toString().padLeft(2, '0');

  final hTime = <String>[];
  final temp = <double>[], hum = <int>[], precip = <double>[];
  final pp = <int>[], code = <int>[], ws = <double>[], wd = <int>[];
  final pres = <double>[], uv = <double>[], cloud = <double>[];

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
    pres.add(1008.0 + (i % 20) * 0.8);
    uv.add((i % 10) * 0.8);
    cloud.add(40.0 + (i % 50));
  }
  final dTime = List.generate(
      7,
      (i) =>
          '${start.add(Duration(days: i)).year}-${d2(start.add(Duration(days: i)).month)}-${d2(start.add(Duration(days: i)).day)}');

  final hourly = <String, dynamic>{
    'time': hTime,
    'temperature_2m': temp,
    'relative_humidity_2m': hum,
    'precipitation': precip,
    'precipitation_probability': pp,
    'weather_code': code,
    'wind_speed_10m': ws,
    'wind_direction_10m': wd,
    'uv_index': uv,
    'cloud_cover': cloud,
  };
  if (withPressure) hourly['pressure_msl'] = pres;

  return {
    'current': {
      'temperature_2m': 16.4,
      'relative_humidity_2m': 72,
      'weather_code': 2,
      'wind_speed_10m': 7.2,
      'wind_direction_10m': 315,
      if (withPressure) 'pressure_msl': 1008.6,
    },
    'hourly': hourly,
    'daily': {
      'time': dTime,
      'weather_code': List.generate(7, (i) => i % 4),
      'temperature_2m_max': List.generate(7, (i) => 22.0 + i),
      'temperature_2m_min': List.generate(7, (i) => 12.0 + i * 0.4),
      'sunrise': List.generate(7, (i) => '${dTime[i]}T06:12'),
      'sunset': List.generate(7, (i) => '${dTime[i]}T18:05'),
    },
  };
}

void main() {
  // ── 1. 顶栏可读性（v2.1.36 换浅底后标题/图标曾变成白字白底）──
  testWidgets('天气页顶栏标题与图标在浅底上必须能看清', (tester) async {
    SharedPreferences.setMockInitialValues({
      'wx_forecast_v1': jsonEncode({
        'lat': 30.2741,
        'lng': 120.1551,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'json': _mockForecast(),
      }),
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const WeatherScreen()),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final rp = tester.renderObject<RenderParagraph>(find.text('钓鱼天气预报'));
    final titleColor = rp.text.style?.color;
    expect(titleColor, isNotNull, reason: '标题没有解析出颜色');
    final c = _contrast(titleColor!, AppTheme.background);
    expect(c, greaterThanOrEqualTo(4.0),
        reason: '标题与页面底对比度只有 ${c.toStringAsFixed(2)}:1，'
            '等于白字白底（换浅底后曾整条顶栏消失）');

    final iconCtx = tester.element(find.byIcon(Icons.refresh));
    final iconColor = IconTheme.of(iconCtx).color;
    expect(iconColor, isNotNull);
    final ci = _contrast(iconColor!, AppTheme.background);
    expect(ci, greaterThanOrEqualTo(3.0),
        reason: '刷新图标对比度只有 ${ci.toStringAsFixed(2)}:1');
  });

  // ── 2. 气压缺失时不能显示 0，也不能被两模型平均成 506 ──
  test('数据源没有气压字段时按「未知」处理，而不是 0 或半个值', () {
    final noPres = WeatherBundle.fromOpenMeteo(30.27, 120.15, _mockForecast(withPressure: false));
    expect(noPres.curPressure, 0, reason: '缺字段应保持 0 = 未知，页面显示「—」');
    expect(noPres.hours.every((h) => h.pressure == 0), isTrue,
        reason: '逐时气压缺字段时应是 0（未知），不能编一个 1013 冒充实测');

    // 只有第二模型（CMA）给气压：必须直接用第二模型，不能与 0 平均
    final base = _mockForecast(withPressure: false);
    final ensHours = (base['hourly'] as Map)['time'] as List;
    final ens = {
      'hourly': {
        'time': ensHours,
        'temperature_2m_cma_grapes_global':
            List.generate(ensHours.length, (_) => 15.0),
        'pressure_msl_cma_grapes_global':
            List.generate(ensHours.length, (_) => 1005.0),
      },
    };
    final onlyEns = WeatherBundle.fromOpenMeteo(30.27, 120.15, base, ensembleJson: ens);
    for (final h in onlyEns.hours) {
      expect(h.pressure, closeTo(1005.0, 0.001),
          reason: '只有第二模型有气压时，值必须是 1005，不能是 (0+1005)/2=502.5');
    }

    // 两套都有：等权平均
    final both = WeatherBundle.fromOpenMeteo(30.27, 120.15, _mockForecast(), ensembleJson: ens);
    expect(both.hours.first.pressure, closeTo((1008.0 + 1005.0) / 2, 0.001));
  });

  // ── 3. 「宜钓指数」图例必须给出刻度方向 ──
  testWidgets('宜钓指数图例有「低 / 高」刻度', (tester) async {
    SharedPreferences.setMockInitialValues({
      'wx_forecast_v1': jsonEncode({
        'lat': 30.2741,
        'lng': 120.1551,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'json': _mockForecast(),
      }),
    });
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const WeatherScreen()),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('宜钓指数'), findsOneWidget);
    expect(find.text('低'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
  });

  // ── 4. 主题层：顶栏颜色不许写死，否则浅底页面改不动 ──
  testWidgets('appBarTheme 不写死图标/标题颜色，浅底页面才能覆盖', (tester) async {
    final ab = AppTheme.light.appBarTheme;
    expect(ab.iconTheme?.color, isNull,
        reason: 'iconTheme 写死白色后，浅底页面只改 foregroundColor 管不到图标，'
            '返回箭头会白字白底消失');
    expect(ab.titleTextStyle?.color, isNull,
        reason: '标题颜色写死后同样无法被页面覆盖');
    expect(ab.foregroundColor, Colors.white,
        reason: '深色顶栏（默认）仍要靠 foregroundColor 给出白色前景');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('默认顶栏'),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    final ctx = tester.element(find.byIcon(Icons.refresh));
    expect(IconTheme.of(ctx).color, Colors.white,
        reason: '默认深色顶栏的图标应跟随 foregroundColor = 白');
  });
}
