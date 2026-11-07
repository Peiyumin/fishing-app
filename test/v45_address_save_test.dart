import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/services/spot_service.dart';
import 'package:fishing_app/utils/address_lookup.dart';

/// v45：文字地址保存到地图上「位置不对」的修复
/// ------------------------------------------------------------
/// 线上问题：三个添加页里打字填了地址，保存下来的点却是用户当时所在地。
/// 根因链：
///   1. 后台没配高德 Key
///   2. OSM 在国内连不上（实测 21 秒超时）
///   3. 后端报错串写错，只回了「地址解析失败：」（冒号后面空的）
///   4. App 拿不到坐标 → 静默沿用「打开页面时读到的当前定位」
/// 这份测试守的是第 4 步和第 3 步：失败必须带原因，而且必须停下来问用户。
void main() {
  group('AddressLookup：解析结果必须带原因', () {
    test('成功结果能带出坐标 / 规范化地址 / 精度说明', () {
      final r = AddressLookup.success(const GeoPoint(
        lat: 34.1548,
        lng: 113.4568,
        levelText: '街道级',
        formatted: '河南省许昌市禹州市夏都街道',
        source: 'amap',
      ));
      expect(r.ok, isTrue);
      expect(r.lat, closeTo(34.1548, 1e-6));
      expect(r.formatted, contains('许昌'));
      expect(r.hint, '街道级');
    });

    test('失败结果一定有非空原因（空字符串兜底成人话）', () {
      expect(AddressLookup.failure('').reason, '没能解析成位置');
      expect(AddressLookup.failure('   ').reason, '没能解析成位置');
      expect(AddressLookup.failure('后端三条通道全挂').reason, '后端三条通道全挂');
      expect(AddressLookup.failure('x').ok, isFalse);
    });

    test('地址太短直接给原因，不发网络请求', () async {
      final r = await AddressLookup.resolve('水库');
      expect(r.ok, isFalse);
      expect(r.reason, contains('太短'));
    });

    test('GeoPoint.hint 不会拼出「（百度）· OpenStreetMap」这种鬼话', () {
      const baidu = GeoPoint(
        lat: 34.15,
        lng: 113.45,
        levelText: 'POI 级（百度）',
        source: 'baidu',
      );
      expect(baidu.hint, 'POI 级（百度）');

      const osm = GeoPoint(
        lat: 34.15,
        lng: 113.45,
        levelText: '道路级',
        source: 'osm',
      );
      expect(osm.hint, contains('OpenStreetMap'));
    });
  });

  group('解析失败的选择层', () {
    Widget host(void Function(AddressFallbackAction?) onResult) {
      return MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final a = await showAddressFallbackSheet(
                    ctx,
                    address: '河南省许昌市禹州市夏都街道',
                    reason: '地址解析失败（高德未配置 Key；OSM 连不上）',
                  );
                  onResult(a);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('三个选项都在，且把失败原因摊给用户看', (tester) async {
      await tester.pumpWidget(host((_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('这个地址没能解析成位置'), findsOneWidget);
      expect(find.text('重新填地址'), findsOneWidget);
      expect(find.text('就用我当前的定位'), findsOneWidget);
      expect(find.text('在地图上点一下'), findsOneWidget);
      expect(find.textContaining('高德未配置 Key'), findsOneWidget);
    });

    testWidgets('选「当前的定位」返回 useCurrentLocation', (tester) async {
      AddressFallbackAction? got;
      await tester.pumpWidget(host((a) => got = a));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('就用我当前的定位'));
      await tester.pumpAndSettle();
      expect(got, AddressFallbackAction.useCurrentLocation);
    });

    testWidgets('关掉弹层返回 null（等于先不提交）', (tester) async {
      AddressFallbackAction? got = AddressFallbackAction.pickOnMap;
      await tester.pumpWidget(host((a) => got = a));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(got, isNull);
    });
  });

  group('三个添加页的 v45 契约', () {
    String read(String p) => File(p).readAsStringSync();
    final wild = read('lib/screens/publish_spot_screen.dart');
    final venue = read('lib/screens/publish_venue_screen.dart');
    final shop = read('lib/screens/publish_shop_screen.dart');
    final svc = read('lib/services/spot_service.dart');

    test('边打字边解析：700ms 防抖 + 解析后把地图挪过去', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('Timer(const Duration(milliseconds: 700)'),
            isTrue);
        expect(f.contains('Future<void> _previewByAddress()'), isTrue);
        // 地图必须跟着解析点走，用户才看得见点落在哪
        expect(f.contains('_mapController.move(LatLng(g[0], g[1]), 14)'),
            isTrue);
      }
    });

    test('系统回填地址不算「用户手改」，别把 GPS 点降级', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('_suppressAddrListener = true;'), isTrue);
        expect(f.contains('_suppressAddrListener = false;'), isTrue);
      }
    });

    test('解析成功后由地址决定坐标，可信度记 0', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('lat = r.lat;'), isTrue);
        expect(f.contains('lng = r.lng;'), isTrue);
        expect(f.contains('precise = false;'), isTrue);
      }
    });

    test('顶部提示会说明「按地址定位」', () {
      expect(wild.contains("'按地址定位："), isTrue);
      expect(venue.contains("'按地址定位："), isTrue);
      expect(shop.contains("'按地址定位："), isTrue);
    });

    test('辅助文案把「没解析出位置」的原因显示出来', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('没解析出位置：'), isTrue);
      }
    });

    test('服务层：失败原因写进 lastGeocodeError，不再 catch 掉', () {
      expect(svc.contains('static String lastGeocodeError'), isTrue);
      expect(svc.contains("lastGeocodeError = e.message"), isTrue);
      expect(svc.contains('on ApiException catch (e)'), isTrue);
      // 老写法 `catch (_) { return null; }` 会把 401/400/网络错误一起吞掉
      expect(svc.contains('} catch (_) {\n      return null;\n    }'), isFalse);
    });
  });

  group('后端 v45：多一条免 Key 通道', () {
    final p = File('C:/Users/Administrator/Desktop/垂钓圈/fishing_php_admin/'
        'lib/geocode.php');

    test('geo_forward 走「高德 → 百度 → OSM」三条通道', () {
      if (!p.existsSync()) return; // 后台源码不在这台机器上就跳过
      final s = p.readAsStringSync();
      expect(s.contains('function geo_baidu_parse'), isTrue);
      expect(s.contains('function geo_baidu_mc_to_ll'), isTrue);
      expect(s.contains('地图网页搜索'), isTrue);
      final a = s.indexOf('通道 1：高德');
      final b = s.indexOf('通道 2：百度');
      final c = s.indexOf('通道 3：Nominatim');
      expect(a > 0 && b > a && c > b, isTrue);
      // 百度给的是 BD-09 / 自家墨卡托，必须过两道换算
      expect(s.contains("'bd09'"), isTrue);
    });
  });
}
