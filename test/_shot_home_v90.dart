// 临时：v2.1.90 首页改版人眼验收 —— 头部（标题 + 分类 + 天气）与卡片组整体滚动。
// 跑法：flutter test test/_shot_home_v90.dart
//
// 三张图：
//   home_v90_top.png    滚动 0   —— 头部完整、渐变一整块没有接缝
//   home_v90_mid.png    滚动 300 —— 头像/标题/天气一起上移，白卡跟着上来
//   home_v90_deep.png   滚动 700 —— 头部整块滚走，状态栏下面已是浅色卡片
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/services/tide_service.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/grid_nav.dart';
import 'package:fishing_app/widgets/home_top_bar.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';
import 'package:fishing_app/widgets/section_header.dart';

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

FishingWeather demoWeather() => const FishingWeather(
      temperature: 13,
      humidity: 66,
      pressure: 1015,
      windSpeed: 6,
      windDir: 45,
      weatherCode: 3,
      description: '阴',
      fishIndex: '爆护',
      fishAdvice: '水氧 9.1mg/L，是鲫鱼需求（4.2）的 216%，开口欲望强，可以出钓',
      score: 91,
      atLabel: '17:00',
      oxygen: 9.1,
    );

/// 横向钓点卡占位（真实卡片是 SpotCard，这里只要高度与观感）
Widget fakeSpotCard() => Container(
      width: 190,
      height: 96,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2430),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.place, color: Colors.white54, size: 22),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('槐树乡水库',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 5),
                Text('野钓 · 513.3km',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8A919E))),
              ],
            ),
          ),
        ],
      ),
    );

/// 瀑布流占位：两块灰底假图，高度在 1200 内才有滚动余量
Widget fakeWaterfall() => Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.pagePad, 2, AppTheme.pagePad, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 2; i++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == 0 ? 5 : 0, left: i == 1 ? 5 : 0),
                height: 260.0 + i * 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3038),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );

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

  testWidgets('首页头部与卡片组整体滚动', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final sc = ScrollController();

    // 完全复刻 HomeScreen.build 里改版后的结构
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light.copyWith(
          textTheme:
              AppTheme.light.textTheme.apply(fontFamily: 'Microsoft YaHei'),
        ),
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: ListView(
            controller: sc,
            physics: const ClampingScrollPhysics(),
            children: [
              Container(
                key: const ValueKey('header'),
                decoration:
                    const BoxDecoration(gradient: AppTheme.headerGradient),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HomeTopBar(
                        mode: HomeMode.haiDiao,
                        onModeChanged: (_) {},
                        embedded: true),
                    HomeWeatherHero(
                      weather: demoWeather(),
                      placeLabel: '汉寿县',
                      waterTemp: 13,
                      mode: HomeMode.haiDiao,
                      tide: const TideInfo(
                          heightM: 1.5, state: '平潮', rising: true, amp: 1.6),
                      flat: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GridNav(items: const [], crossAxisCount: 5),
              const SectionHeader(title: '附近钓点', subtitle: '由近到远', actionLabel: '更多'),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.pagePad),
                  children: [fakeSpotCard(), fakeSpotCard(), fakeSpotCard()],
                ),
              ),
              const SectionHeader(title: '钓友动态', subtitle: '实时更新'),
              fakeWaterfall(),
              fakeWaterfall(),
              fakeWaterfall(),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    await shoot(tester, key, 'home_v90_top');

    // 头部真实高度（行内判断状态栏深浅用的就是它）—— 先在滚动前量，
    // 滚远之后这块会被 ListView 回收，就找不到了
    final header = tester.getRect(find.byKey(const ValueKey('header')));
    debugPrint('头部整块高度 = ${header.height}');

    sc.jumpTo(150);
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, key, 'home_v90_half');

    sc.jumpTo(300);
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, key, 'home_v90_mid');

    sc.jumpTo(700);
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, key, 'home_v90_deep');
  });
}
