// v46 首页改版：顶部天气 + 后台可配分类导航 + 4/5 列切换 + 首页广告位
//
// 守的四件事：
//   1. 后台没配 / 断网时首页**不能变空**（必须有内置兜底，且和改版前一致）
//   2. 分类是后台下发的，名字/图标/顺序/列数都跟着接口走
//   3. 广告只展示在投的那一条，图片框固定 12:5（不因素材尺寸把首页顶变形）
//   4. 首页顺序：天气在最上 → 分类 → 广告 → 附近钓点

import 'dart:convert';
import 'dart:io';

import 'package:fishing_app/models/home_layout.dart';
import 'package:fishing_app/services/home_service.dart';
import 'package:fishing_app/utils/home_icons.dart';
import 'package:fishing_app/widgets/grid_nav.dart';
import 'package:fishing_app/widgets/home_ad_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String read(String p) => File(p).readAsStringSync();

/// 后台源码（不在这个仓库里，仅本机存在时做跨端一致性校验）
File? phpLib() {
  for (final p in [
    'C:/Users/Administrator/Desktop/垂钓圈/fishing_php_admin/lib/home_layout.php',
    '../fishing_php_admin/lib/home_layout.php',
  ]) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  return null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeService.resetForTest();
  });

  group('HomeLayout 解析', () {
    test('grid_cols 4 / 5 都认，其他值回落 5', () {
      expect(HomeLayout.fromJson({'grid_cols': 4, 'categories': [], 'ads': []})
          .gridCols, 4);
      expect(HomeLayout.fromJson({'grid_cols': 5, 'categories': [], 'ads': []})
          .gridCols, 5);
      // 后台被改成别的数（比如手改数据库），App 不能画出 3 列或 7 列
      expect(HomeLayout.fromJson({'grid_cols': 3, 'categories': [], 'ads': []})
          .gridCols, 5);
      expect(HomeLayout.fromJson({'grid_cols': 'x', 'categories': [], 'ads': []})
          .gridCols, 5);
    });

    test('分类按后台顺序解析，空名字的丢掉', () {
      final l = HomeLayout.fromJson({
        'grid_cols': 4,
        'categories': [
          {'id': '1', 'name': '黑坑', 'icon': 'blackpit', 'value': 'blackpit'},
          {'id': '2', 'name': '   ', 'icon': 'spot', 'value': 'spot'},
          {'id': '3', 'name': '钓场', 'icon': 'pond', 'value': 'pond'},
        ],
        'ads': [],
      });
      expect(l.categories.map((c) => c.name).toList(), ['黑坑', '钓场']);
      expect(l.gridCols, 4);
    });

    test('没有图片的广告直接丢掉（否则首页会出现一个空框）', () {
      final l = HomeLayout.fromJson({
        'grid_cols': 5,
        'categories': [],
        'ads': [
          {'id': 'a', 'title': '有图', 'image': 'https://x/1.jpg'},
          {'id': 'b', 'title': '没图', 'image': ''},
        ],
      });
      expect(l.ads.length, 1);
      expect(l.ads.first.title, '有图');
    });

    test('外链留空时 link 是 null（详情页不该画「打开链接」）', () {
      final ad = HomeAd.fromJson({'id': 'a', 'title': 't', 'image': 'i', 'link': '  '});
      expect(ad.link, isNull);
      final ad2 = HomeAd.fromJson(
          {'id': 'a', 'title': 't', 'image': 'i', 'link': 'https://x'});
      expect(ad2.link, 'https://x');
    });

    test('分类一条都没有时回落到内置 10 个（首页不能空）', () {
      final l = HomeLayout.fromJson({'grid_cols': 5, 'categories': [], 'ads': []});
      expect(l.categories.length, 10);
      expect(l.categories.first.name, '天气');
    });
  });

  group('内置兜底 = 改版前的 10 个入口', () {
    test('名字和顺序与旧 GridNav 一致', () {
      expect(
        HomeLayout.fallback.categories.map((c) => c.name).toList(),
        ['天气', '钓点', '渔获', '路亚', '黑坑', '装备', '技巧', '活动', '商城', '直播'],
      );
      expect(HomeLayout.fallback.gridCols, 5);
      expect(HomeLayout.fallback.ads, isEmpty);
    });

    test('每个兜底分类都能找到图标，不会画成兜底问号', () {
      for (final c in HomeLayout.fallback.categories) {
        expect(kHomeIcons.containsKey(c.icon), isTrue, reason: c.name);
      }
    });
  });

  group('分类点击路由', () {
    test('实现了的页面都能拿到 Widget', () {
      const tags = [
        'weather', 'spot', 'catch', 'lure', 'skill', 'event',
        'shop', 'pond', 'guide', 'nearby', 'signin', 'member',
      ];
      for (final t in tags) {
        expect(GridNav.routeOf(t), isNotNull, reason: 'tag=$t 没有对应页面');
      }
    });

    test('还没做的频道返回 null（点上去给提示，而不是跳到空白页）', () {
      for (final t in ['blackpit', 'gear', 'live', '']) {
        expect(GridNav.routeOf(t), isNull, reason: 'tag=$t');
      }
    });
  });

  group('图标表跨端一致', () {
    test('后台 home_icon_catalog 的 key 都能在 App 里找到图标', () {
      final f = phpLib();
      if (f == null) {
        // ignore: avoid_print
        print('跳过：本机没有后端源码，跨端一致性检查需要 fishing_php_admin');
        return;
      }
      final src = f.readAsStringSync();
      final start = src.indexOf('function home_icon_catalog');
      final end = src.indexOf('function home_action_catalog');
      final block = src.substring(start, end);
      final keys = RegExp(r"'([a-z]+)'\s*=>\s*'").allMatches(block).map((m) => m.group(1)!).toSet();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(kHomeIcons.containsKey(k), isTrue,
            reason: '后台给了图标 key=$k，App 的 kHomeIcons 里没有 → 会显示兜底图标');
      }
    });

    test('后台 home_action_catalog 的 tag 都能跳页面', () {
      final f = phpLib();
      if (f == null) return;
      final src = f.readAsStringSync();
      final start = src.indexOf('function home_action_catalog');
      final block = src.substring(start);
      final tags = RegExp(r"'([a-z]+)'\s*=>\s*'")
          .allMatches(block)
          .map((m) => m.group(1)!)
          .toSet();
      expect(tags, isNotEmpty);
      for (final t in tags) {
        expect(GridNav.routeOf(t), isNotNull,
            reason: '后台能选 tag=$t，但 App 里没有对应页面');
      }
    });

    test('后台的兜底 seed 也在 App 图标表里', () {
      final f = phpLib();
      if (f == null) return;
      final src = f.readAsStringSync();
      final start = src.indexOf('function home_categories_seed');
      final block = src.substring(start, start + 1200);
      // seed 里每行形如 ['weather', '天气', 'weather']
      for (final m in RegExp(r"\['([a-z]+)',\s*'([^']+)',\s*'([a-z]+)'\]").allMatches(block)) {
        expect(kHomeIcons.containsKey(m.group(1)), isTrue, reason: m.group(1));
      }
    });
  });

  group('HomeService 缓存', () {
    test('没缓存时 current 就是内置兜底，不是空', () {
      expect(HomeService.current.categories.length, 10);
    });

    test('后台配置能写进缓存再读出来（下次启动首帧就是新宫格）', () async {
      final layout = HomeLayout.fromJson({
        'grid_cols': 4,
        'categories': [
          {'id': '1', 'name': '黑坑', 'icon': 'blackpit', 'value': 'blackpit'},
        ],
        'ads': [
          {'id': 'a', 'title': '双十一', 'image': 'https://x/a.jpg', 'content': '正文'},
        ],
      });
      final sp = await SharedPreferences.getInstance();
      await sp.setString('home_layout_v1', jsonEncode(layout.toJson()));

      HomeService.resetForTest();
      final cached = await HomeService.loadCache();
      expect(cached, isNotNull);
      expect(cached!.gridCols, 4);
      expect(cached.categories.single.name, '黑坑');
      expect(cached.ads.single.title, '双十一');
      expect(HomeService.current.gridCols, 4);
    });

    test('缓存是坏 JSON 时当作没缓存（不能崩首页）', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('home_layout_v1', '这不是 JSON');
      HomeService.resetForTest();
      expect(await HomeService.loadCache(), isNull);
      expect(HomeService.current.categories.length, 10);
    });
  });

  group('宫格列数', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('后台配 4 个一行，GridView 就是 4 列', (tester) async {
      await tester.pumpWidget(wrap(const GridNav(crossAxisCount: 4)));
      final g = tester.widget<GridView>(find.byType(GridView));
      final delegate = g.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 4);
      // 兜底 10 个 → 两行半，至少 3 行
      expect(find.text('天气'), findsOneWidget);
    });

    testWidgets('默认 5 个一行', (tester) async {
      await tester.pumpWidget(wrap(const GridNav()));
      final g = tester.widget<GridView>(find.byType(GridView));
      final delegate = g.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 5);
    });

    testWidgets('后台只配了 3 个就只画 3 个（没有硬编码的残留入口）', (tester) async {
      await tester.pumpWidget(wrap(const GridNav(
        crossAxisCount: 5,
        items: [
          HomeCategory(id: '1', name: '黑坑', icon: 'blackpit', value: 'blackpit'),
          HomeCategory(id: '2', name: '钓场', icon: 'pond', value: 'pond'),
          HomeCategory(id: '3', name: '图鉴', icon: 'guide', value: 'guide'),
        ],
      )));
      expect(find.text('黑坑'), findsOneWidget);
      expect(find.text('钓场'), findsOneWidget);
      expect(find.text('图鉴'), findsOneWidget);
      expect(find.text('直播'), findsNothing);
    });
  });

  group('广告位', () {
    testWidgets('固定 12:5，不随图片原始尺寸变化', (tester) async {
      expect(HomeAdBanner.aspect, 12 / 5);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeAdBanner(
            ad: const HomeAd(id: 'a', title: '双十一', image: 'https://x/a.jpg'),
          ),
        ),
      ));
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(ar.aspectRatio, 12 / 5);
    });
  });

  group('首页版式顺序', () {
    test('天气在最上，然后分类导航，再广告位，最后附近钓点', () {
      final src = read('lib/screens/home_screen.dart');
      final hero = src.indexOf('HomeWeatherHero(');
      final grid = src.indexOf('GridNav(items: _layout.categories');
      final ad = src.indexOf('HomeAdBanner(ad: topAd)');
      final spots = src.indexOf("title: '附近钓点'");
      expect(hero, greaterThan(-1));
      expect(grid, greaterThan(hero), reason: '分类导航必须在天气下面');
      expect(ad, greaterThan(grid), reason: '广告位必须在分类导航下面');
      expect(spots, greaterThan(ad), reason: '附近钓点必须在广告位下面');
    });

    test('天气块绑的是内存里的天气（首帧就有数，不是转圈）', () {
      final src = read('lib/screens/home_screen.dart');
      expect(src.contains('weather: _weather'), isTrue);
      expect(src.contains('waterTemp: WeatherService.memoryWaterTemp'), isTrue);
    });

    test('广告位跟着后台开关走：没有在投广告就不占位', () {
      final src = read('lib/screens/home_screen.dart');
      expect(src.contains('if (topAd != null) HomeAdBanner'), isTrue);
    });
  });

  group('广告详情页（App 内展示，不甩浏览器）', () {
    test('页面结构：大图 + 标题 + 正文 + 可选外链按钮', () {
      final src = read('lib/screens/ad_detail_screen.dart');
      expect(src.contains('ad.title'), isTrue);
      expect(src.contains('ad.content'), isTrue);
      expect(src.contains("Text('打开链接')"), isTrue);
      // 没配外链时不能出现按钮
      expect(src.contains('if (hasLink)'), isTrue);
      // 正文为空要给一句人话，而不是空白页
      expect(src.contains('该广告没有填写正文'), isTrue);
    });

    test('外链缺协议头时自动补 https://', () {
      final src = read('lib/screens/ad_detail_screen.dart');
      expect(src.contains("url = 'https://\$url'"), isTrue);
    });
  });
}
