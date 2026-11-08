// v2.1.87 首页天气通栏首行重排
//
// 用户需求（原话）：
//   「把定位显示位置移到垂钓指数前面并放大，把7天预报取消，
//     把垂钓指数往右边移靠右边，把垂钓指数数字字体在放大一点数字时斜体字，要突出出来」
//
// 拆成可验证的 5 件事：
//   ① 「7 天预报」整条没了（不是藏起来，是删掉）
//   ② 地名挪到指数左边（中心 x 更小），字号 ≥ 18（原来是 13）
//   ③ 指数靠右：等级列的右边缘贴容器右缘（16 的内边距内）
//   ④ 数字更大（≥ 50，原来 46）且是斜体
//   ⑤ 320dp 小屏不溢出
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';
import 'package:fishing_app/widgets/weather_icon.dart';

const _weather = FishingWeather(
  temperature: 22,
  humidity: 78,
  pressure: 1008,
  windSpeed: 16,
  windDir: 90,
  weatherCode: 61,
  description: '小雨',
  fishIndex: '有口',
  fishAdvice: '气压 1008hPa 缓降、小雨增氧，鱼口比晴天活，注意防风',
  score: 72,
  atLabel: '23:00',
  oxygen: 7.4,
);

Widget wrap(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    );

Widget hero() => HomeWeatherHero(
      weather: _weather,
      onTap: () {},
      placeLabel: '青岛 · 市南区',
      waterTemp: 19,
    );

void main() {
  // 截图/测试环境没有中文系统字体时，Text 会退到 Ahem（方块），
  // 但字号、方位、斜体这些**排版属性**照样能测 —— 这正是这组断言的边界：
  // 只管「在哪、多大、斜不斜」，不管「像不像毛笔字」。

  group('① 7 天预报已取消', () {
    testWidgets('通栏里不再出现「7 天预报」和那个右箭头', (t) async {
      await t.pumpWidget(wrap(hero()));
      expect(find.text('7 天预报'), findsNothing);
      // 箭头以前只在「7 天预报」后面出现过一处
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });

  group('② 定位挪到指数左边并放大', () {
    testWidgets('地名中心 x 小于指数中心 x', (t) async {
      await t.pumpWidget(wrap(hero()));
      final placeX = t.getCenter(find.text('青岛 · 市南区')).dx;
      final scoreX = t.getCenter(find.text('72')).dx;
      expect(placeX, lessThan(scoreX),
          reason: '用户要求「定位放到垂钓指数前面」，地名必须在数字左侧');
    });

    testWidgets('地名字号 ≥ 18（原来 13）、白色加粗', (t) async {
      await t.pumpWidget(wrap(hero()));
      final style = t.widget<Text>(find.text('青岛 · 市南区')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(18),
          reason: '用户要求「放大」；旧版 13pt 是辅助信息的字号，不是主角');
      expect(style.color, Colors.white);
      expect(style.fontWeight, FontWeight.w700);
    });

    testWidgets('没拿到地名时退成「当前位置」，不是空白', (t) async {
      await t.pumpWidget(wrap(HomeWeatherHero(
        weather: _weather,
        onTap: () {},
      )));
      expect(find.text('当前位置'), findsOneWidget);
    });
  });

  group('③ 指数靠右贴边', () {
    testWidgets('「钓鱼指数 / 100」的右边缘距容器右缘 ≈ 内边距 16', (t) async {
      await t.pumpWidget(wrap(hero()));
      final heroRect = t.getRect(find.byType(HomeWeatherHero));
      final labelRight = t.getRect(find.text('钓鱼指数 / 100')).right;
      final gap = heroRect.right - labelRight;
      expect(gap, closeTo(16, 2.5),
          reason: '用户要求「往右移靠右边」：等级列必须贴右缘（内边距 16），'
              '偏离说明右半边还留着空白');
    });
  });

  group('④ 数字更大 + 斜体', () {
    testWidgets('字号 ≥ 50（原来 46）且 fontStyle 是 italic', (t) async {
      await t.pumpWidget(wrap(hero()));
      final style = t.widget<Text>(find.text('72')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(50),
          reason: '用户要求「数字字体再放大一点」');
      expect(style.fontStyle, FontStyle.italic,
          reason: '用户明确要求「数字时斜体字」');
      expect(style.fontWeight, FontWeight.w900,
          reason: '斜体 + 更重的字重才「突出」，w800 在 58pt 上偏软');
    });

    testWidgets('没数据时是「--」，但字号/斜体不变（不跳版）', (t) async {
      await t.pumpWidget(wrap(HomeWeatherHero(weather: null, onTap: () {})));
      final style = t.widget<Text>(find.text('--').first).style!;
      expect(style.fontSize, greaterThanOrEqualTo(50));
      expect(style.fontStyle, FontStyle.italic);
    });

    testWidgets('天气图标还在（没被重排挤掉）', (t) async {
      await t.pumpWidget(wrap(hero()));
      expect(find.byType(WeatherGlyph), findsOneWidget);
    });
  });

  group('⑤ 小屏不溢出', () {
    testWidgets('320dp 宽也能排下，不报 overflow', (t) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: hero())));
      expect(t.takeException(), isNull,
          reason: '320dp 上地名会被压缩，但不能溢出（必须靠 Expanded + ellipsis）');
      // 地名被压缩后仍然是第一个可见元素
      expect(find.text('青岛 · 市南区'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
    });
  });
}
