import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/weather_card.dart';
import 'package:fishing_app/widgets/weather_icon.dart';

/// v2.1.70 天气图标重做 + 首页指数绿色胶囊
///
/// 用户报：
///   ① 毛毛雨画成一排小点，「不像下毛毛雨」，要雨丝；
///   ② 毛毛雨/小雨→细丝，中雨/大雨/暴雨要**越来越粗、越来越密**；
///   ③ 雷阵雨必须是「闪电 + 雨丝」；
///   ④ 夜里晴天要**黄色月牙**；夜里阴天要**灰月亮**；
///   ⑤ 首页指数的数字 ≥90 时要用主题黄绿底 + 数字（和天气页一样）。
void main() {
  group('雨丝分级（等级越高越粗越密）', () {
    test('毛毛雨 → 小雨 → 中雨 → 大雨 → 暴雨 三轴同时递增', () {
      const codes = [51, 61, 63, 65, 82];
      final specs = codes.map(rainSpecOf).toList();
      expect(specs.every((s) => s != null), isTrue, reason: '这几个都必须是雨');
      for (var i = 1; i < specs.length; i++) {
        expect(specs[i]!.lines, greaterThan(specs[i - 1]!.lines),
            reason: '${codes[i]} 的雨丝根数必须多于 ${codes[i - 1]}');
        expect(specs[i]!.width, greaterThan(specs[i - 1]!.width),
            reason: '${codes[i]} 的雨丝必须更粗');
        expect(specs[i]!.length, greaterThan(specs[i - 1]!.length),
            reason: '${codes[i]} 的雨丝必须更长');
      }
    });

    test('毛毛雨是最细的一档（不再是小点）', () {
      final d = rainSpecOf(51)!;
      expect(d.lines, 3);
      expect(d.width, lessThan(rainSpecOf(61)!.width));
      expect(d.width, lessThan(0.05));
    });

    test('阵雨 / 冻雨也走雨丝，不会掉回默认图标', () {
      for (final c in [53, 55, 56, 57, 66, 67, 80, 81]) {
        expect(rainSpecOf(c), isNotNull, reason: '$c 没配雨丝规格');
      }
    });

    test('雷阵雨 = 闪电 + 雨丝，不当普通雨处理', () {
      for (final c in [95, 96, 99]) {
        expect(isThunderCode(c), isTrue);
        expect(rainSpecOf(c), isNull);
      }
    });

    test('雪 / 雾不会被误判成雨', () {
      for (final c in [71, 73, 75, 77, 85, 86]) {
        expect(isSnowCode(c), isTrue);
        expect(rainSpecOf(c), isNull);
      }
      for (final c in [45, 48]) {
        expect(isFogCode(c), isTrue);
        expect(rainSpecOf(c), isNull);
      }
    });
  });

  group('颜色口径', () {
    test('晴天夜里是暖黄月牙（不是灰蓝）', () {
      expect(Wmo.color(0, day: true), AppTheme.star);
      expect(Wmo.color(0, day: false), AppTheme.star);
      expect(Wmo.color(1, day: false), AppTheme.star);
    });

    test('阴天夜里是中性灰月亮，白天仍是深冷蓝厚云', () {
      expect(Wmo.color(3, day: false), AppTheme.textSecondary);
      expect(Wmo.color(3, day: true), AppTheme.skyDeep);
    });

    test('雨=水蓝、雷=危险红不变', () {
      expect(Wmo.color(51), AppTheme.water);
      expect(Wmo.color(82), AppTheme.water);
      expect(Wmo.color(95), AppTheme.danger);
    });

    test('雷阵雨文案统一（不再写雷暴）', () {
      expect(Wmo.text(95), '雷阵雨');
      expect(Wmo.text(96), '雷阵雨冰雹');
      expect(Wmo.text(99), '强雷阵雨');
    });
  });

  group('渲染', () {
    testWidgets('全部天气代码 × 日/夜 × 18/38 两个尺寸都能画出来', (tester) async {
      const codes = [
        0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, //
        71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(children: [
              for (final c in codes) ...[
                WeatherGlyph(code: c, size: 18),
                WeatherGlyph(code: c, day: false, size: 38),
              ],
            ]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(WeatherGlyph), findsNWidgets(codes.length * 2));
    });

    testWidgets('0 尺寸不会崩（列表里偶发约束为 0 的情况）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: SizedBox.shrink(child: WeatherGlyph(code: 51, size: 0)),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('首页指数胶囊（≥90 绿底）', () {
    FishingWeather w(int score) => FishingWeather(
          temperature: 20,
          humidity: 60,
          windSpeed: 8,
          pressure: 1010,
          weatherCode: 0,
          description: '晴',
          fishIndex: '爆护',
          fishAdvice: '气压稳、水温合适，可以出钓',
          score: score,
          atLabel: '12:00',
        );

    BoxDecoration pill(WidgetTester tester) {
      final c = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((x) =>
              x.decoration is BoxDecoration &&
              (x.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(20));
      return c.decoration as BoxDecoration;
    }

    testWidgets('90 / 95 / 100 分：主题黄绿实底 + 近黑数字', (tester) async {
      for (final s in [90, 95, 100]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: WeatherCard(weather: w(s))),
        ));
        expect(pill(tester).color, AppTheme.accent, reason: '$s 分必须是绿底');
        final num = tester.widget<Text>(find.text('$s'));
        expect(num.style!.color, AppTheme.primary,
            reason: '$s 分数字要压近黑色，绿底上才读得清');
      }
    });

    testWidgets('89 分不是绿底（避免天天一片绿）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WeatherCard(weather: w(89))),
      ));
      expect(pill(tester).color, AppTheme.biteScoreSoft(89));
      final num = tester.widget<Text>(find.text('89'));
      expect(num.style!.color, AppTheme.biteScore(89));
    });

    testWidgets('首页卡片按小时判断昼夜（19:00 后画月牙）', (tester) async {
      expect(w(80).isNightAt, isFalse);
      final night = FishingWeather(
        temperature: 20, humidity: 60, windSpeed: 8, pressure: 1010,
        weatherCode: 0, description: '晴', fishIndex: '有口',
        fishAdvice: 'x', score: 80, atLabel: '21:00',
      );
      expect(night.isNightAt, isTrue);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WeatherCard(weather: night)),
      ));
      final g = tester.widget<WeatherGlyph>(find.byType(WeatherGlyph));
      expect(g.day, isFalse, reason: '21:00 不能画太阳');
    });
  });

  group('源码护栏（防回退到 Material 点阵图标）', () {
    test('天气页两处图标都换成手绘 WeatherGlyph', () {
      final s = File('lib/screens/weather_screen.dart').readAsStringSync();
      expect(s.contains('WeatherGlyph('), isTrue);
      expect(s.contains('Icons.grain'), isFalse,
          reason: 'Icons.grain 就是那排小点，已废弃');
    });

    test('首页天气卡不再用 Wmo.icon 画图标', () {
      final s = File('lib/widgets/weather_card.dart').readAsStringSync();
      expect(s.contains('WeatherGlyph('), isTrue);
      expect(s.contains('Wmo.icon('), isFalse);
    });
  });
}
