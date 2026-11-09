// 临时：v2.1.89 人眼验收截图
//   首页天气通栏：缓存里故意塞繁体「漢壽縣」，界面必须显示「汉寿县」
// 跑法：flutter test test/_shot_v52.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/services/geo_place.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';

Future<void> loadFonts() async {
  final zh = File('C:/Windows/Fonts/simhei.ttf').readAsBytesSync();
  await ui.loadFontFromList(zh, fontFamily: 'Microsoft YaHei');
  await ui.loadFontFromList(zh, fontFamily: 'Roboto');
  final icons = File(
          'C:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
      .readAsBytesSync();
  await ui.loadFontFromList(icons, fontFamily: 'MaterialIcons');
  final brush = File('assets/fonts/yubao_brush.ttf').readAsBytesSync();
  await ui.loadFontFromList(brush, fontFamily: 'YuBaoBrush');
}

Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final bd = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await bd.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('.verify/shot_$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首页地名：繁体进 → 简体出', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 470 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 第三方地名库对汉寿返回的就是繁体，这里照原样塞进 GeoPlace，看最终渲染
    final place = GeoPlace.fromJson({
      'province': '湖南省',
      'city': '常德市',
      'district': '漢壽縣',
      'short': '漢壽縣',
      'display': '湖南省常德市漢壽縣',
    });
    expect(place.label, '汉寿县');

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Material(
          color: const Color(0xFF101014),
          child: SizedBox(
            width: 390,
            child: HomeWeatherHero(
              weather: const FishingWeather(
                temperature: 22,
                humidity: 78,
                pressure: 1008,
                windSpeed: 16,
                windDir: 90,
                weatherCode: 0,
                description: '晴',
                fishIndex: '有口',
                fishAdvice: '微风',
                score: 82,
                atLabel: '14:00',
                oxygen: 9.8,
              ),
              placeLabel: place.label,
              waterTemp: 13,
              mode: HomeMode.taiDiao,
              onTap: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    await shoot(tester, key, 'v52_home_zh');

    expect(find.text('汉寿县'), findsOneWidget);
    expect(find.text('漢壽縣'), findsNothing, reason: '界面里不能出现繁体');
  });
}
