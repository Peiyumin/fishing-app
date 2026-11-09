// v2.1.91 首页顶部三改回归护栏
//
// 用户原话（附截图，状态栏那一带是浅灰色）：
//   「顶部不要留白，也该为黑色，首页左上角标题在大一点，下面的定位名字在小一点」
//
// 拆成四条，每条都对着「改回去就会失败」写：
//   ① 深色头部必须从 y=0 起铺 —— 顶部那一截不能露出 Scaffold 的浅色底
//   ② 顶部状态栏区域的实际像素必须是深色（不是「看起来深」，是真的取了像素）
//   ③ 「渔报」40pt，且明显大于地名（两个层级不能混）
//   ④ 地名 17pt（v2.1.87 曾放大到 21，本版按用户要求收回）
//
// ★ 本轮踩到的坑（护栏就是为了别再踩）
//   `ListView` 的 `padding` 传 null 时，Flutter 会**自动套用 MediaQuery 的
//   垂直 padding**（顶部 = 状态栏高度）。于是第一项深色头部从状态栏下方才
//   开始画，上面那一条露出 Scaffold.backgroundColor —— 就是用户看到的
//   「顶部留白」。而状态栏图标被我们设成白色（light），白压浅灰几乎看不见。
//   修法：`padding: EdgeInsets.only(bottom: 系统底部安全区)`，顶部归零。
//
//   v2.1.90 的截图脚本 `tester.view.padding` 是 0，所以这个 bug 在图里根本
//   看不出来 —— 本文件的 ①② 两条都**带着 47 的状态栏高度**渲染。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_top_bar.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';
import 'package:fishing_app/widgets/mode_tabs.dart';

/// iPhone 14 的状态栏高度。这就是 v2.1.90 漏测的那个变量。
const double kStatusBar = 47;
const double kWidth = 390;

FishingWeather demoWeather() => const FishingWeather(
      temperature: 10,
      humidity: 66,
      pressure: 1015,
      windSpeed: 6,
      windDir: 45,
      weatherCode: 3,
      description: '少云',
      fishIndex: '有口',
      fishAdvice: '水氧 8.8mg/L，开口欲望强',
      score: 86,
      atLabel: '20:00',
      oxygen: 8.8,
    );

