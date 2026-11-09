// v2.1.89 回归护栏
//
// 这一版用户提了五件事，每件都钉在这里：
//   ① 首页定位名字要是**简体中文**（截图里是「漢壽縣」）；
//   ② 取消首页下拉刷新 + 上滑加载更多，改成「打开刷一次 / 回来自动刷」；
//   ③ 打开 App 就要把定位地址填好（首帧不能是空）；
//   ④ 冷启动别卡（启动配置走本机缓存，不再每次等接口）；
//   ⑤ 底图压进安装包：地图打开先用本机瓦片秒出图，放大后才联网。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/screens/home_screen.dart';
import 'package:fishing_app/services/app_service.dart';
import 'package:fishing_app/services/geo_place.dart';
import 'package:fishing_app/services/map_style.dart';
import 'package:fishing_app/services/map_tile_source.dart';
import 'package:fishing_app/services/offline_tiles.dart';
import 'package:fishing_app/services/refresh_bus.dart';
import 'package:fishing_app/services/session_provider.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/utils/county_label.dart';
import 'package:fishing_app/utils/zh_hans.dart';

const _kCurKey = 'wx_current_v1';

Map<String, dynamic> _wxCache() => {
      'lat': 28.9,
      'lng': 111.97,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'w': {
        't': 22.0,
        'h': 78,
        'ws': 16.0,
        'wd': 90,
        'p': 1008.0,
        'c': 0,
        'd': '晴',
        'fi': '有口',
        'fa': '微风',
        'sc': 82,
        'al': '14:00',
        'ox': 9.8,
      },
    };

Widget _wrap(Widget page) => ChangeNotifierProvider<SessionProvider>(
      create: (_) => SessionProvider(),
      child: MaterialApp(theme: AppTheme.light, home: page),
    );

