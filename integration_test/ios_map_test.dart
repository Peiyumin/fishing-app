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
import 'package:fishing_app/models/no_fishing_zone.dart';
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
/// ★ 这里踩过一个很隐蔽的坑，写清楚免得以后又改回去：
///
/// 长江的折线横跨 91°E~121°E（约 30 个经度、90 多个顶点）。相机对准
/// 几何中点放大到 z12 时，视野宽度只有约 0.07 度 —— 也就是说，除了中点
/// 附近那一两个顶点，**其余顶点本来就该在屏幕外**。
/// 于是「沿折线取 24 个顶点逐个 toScreenLocation + 查要素」这种写法会
/// 拿到 `screen=Point(78839, -15182)` 这种量级的坐标（离屏幕几万点），
/// 查询必然空手而归 —— 但它根本不代表图层坏了。
///
/// （更讽刺的是：这条测试曾经「通过」，恰恰是因为那时相机没真放大、
///   整个长江都在视野里，随便哪个顶点都能查到。定位修好之后才暴露。）
///
/// 正确判据：相机中心就落在河流折线的顶点上 → 河流必然穿过视口 →
/// 直接查**整个视口矩形**，命中即证明 GeoJSON 源被接受、图层真渲染了。
Future<({List hits, Point<num> at, int onScreen})> _probeRiver(
  WidgetTester tester,
  mgl.MapLibreMapController ctl,
  WaterBody river,
  Size mapSize,
) async {
  final pts = river.geometry;
  if (pts.isEmpty || mapSize.width < 8 || mapSize.height < 8) {
    return (hits: const [], at: const Point<num>(0, 0), onScreen: 0);
  }

  // 统计有多少顶点真的落在屏幕里，纯粹为了日志能看出「是视野问题还是图层问题」
  var onScreen = 0;
  var nearest = const Point<num>(0, 0);
  var nearestDist = double.infinity;
  final step = pts.length <= 40 ? 1 : (pts.length / 40).ceil();
  for (var i = 0; i < pts.length; i += step) {
    final scr = await ctl.toScreenLocation(_mapLat(pts[i]));
    final x = scr.x.toDouble();
    final y = scr.y.toDouble();
    if (x >= 0 && x <= mapSize.width && y >= 0 && y <= mapSize.height) {
      onScreen++;
    }
    final d = (x - mapSize.width / 2) * (x - mapSize.width / 2) +
        (y - mapSize.height / 2) * (y - mapSize.height / 2);
    if (d < nearestDist) {
      nearestDist = d;
      nearest = scr;
    }
  }

  // 主判据：整个视口矩形里查河流图层
  //
  // ★ 要同时查本地和在线两套：在线河网（hydro）加载成功之后，
  //   App 会把本地 rivers-line 关掉（否则长江会被画两遍），
  //   而 queryRenderedFeatures 对不可见图层返回空 —— 只查 rivers-line 会假阴性。
  final rect = Rect.fromLTWH(
    2,
    2,
    (mapSize.width - 4).clamp(1.0, double.infinity),
    (mapSize.height - 4).clamp(1.0, double.infinity),
  );
  final hits = await ctl.queryRenderedFeaturesInRect(rect, _riverLayers, null);
  if (hits.isNotEmpty) return (hits: hits, at: nearest, onScreen: onScreen);

  // 兜底 1：中心附近 44x44（万一线太细、视口边缘被裁）
  final cRect = Rect.fromCenter(
    center: Offset(mapSize.width / 2, mapSize.height / 2),
    width: 44,
    height: 44,
  );
  final cHits =
      await ctl.queryRenderedFeaturesInRect(cRect, _riverLayers, null);
  if (cHits.isNotEmpty) return (hits: cHits, at: nearest, onScreen: onScreen);

  // 兜底 2：相机中心就是折线顶点，所以屏幕正中心必然压在这条线上
  final centerHits = await ctl.queryRenderedFeatures(
    Point<double>(mapSize.width / 2, mapSize.height / 2),
    _riverLayers,
    null,
  );
  return (hits: centerHits, at: nearest, onScreen: onScreen);
}

