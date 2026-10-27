// 首页「钓鱼天气」卡的风口径（v2.1.36）
//
// 护栏目标：
//   ① 只显示「几级 + 什么风」，不许出现 km/h —— 旧代码这里是
//      `_Metric('${windSpeed.toStringAsFixed(0)}km/h', '风速')`，
//      用户拿首页卡对照天气页（那时主卡也写 km/h 但逐时表写「3级」）
//      会以为两处数据不一样；
//   ② 320dp 窄屏下 4 列指标不能溢出 —— 风向从 2 字「风速」变成 3 字「东南风」，
//      是最容易挤爆的一列；
//   ③ 旧缓存没有风向字段时不能硬套一个方位（把 0° 当北风）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/weather_card.dart';

/// 挂真实中文字体。
///
/// 不挂字体时测试里的中文会画成方块（每个方块按 fontSize 占宽），
/// 量出来的行宽和真机差 20~30%，会报出真机上根本不存在的 overflow
/// —— 用真字体量，结论才作数。
Future<void> _loadFonts(WidgetTester tester) async {
  const cjk = 'C:/Windows/Fonts/simhei.ttf';
  if (!File(cjk).existsSync()) return;
  final bytes = File(cjk).readAsBytesSync();
  await tester.runAsync(() async {
    for (final family in const [
      'Microsoft YaHei',
      'Roboto',
      'PingFang SC',
      'Noto Sans SC',
    ]) {
      await ui.loadFontFromList(bytes, fontFamily: family);
    }
  });
}

FishingWeather _w({int? windDir = 135, double windSpeed = 18}) => FishingWeather(
      temperature: 20.1,
      humidity: 79,
      windSpeed: windSpeed,
      windDir: windDir,
      pressure: 1012,
      weatherCode: 2,
      description: '多云',
      fishIndex: '有口',
      fishAdvice: '多云天光照平稳，鱼不惊慌、愿意靠边，可以出钓',
      score: 86,
      atLabel: '19:00',
    );

Future<void> _pump(WidgetTester tester, FishingWeather w, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 700));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: WeatherCard(weather: w, placeLabel: '禹州'),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('首页天气卡只说风级 + 风向，不出现 km/h', (tester) async {
    await _loadFonts(tester);
    await _pump(tester, _w(), 390);

    expect(find.text('3级'), findsOneWidget,
        reason: '18km/h 应换算成 3 级');
    expect(find.text('东南风'), findsOneWidget,
        reason: '135° 是东南风，要写在「3级」下面当标签');
    expect(find.textContaining('km/h'), findsNothing,
        reason: '首页卡不许再显示 km/h（v2.1.36 全站统一为蒲福风级）');
    expect(find.text('风速'), findsNothing, reason: '标签换成风向了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 窄屏 4 列指标不溢出', (tester) async {
    await _loadFonts(tester);
    // 风向最长的一种：西北风（3 字）+ 两位数风级
    await _pump(tester, _w(windDir: 315, windSpeed: 105), 320);

    expect(find.text('西北风'), findsOneWidget);
    expect(find.text('11级'), findsOneWidget);
    // RenderFlex overflow 会在测试里直接抛异常 / 让 takeException 非空
    expect(tester.takeException(), isNull,
        reason: '320dp 下风一列（11级 / 西北风）不能挤爆 4 列布局');
  });

  testWidgets('风向缺失（旧缓存）只显示风力，不硬套「北风」', (tester) async {
    await _loadFonts(tester);
    await _pump(tester, _w(windDir: null), 390);

    expect(find.text('3级'), findsOneWidget);
    expect(find.text('风力'), findsOneWidget,
        reason: '没有风向时标签只能是「风力」，不能显示「北风」误导');
    expect(find.textContaining('风风'), findsNothing);
  });
}