/// 复刻线上骨架：深色整块（顶栏 + 天气）+ 一张白卡，ListView 顶部不留 padding
Widget page(GlobalKey key, ScrollController sc) {
  return RepaintBoundary(
    key: key,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: AppTheme.background,
        body: ListView(
          controller: sc,
          physics: const ClampingScrollPhysics(),
          // 与 home_screen.dart 线上写法一致：只留底部安全区
          padding: const EdgeInsets.only(bottom: 34),
          children: [
            Container(
              key: const ValueKey('header'),
              decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const HomeTopBar(mode: HomeMode.haiDiao, embedded: true),
                  HomeWeatherHero(
                    weather: demoWeather(),
                    placeLabel: '汉寿县',
                    waterTemp: 12,
                    mode: HomeMode.haiDiao,
                    flat: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 120, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

/// 取逻辑坐标 (x, y) 处的像素（pixelRatio = 1，坐标不用换算）
Future<Color> pick(WidgetTester t, GlobalKey key, double x, double y) async {
  Color out = const Color(0x00000000);
  await t.runAsync(() async {
    final bd = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await bd.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final i = (y.round() * img.width + x.round()) * 4;
    out = Color.fromARGB(data!.getUint8(i + 3), data.getUint8(i),
        data.getUint8(i + 1), data.getUint8(i + 2));
  });
  return out;
}

void main() {
  group('① 深色头部从 y=0 起铺（顶部不留白）', () {
    testWidgets('带 47 状态栏渲染时，头部顶边正好是 0', (t) async {
      t.view.physicalSize = const Size(kWidth * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      t.view.padding = const FakeViewPadding(top: kStatusBar * 3);
      t.view.viewPadding = const FakeViewPadding(top: kStatusBar * 3);
      addTearDown(t.view.reset);

      final key = GlobalKey();
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(key, sc));
      await t.pump(const Duration(milliseconds: 100));

      final header = t.getRect(find.byKey(const ValueKey('header')));
      expect(header.top, 0,
          reason: 'ListView 的 padding 顶部必须为 0 —— 传 null 时 Flutter 会自动'
              '套上状态栏高度，深色块从状态栏下方才开始，上面就露白');
      expect(header.height, greaterThan(kStatusBar),
          reason: '头部要比状态栏高，否则「渔报」会被顶进状态栏');
    });

    testWidgets('源码：首页 ListView 必须显式给 padding（不能是 null）', (t) async {
      final src = File('lib/screens/home_screen.dart').readAsStringSync();
      // 找 HomeScreen.build 里那个 ListView（唯一带 _feedScroll 的那个）
      final i = src.indexOf('controller: _feedScroll');
      expect(i, greaterThan(0), reason: '首页 ListView 找不到了？结构变了就得重看这段护栏');
      // 往后 900 字以内必须出现显式 padding
      final window = src.substring(i, (i + 900).clamp(0, src.length));
      expect(window.contains('padding:'), isTrue,
          reason: 'ListView 不显式给 padding 就会自动套 MediaQuery.padding，'
              '顶部那条留白会回来');
      expect(window.contains('MediaQuery.paddingOf(context).bottom'), isTrue,
          reason: '底部安全区要留（iPhone 的 home indicator），顶部必须归零');
    });

    testWidgets('状态栏区域的实际像素是深色', (t) async {
      t.view.physicalSize = const Size(kWidth * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      t.view.padding = const FakeViewPadding(top: kStatusBar * 3);
      t.view.viewPadding = const FakeViewPadding(top: kStatusBar * 3);
      addTearDown(t.view.reset);

      final key = GlobalKey();
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(key, sc));
      await t.pump(const Duration(milliseconds: 100));

      // 状态栏正中，左右各避开头像/电池图标
      final left = await pick(t, key, 8, kStatusBar / 2);
      final right = await pick(t, key, kWidth - 8, kStatusBar / 2);
      expect(left.computeLuminance(), lessThan(0.25),
          reason: '顶部左侧（状态栏）必须是深色，实际是 $left');
      expect(right.computeLuminance(), lessThan(0.25),
          reason: '顶部右侧（状态栏）必须是深色，实际是 $right');

      // 对照组：状态栏下方仍是深色，说明整块是连着的，没有接缝
      final below = await pick(t, key, kWidth / 2, kStatusBar + 30);
      expect(below.computeLuminance(), lessThan(0.25),
          reason: '状态栏与标题行之间不该出现浅色接缝，实际是 $below');
    });
  });

  group('② 标题更大', () {
    testWidgets('「渔报」40pt，比 v2.1.90 的 34 大一档', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(GlobalKey(), sc));

      final title = t.widget<Text>(find.text('渔报'));
      expect(title.style!.fontSize, 40,
          reason: '用户要求「左上角标题再大一点」：34 → 40');
      expect(title.style!.fontFamily, 'YuBaoBrush',
          reason: '字体族名必须与 pubspec 声明一致，否则静默回落系统字体');
    });

    testWidgets('工具栏容得下 40pt 而不裁笔锋', (t) async {
      // 行高 1.05 → 42；上下各留 ≥ 12 才不会被裁
      expect(HomeTopBar.barHeight, greaterThanOrEqualTo(40 * 1.05 + 24),
          reason: '只加字号不加栏高，行书的上下出锋会被工具栏裁掉');
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(GlobalKey(), sc));
      final r = t.getRect(find.text('渔报'));
      // Text 的实际高度要完整落在工具栏里
      final barTop = t.getRect(find.byType(AppBar)).top;
      final tabsTop = t.getRect(find.byType(ModeTabs)).top;
      expect(r.top, greaterThan(barTop),
          reason: '标题顶边不能低过工具栏顶边（会被裁）');
      expect(r.bottom, lessThan(tabsTop),
          reason: '标题底边不能压到下面的分类条');
    });
  });

  group('③ 定位名字更小', () {
    testWidgets('地名 17pt（v2.1.87 是 21）', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(GlobalKey(), sc));

      final place = t.widget<Text>(find.text('汉寿县'));
      expect(place.style!.fontSize, 17,
          reason: '用户要求「下面的定位名字小一点」：21 → 17');
    });

    testWidgets('标题必须明显大于地名（视觉层级不能倒）', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(GlobalKey(), sc));

      final titleSize = t.widget<Text>(find.text('渔报')).style!.fontSize!;
      final placeSize = t.widget<Text>(find.text('汉寿县')).style!.fontSize!;
      expect(titleSize, greaterThan(placeSize * 2),
          reason: '「渔报」是本页第一层级，地名是次要信息，前者至少要是后者的两倍');
    });
  });
}
