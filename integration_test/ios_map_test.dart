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

import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/models/water_body.dart';
import 'package:fishing_app/screens/spot_map_gl.dart';
import 'package:fishing_app/services/location_service.dart';
import 'package:fishing_app/services/map_data_service.dart';
import 'package:fishing_app/services/spot_service.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracy, Position;
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

/// 关掉真实定位
///
/// 地图页 initState 里会自动定位一次并 animateCamera 到「我的位置」。
/// 模拟器上定位回调什么时候回来不确定，**经常在测试已经把镜头移到
/// 河流之后才回来**，一下把镜头抢走 —— 于是「压测后查询要素」那条
/// 断言查了个空，看着像是功能坏了，其实是测试自己把镜头移开了。
/// 这里把定位直接设成必然失败（_locate 内部 catch 掉，静默跳过），
/// 保证整条测试里镜头只由测试代码控制。
void _disableRealLocation() {
  LocationService.testDetermineOverride =
      ({LocationAccuracy accuracy = LocationAccuracy.high}) async {
    throw Exception('integration_test: 关闭真实定位');
  };
}

/// 在屏幕上找到「河流图层被真的画出来」的证据
///
/// 只用几何中点单点查询是不稳的：waters.json 里河流是抽稀过的折线，
/// 中点可能落在两个采样点之间的长直线上，而线宽只有 4.5px，
/// 屏幕坐标一像素的误差就查空 —— 之前的失败就是这种假阴性。
/// 这里沿折线取若干顶点逐个查，任意一个命中即证明：GeoJSON 源被接受、
/// 图层真的渲染在当前视野里。
Future<({List hits, Point<num> at})> _probeRiver(
  mgl.MapLibreMapController ctl,
  WaterBody river,
) async {
  final pts = river.geometry;
  if (pts.isEmpty) {
    return (hits: const [], at: const Point<num>(0, 0));
  }
  final step = pts.length <= 24 ? 1 : (pts.length / 24).ceil();
  var last = const Point<num>(0, 0);
  for (var i = 0; i < pts.length; i += step) {
    final scr = await ctl.toScreenLocation(_mapLat(pts[i]));
    last = scr;
    final hits =
        await ctl.queryRenderedFeatures(_dbl(scr), ['rivers-line'], null);
    if (hits.isNotEmpty) return (hits: hits, at: scr);
  }
  // 再试几个中间点（有些数据中间点是重复坐标）
  final mid = pts[pts.length ~/ 2];
  final scr = await ctl.toScreenLocation(_mapLat(mid));
  final hits = await ctl.queryRenderedFeatures(_dbl(scr), ['rivers-line'], null);
  if (hits.isNotEmpty) return (hits: hits, at: scr);
  return (hits: const [], at: last);
}

