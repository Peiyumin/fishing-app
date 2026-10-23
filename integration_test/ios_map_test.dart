// iOS 原生地图全链路集成测试
//
// 目的：在**真正的 iOS 运行时**（GitHub Actions 的 macos runner + iOS 模拟器）
// 上验证三件事，而不是靠"看代码觉得没问题"：
//
//   1. 底图到底是不是星图地球 —— 读回原生层的 source / layer 列表。
//      如果 style 被 iOS 丢掉（JSON 那个坑），SDK 会渲染 demotiles，
//      它的 source 叫 `maplibre`、图层是 countries-fill 之类；
//      只要读回 sat/vec/cia 和 lakes-fill/rivers-line/spots-circle，
//      就说明我们的样式真的生效了。
//   2. 河流 / 湖泊图层是不是真的建起来了、开关能不能切。
//   3. 按屏幕坐标能不能 query 到河流和钓点要素（点钓点进详情的前半段）。
//      后半段（id → 详情页）是纯 Dart 查表，由本地单测覆盖。
//
// 跑法（只在 macOS 上有效）：
//   flutter test integration_test/ios_map_test.dart -d <iOS 模拟器 UDID>
import 'dart:math' show Point;

import 'package:fishing_app/models/water_body.dart';
import 'package:fishing_app/screens/spot_map_gl.dart';
import 'package:fishing_app/services/map_data_service.dart';
import 'package:fishing_app/services/spot_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as mgl;

/// maplibre_gl 自带一套 LatLng（不依赖 latlong2），要显式转换
mgl.LatLng _mapLat(ll.LatLng p) => mgl.LatLng(p.latitude, p.longitude);

/// toScreenLocation 返回 Point<num>，queryRenderedFeatures 要 Point<double>
Point<double> _dbl(Point<num> p) => Point<double>(p.x.toDouble(), p.y.toDouble());

/// 真实时间等待 + 推进一帧
///
/// integration_test 跑在 LiveTestWidgetsFlutterBinding 上，网络/原生回调
/// 用的是真实时间，所以 `pump(Duration)` 那种假时钟推进在这里没用，
/// 必须真的 sleep 再 pump 一次让 setState 生效。
Future<void> wait(WidgetTester tester, int ms) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

/// 轮询直到条件成立，超时返回 false
Future<bool> until(
  WidgetTester tester,
  Future<bool> Function() cond, {
  int timeoutMs = 60000,
  int stepMs = 500,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    if (await cond()) return true;
    await wait(tester, stepMs);
  }
  return false;
}

