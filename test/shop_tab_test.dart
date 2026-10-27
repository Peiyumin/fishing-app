import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/screens/shop_detail_screen.dart';
import 'package:fishing_app/screens/spots_screen.dart';
import 'package:fishing_app/services/location_service.dart';
import 'package:fishing_app/screens/spot_map_screen.dart';

/// 渔具店提成一级 Tab + 独立详情页（v2.1.39 回归）
///
/// 用户提的三件事，逐条钉死：
///   ① 本地钓场的类型筛选里**不许再有「野钓场」**（野钓点有独立 Tab）；
///   ② 「渔具店」不许再混在筛选里，必须是顶部的一级 Tab；
///   ③ 点渔具店进独立详情页，页面必须同时有：店内店外图 / 售卖种类 /
///      具体位置 / 是否外送 / 顾客评价 / 导航。
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

  testWidgets('顶部是三个一级 Tab，筛选里不再有「野钓场」「渔具店」',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
    // 等首屏数据（测试环境无网络 → 回落演示数据），并让定位回调跑完
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // ① 三个一级 Tab 都在
    expect(find.textContaining('本地钓场（'), findsOneWidget);
    expect(find.text('野钓钓点'), findsOneWidget);
    expect(find.textContaining('渔具店（'), findsOneWidget);

    // ② 「野钓场」必须彻底消失（卡片上的标签文字可能同名，所以限定在筛选胶囊上判）
    expect(find.widgetWithText(ChoiceChip, '野钓场'), findsNothing);

    // ③ 筛选里不能再用「渔具店」当类型（它现在只在顶部 Tab 上出现）
    expect(find.widgetWithText(ChoiceChip, '渔具店'), findsNothing);

    // ④ 其他筛选还在，说明不是把筛选整块删了
    expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '黑坑'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '路亚'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '海钓'), findsOneWidget);

    // ⑤ 切到渔具店 Tab：空列表要有明确引导文案（演示数据里没有 shop）
    //    ★ 必须逐帧推进而不是 pumpAndSettle：中间的「野钓钓点」是原生 GL 地图，
    //      会挂常驻 ticker，pumpAndSettle 会一直等不到静止。
    await tester.tap(find.textContaining('渔具店（'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('附近还没有渔具店'), findsOneWidget);
  });

  testWidgets('渔具店详情页：店内店外图 / 售卖种类 / 具体位置 / 外送 / 评价 / 导航',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const shop = FishingSpot(
      id: 'shop1',
      name: '老李路亚渔具',
      type: '渔具店',
      kind: 'shop',
      lat: 30.2741,
      lng: 120.1551,
      rating: 4.6,
      description: '老板懂路亚，能现场试竿。',
      address: '杭州市西湖区文三路 100 号',
      fish: '竿、轮、饵料', // 售卖种类
      tags: '推荐,电话认证',
      phone: '13800001111',
      delivery: true,
      commentCount: 3,
    );

    await tester.pumpWidget(const MaterialApp(
      home: ShopDetailScreen(spot: shop, distanceText: '1.2km'),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // ① 店内店外图区域（无图时给占位文案，但不能整块缺失）
    expect(find.text('店内 / 店外实拍'), findsOneWidget);

    // ② 售卖种类：标题 + 三个品类
    expect(find.text('售卖种类'), findsOneWidget);
    expect(find.text('竿'), findsOneWidget);
    expect(find.text('轮'), findsOneWidget);
    expect(find.text('饵料'), findsOneWidget);

    // ③ 具体位置 + 距离
    expect(find.text('具体位置'), findsOneWidget);
    expect(find.text('杭州市西湖区文三路 100 号'), findsOneWidget);
    expect(find.text('距你约 1.2km'), findsOneWidget);

    // ④ 是否外送
    expect(find.text('是否外送'), findsOneWidget);
    expect(find.text('支持外送'), findsOneWidget);

    // ⑤ 顾客评价
    expect(find.text('顾客评价'), findsOneWidget);
    expect(find.text('写评价'), findsOneWidget);

    // ⑥ 导航按钮（点了才会探测本机地图 App，这里只验入口存在）
    expect(find.text('导航前往'), findsOneWidget);
    // 电话入口
    expect(find.text('电话'), findsOneWidget);
  });

  testWidgets('不支持外送的渔具店显示「暂不支持外送」', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const shop = FishingSpot(
      id: 'shop2',
      name: '渔乐渔具',
      type: '渔具店',
      kind: 'shop',
      lat: 30.1,
      lng: 120.1,
      rating: 4.0,
      description: '',
      address: '某市某路 1 号',
      fish: '',
    );

    await tester.pumpWidget(const MaterialApp(home: ShopDetailScreen(spot: shop)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('暂不支持外送'), findsOneWidget);
    // 经营范围没填时给明确占位，不留空白
    expect(find.text('店主暂未填写经营范围'), findsOneWidget);
    expect(find.text('支持外送'), findsNothing);
  });
}
