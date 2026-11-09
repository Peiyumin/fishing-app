// v2.1.90 首页改版回归护栏
//
// 用户原话：「把顶部标题导航和下面的卡片组组在一起不要分开，滑动时一个整体滑动
//            不要下面滑动和顶部分开」
//
// 改动前：`appBar: HomeTopBar(...)` 占 Scaffold 的 appBar 槽，钉死在顶上；
//         body 的 ListView 自己滚 —— 内容从顶栏底下钻过去，视觉上两截。
// 改动后：顶栏缩成普通 widget 进 ListView 第一项，外面套一层画 headerGradient
//         的 Container，和天气卡、卡片组一起滚。
//
// 四条断言，每条都对着「改回去就会失败」写的：
//   ① 首页不许再把 HomeTopBar 挂回 Scaffold.appBar
//   ② 渐变只能画一次（两块各画一次，对角渐变会在接缝处断层）
//   ③ AppBar 进滚动流必须给定高度，否则无界高度直接崩（本轮踩到的坑）
//   ④ 滚动时头部与卡片的位移必须同向同量（这就是「一个整体」的机械定义）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_top_bar.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';
import 'package:fishing_app/widgets/mode_tabs.dart';

FishingWeather demo() => const FishingWeather(
      temperature: 13,
      humidity: 66,
      pressure: 1015,
      windSpeed: 6,
      windDir: 45,
      weatherCode: 3,
      description: '阴',
      fishIndex: '爆护',
      fishAdvice: '水氧 9.1mg/L，可以出钓',
      score: 91,
      atLabel: '17:00',
      oxygen: 9.1,
    );

/// 复刻改版后的首页骨架：深色整块（标题 + 分类 + 天气）+ 一张白卡
Widget page(ScrollController sc, {bool embedded = true, bool flat = true}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        controller: sc,
        physics: const ClampingScrollPhysics(),
        children: [
          Container(
            key: const ValueKey('header'),
            decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeTopBar(
                    mode: HomeMode.haiDiao,
                    onModeChanged: (_) {},
                    embedded: embedded),
                HomeWeatherHero(
                  weather: demo(),
                  placeLabel: '汉寿县',
                  waterTemp: 13,
                  mode: HomeMode.haiDiao,
                  flat: flat,
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('card'),
            height: 900,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('① 首页不再把顶栏钉在 Scaffold.appBar 上', () {
    test('home_screen.dart 里没有 appBar: HomeTopBar', () {
      final src = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(src.contains('appBar: HomeTopBar'), isFalse,
          reason: '顶栏挂回 appBar 槽就又变成「上面一条固定、下面自己滚」，'
              '用户要的是整体滚动');
      // 必须真的用上了 embedded 模式
      expect(src.contains('embedded: true'), isTrue,
          reason: 'HomeTopBar 必须用 embedded: true 进滚动流');
      expect(src.contains('flat: true'), isTrue,
          reason: 'HomeWeatherHero 必须用 flat: true，背景交给外层统一画');
    });

    testWidgets('顶栏确实在 ListView 内部，而不是 Scaffold 的槽位', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(sc));

      expect(
        find.descendant(
            of: find.byType(ListView), matching: find.byType(HomeTopBar)),
        findsOneWidget,
        reason: '顶栏必须长在滚动视图里，才会跟着列表一起滚',
      );
      // Scaffold 自己没有 appBar
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.appBar, isNull);
    });
  });

  group('② 渐变只画一次', () {
    testWidgets('embedded 的顶栏不画 flexibleSpace 渐变', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(sc));

      final bar = t.widget<AppBar>(find.byType(AppBar));
      expect(bar.flexibleSpace, isNull,
          reason: '顶栏再画一次对角渐变，和天气卡那块会在接缝处断层');
      expect(bar.backgroundColor, Colors.transparent,
          reason: 'embedded 时背景必须透明，露出外层的整块渐变');
    });

    testWidgets('flat 的天气卡不画背景、不留外边距', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(sc));

      final hero = t.widget<HomeWeatherHero>(find.byType(HomeWeatherHero));
      expect(hero.flat, isTrue);
      // 天气卡 build 出来的第一个 Container 就是它自己的根容器
      final box = t.widget<Container>(find
          .descendant(
            of: find.byType(HomeWeatherHero),
            matching: find.byType(Container),
          )
          .first);
      expect(box.decoration, isNull,
          reason: 'flat 时天气卡自己不许再画 headerGradient');
      expect(box.margin, EdgeInsets.zero,
          reason: '外边距要挪到外层，否则那段间距会被渐变吃掉');
    });

    testWidgets('默认（非 embedded）仍然是原来的 AppBar 版', (t) async {
      // 非 embedded 就是要在 appBar 槽里用，所以这里也放回槽位测
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
            appBar: HomeTopBar(), body: SizedBox.expand()),
      ));

      final bar = t.widget<AppBar>(find.byType(AppBar));
      expect(bar.flexibleSpace, isNotNull,
          reason: '默认路径不能被改坏：别的用法还是自己画渐变');
      expect(t.getSize(find.byType(AppBar)).height,
          HomeTopBar.barHeight + ModeTabs.height);
    });
  });

  group('③ AppBar 进滚动流必须有确定高度', () {
    testWidgets('无界高度下不抛 unbounded 断言（本轮踩到的白屏坑）', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(sc));

      expect(t.takeException(), isNull,
          reason: 'AppBar 内部是 Column(mainAxisSize.max) + flex 子项，'
              '塞进 ListView（高度无界）会直接断言崩掉 —— '
              'HomeTopBar 必须用 SizedBox 兜住高度');
      // 高度 = 标题行 + 分类条（+ 状态栏，测试环境为 0）
      final h = t.getSize(find.byType(AppBar)).height;
      expect(h, HomeTopBar.barHeight + ModeTabs.height);
    });
  });

  group('④ 滚动时头部与卡片同向同量位移', () {
    testWidgets('滚 120 后，顶栏和卡片都正好上移 120', (t) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await t.pumpWidget(page(sc));

      final bar0 = t.getRect(find.byType(AppBar)).top;
      final card0 = t.getRect(find.byKey(const ValueKey('card'))).top;

      sc.jumpTo(120);
      await t.pump();

      final bar1 = t.getRect(find.byType(AppBar)).top;
      final card1 = t.getRect(find.byKey(const ValueKey('card'))).top;

      expect(bar0 - bar1, closeTo(120, 0.5),
          reason: '顶部标题导航必须跟着一起滚（钉住的话这里会是 0）');
      expect(card0 - card1, closeTo(120, 0.5));
      expect(bar0 - bar1, closeTo(card0 - card1, 0.5),
          reason: '两者位移量不同就说明还是「两截各滚各的」');
    });
  });
}