ll.LatLng? _centerOf(WaterBody w) {
  if (w.geometry.isEmpty) return null;
  return w.geometry[w.geometry.length ~/ 2];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS：底图是星图、河湖图层生效、河流与钓点可命中', (tester) async {
    // 模拟器比真机慢，把 8 秒看门狗放宽，避免"还没 ready 就降级"
    SpotMapGlScreen.readyTimeout = const Duration(seconds: 90);
    addTearDown(() {
      SpotMapGlScreen.readyTimeout = const Duration(seconds: 8);
      SpotMapGlScreen.debugOnControllerCreated = null;
    });

    mgl.MapLibreMapController? ctl;
    SpotMapGlScreen.debugOnControllerCreated = (c) => ctl = c;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpotMapGlScreen()),
    ));

    // ---------------------------------------------------------------- 1. 原生内核必须起来
    final up = await until(tester, () async => ctl != null, timeoutMs: 90000);
    expect(up, isTrue,
        reason: '原生 MapLibre 内核没起来（可能已降级到 flutter_map 老内核，'
            '或 style 文件加载失败）');

    // ---------------------------------------------------------------- 2. 底图源必须是星图
    // 这是"是不是卫星地图"的判据：style 生效 → sat/vec/cia 三源存在；
    // style 被丢弃 → SDK 用 demotiles → 源叫 maplibre。
    late List<String> sources;
    final srcOk = await until(tester, () async {
      sources = (await ctl!.getSourceIds()).map((e) => e.toString()).toList();
      return sources.contains('sat');
    }, timeoutMs: 60000);

    // ignore: avoid_print
    print('[TEST] sources = $sources');
    expect(srcOk, isTrue, reason: '样式里的 sat 源没建出来：$sources');
    expect(sources, contains('vec'));
    expect(sources, contains('cia'));
    expect(sources, isNot(contains('maplibre')),
        reason: '出现 maplibre 源 = 原生层用的是 SDK 自带的 demotiles 示例样式，'
            '我们的星图样式没被接受');

    // ---------------------------------------------------------------- 3. 图层齐全
    late List<String> layers;
    final layersOk = await until(tester, () async {
      layers = (await ctl!.getLayerIds()).map((e) => e.toString()).toList();
      return layers.contains('spots-circle');
    }, timeoutMs: 60000);

    // ignore: avoid_print
    print('[TEST] layers = $layers');
    expect(layersOk, isTrue, reason: '业务图层没加上：$layers');
    for (final id in [
      'sat',
      'vec',
      'cia',
      'lakes-fill',
      'lakes-line',
      'rivers-line',
      'zones-fill',
      'zones-line',
      'spots-circle',
    ]) {
      expect(layers, contains(id), reason: '缺图层 $id');
    }

    // ---------------------------------------------------------------- 4. 河湖开关能切
    // 图层存在但 setLayerVisibility 在 iOS 上抛错的话，用户点开关没反应。
    await ctl!.setLayerVisibility('lakes-fill', false);
    await ctl!.setLayerVisibility('lakes-fill', true);
    await ctl!.setLayerVisibility('rivers-line', false);
    await ctl!.setLayerVisibility('rivers-line', true);

    // ---------------------------------------------------------------- 5. 河流能命中
    // 把相机对准一条真实河流，再按屏幕坐标查要素。
    // 命中说明：GeoJSON 源被原生层接受了、图层真的画在屏幕上。
    final waters = await MapDataService.waters();
    final river = waters.where((w) => w.isRiver).firstWhere(
          (w) => _centerOf(w) != null,
          orElse: () => waters.first,
        );
    final riverPt = _centerOf(river)!;
    await ctl!.animateCamera(mgl.CameraUpdate.newLatLngZoom(_mapLat(riverPt), 12));
    await wait(tester, 6000);

    final riverScreen = await ctl!.toScreenLocation(_mapLat(riverPt));
    final riverHits = await ctl!
        .queryRenderedFeatures(_dbl(riverScreen), ['rivers-line'], null);
    // ignore: avoid_print
    print('[TEST] river="${river.name}" screen=$riverScreen hits=${riverHits.length}');
    expect(riverHits, isNotEmpty,
        reason: '对着「${river.name}」中心查不到 rivers-line 要素，'
            '说明河流图层没真正渲染出来');

    // ---------------------------------------------------------------- 6. 钓点能命中且 id 对得上
    final spots = await SpotService.fetchSpots();
    final usable = spots.where((s) => s.lat != 0 && s.lng != 0).toList();
    expect(usable, isNotEmpty, reason: '后端没返回钓点，无法验证点击进详情');

    final spot = usable.first;
    final spotPt = ll.LatLng(spot.lat, spot.lng);
    await ctl!.animateCamera(mgl.CameraUpdate.newLatLngZoom(_mapLat(spotPt), 15));
    await wait(tester, 5000);

    final spotScreen = await ctl!.toScreenLocation(_mapLat(spotPt));
    final spotHits =
        await ctl!.queryRenderedFeatures(_dbl(spotScreen), ['spots-circle'], null);
    // ignore: avoid_print
    print('[TEST] spot="${spot.name}" id=${spot.id} screen=$spotScreen '
        'hits=${spotHits.length}');
    expect(spotHits, isNotEmpty,
        reason: '钓点「${spot.name}」在屏幕 $spotScreen 处查不到要素，'
            '点它不会进详情');

    final props = spotHits.first is Map
        ? (spotHits.first as Map)['properties']
        : null;
    final hitId = props is Map ? props['id'] : null;
    // ignore: avoid_print
    print('[TEST] hitId=$hitId spotId=${spot.id}');
    expect('$hitId', spot.id,
        reason: '命中的要素 id 和钓点 id 对不上，点击会跳错人或跳不动');
  });

  // ---------------------------------------------------------------- 压测
  // 说明清楚边界：CI 的 macOS runner 没有 GPU，MapLibre 走软件渲染，
  // **帧率在这里没有参考价值**，跑出来的 FPS 只会误导人。
  // 这里能测、且值得测的是"长时间连续拖动缩放会不会崩 / 图层会不会丢 /
  // 原生内核会不会中途失效"—— 这正是之前闪退、白屏那类问题的形态。
  testWidgets('iOS：连续跨城拖动缩放压测，不崩不丢图层', (tester) async {
    SpotMapGlScreen.readyTimeout = const Duration(seconds: 90);
    addTearDown(() {
      SpotMapGlScreen.readyTimeout = const Duration(seconds: 8);
      SpotMapGlScreen.debugOnControllerCreated = null;
    });

    mgl.MapLibreMapController? ctl;
    SpotMapGlScreen.debugOnControllerCreated = (c) => ctl = c;
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpotMapGlScreen()),
    ));

    expect(await until(tester, () async => ctl != null, timeoutMs: 90000),
        isTrue, reason: '原生内核没起来');
    expect(
        await until(tester, () async {
          final ids = (await ctl!.getLayerIds()).map((e) => e.toString()).toList();
          return ids.contains('spots-circle');
        }, timeoutMs: 60000),
        isTrue,
        reason: '图层没就绪');

    // 5 个城市 × 3 轮 = 15 次跨城跳转，覆盖 z11~z15（不同瓦片层级）
    final targets = <(double, double, double)>[
      (39.9042, 116.4074, 11), // 北京
      (31.2304, 121.4737, 13), // 上海
      (23.1291, 113.2644, 12), // 广州
      (30.5728, 104.0668, 14), // 成都
      (26.0745, 119.2965, 15), // 福州
    ];

    final cost = <int>[];
    for (var round = 0; round < 3; round++) {
      for (final t in targets) {
        final sw = Stopwatch()..start();
        await ctl!.animateCamera(
          mgl.CameraUpdate.newLatLngZoom(mgl.LatLng(t.$1, t.$2), t.$3),
          duration: const Duration(milliseconds: 350),
        );
        // 给原生层时间下瓦片、解码、上屏
        await wait(tester, 1200);
        cost.add(sw.elapsedMilliseconds);

        // 每一跳都必须还活着：能读到相机、图层没丢
        expect(ctl!.cameraPosition, isNotNull,
            reason: '第 ${cost.length} 次跳转后相机位置读不到，原生层可能已失效');
        final ids = (await ctl!.getLayerIds()).map((e) => e.toString()).toList();
        expect(ids, contains('spots-circle'),
            reason: '第 ${cost.length} 次跳转后钓点图层丢了');
        expect(ids, contains('rivers-line'),
            reason: '第 ${cost.length} 次跳转后河流图层丢了');
      }
    }

    cost.sort();
    final avg = cost.reduce((a, b) => a + b) ~/ cost.length;
    // ignore: avoid_print
    print('[PERF] 15 次跨城跳转（含 1.2s 观察窗）：'
        '平均 ${avg}ms 中位 ${cost[cost.length ~/ 2]}ms '
        '最慢 ${cost.last}ms 最快 ${cost.first}ms');

    // 压测收尾再查一次要素，确认查询能力没被拖垮
    final waters = await MapDataService.waters();
    final river = waters.firstWhere((w) => w.isRiver, orElse: () => waters.first);
    final pt = _centerOf(river)!;
    await ctl!.animateCamera(mgl.CameraUpdate.newLatLngZoom(_mapLat(pt), 12),
        duration: const Duration(milliseconds: 300));
    await wait(tester, 5000);
    final screen = await ctl!.toScreenLocation(_mapLat(pt));
    final hits =
        await ctl!.queryRenderedFeatures(_dbl(screen), ['rivers-line'], null);
    // ignore: avoid_print
    print('[PERF] 压测后仍可命中「${river.name}」: ${hits.length} 个要素');
    expect(hits, isNotEmpty, reason: '压测后要素查询失效了');
  });
}
