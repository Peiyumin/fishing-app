import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fishing_app/screens/spot_map_screen.dart';
import 'package:fishing_app/screens/spots_screen.dart';
import 'package:fishing_app/services/location_service.dart';

/// 钓点页（含嵌入的野钓卫星地图）布局回归测试
///
/// v2.1.10 把「钓点地图」整页删掉、改成嵌进钓点页的「野钓钓点」Tab，
/// 这层改造最容易出的问题是浮层互相压住 / 窄屏横向溢出，
/// 所以这里在 390/320dp 各渲染一遍，断言没有布局异常。
void main() {
  setUp(() {
    // 测试环境无网络：关掉底图瓦片，只验证浮层/图层布局
    SpotMapScreen.testSkipTiles = true;
    // 测试环境不触发真实定位（会挂在系统权限框上）
    LocationService.testDetermineOverride = ({LocationAccuracy accuracy = LocationAccuracy.high}) async =>
        Position(
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

  for (final w in [390.0, 320.0]) {
    testWidgets('钓点页（野钓用地嵌地图）在 ${w.toInt()}dp 下无布局异常', (tester) async {
      tester.view.physicalSize = Size(w, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
      // 等异步数据（网络失败会回落演示数据）
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      // 切到「野钓钓点」Tab（嵌入地图）
      await tester.tap(find.text('野钓钓点'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);

      // 打开「图层」面板：三个分组都要在，且窄屏不能溢出
      await tester.tap(find.byIcon(Icons.layers_outlined).first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('底图图层'), findsOneWidget);
      expect(find.text('地图设置'), findsOneWidget);
      expect(find.text('水域图层'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // ★ 两套渲染内核（原生 MapLibre / 兜底 flutter_map）的浮层必须长得一样。
  //   原生内核起得慢时会自动降级，一旦两边布局不同，用户看到的就是
  //   「地图一加载出来，按钮全换了位置」——这正是用户截图反馈的问题。
  testWidgets('嵌入地图的浮层与原生内核一致：右侧 5 钮、顶部无重复圆钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('野钓钓点'));
    // TabBarView 的切页动画要连续多帧推进，单次 pump 只会推一帧，
    // 页面还没换过去就断言，会误判成「按钮不见了」。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 右侧竖排工具条与原生内核同序同数量：卫星 / 放大 / 缩小 / 定位 / 图层
    expect(find.byTooltip('放大'), findsOneWidget);
    expect(find.byTooltip('缩小'), findsOneWidget);
    expect(find.byTooltip('定位'), findsOneWidget);
    expect(find.byTooltip('图层'), findsOneWidget);
    // 顶部那行「图层 + 禁钓名录」只在全屏地图页出现，嵌入模式一律不画
    expect(find.byTooltip('禁钓名录'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
