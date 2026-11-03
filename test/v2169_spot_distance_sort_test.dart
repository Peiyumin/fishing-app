import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/screens/spot_map_screen.dart';
import 'package:fishing_app/screens/spots_screen.dart';
import 'package:fishing_app/services/location_service.dart';
import 'package:fishing_app/services/spot_service.dart';
import 'package:fishing_app/utils/spot_sort.dart';

/// 钓点列表「距我由近到远」（v2.1.69）
///
/// 用户报：「导入新钓场后显示排序不是由近到远，而是随便的顺序。」
///
/// 真因两条，缺一条都不会是这个现象：
///   ① 「钓点」页从来没做过距离排序 —— 直接把接口顺序铺成列表，
///      而接口只有 `ORDER BY s.created_at DESC`；
///   ② 批量导入的 51 个钓场在 4 毫秒内全部入库（线上实测 created_at
///      只有 18 个不同值），并列行的返回顺序由 MySQL 决定，看起来就是乱排。
///
/// 所以判据定成三条机器可判定的：
///   · 有定位 → 列表按距离升序，无坐标的点沉底；
///   · 同距离 → 顺序稳定（不能每次重建都跳）；
///   · 没定位 → 保持后端顺序，不能凭空乱动。
void main() {
  FishingSpot spot({
    required String id,
    required String name,
    required double lat,
    required double lng,
    String kind = 'venue',
    String type = '黑坑',
  }) =>
      FishingSpot(
        id: id,
        name: name,
        type: type,
        kind: kind,
        lat: lat,
        lng: lng,
        rating: 0,
        description: '简介$name',
        address: '河南省许昌市$name',
        tags: '黑坑,官方整理',
      );

  group('sortSpotsByDistance', () {
    // 参考点：许昌（34.19, 113.47）
    const myLat = 34.19;
    const myLng = 113.47;

    test('由近到远：远端在前也会被重排', () {
      final list = [
        spot(id: 'c', name: '远点', lat: 34.24, lng: 113.47), // ~5.5km
        spot(id: 'a', name: '近点', lat: 34.191, lng: 113.47), // ~111m
        spot(id: 'b', name: '中点', lat: 34.20, lng: 113.47), // ~1.1km
      ];
      final out = sortSpotsByDistance(list, myLat, myLng);
      expect(out.map((s) => s.name).toList(), ['近点', '中点', '远点']);
      // 不就地修改入参（列表可能被别处复用）
      expect(list.map((s) => s.name).toList(), ['远点', '近点', '中点']);
    });

    test('无坐标（0,0）/ 越界的点沉底，不参与「几千公里」排序', () {
      final list = [
        spot(id: 'z', name: '阿无坐标', lat: 0, lng: 0),
        spot(id: 'y', name: '越界点', lat: 999, lng: 999),
        spot(id: 'a', name: '近点', lat: 34.191, lng: 113.47),
        spot(id: 'b', name: '远点', lat: 34.30, lng: 113.47),
      ];
      final out = sortSpotsByDistance(list, myLat, myLng);
      expect(out.take(2).map((s) => s.name).toList(), ['近点', '远点']);
      expect(out.skip(2).map((s) => s.name).toList(), ['越界点', '阿无坐标']);
    });

    test('距离相同按名称定序，多次排序结果完全一致', () {
      final list = [
        spot(id: '3', name: '丙点', lat: 34.191, lng: 113.47),
        spot(id: '1', name: '甲点', lat: 34.191, lng: 113.47),
        spot(id: '2', name: '乙点', lat: 34.191, lng: 113.47),
      ];
      final first = sortSpotsByDistance(list, myLat, myLng);
      final second = sortSpotsByDistance(list, myLat, myLng);
      expect(first.map((s) => s.id).toList(), second.map((s) => s.id).toList());
      expect(first.map((s) => s.name).toList(), ['丙点', '乙点', '甲点']);
    });

    test('没有定位 / 少于两条：原样返回，不动后端顺序', () {
      final list = [
        spot(id: 'c', name: '远点', lat: 34.30, lng: 113.47),
        spot(id: 'a', name: '近点', lat: 34.191, lng: 113.47),
      ];
      expect(identical(sortSpotsByDistance(list, null, null), list), isTrue);
      expect(identical(sortSpotsByDistance(list, myLat, null), list), isTrue);
      final one = [list.first];
      expect(identical(sortSpotsByDistance(one, myLat, myLng), one), isTrue);
    });
  });

  group('钓点页渲染', () {
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
      // 故意按「后端顺序 = 入库倒序」给：远端最新，所以排在最前
      SpotService.testSpotsOverride = [
        spot(id: 'v3', name: '远钓场', lat: 34.30, lng: 113.47),
        spot(id: 'v2', name: '中钓场', lat: 34.20, lng: 113.47),
        spot(id: 'v1', name: '近钓场', lat: 34.191, lng: 113.47),
        spot(id: 's2', name: '远渔具店', lat: 34.30, lng: 113.47, kind: 'shop'),
        spot(id: 's1', name: '近渔具店', lat: 34.20, lng: 113.47, kind: 'shop'),
      ];
    });

    tearDown(() {
      SpotMapScreen.testSkipTiles = false;
      LocationService.testDetermineOverride = null;
      SpotService.testSpotsOverride = null;
    });

    testWidgets('本地钓场 Tab：离我近的排在前面', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('近钓场'), lessThan(y('中钓场')));
      expect(y('中钓场'), lessThan(y('远钓场')));
    });

    testWidgets('渔具店 Tab：同样离我近的排在前面', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.textContaining('渔具店（'));
      // 胶囊切换是 animateTo（300ms）+ 一次重建，400ms 单帧偶尔还没落位
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.getTopLeft(find.text('近渔具店')).dy,
          lessThan(tester.getTopLeft(find.text('远渔具店')).dy));
    });
  });

  test('源码护栏：两个列表都必须走 sortSpotsByDistance', () {
    final src = File('lib/screens/spots_screen.dart').readAsStringSync();
    expect(src.contains('sortSpotsByDistance(list, _myLat, _myLng)'), isTrue,
        reason: '本地钓场列表丢了距离排序');
    expect(src.contains('sortSpotsByDistance(_shops, _myLat, _myLng)'), isTrue,
        reason: '渔具店列表丢了距离排序');
    expect(src.contains('itemBuilder: (_, i) => _shopCard(shops[i])'), isTrue,
        reason: '渔具店列表渲染必须用排序后的 shops，不能用原始 _shops');
  });
}