/// 确保相机真的停在目标点附近，返回是否成功
///
/// ★ CI 上出现过这种假阴性：`animateCamera` 之后 6 秒，
///   `toScreenLocation(长江中点)` 返回 `Point(83086, -16025)` ——
///   一个远在屏幕外的坐标，于是后面所有查询都是 0 命中，
///   看着像「河流图层没生效」，其实是**相机没真正移动到位**。
///   style 刚加载完的那段时间里，`toScreenLocation` 会返回未就绪矩阵算出的
///   垃圾值；同一份代码上一次跑是通过的（screen=196,426），说明是时序问题。
///   这里改成「移动 → 等 → 反算屏幕坐标是否合理 → 不合理再移一次」，
///   最多 8 轮，让这条断言只反映图层本身对不对。
Future<bool> _ensureCameraAt(
  WidgetTester tester,
  mgl.MapLibreMapController ctl,
  ll.LatLng target,
  double zoom,
) async {
  for (var i = 0; i < 8; i++) {
    await ctl.animateCamera(
      mgl.CameraUpdate.newLatLngZoom(_mapLat(target), zoom),
      duration: const Duration(milliseconds: 1),
    );
    await wait(tester, i == 0 ? 5000 : 1800);
    try {
      final scr = await ctl.toScreenLocation(_mapLat(target));
      // 屏幕坐标合理 = 落在屏幕尺寸的几十倍以内；83086 这种就是坏的
      if (scr.x.abs() < 4000 && scr.y.abs() < 4000) return true;
      // ignore: avoid_print
      print('[TEST] 相机未到位（第 ${i + 1} 轮）screen=$scr，重试');
    } catch (_) {}
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
    _disableRealLocation();
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
    expect(await _ensureCameraAt(tester, ctl!, riverPt, 12), isTrue,
        reason: '相机没能移到「${river.name}」所在位置，后续查询结果不可信');

    final probe = await _probeRiver(ctl!, river);
    // ignore: avoid_print
    print('[TEST] river="${river.name}" screen=${probe.at} hits=${probe.hits.length}');
    expect(probe.hits, isNotEmpty,
        reason: '在「${river.name}」可见范围内所有采样点都查不到 rivers-line 要素，'
            '说明河流图层没真正渲染出来');

    // ---------------------------------------------------------------- 6. 钓点能命中且 id 对得上
    final spots = await SpotService.fetchSpots();
    final usable = spots.where((s) => s.lat != 0 && s.lng != 0).toList();
    expect(usable, isNotEmpty, reason: '后端没返回钓点，无法验证点击进详情');

    final spot = usable.first;
    final spotPt = ll.LatLng(spot.lat, spot.lng);
    expect(await _ensureCameraAt(tester, ctl!, spotPt, 15), isTrue,
        reason: '相机没能移到钓点「${spot.name}」所在位置');

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
    _disableRealLocation();
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
    expect(await _ensureCameraAt(tester, ctl!, pt, 12), isTrue,
        reason: '压测后相机移不回「${river.name}」');
    final probe = await _probeRiver(ctl!, river);
    // ignore: avoid_print
    print('[PERF] 压测后仍可命中「${river.name}」: ${probe.hits.length} 个要素');
    expect(probe.hits, isNotEmpty, reason: '压测后要素查询失效了');
  });

  // ------------------------------------------------------- 打开地图是否定位
  // 用户反馈的核心问题：「打开野钓钓点后，地图不显示当前定位」。
  //
  // 这条断言的判据很硬：注入一个固定坐标作为「当前位置」，等定位生效后
  // 把**屏幕中心**反算成经纬度，必须落在这个坐标附近。
  // 如果定位坐标被流程吞掉（宿主页定位早于地图创建、animateCamera 被
  // style 覆盖等），中心会停在全国视角 (34.5, 108.9)，差异一眼就能看出来。
  testWidgets('iOS：打开野钓钓点自动定位到当前位置（我的位置图层 + 镜头中心）',
      (tester) async {
    const targetLat = 30.2465; // 杭州西湖
    const targetLng = 120.1295;
    LocationService.testDetermineOverride =
        ({LocationAccuracy accuracy = LocationAccuracy.high}) async => Position(
              latitude: targetLat,
              longitude: targetLng,
              timestamp: DateTime.now(),
              accuracy: 5,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );

    SpotMapGlScreen.readyTimeout = const Duration(seconds: 90);
    addTearDown(() {
      LocationService.testDetermineOverride = null;
      SpotMapGlScreen.readyTimeout = const Duration(seconds: 8);
      SpotMapGlScreen.debugOnControllerCreated = null;
      SpotMapGlScreen.debugOnLayersReady = null;
    });

    mgl.MapLibreMapController? ctl;
    SpotMapGlScreen.debugOnControllerCreated = (c) => ctl = c;
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpotMapGlScreen()),
    ));

    expect(await until(tester, () async => ctl != null, timeoutMs: 90000), isTrue,
        reason: '原生内核没起来');

    // 「我的位置」图层存在 = 定位结果真的画到地图上了
    expect(
        await until(tester, () async {
          final ids =
              (await ctl!.getLayerIds()).map((e) => e.toString()).toList();
          return ids.contains('me-circle');
        }, timeoutMs: 90000),
        isTrue,
        reason: 'me-circle 图层没建出来 —— 定位结果没画到地图上');

    // 等定位动画（400ms）+ 瓦片稳定
    await wait(tester, 4000);

    final size = tester.getSize(find.byType(SpotMapGlScreen));
    final center = await ctl!
        .toLatLng(Point<double>(size.width / 2, size.height / 2));
    // ignore: avoid_print
    print('[TEST] 屏幕中心=${center.latitude},${center.longitude} '
        '定位目标=$targetLat,$targetLng');

    expect((center.latitude - targetLat).abs() < 0.05, isTrue,
        reason: '打开地图后镜头中心纬度是 ${center.latitude}，'
            '不在当前位置 $targetLat 附近 —— 定位坐标被流程吞掉了');
    expect((center.longitude - targetLng).abs() < 0.05, isTrue,
        reason: '打开地图后镜头中心经度是 ${center.longitude}，'
            '不在当前位置 $targetLng 附近 —— 定位坐标被流程吞掉了');
  });

  // ------------------------------------------------- 新增钓点能否增量进地图
  // 用户反馈：「添加新钓点，点击查看详情不能」。
  //
  // 这里模拟宿主页的真实行为：发布成功后宿主页 `_load()` 拿到新列表，
  // 重新 build 出带新 extraSpots 的地图 —— 地图 State 复用，走 didUpdateWidget。
  // 断言两条：新钓点的圈出现在屏幕上、按屏幕坐标能查到它的 id（进详情的前半段）。
  testWidgets('iOS：宿主页刷新后新钓点增量进入地图且可命中', (tester) async {
    _disableRealLocation();
    SpotMapGlScreen.readyTimeout = const Duration(seconds: 90);
    addTearDown(() {
      SpotMapGlScreen.readyTimeout = const Duration(seconds: 8);
      SpotMapGlScreen.debugOnControllerCreated = null;
    });

    mgl.MapLibreMapController? ctl;
    SpotMapGlScreen.debugOnControllerCreated = (c) => ctl = c;

    // ① 首帧：宿主页刚进来，还没有新钓点
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpotMapGlScreen(extraSpots: [])),
    ));
    expect(await until(tester, () async => ctl != null, timeoutMs: 90000), isTrue);
    expect(
        await until(tester, () async {
          final ids =
              (await ctl!.getLayerIds()).map((e) => e.toString()).toList();
          return ids.contains('spots-circle');
        }, timeoutMs: 90000),
        isTrue,
        reason: '钓点图层没就绪');

    // ② 镜头移到一片不会有钓点的海面（东海外海），
    //    这样「查询结果从空 → 有」就只可能是新注入的钓点造成的
    const newLat = 29.9500;
    const newLng = 122.4000;
    await ctl!.animateCamera(
      mgl.CameraUpdate.newLatLngZoom(mgl.LatLng(newLat, newLng), 15),
      duration: const Duration(milliseconds: 300),
    );
    await wait(tester, 4000);

    final before = await ctl!.toScreenLocation(mgl.LatLng(newLat, newLng));
    final beforeHits = await ctl!.queryRenderedFeaturesInRect(
      Rect.fromCenter(
          center: Offset(before.x.toDouble(), before.y.toDouble()),
          width: 20,
          height: 20),
      ['spots-circle'],
      null,
    );
    expect(beforeHits, isEmpty,
        reason: '测试点位本来就有钓点，无法证明「新点增量出现」，换个坐标');

    // ③ 宿主页 _load() 回来，带着刚发布的新钓点重新 build
    const newSpot = FishingSpot(
      id: 'itest-new-spot-01',
      name: '集成测试·新标记钓点',
      type: '野钓',
      kind: 'wild',
      lat: newLat,
      lng: newLng,
      rating: 0,
      description: 'integration_test 注入',
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpotMapGlScreen(extraSpots: [newSpot])),
    ));
    await wait(tester, 3000);

    // ④ 新钓点必须出现在屏幕上，并且能查到 id
    final scr = await ctl!.toScreenLocation(mgl.LatLng(newLat, newLng));
    final hits = await ctl!.queryRenderedFeaturesInRect(
      Rect.fromCenter(
          center: Offset(scr.x.toDouble(), scr.y.toDouble()),
          width: 44,
          height: 44),
      ['spots-circle'],
      null,
    );
    // ignore: avoid_print
    print('[TEST] 新钓点 screen=$scr hits=${hits.length}');
    expect(hits, isNotEmpty,
        reason: '新发布的钓点没有进地图（extraSpots 更新后地图没刷新），'
            '用户点了也不会有反应');

    final props = hits.first is Map ? (hits.first as Map)['properties'] : null;
    final hitId = props is Map ? props['id'] : null;
    expect('$hitId', 'itest-new-spot-01',
        reason: '命中的要素 id 不是新钓点，点击会跳到别的钓点或跳不动');
  });
}