/// 河流相关的全部图层：本地兜底 + 在线河网
///
/// 在线河网就绪后本地那两层会被隐藏，所以两条链路都要查，
/// 否则「在线数据好了」反而让测试变红。
const List<String> _riverLayers = [
  'rivers-line',
  'hydro-river-line',
  // v2.1.22：大河中心线单独成层，只在 z6~10 出现（z11 起交给 hydro-water）
  'hydro-river-major',
  'hydro-water',
];

/// 湖泊/水面图层：本地填充 + 在线水体面
const List<String> _lakeLayers = [
  'lakes-fill',
  'lakes-line',
  'hydro-water',
];

/// 确保相机真的停在目标点附近，返回是否成功
///
/// ★ 两个 CI 假阴性都出在这里，所以判据做得很硬：
///
///   ① `animateCamera` 的返回值是 `Future<bool?>`，**false 表示原生层没接受
///      这次移动**（正在应用 style / 正在渲染时会被拒）。忽略了返回值就会
///      以为「移过去了」，其实镜头纹丝不动。这里失败立刻退回 `moveCamera`。
///   ② 光看「目标点在屏幕内」不够：z4 全国视角下长江中点也在屏幕内。
///      改用 `getVisibleRegion()` 判断 —— 视野经度跨度 < 1 度才算真的放大到
///      街区级；再叠加中心点匹配，才能证明相机确实落在目标上。
Future<bool> _ensureCameraAt(
  WidgetTester tester,
  mgl.MapLibreMapController ctl,
  ll.LatLng target,
  double zoom,
) async {
  for (var i = 0; i < 8; i++) {
    final upd = mgl.CameraUpdate.newLatLngZoom(_mapLat(target), zoom);
    var ok = false;
    try {
      ok = (await ctl.animateCamera(upd,
              duration: const Duration(milliseconds: 1))) ??
          false;
    } catch (_) {}
    if (!ok) {
      try {
        await ctl.moveCamera(upd);
      } catch (_) {}
    }
    await wait(tester, i == 0 ? 5000 : 1800);
    try {
      final r = await ctl.getVisibleRegion();
      final spanLng =
          (r.northeast.longitude - r.southwest.longitude).abs();
      final cLat = (r.northeast.latitude + r.southwest.latitude) / 2;
      final cLng = (r.northeast.longitude + r.southwest.longitude) / 2;
      if (spanLng < 1.0 &&
          (cLat - target.latitude).abs() < 0.05 &&
          (cLng - target.longitude).abs() < 0.05) {
        return true;
      }
      // ignore: avoid_print
      print('[TEST] 相机未到位(第 ${i + 1} 轮) '
          'span=$spanLng center=$cLat,$cLng animateOk=$ok');
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
      return layers.contains('spots-pin');
    }, timeoutMs: 60000);

    // ignore: avoid_print
    print('[TEST] layers = $layers');
    expect(layersOk, isTrue, reason: '业务图层没加上：$layers');
    for (final id in [
      'sat',
      'vec',
      'cia',
      // 在线河网（OSM）：所有有名字的河流、水体面、水库池塘图标
      'hydro-water',
      'hydro-water-line',
      'hydro-river-major',
      'hydro-river-line',
      'hydro-lake-icon',
      'hydro-pond-icon',
      // 本地兜底数据
      'lakes-fill',
      'lakes-line',
      'rivers-line',
      'zones-fill',
      'zones-line',
      'spots-pin',
    ]) {
      expect(layers, contains(id), reason: '缺图层 $id');
    }

    // ---------------------------------------------------------------- 3.5 在线河网真的加载了
    // 图层存在 ≠ 有数据。这里直接问原生层：hydro 源里的 waterway 要素有没有进来。
    // 空数组说明矢量瓦片没下载成功（离线 / 域名不通），此时 App 会退回本地数据。
    var hydroFeats = const [];
    var hydroWater = const [];
    final hydroOk = await until(tester, () async {
      hydroFeats = await ctl!.querySourceFeatures('hydro', 'waterway', null);
      hydroWater = await ctl!.querySourceFeatures('hydro', 'water', null);
      // waterway 是河流中心线、water 是水体面；只要有一类进来就说明瓦片到了
      return hydroFeats.isNotEmpty || hydroWater.isNotEmpty;
    }, timeoutMs: 90000);
    // ignore: avoid_print
    print('[TEST] hydro waterway features = ${hydroFeats.length} '
        'water features = ${hydroWater.length} loaded=$hydroOk');
    expect(hydroOk, isTrue,
        reason: '在线河网（OSM 矢量瓦片）一条要素都没加载到，'
            '说明 tiles.openfreemap.org 拉不到数据，小河仍然不会显示');

    // 水库 / 池塘图标层必须能查到水体面
    // ignore: avoid_print
    print('[TEST] hydro water features（复核） = ${hydroWater.length}');
    expect(hydroWater, isNotEmpty,
        reason: 'hydro 源里没有 water 面要素，水库池塘图标没有可标注的对象');

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

    // 地图视口尺寸 —— 整视口矩形查询要用
    var mapSize = tester.getSize(find.byType(mgl.MapLibreMap));
    // 兜底：某些情况下 MapLibreMap 尺寸拿不到合理值
    if (mapSize.width < 8 || mapSize.height < 8) {
      mapSize = tester.getSize(find.byType(SpotMapGlScreen));
    }
    final region = await ctl!.getVisibleRegion();
    // ignore: avoid_print
    print('[TEST] mapSize=$mapSize region='
        '${region.southwest.latitude},${region.southwest.longitude} ~ '
        '${region.northeast.latitude},${region.northeast.longitude} '
        'riverCenter=$riverPt verts=${river.geometry.length}');

    final probe = await _probeRiver(tester, ctl!, river, mapSize);
    // queryRenderedFeaturesInRect 返回的是 List<Map>，取图层名要用 ['layerId']
    final hitLayers = probe.hits.isEmpty
        ? '-'
        : probe.hits.map((h) => '${(h as Map)['layerId']}').toSet();
    // ignore: avoid_print
    print('[TEST] river="${river.name}" hits=${probe.hits.length} '
        'layers=$hitLayers '
        'onScreenVerts=${probe.onScreen} nearest=$probe.at');
    expect(probe.hits, isNotEmpty,
        reason: '相机已停在「${river.name}」折线顶点上，但整视口矩形里查不到 '
            '河流要素（本地 rivers-line 或在线 hydro-river-line / hydro-water '
            '都算，视口内顶点数=${probe.onScreen}），说明河流图层没真正渲染出来');

    // ---------------------------------------------------------------- 5.5 在线河网在当前视野画出蓝色
    // 这条才是用户真正要的：站在长江边，屏幕上必须能看到蓝色的水体/河道，
    // 而且来自 OSM 那一层（不是本地那 43 条兜底数据）。
    final viewAll = Rect.fromLTWH(
        2, 2, mapSize.width - 4, mapSize.height - 4);
    var hydroHits = const [];
    final hydroRendered = await until(tester, () async {
      hydroHits = await ctl!.queryRenderedFeaturesInRect(
          viewAll, ['hydro-river-line', 'hydro-water'], null);
      return hydroHits.isNotEmpty;
    }, timeoutMs: 90000);
    // ignore: avoid_print
    print('[TEST] hydro rendered in view = ${hydroHits.length} '
        'ok=$hydroRendered');
    expect(hydroRendered, isTrue,
        reason: '在线河网图层在当前视野里没有渲染出任何要素 —— '
            '数据加载到了但图层没显示（可能是开关联动把它关了）');

    // ---------------------------------------------------------------- 5b. 禁钓区 / 湖泊真的画出来了
    //
    // 「图层开关点了没反应」最常见的真因不是开关坏了，而是图层压根没渲染成像素：
    //   - 禁钓区填色只有 0.14 不透明度，在卫星影像上基本看不见；
    //   - minzoom 定得太高（6 级），城市级别根本不显示。
    // 这里挑一个「紧凑的」多边形，把相机对准它再查整视口 ——
    // 能查到要素，才说明红色禁钓区真的落在屏幕上了。
    ({double lat, double lng, double span})? bboxOf(List<ll.LatLng> ring) {
      if (ring.length < 3) return null;
      var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      var la = 0.0, ln = 0.0;
      for (final p in ring) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
        la += p.latitude;
        ln += p.longitude;
      }
      return (
        lat: la / ring.length,
        lng: ln / ring.length,
        span: (maxLng - minLng).abs(),
      );
    }

    final zonesData = await MapDataService.zones();
    final compactZones = <NoFishingZone>[];
    for (final z in zonesData.zones) {
      if (!z.onMap || z.rings.isEmpty) continue;
      final b = bboxOf(z.rings.first);
      if (b == null) continue;
      if (b.span >= 0.02 && b.span <= 0.6) compactZones.add(z);
    }
    expect(compactZones, isNotEmpty, reason: '禁钓区里没有紧凑多边形，无法验证渲染');
    final zone = compactZones.first;
    final zoneB = bboxOf(zone.rings.first)!;
    expect(
        await _ensureCameraAt(tester, ctl!, ll.LatLng(zoneB.lat, zoneB.lng), 11),
        isTrue,
        reason: '相机没能移到禁钓区「${zone.name}」');
    await wait(tester, 500);
    final viewRect =
        Rect.fromLTWH(4, 4, mapSize.width - 8, mapSize.height - 8);
    final zoneHits =
        await ctl!.queryRenderedFeaturesInRect(viewRect, ['zones-fill'], null);
    // ignore: avoid_print
    print('[TEST] zone="${zone.name}" center=${zoneB.lat},${zoneB.lng} '
        'hits=${zoneHits.length}');
    expect(zoneHits, isNotEmpty,
        reason: '禁钓区「${zone.name}」在视野里查不到 zones-fill 要素，'
            '红色禁钓区没渲染出来');

    WaterBody? lake;
    var lakeSpan = 9e9;
    for (final w in waters) {
      if (w.isRiver || w.geometry.length < 4) continue;
      final b = bboxOf(w.geometry);
      if (b == null) continue;
      if (b.span >= 0.02 && b.span < lakeSpan) {
        lakeSpan = b.span;
        lake = w;
      }
    }
    expect(lake, isNotNull, reason: '没有可用的湖泊多边形');
    final lk = lake!;
    final lakeB = bboxOf(lk.geometry)!;
    expect(
        await _ensureCameraAt(tester, ctl!, ll.LatLng(lakeB.lat, lakeB.lng), 10),
        isTrue,
        reason: '相机没能移到湖泊「${lk.name}」');
    await wait(tester, 500);
    // 同上：在线河网就绪后本地 lakes-fill 会被隐藏，所以同时查 hydro-water
    final lakeHits = await ctl!
        .queryRenderedFeaturesInRect(viewRect, _lakeLayers, null);
    final lakeHitLayers = lakeHits.isEmpty
        ? '-'
        : lakeHits.map((h) => '${(h as Map)['layerId']}').toSet();
    // ignore: avoid_print
    print('[TEST] lake="${lk.name}" center=${lakeB.lat},${lakeB.lng} '
        'hits=${lakeHits.length} layers=$lakeHitLayers');
    expect(lakeHits, isNotEmpty,
        reason: '湖泊「${lk.name}」在视野里查不到蓝色水面要素'
            '（本地 lakes-fill 或在线 hydro-water），水面没渲染出来');

    // ---------------------------------------------------------------- 6. 钓点能命中且 id 对得上
    final spots = await SpotService.fetchSpots();
    final usable = spots.where((s) => s.lat != 0 && s.lng != 0).toList();
    expect(usable, isNotEmpty, reason: '后端没返回钓点，无法验证点击进详情');

    final spot = usable.first;
    final spotPt = ll.LatLng(spot.lat, spot.lng);
    expect(await _ensureCameraAt(tester, ctl!, spotPt, 15), isTrue,
        reason: '相机没能移到钓点「${spot.name}」所在位置');

    final spotScreen = await ctl!.toScreenLocation(_mapLat(spotPt));
    // 和 App 内真实点击逻辑保持一致：以点为中心取 44x44 的可点区域
    final spotRect = Rect.fromCenter(
      center: Offset(spotScreen.x.toDouble(), spotScreen.y.toDouble()),
      width: 44,
      height: 44,
    );
    final spotHits =
        await ctl!.queryRenderedFeaturesInRect(spotRect, ['spots-pin'], null);
    // ignore: avoid_print
    print('[TEST] spot="${spot.name}" id=${spot.id} screen=$spotScreen '
        'hits=${spotHits.length} (44x44)');
    expect(spotHits, isNotEmpty,
        reason: '钓点「${spot.name}」在屏幕 $spotScreen 处 44x44 区域内查不到要素，'
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
          return ids.contains('spots-pin');
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
        final upd = mgl.CameraUpdate.newLatLngZoom(mgl.LatLng(t.$1, t.$2), t.$3);
        // 同样要检查返回值：被拒绝的移动等于没跳，压测就白跑了
        var ok = false;
        try {
          ok = (await ctl!.animateCamera(upd,
                  duration: const Duration(milliseconds: 350))) ??
              false;
        } catch (_) {}
        if (!ok) {
          try {
            await ctl!.moveCamera(upd);
          } catch (_) {}
        }
        // 给原生层时间下瓦片、解码、上屏
        await wait(tester, 1200);
        cost.add(sw.elapsedMilliseconds);

        // 每一跳都必须还活着：能读到相机、图层没丢
        expect(ctl!.cameraPosition, isNotNull,
            reason: '第 ${cost.length} 次跳转后相机位置读不到，原生层可能已失效');
        final ids = (await ctl!.getLayerIds()).map((e) => e.toString()).toList();
        expect(ids, contains('spots-pin'),
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
    var stressSize = tester.getSize(find.byType(mgl.MapLibreMap));
    if (stressSize.width < 8 || stressSize.height < 8) {
      stressSize = tester.getSize(find.byType(SpotMapGlScreen));
    }
    final probe = await _probeRiver(tester, ctl!, river, stressSize);
    // ignore: avoid_print
    print('[PERF] 压测后仍可命中「${river.name}」: ${probe.hits.length} 个要素 '
        '(视口内顶点=${probe.onScreen})');
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
          return ids.contains('spots-pin');
        }, timeoutMs: 90000),
        isTrue,
        reason: '钓点图层没就绪');

    // ② 镜头移到一片不会有钓点的海面（东海外海），
    //    这样「查询结果从空 → 有」就只可能是新注入的钓点造成的
    const newLat = 29.9500;
    const newLng = 122.4000;
    expect(await _ensureCameraAt(tester, ctl!, ll.LatLng(newLat, newLng), 15),
        isTrue,
        reason: '相机没能移到测试海域');

    final before = await ctl!.toScreenLocation(mgl.LatLng(newLat, newLng));
    final beforeHits = await ctl!.queryRenderedFeaturesInRect(
      Rect.fromCenter(
          center: Offset(before.x.toDouble(), before.y.toDouble()),
          width: 20,
          height: 20),
      ['spots-pin'],
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
      ['spots-pin'],
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
