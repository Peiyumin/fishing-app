import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/screens/spots_screen.dart';
import 'package:fishing_app/screens/spot_map_screen.dart';
import 'package:fishing_app/services/location_service.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';

/// v2.1.88 两处「去掉多余的东西」
///
/// ① 首页天气区：地名前面的图钉图标删掉，只留名字（用户截图反馈）；
/// ② 钓点页：顶部标题「钓点」删掉、导航条改半透明、二级胶囊上移到
///    贴住状态栏，地图铺到屏幕最上沿。
///
/// 这层改动最容易回归的不是「好不好看」，而是：
///   - 标题删了但 AppBar 还占着 46pt，胶囊没真上移；
///   - 胶囊是浮层了，但地图浮层（右侧 5 个圆钮、左侧信息条）还按老的 64
///     往下排，被导航条压住 / 或者压住导航条；
///   - 列表 Tab 没让出导航条高度，第一条卡被压掉一半。
void main() {
  setUp(() {
    SpotMapScreen.testSkipTiles = true;
    LocationService.testDetermineOverride =
        ({LocationAccuracy accuracy = LocationAccuracy.high}) async => Position(
              longitude: 113.47,
              latitude: 34.19,
              timestamp: DateTime.now(),
              accuracy: 10,
              altitude: 100,
              altitudeAccuracy: 1,
              heading: 0,
              headingAccuracy: 1,
              speed: 0,
              speedAccuracy: 1,
            );
  });

  tearDown(() {
    SpotMapScreen.testSkipTiles = false;
    LocationService.testDetermineOverride = null;
  });

  /// 真机顶部有状态栏：widget 测试默认 padding=0，必须自己补，
  /// 否则「胶囊有没有贴住状态栏」这条根本测不出来。
  const statusBar = 47.0;
  Widget phone(Widget child, double width) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          padding: const EdgeInsets.only(top: statusBar, bottom: 34),
          viewPadding: const EdgeInsets.only(top: statusBar, bottom: 34),
        ),
        child: child,
      );

  Future<void> pumpSpots(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: phone(const SpotsScreen(), width),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> goMapTab(WidgetTester tester) async {
    await tester.tap(find.text('野钓钓点'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  // ───────────────────────── ① 钓点页头部 ─────────────────────────

  group('① 钓点页：无标题 + 半透明导航 + 胶囊上移', () {
    testWidgets('标题「钓点」删了，顶栏不再是 AppBar', (tester) async {
      await pumpSpots(tester);
      expect(find.text('钓点'), findsNothing);
      // 原来用的是 AppBar(title: Text('钓点'))，现在换成 PreferredSize 浮层
      expect(find.byType(AppBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('二级胶囊贴在状态栏下面（不是老布局的 90+44）', (tester) async {
      await pumpSpots(tester);
      final chip = tester.getRect(find.text('野钓钓点'));
      // 老布局：状态栏 47 + toolbar 46 + 胶囊行 44 → 胶囊中心 ≈ 115
      // 新布局：状态栏 47 + 导航条 52 → 胶囊中心 ≈ 73
      expect(chip.center.dy, lessThan(statusBar + kSpotsHeaderH));
      expect(chip.center.dy, greaterThan(statusBar));
      // 三个 Tab 都在一行：纵向中心一致
      expect(tester.getRect(find.text('渔具店（0）')).center.dy,
          closeTo(chip.center.dy, 1.0));
    });

    testWidgets('二级分类是灰色透明胶囊（0<alpha<255），顶栏本体全透明', (tester) async {
      await pumpSpots(tester);
      // 顶部那层的「最高祖先 Container」不能有底色 —— 用户要求背景透明/去掉
      final header = find.byType(PreferredSize).first;
      final topBoxes = tester
          .widgetList<Container>(
              find.descendant(of: header, matching: find.byType(Container)))
          .toList();
      expect(topBoxes.first.decoration, isNull,
          reason: '顶栏最外层不能画底色，地图要从状态栏后面透出来');

      // 但包住三颗胶囊的那一个必须是灰色透明
      final translucent = topBoxes
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null)
          .where((d) => d.color!.alpha > 0 && d.color!.alpha < 255)
          .toList();
      expect(translucent, hasLength(1),
          reason: '只留一条灰色透明的胶囊底，别再造第二条半透明横条');
    });

    testWidgets('状态栏图标随 Tab 走：地图页白、列表页深', (tester) async {
      await pumpSpots(tester);
      SystemUiOverlayStyle style() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find
              .descendant(
                  of: find.byType(PreferredSize).first,
                  matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
              .first)
          .value;
      expect(style(), SystemUiOverlayStyle.dark);
      await goMapTab(tester);
      expect(style(), SystemUiOverlayStyle.light,
          reason: '地图页底下是卫星图（深色），状态栏必须是白图标');
    });

    testWidgets('列表 Tab 右上角「+」还在，且落在导航条里', (tester) async {
      await pumpSpots(tester);
      final add = find.byTooltip('添加钓场');
      expect(add, findsOneWidget);
      final r = tester.getRect(add);
      expect(r.center.dy, lessThan(statusBar + kSpotsHeaderH));
      // 触控目标 ≥ 44
      expect(r.width, greaterThanOrEqualTo(44));
      expect(r.height, greaterThanOrEqualTo(44));
    });

    testWidgets('地图 Tab 右上角「+」去掉（左侧竖条已有「标记」）', (tester) async {
      await pumpSpots(tester);
      await goMapTab(tester);
      expect(find.byTooltip('标记野钓点'), findsNothing);
      expect(find.byTooltip('添加钓场'), findsNothing);
      // 但「标记」入口必须在，否则没法发钓点
      expect(find.text('标记'), findsOneWidget);
    });

    testWidgets('列表 Tab 让出了导航条：第一条卡不被压住', (tester) async {
      await pumpSpots(tester);
      final card = tester.getRect(find.text('太湖湾黑坑塘').first);
      expect(card.top, greaterThan(statusBar + kSpotsHeaderH),
          reason: '卡片顶边必须在导航条下沿之下');
    });
  });

  // ───────────────────────── ② 地图铺到最上沿 ─────────────────────────

  group('② 野钓钓点：地图铺满整屏，浮层让开导航条', () {
    testWidgets('Scaffold 开了 extendBodyBehindAppBar', (tester) async {
      await pumpSpots(tester);
      final scaf = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaf.extendBodyBehindAppBar, isTrue);
    });

    testWidgets('TabBarView 从 y=0 开始（地图能顶到状态栏后面）', (tester) async {
      await pumpSpots(tester);
      expect(tester.getRect(find.byType(TabBarView)).top, 0);
    });

    testWidgets('右侧工具条第一个圆钮在导航条下沿之下，不重叠', (tester) async {
      await pumpSpots(tester);
      await goMapTab(tester);
      final zoomIn = tester.getRect(find.byTooltip('放大'));
      expect(zoomIn.top,
          greaterThanOrEqualTo(statusBar + kSpotsHeaderH));
      expect(tester.takeException(), isNull);
    });

    testWidgets('地图 Tab：AI 找钓点胶囊往下移了（bottom 88 → 52）', (tester) async {
      await pumpSpots(tester);
      await goMapTab(tester);
      final mapBottom = tester.getRect(find.byType(TabBarView)).bottom;
      final ai = tester.getRect(find.text('AI 找钓点'));
      // 老位置 88：文字底边离地图底边 ~100+；现在应当在 60 以内
      expect(mapBottom - ai.bottom, lessThan(72),
          reason: 'AI 胶囊要更贴底，但别压住底部「+」发布按钮');
      expect(mapBottom - ai.bottom, greaterThan(20));
    });

    testWidgets('窄屏 320dp：灰色透明胶囊不溢出', (tester) async {
      await pumpSpots(tester, width: 320);
      await goMapTab(tester);
      final shopChip = tester.getRect(find.text('渔具店（0）'));
      expect(shopChip.right, lessThanOrEqualTo(320 - 12),
          reason: '最右那颗胶囊不能顶出屏幕（右边距 12）');
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────────────── ③ 首页地名去图标 ─────────────────────────

  group('③ 首页天气区：地名只留文字', () {
    // 天气区内部用了 InkWell（点整块进天气页），必须有 Material 祖先
    Widget hero({double width = 390}) => MaterialApp(
          theme: AppTheme.light,
          home: Material(
            color: const Color(0xFF101014),
            child: Center(
              child: SizedBox(
                width: width,
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
                  placeLabel: '禹州',
                  waterTemp: 12,
                  mode: HomeMode.taiDiao,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('地名前没有图钉图标', (tester) async {
      await tester.pumpWidget(hero());
      await tester.pump();
      expect(find.byIcon(Icons.place), findsNothing);
      expect(find.byIcon(Icons.location_on), findsNothing);
      expect(find.text('禹州'), findsOneWidget);
    });

    testWidgets('地名贴左边距（图标去掉后没有那 20px 空位）', (tester) async {
      await tester.pumpWidget(hero());
      await tester.pump();
      final r = tester.getRect(find.text('禹州'));
      final panel = tester.getRect(find.byType(HomeWeatherHero));
      // 面板左右内边距 16：文字左边缘应当就在 16 附近
      expect(r.left - panel.left, lessThan(20));
    });

    testWidgets('320 窄屏：地名去掉图标后仍不溢出', (tester) async {
      await tester.pumpWidget(hero(width: 320));
      await tester.pump();
      expect(find.text('禹州'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