void main() {
  group('① 地名必须是简体', () {
    test('漢壽縣 → 汉寿县（用户截图里的那个县）', () {
      expect(ZhHans.toSimplified('漢壽縣'), '汉寿县');
    });

    test('常见繁体地名逐字转简体', () {
      expect(ZhHans.toSimplified('臺灣省'), '台湾省');
      expect(ZhHans.toSimplified('湖南省常德市漢壽縣'), '湖南省常德市汉寿县');
      expect(ZhHans.toSimplified('黑龍江省齊齊哈爾市'), '黑龙江省齐齐哈尔市');
      expect(ZhHans.toSimplified('廣東省深圳市龍崗區'), '广东省深圳市龙岗区');
    });

    test('本来就是简体 / 非中文：原样返回（不改长度、不动顺序）', () {
      expect(ZhHans.toSimplified('禹州市'), '禹州市');
      expect(ZhHans.toSimplified('Hangzhou'), 'Hangzhou');
      expect(ZhHans.toSimplified(''), '');
      expect(ZhHans.toSimplified('2026-11-09'), '2026-11-09');
    });

    test('GeoPlace 入口统一转简体（后端 / 直连 / 旧缓存三条路一起治）', () {
      final p = GeoPlace.fromJson({
        'province': '湖南省',
        'city': '常德市',
        'district': '漢壽縣',
        'street': '龍陽街道',
        'short': '漢壽',
        'display': '湖南省常德市漢壽縣龍陽街道',
      });
      expect(p.district, '汉寿县');
      expect(p.street, '龙阳街道');
      expect(p.short, '汉寿');
      expect(p.label, '汉寿');
      expect(p.display, '湖南省常德市汉寿县龙阳街道');
      expect(p.display.contains('漢'), isFalse, reason: '首页天气区读的就是这些字段');
    });

    test('转简体后县级截取照旧（不改地名长度，截取规则不受影响）', () {
      final p = GeoPlace.fromJson({
        'city': '常德市',
        'district': '漢壽縣',
        'display': '湖南省常德市漢壽縣龍陽街道',
      });
      expect(countyLabel(city: p.city, district: p.district),
          '常德市汉寿县');
      expect(countyFromDisplay(p.display), '常德市汉寿县');
    });
  });

  group('③ 定位地名首帧就要有', () {
    test('GeoPlace.warmUp 把 12h 内的缓存提到内存，供首页同步取', () async {
      SharedPreferences.setMockInitialValues({
        'geo_place_v1': jsonEncode({
          'province': '湖南省',
          'city': '常德市',
          'district': '漢壽縣',
          'short': '漢壽',
          'display': '湖南省常德市漢壽縣',
        }),
        'geo_place_v1_at': DateTime.now().millisecondsSinceEpoch,
      });
      await GeoPlace.warmUp();
      final memo = GeoPlace.memo;
      expect(memo, isNotNull, reason: '启动预热没把地名读进内存，首页首帧就是空的');
      expect(memo!.label, '汉寿', reason: '缓存里是繁体，读出来必须已经是简体');
    });
  });

  group('④ 启动配置走本机缓存，不再每次等接口', () {
    setUp(AppService.resetForTest);

    test('warmUp 读到缓存 → cached 立刻可用（放行不必等网络）', () async {
      SharedPreferences.setMockInitialValues({
        'boot_cache_v1': jsonEncode({'previews': [], 'ads': []}),
        'boot_cache_v1_at': DateTime.now().millisecondsSinceEpoch,
      });
      await AppService.warmUp();
      expect(AppService.cached, isNotNull,
          reason: '有新鲜缓存时应当直接放行，而不是再等一次 /app/bootstrap');
    });

    test('缓存过期（>6h）→ 视为没有，该等一次接口', () async {
      SharedPreferences.setMockInitialValues({
        'boot_cache_v1': jsonEncode({'previews': [], 'ads': []}),
        'boot_cache_v1_at': DateTime.now()
            .subtract(const Duration(hours: 7))
            .millisecondsSinceEpoch,
      });
      await AppService.warmUp();
      expect(AppService.cached, isNull);
    });
  });

  group('② 首页取消下拉 / 上滑加载', () {
    testWidgets('首页里没有 RefreshIndicator（下拉刷新已移除）', (tester) async {
      SharedPreferences.setMockInitialValues({_kCurKey: jsonEncode(_wxCache())});
      WeatherService.clearMemory();
      await WeatherService.warmUp();

      await tester.pumpWidget(_wrap(const HomeScreen()));
      expect(find.byType(RefreshIndicator), findsNothing,
          reason: '用户要求取消下拉刷新，首页不能再挂 RefreshIndicator');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 20));
    });

    testWidgets('底部没有「没有更多了」/加载更多转圈', (tester) async {
      SharedPreferences.setMockInitialValues({_kCurKey: jsonEncode(_wxCache())});
      WeatherService.clearMemory();
      await WeatherService.warmUp();

      await tester.pumpWidget(_wrap(const HomeScreen()));
      expect(find.text('没有更多了'), findsNothing,
          reason: '上滑加载更多已取消，底部指示器不该再出现');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 20));
    });

    test('homeTick 是「回到首页」的刷新信号', () {
      var n = 0;
      void f() => n++;
      RefreshBus.homeTick.addListener(f);
      addTearDown(() => RefreshBus.homeTick.removeListener(f));
      RefreshBus.bumpHome();
      expect(n, 1, reason: '点底部「首页」/ 从别的 Tab 切回来就靠它触发刷新');
    });

    test('源码护栏：首页不套 AppRefresh，MainShell 点「首页」打 homeTick', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home.contains('AppRefresh('), isFalse,
          reason: '首页还套着下拉刷新容器');
      expect(home.contains('didPopNext'), isTrue,
          reason: '从二级页返回时没有自动刷新');
      expect(home.contains('RefreshBus.homeTick.addListener'), isTrue);

      final shell = File('lib/main.dart').readAsStringSync();
      expect(shell.contains('RefreshBus.bumpHome()'), isTrue,
          reason: '点底部导航「首页」必须打一枪刷新');
      expect(shell.contains('navigatorObservers: [routeObserver]'), isTrue,
          reason: '没挂 RouteObserver，didPopNext 永远不会回调');
    });
  });

  group('⑤ 随包底图', () {
    setUp(OfflineTiles.resetForTest);
    tearDown(OfflineTiles.resetForTest);

    test('清单里确实带了 2000+ 张瓦片，且命名符合 {z}/{x}_{y}', () {
      final raw = File('assets/tiles/manifest.json').readAsStringSync();
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final tiles = (m['tiles'] as List).cast<String>();
      expect(tiles.length, greaterThan(2000));
      expect(m['maxZoom'], OfflineTiles.maxZoom);
      for (final t in tiles.take(50)) {
        expect(RegExp(r'^\d{1,2}/\d{1,4}_\d{1,4}$').hasMatch(t), isTrue,
            reason: '瓦片键格式不对：$t');
      }
      // 抽查一张真的在磁盘上
      final first = tiles.first.split('/');
      final z = first[0];
      final xy = first[1].split('_');
      final f = File('assets/tiles/img/$z/${xy[0]}_${xy[1]}.webp');
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(500));
    });

    test('解压目录就绪后给出 file:// 模板（MapLibre 认这个 scheme）', () {
      expect(OfflineTiles.tileTemplate, isNull, reason: '还没解压时不该给出模板');
      OfflineTiles.debugSetDir('/data/user/0/app/files/map_offline/v1', count: 2394);
      expect(OfflineTiles.tileTemplate,
          'file:///data/user/0/app/files/map_offline/v1/{z}/{x}/{y}.webp');
      expect(OfflineTiles.tileFile(8, 208, 104),
          '/data/user/0/app/files/map_offline/v1/8/208/104.webp');
      expect(OfflineTiles.tileFile(9, 416, 208), isNull,
          reason: 'z9 以上随包没有，必须走网络');
    });

    test('样式里随包层在在线低清层之上、高清层之下', () {
      OfflineTiles.debugSetDir('/tmp/map_offline/v1', count: 10);
      const tile = TileSource(kind: TileSourceKind.geovisearth, geoToken: 't');
      final style = buildRasterStyle(
        tile: tile,
        urls: (t) => [t],
        offlineTemplate: OfflineTiles.tileTemplate,
        background: '#EDF1F6',
      );
      final sources = style['sources'] as Map;
      expect(sources.containsKey('sat-off'), isTrue);
      final off = sources['sat-off'] as Map;
      expect(off['maxzoom'], OfflineTiles.maxZoom);
      expect((off['tiles'] as List).first, startsWith('file://'));

      final ids = [
        for (final l in (style['layers'] as List)) (l as Map)['id']
      ];
      expect(ids.indexOf('sat-low'), lessThan(ids.indexOf('sat-off')));
      expect(ids.indexOf('sat-off'), lessThan(ids.indexOf('sat')));
      // 高清层仍是 z9 起接管 = 「放大后再联网」
      expect((sources['sat'] as Map)['minzoom'], 9);
    });

    test('没有随包底图时样式不多出 sat-off（退回纯在线）', () {
      final style = buildRasterStyle(
        tile: const TileSource(kind: TileSourceKind.gaode),
        urls: (t) => [t],
        background: '#EDF1F6',
      );
      expect((style['sources'] as Map).containsKey('sat-off'), isFalse);
      final ids = [
        for (final l in (style['layers'] as List)) (l as Map)['id']
      ];
      expect(ids.contains('sat-off'), isFalse);
    });
  });
}
