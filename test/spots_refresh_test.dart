import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fishing_app/screens/spot_map_screen.dart';
import 'package:fishing_app/screens/spots_screen.dart';
import 'package:fishing_app/services/location_service.dart';

/// 野钓钓点页：刷新按钮反馈 + 右下角定位按钮移除（v2.1.21 回归）
///
/// 背景 —— 用户反馈「左侧的刷新按钮点着没反应」。
/// 查下来**不是点击没接上**（onTap 一直挂着 `_load`），而是两件事叠在一起：
///   ① 数据没变化时，界面本来就不会有任何变化（钓点数一样、地图上的点一样）；
///   ② 整条链路全程没有 loading 也没有提示。
/// 于是手感等于"按钮坏了"。修法是把反馈补上，所以判据也定成
/// 两条**机器可判定**的：
///   ① 点「刷新」后必须弹出结果提示 —— 证明回调真的跑了、数据真的回来了；
///   ② 右下角那个 `heroTag == spots_locate` 的悬浮定位按钮必须已经不存在。
///
/// 注意：测试环境没有真网络，`SpotService.fetchSpots()` 会走异常分支回落到
/// 演示数据 —— 这不影响判据，反而正好覆盖了"数据没变也要给反馈"的场景。
void main() {
  setUp(() {
    // 测试环境无网络：关掉底图瓦片，只验浮层与按钮行为
    SpotMapScreen.testSkipTiles = true;
    // 不触发真实定位（会挂在系统权限框上）
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

  testWidgets('点「刷新」弹出结果提示，右下角定位按钮已移除', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
    // 等首屏数据（网络失败回落演示数据）
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 切到「野钓钓点」Tab —— 左侧竖排信息条只在这个 Tab 里
    await tester.tap(find.text('野钓钓点'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // ① 刷新按钮必须在（否则下面找不到目标，测试会以另一种方式失败）
    expect(find.text('刷新'), findsOneWidget, reason: '左侧竖排信息条里应有「刷新」');

    // ② 右下角的悬浮定位按钮必须已经删除
    expect(
      find.byWidgetPredicate((w) =>
          w is FloatingActionButton && w.heroTag == 'spots_locate'),
      findsNothing,
      reason: '右下角「我的位置」悬浮按钮已按用户要求移除',
    );

    // ③ 点刷新 —— 必须出现可见反馈
    await tester.tap(find.text('刷新'));
    await tester.pump(); // 让 setState(_refreshing = true) 生效
    await tester.pump(const Duration(milliseconds: 800)); // 等请求回来 + toast 插入
    await tester.pump(const Duration(milliseconds: 300)); // 等 toast 动画起帧

    expect(
      find.textContaining('已刷新'),
      findsOneWidget,
      reason: '点刷新后必须给出结果提示，否则用户看到的就是"点了没反应"',
    );
    expect(tester.takeException(), isNull);

    // 等 toast 自己的 1.6s 定时器走完再结束，否则 flutter_test 会报
    // "A Timer is still pending even after the widget tree was disposed"。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
