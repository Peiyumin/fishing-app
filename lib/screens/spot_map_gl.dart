import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Point;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/no_fishing_zone.dart';
import '../models/water_body.dart';
import '../services/location_service.dart';
import '../services/map_config_service.dart';
import '../services/map_data_service.dart';
import '../services/map_tile_source.dart';
import '../services/spot_service.dart';
import 'spot_detail_screen.dart';
import 'spot_map_screen.dart' show SpotMapController, SpotMapScreen;

/// 钓点地图 · 原生 MapLibre 内核（v2.1.12）
///
/// ------------------------------------------------------------
/// 为什么另起一套：
///   竞品（川钓圈）反编译出来是 `org.maplibre.android.maps.MapView`，
///   瓦片在原生层走 GPU 贴图，原生自带瓦片调度、多线程下载、磁盘缓存，
///   所以「清晰且不卡」。而 flutter_map 是纯 Dart 画布逐瓦片贴图，
///   一屏几十张就要几十次解码 + 几十条绘制命令挤在 UI 线程，
///   老机型直接掉帧，再叠加内存峰值就被系统杀掉（卡死闪退）。
///
///   这里用 maplibre_gl 把地图整个交给原生 GL：
///     - 底图（星图地球影像 / 注记 / 路网）→ raster source
///     - 河流 / 湖泊 / 禁钓区 → GeoJSON source + fill / line layer
///     - 钓点 → circle layer（点击靠 queryRenderedFeatures 命中）
///   Dart 只负责发指令，渲染、缓存、手势全在原生侧。
///
/// 兜底：
///   1. 后台「地图底图 → 渲染内核」可切回 flutter_map，不发版即可回退；
///   2. 原生层若 8 秒内没起来（某些模拟器 / 老 GPU），本页自动降级到
///      flutter_map 内核，不会白屏。
class SpotMapGlScreen extends StatefulWidget {
  const SpotMapGlScreen({
    super.key,
    this.embedded = false,
    this.extraSpots = const [],
    this.controller,
  });

  /// 嵌入钓点页「野钓钓点」Tab 时为 true（不画搜索栏，顶部让位）
  final bool embedded;

  /// 外层传入的野钓点（钓点页已拉过，避免重复请求）
  final List<FishingSpot> extraSpots;

  /// 宿主页联动定位用
  final SpotMapController? controller;

  /// 集成测试钩子：地图创建后把原生 controller 交出去
  ///
  /// 生产环境恒为 null（不持有任何引用，无泄漏风险）。
  /// 只有 `integration_test/` 会在 iOS 模拟器上设它，用来断言：
  /// 底图源是不是星图（而不是 SDK 默认 demotiles）、河湖/禁钓区/钓点
  /// 图层有没有真的加上、按屏幕坐标能不能查到钓点要素。
  static void Function(MapLibreMapController c)? debugOnControllerCreated;

  /// 集成测试钩子：六个业务图层全部加完（或重试放弃）时回调一次
  ///
  /// 测试里据此断言 `getLayerIds()` 是否包含全部图层 —— 这是「图层生效」
  /// 唯一的机器可判定证据，比肉眼看截图可靠。
  static void Function(MapLibreMapController c)? debugOnLayersReady;

  /// 原生内核就绪的超时时长（生产 8 秒；集成测试会放宽，模拟器起得慢）
  static Duration readyTimeout = const Duration(seconds: 8);

  @override
  State<SpotMapGlScreen> createState() => _SpotMapGlScreenState();
}

class _SpotMapGlScreenState extends State<SpotMapGlScreen> {
  MapLibreMapController? _map;
  bool _styleReady = false;

  /// 底图配置是否已读到位（读到才建地图，避免样式二次加载）
  bool _cfgReady = false;
  TileSource _tile = const TileSource(kind: TileSourceKind.gaode);

  /// 样式文件的**绝对路径**（不是 JSON 内容）
  ///
  /// ★★ 这里有个坑，v2.1.13 之前一直是错的（iOS 上表现为「不是卫星地图」）：
  /// `maplibre_gl 0.22.0` 的 iOS 端 **不支持 JSON 字符串样式** ——
  /// `MapLibreMapController.swift` 的 `setStyleString` 里写得很清楚：
  ///
  ///     } else if styleString.hasPrefix("{") || styleString.hasPrefix("[") {
  ///       // Currently the iOS MapLibre SDK does not have a builder for json.
  ///       NSLog("setStyleString - JSON style currently not supported")
  ///     }
  ///
  /// 也就是说传 JSON 会被**直接丢掉**，`styleURL` 保持 SDK 默认值 →
  /// 地图渲染成 MapLibre 内置的 demo 底图（国家填色 + 英文国名 + 北回归线），
  /// 我们的星图影像 / 河湖 / 禁钓区 / 钓点图层全部不生效。
  /// Android 端倒是支持 `fromJson`，所以只有 iOS 中招。
  ///
  /// 解法：把样式 **落成临时文件、传绝对路径**。两端都认这个分支 ——
  ///   iOS:     `hasPrefix("/")` → `mapView.styleURL = URL(fileURLWithPath:)`
  ///   Android: `startsWith("/")` → `setStyle(Style.Builder().fromUri(...))`
  String? _stylePath;

  List<WaterBody> _waters = const [];
  NoFishingData _zones = NoFishingData.empty;
  List<FishingSpot> _spots = const [];
  Map<String, FishingSpot> _spotById = const {};

  /// 默认只挂一层底图（卫星），路网注记关掉。
  ///
  /// 竞品「钓鱼佬」的底图配置里，卫星 / 路网是**互斥的两个选项**，
  /// 永远不会同时请求两套瓦片。我们之前默认把影像 + 注记一起叠上，
  /// 每屏瓦片请求直接翻倍（40 张 vs 20 张），这才是拖动发涩的主因。
  /// 需要地名时在「图层」里手动打开即可。
  final MapLayerState _layers =
      MapLayerState(satellite: true, roadLabels: false);

  double? _myLat;
  double? _myLng;
  bool _locating = false;

  /// 业务图层（河湖/禁钓/钓点）是否已经加过一轮
  bool _layersReady = false;
  bool _rendering = false;

  /// 图层添加失败的重试次数（原生层刚 ready 时偶尔会抛「style 未就绪」）
  int _renderAttempt = 0;

  /// 原生内核起不来 → 自动降级 flutter_map
  bool _fallback = false;
  Timer? _guard;

  @override
  void initState() {
    super.initState();
    widget.controller?.bind(_moveTo);
    _loadData();
    MapConfigService.load().then((_) async {
      if (!mounted) return;
      // 先切底图源，_buildStyle() 依赖 _tile
      _tile = MapConfigService.source;
      // ★ 样式必须落成文件传绝对路径，原因见 _stylePath 注释
      final path = await _writeStyleFile(_buildStyle());
      if (!mounted) return;
      setState(() {
        _stylePath = path;
        _cfgReady = true;
      });
      // 原生层 8 秒还没 ready 就降级，绝不让用户对着白屏
      //
      // ★ 判定条件必须是「原生 View 压根没创建」（_map == null），
      //   而不是「样式没加载完」。底图瓦片在网络差的时候本来就慢，
      //   这时候把用户切到 Dart 版内核（flutter_map 逐瓦片画布贴图）
      //   只会更卡 —— 老内核在 iOS 上一屏几十张图解码，正好是
      //   「一拖动就卡死」的形态。只要 View 起来了就继续等瓦片。
      _guard = Timer(SpotMapGlScreen.readyTimeout, () {
        if (!mounted || _map != null) return;
        setState(() {
          _map = null;
          _fallback = true;
        });
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 宿主页（钓点页）已经定位过、并把坐标通过 controller 补发过来了，
      // 这里就不要再定一次 —— 重复定位等于让用户多等一次 GPS 冷启动，
      // 表现就是「切到野钓钓点后盯着全国视角好几秒」。
      if (_pendingMove != null) return;
      _locate(silent: true);
    });
  }

  /// 宿主页（钓点页）刷新后把新钓点并进地图
  ///
  /// ★ 修的是「添加新钓点后在地图上点不进详情」的真 bug：
  ///   以前 `extraSpots` 只在本页 initState 用一次，之后宿主页 `_load()`
  ///   拿到新钓点重新 build，本页因为 State 没重建，`_spots` / `_spotById`
  ///   一直是旧快照 —— 新钓点既不显示，也查不到 id，点了自然没反应。
  @override
  void didUpdateWidget(covariant SpotMapGlScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.extraSpots, widget.extraSpots)) {
      _mergeSpots(widget.extraSpots);
    }
  }

  /// 把一批钓点并进现有集合（只增不删），然后只更新 GeoJSON source
  ///
  /// 用 `setGeoJsonSource` 而不是重建图层：重建会让整层闪一下，
  /// 而且 addLayer 在同名图层已存在时会直接抛异常。
  Future<void> _mergeSpots(List<FishingSpot> incoming) async {
    if (incoming.isEmpty) return;
    final map = <String, FishingSpot>{for (final s in _spots) s.id: s};
    var added = 0;
    for (final s in incoming) {
      if (s.lat == 0 && s.lng == 0) continue;
      if (!map.containsKey(s.id)) added++;
      map[s.id] = s; // 覆盖成最新数据（名称/简介可能在后台改过）
    }
    if (added == 0) return; // 没有新钓点，没必要惊动原生层
    if (!mounted) return;
    setState(() {
      _spots = map.values.toList();
      _spotById = map;
    });
    await _updateSpotsSource();
  }

  Future<void> _updateSpotsSource() async {
    final c = _map;
    if (c == null || !_styleReady || !_layersReady) return;
    try {
      await c.setGeoJsonSource('spots', _fc(_spotFeatures()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _guard?.cancel();
    widget.controller?.unbind();
    // 不要在这里 dispose controller：
    // MapLibreMap 自己的 State.dispose() 会 dispose 同一个 controller
    // （maplibre_gl/src/maplibre_map.dart 的 _MapLibreMapState.dispose），
    // 我们再调一次就是二次 dispose，debug 下直接抛
    // "A MapLibreMapController was used after being disposed"。
    // 之前 iOS 上一直是 demotiles（样式没生效），这条路径没人真正走到过，
    // 是 iOS 集成测试跑通后才发现的老问题。
    _map = null;
    super.dispose();
  }

  // ---------------------------------------------------------------- 数据

  Future<void> _loadData() async {
    try {
      final r = await Future.wait([
        MapDataService.waters(),
        MapDataService.zones(),
        SpotService.fetchSpots(),
      ]);
      if (!mounted) return;
      final spots = (r[2] as List<FishingSpot>)
          .where((s) => s.lat != 0 && s.lng != 0)
          .toList();
      final map = <String, FishingSpot>{for (final s in spots) s.id: s};
      for (final s in widget.extraSpots) {
        map[s.id] = s;
      }
      setState(() {
        _waters = r[0] as List<WaterBody>;
        _zones = r[1] as NoFishingData;
        _spots = map.values.toList();
        _spotById = map;
      });
      await _renderLayers();
    } catch (_) {
      // 数据拉不到不影响底图
    }
  }

  // ---------------------------------------------------------------- 样式

  /// 把模板里的占位符替换成真实地址
  ///
  /// MapLibre 的 raster source **不支持 {s} 子域占位符**，
  /// 必须展开成 tiles1/2/3 三条 URL 交给原生层轮询。
  List<String> _urls(String tpl) {
    var s = tpl;
    _tile.additionalOptions.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    if (!s.contains('{s}')) return [s];
    return ['1', '2', '3'].map((i) => s.replaceAll('{s}', i)).toList();
  }

  String _buildStyle() {
    return jsonEncode(<String, dynamic>{
      'version': 8,
      'sources': {
        'sat': {
          'type': 'raster',
          'tiles': _urls(_tile.satelliteTemplate),
          'tileSize': 256,
          'maxzoom': _tile.maxNativeZoom,
          'attribution': _tile.attribution,
        },
        'vec': {
          'type': 'raster',
          'tiles': _urls(_tile.vectorTemplate),
          'tileSize': 256,
          'maxzoom': _tile.maxNativeZoom,
        },
        'cia': {
          'type': 'raster',
          'tiles': _urls(_tile.labelTemplate),
          'tileSize': 256,
          'maxzoom': _tile.maxNativeZoom,
        },
      },
      'layers': [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': '#DDE6EC'},
        },
        // raster-fade-duration: 0 —— 关掉瓦片淡入动画。
        // 默认 300ms 的淡入会让原生层在瓦片刚到时反复重绘，
        // 快速拖动时叠加上一层重绘，是掉帧的隐形大头。
        {
          'id': 'sat',
          'type': 'raster',
          'source': 'sat',
          'paint': {'raster-fade-duration': 0},
        },
        {
          'id': 'vec',
          'type': 'raster',
          'source': 'vec',
          'layout': {'visibility': 'none'},
          'paint': {'raster-fade-duration': 0},
        },
        {
          'id': 'cia',
          'type': 'raster',
          'source': 'cia',
          // 低倍视野下地名注记看不清也没意义，却不省瓦片请求 ——
          // 10 级以下直接不请求，全国视角只拉一层影像。
          'minzoom': 10,
          'paint': {'raster-fade-duration': 0},
        },
      ],
    });
  }

  /// 把样式 JSON 写进临时目录，返回绝对路径
  ///
  /// 为什么不用 `file://`：0.22.0 的 iOS 实现里 `file://` 分支是拿
  /// `Bundle.main.path(forResource:)` 去找**打包进 App 的资源**，
  /// 传沙盒绝对路径会直接 `NSLog("Path not found")` 失败；
  /// 而以 `/` 开头的裸路径才会走 `URL(fileURLWithPath:)`。
  /// 所以这里返回不带 scheme 的纯路径。
  Future<String> _writeStyleFile(String json) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/spot_map_style.json');
    try {
      // 内容没变就不重写，省掉每次进页面的一次 IO
      if (await f.exists() && await f.readAsString() == json) return f.path;
    } catch (_) {
      // 读失败就当作需要重写
    }
    await f.writeAsString(json, flush: true);
    debugPrint('[SpotMapGL] style -> ${f.path}');
    return f.path;
  }

  // ---------------------------------------------------------------- 图层

  Map<String, dynamic> _fc(List<Map<String, dynamic>> feats) =>
      {'type': 'FeatureCollection', 'features': feats};

  Map<String, dynamic> _feature(
          String type, dynamic coords, Map<String, dynamic> props) =>
      {
        'type': 'Feature',
        'properties': props,
        'geometry': {'type': type, 'coordinates': coords},
      };

  /// WGS-84 环 → 当前底图坐标系环
  ///
  /// 高德是 GCJ-02 必须纠偏，否则叠加物整体偏移 300~500 米；
  /// 星图地球 / 天地图未加偏，原样输出。
  ///
  /// ★ [close] 必须对河流传 false。
  ///   旧写法对**所有**要素都补一个「回到首点」的闭合点，河流是折线不是环，
  ///   于是长江从入海口（121°E）被一条直线拉回源头（91°E），
  ///   地图上会横着多出一条穿越整个中国的假蓝线。
  ///   这也是「河道看起来不对 / 像是乱画」的来源之一。
  List<List<double>> _ring(List<ll.LatLng> pts, {bool close = true}) {
    final out = <List<double>>[];
    for (final p in pts) {
      final q = _tile.project(p);
      out.add([q.longitude, q.latitude]);
    }
    if (close &&
        out.length > 2 &&
        (out.first[0] != out.last[0] || out.first[1] != out.last[1])) {
      out.add(out.first);
    }
    return out;
  }

  /// 钓点要素集合（GeoJSON features）
  ///
  /// 抽出来单独一份，是为了「首次加载」和「发布新钓点后增量刷新」走同一条
  /// 生成路径 —— 两边各写一遍很容易出现「新增的点漏了坐标纠偏」这类不一致。
  List<Map<String, dynamic>> _spotFeatures() {
    final feats = <Map<String, dynamic>>[];
    for (final s in _spots) {
      final q = _tile.project(ll.LatLng(s.lat, s.lng));
      feats.add(_feature('Point', [q.longitude, q.latitude], {'id': s.id}));
    }
    return feats;
  }

  /// 幂等加 source：已存在就更新数据，不抛异常
  ///
  /// 重试逻辑要靠它 —— `addGeoJsonSource` 遇到同名 source 会抛
  /// «Source X already exists»，直接重试就永远失败。
  Future<void> _safeSource(String id, Map<String, dynamic> data) async {
    final c = _map;
    if (c == null) return;
    try {
      await c.addGeoJsonSource(id, data);
    } catch (_) {
      await c.setGeoJsonSource(id, data);
    }
  }

  /// 幂等加图层：已存在则跳过（属性由 _applyLayerToggles 控制显隐）
  Future<void> _safeLayer(
      String source, String layer, LayerProperties props,
      {double? minzoom}) async {
    final c = _map;
    if (c == null) return;
    try {
      await c.addLayer(source, layer, props, minzoom: minzoom);
    } catch (_) {
      // 已存在：不重建（重建会闪一下），显隐交给 _applyLayerToggles
    }
  }

  /// 业务图层 id 清单
  ///
  /// ★ 用来做「加了没真的加上」的校验。旧代码的 `_safeLayer` 把
  ///   addLayer 的异常全部吞掉，即使**一个都没加成**也照样把 `_layersReady`
  ///   置为 true —— 表现就是「图层开关只有底图那两个有用，下面几个点了没反应」。
  ///   现在加完必须回读 `getLayerIds()` 逐个确认，缺一个就重试。
  static const List<String> _bizLayers = [
    'lakes-fill',
    'lakes-line',
    'rivers-casing',
    'rivers-line',
    'zones-fill',
    'zones-line',
    'spots-pin',
  ];

  /// 随缩放插值的数值属性（MapLibre 表达式）
  ///
  /// [stops] 是 [zoom1, value1, zoom2, value2, ...]。
  /// 用它而不是固定像素宽度，是因为全国视野（z4）和街道视野（z16）
  /// 需要的线宽差 10 倍以上：固定 4.5px 在 z4 细得看不见，
  /// 在 z16 又细得像根头发 —— 用户就会觉得「河道图层没生效」。
  dynamic _zNum(List<num> stops) {
    final out = <dynamic>[
      'interpolate',
      ['linear'],
      ['zoom'],
    ];
    for (var i = 0; i + 1 < stops.length; i += 2) {
      out.add(stops[i]);
      out.add(stops[i + 1]);
    }
    return out;
  }

  Future<void> _renderLayers() async {
    final c = _map;
    if (c == null || !_styleReady || _layersReady || _rendering) return;
    _rendering = true;
    try {
      // ---------------- 水域 ----------------
      final lakes = <Map<String, dynamic>>[];
      final rivers = <Map<String, dynamic>>[];
      for (final w in _waters) {
        if (w.isRiver) {
          // ★ 河流是折线，不能闭合（见 _ring 注释）
          final coords = _ring(w.geometry, close: false);
          if (coords.length < 2) continue;
          rivers.add(_feature('LineString', coords, {'n': w.name}));
        } else {
          final coords = _ring(w.geometry);
          if (coords.length < 4) continue;
          lakes.add(_feature('Polygon', [coords], {'n': w.name}));
        }
      }

      // ---------------- 禁钓区 ----------------
      final zones = <Map<String, dynamic>>[];
      for (final z in _zones.zones) {
        if (!z.onMap || z.rings.isEmpty) continue;
        final coords = _ring(z.rings.first);
        if (coords.length < 4) continue;
        zones.add(_feature('Polygon', [coords], {
          'active': z.statusNow().active,
          'name': z.name,
        }));
      }

      // ---------------- 钓点图标 ----------------
      // 红色定位针 + 白色鱼形，运行时用 Canvas 画成 PNG 交给原生层当 icon
      await _ensureSpotIcon();

      // ---------------- 湖泊：蓝色水面 ----------------
      await _safeSource('lakes', _fc(lakes));
      await _safeLayer(
          'lakes',
          'lakes-fill',
          const FillLayerProperties(
              fillColor: '#2E9BF0',
              // ★ 不再把传 opacity 设成 0 —— 见 _applyLayerToggles 注释
              fillOpacity: 0.45),
          minzoom: 3);
      await _safeLayer(
          'lakes',
          'lakes-line',
          const LineLayerProperties(
              lineColor: '#0B4FA8', lineWidth: 1.6, lineOpacity: 0.9),
          minzoom: 3);

      // ---------------- 河流：双层水面带 ----------------
      // 深蓝描边在下、亮蓝芯在上，合成「一条有边界的水面」，
      // 也就是参考图里那种河道渲染色；单根半透明细线在卫星图上基本看不见。
      await _safeSource('rivers', _fc(rivers));
      await _safeLayer(
          'rivers',
          'rivers-casing',
          LineLayerProperties(
            lineColor: '#0B4FA8',
            lineWidth: _zNum([3, 1.2, 6, 2.4, 9, 5.0, 12, 10.5, 15, 18.0]),
            lineOpacity: 0.95,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          minzoom: 3);
      await _safeLayer(
          'rivers',
          'rivers-line',
          LineLayerProperties(
            lineColor: '#3FA9F5',
            lineWidth: _zNum([3, 0.9, 6, 1.6, 9, 3.6, 12, 8.0, 15, 14.0]),
            lineOpacity: 0.95,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          minzoom: 3);

      // ---------------- 禁钓区：红色 ----------------
      await _safeSource('zones', _fc(zones));
      await _safeLayer(
          'zones',
          'zones-fill',
          const FillLayerProperties(
            fillColor: '#E53935',
            // 正在禁渔期（active=true）的红得更实，已过期的淡一档
            fillOpacity: [
              'case',
              ['==', ['get', 'active'], true],
              0.34,
              0.20,
            ],
          ),
          minzoom: 3);
      await _safeLayer(
          'zones',
          'zones-line',
          const LineLayerProperties(
            lineColor: '#C62828',
            lineWidth: 2.2,
            lineOpacity: 1.0,
            lineJoin: 'round',
          ),
          minzoom: 3);

      // ---------------- 钓点：红色定位图标 ----------------
      await _safeSource('spots', _fc(_spotFeatures()));
      await _safeLayer(
          'spots',
          'spots-pin',
          SymbolLayerProperties(
            iconImage: 'spot-pin',
            // 目标显示尺寸约 25×32（z11），随缩放微调
            iconSize: _zNum([
              4, 0.46 * _iconUnit,
              8, 0.55 * _iconUnit,
              11, 0.62 * _iconUnit,
              15, 0.78 * _iconUnit,
            ]),
            // 针尖对准坐标点，而不是图标中心
            iconAnchor: 'bottom',
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
            iconPadding: 0,
          ),
          minzoom: 0);

      // ---------------- 校验：真的加上了才算成功 ----------------
      final ids =
          (await c.getLayerIds()).map((e) => e.toString()).toSet();
      final missing = _bizLayers.where((e) => !ids.contains(e)).toList();
      if (missing.isNotEmpty) {
        throw StateError('图层未生效: $missing');
      }

      _layersReady = true;
      _renderAttempt = 0;
      // 首次加完后按当前开关状态应用一次显隐（否则默认关掉的图层仍会显示）
      await _applyLayerToggles();
      await _drawMe();
      _updateScale();
      // 集成测试：图层全部加完后回调一次，断言 6 个图层真的存在
      SpotMapGlScreen.debugOnLayersReady?.call(c);
    } catch (_) {
      // 原生层刚 ready 的一瞬间可能还没把 style 状态同步好，addLayer 会抛异常。
      // 旧写法吞掉就再也不重试 → 表现就是「图层整个不生效」。
      // 这里退避重试，最多 5 次（配合 _safeSource/_safeLayer，重试是幂等的）。
      _layersReady = false;
      if (_renderAttempt < 5) {
        _renderAttempt++;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _renderLayers();
        });
      }
    } finally {
      _rendering = false;
    }
  }

  // ------------------------------------------------------------ 钓点图标

  bool _spotIconReady = false;

  /// 图标「像素 → 显示单位」的换算系数
  ///
  /// 两端的解码方式不一样，必须换算，否则同一份 iconSize 在 Android 上会大 3 倍：
  ///   · iOS：插件用 `UIImage(data:scale: UIScreen.main.scale)`，
  ///     120px 的图在 3x 屏上 = **40pt**；
  ///   · Android：`BitmapFactory.decodeByteArray` 解出的 bitmap 不带 density，
  ///     MapLibre 按 1px = 1dp 处理，120px = **120dp**。
  /// 差一个 devicePixelRatio，所以 Android 侧除以它即可对齐视觉尺寸。
  double get _iconUnit {
    if (Platform.isIOS) return 1.0;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    return dpr > 0 ? 1.0 / dpr : 1.0;
  }

  /// 把「红色定位针 + 白色鱼形」画成 PNG 交给原生层
  ///
  /// 为什么运行时画而不是放 png 资源：
  ///   1. 不用多打包一份 3x 图，省体积；
  ///   2. 颜色跟 App 主题（红色）保持一致，改主题不用重新出图；
  ///   3. MapLibre 的 icon 只吃「图片像素」，画大一点再缩小显示更清晰。
  Future<void> _ensureSpotIcon() async {
    final c = _map;
    if (c == null || _spotIconReady) return;
    final bytes = await _buildPinIcon();
    if (bytes == null) return;
    try {
      await c.addImage('spot-pin', bytes);
    } catch (_) {
      // 同名已存在：直接用
    }
    _spotIconReady = true;
  }

  Future<Uint8List?> _buildPinIcon() async {
    const double w = 120;
    const double h = 156;
    const double cx = 60; // 圆心 x
    const double cy = 56; // 圆心 y
    const double r = 40; // 圆半径
    const double tipY = 148; // 针尖 y

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));

    // 水滴形：圆 + 下方收成尖
    final head = Path()
      ..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: r));
    final tail = Path()
      ..moveTo(cx - r * 0.62, cy + r * 0.62)
      ..quadraticBezierTo(cx - r * 0.32, cy + r * 1.28, cx, tipY)
      ..quadraticBezierTo(cx + r * 0.32, cy + r * 1.28, cx + r * 0.62, cy + r * 0.62)
      ..close();
    final pin = Path.combine(PathOperation.union, head, tail);

    // 白色描边：卫星影像背景很花，没有白边会糊成一团
    canvas.drawPath(
        pin,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(pin, Paint()..color = const Color(0xFFE53935));

    // 白色鱼形：椭圆鱼身 + 三角尾鳍
    final body = Path()
      ..addOval(Rect.fromCenter(
          center: const Offset(cx + 3, cy - 2), width: 42, height: 26));
    final fin = Path()
      ..moveTo(cx - 16, cy - 2)
      ..lineTo(cx - 30, cy - 14)
      ..lineTo(cx - 30, cy + 10)
      ..close();
    canvas.drawPath(
        Path.combine(PathOperation.union, body, fin),
        Paint()..color = Colors.white);
    // 鱼眼（挖回红色）
    canvas.drawCircle(
        const Offset(cx + 16, cy - 7), 3.4, Paint()..color = const Color(0xFFE53935));

    final img = await rec.endRecording().toImage(w.round(), h.round());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd?.buffer.asUint8List();
  }

  Future<void> _setVis(String layer, bool on) async {
    try {
      await _map?.setLayerVisibility(layer, on);
    } catch (_) {}
  }

  /// 业务图层是否都真的存在于原生层
  Future<bool> _bizLayersExist() async {
    final c = _map;
    if (c == null) return false;
    try {
      final ids = (await c.getLayerIds()).map((e) => e.toString()).toSet();
      return _bizLayers.every(ids.contains);
    } catch (_) {
      return false;
    }
  }

  /// 应用图层显隐
  ///
  /// ★ 只切 visibility，**不改 opacity**。
  ///   旧写法把「开/关」编码进了 addLayer 时的 `fillOpacity: _layers.x ? a : 0.0`，
  ///   于是图层一旦以「关」的状态被创建，opacity 就永久是 0 ——
  ///   之后再 `setLayerVisibility(true)` 也还是全透明，看起来就是「开关失灵」。
  ///   现在一律按「开」的样子建层，显隐只由 visibility 决定。
  Future<void> _applyLayerToggles() async {
    await _setVis('sat', _layers.satellite);
    await _setVis('vec', !_layers.satellite);
    // 矢量路网图本身自带地名，再叠注记等于白跑一倍瓦片却看不出差别；
    // 只有卫星模式才需要注记层。
    await _setVis('cia', _layers.roadLabels && _layers.satellite);

    if (!_layersReady) {
      // 业务图层还没真正加成（原生层刚起时 addLayer 可能被拒）：
      // 现场自愈，别让用户点了开关毫无反应
      if (await _bizLayersExist()) {
        _layersReady = true;
      } else {
        _renderAttempt = 0;
        _renderLayers();
        return;
      }
    }
    await _setVis('lakes-fill', _layers.lakes);
    await _setVis('lakes-line', _layers.lakes);
    await _setVis('rivers-casing', _layers.rivers);
    await _setVis('rivers-line', _layers.rivers);
    await _setVis('zones-fill', _layers.noFishingZones);
    await _setVis('zones-line', _layers.noFishingZones);
    await _setVis('spots-pin', _layers.spots);
  }

  // ------------------------------------------------------------ 比例尺

  /// 当前视野的「米 / 像素」，由 onCameraIdle 更新
  ///
  /// 不能用 `cameraPosition.zoom` 算 —— 为了性能我们关掉了
  /// `trackCameraPosition`，那个值根本不会更新（一直是建图时的 zoom）。
  /// 改成从 `getVisibleRegion()` 反算：视野东西向跨度的实地距离 ÷ 视图宽度。
  double? _mpp;

  Future<void> _updateScale() async {
    final c = _map;
    final size = _mapSize;
    if (c == null || size == null || size.width < 40) return;
    try {
      final b = await c.getVisibleRegion();
      final sw = b.southwest;
      final ne = b.northeast;
      final midLat = (sw.latitude + ne.latitude) / 2;
      final meters = const ll.Distance().as(
        ll.LengthUnit.Meter,
        ll.LatLng(midLat, sw.longitude),
        ll.LatLng(midLat, ne.longitude),
      );
      final mpp = meters / size.width;
      if (!mpp.isFinite || mpp <= 0) return;
      if (!mounted) return;
      final old = _mpp;
      // 变化小于 2% 不重建，避免拖动时每帧 setState
      if (old != null && (old - mpp).abs() / mpp < 0.02) return;
      setState(() => _mpp = mpp);
    } catch (_) {}
  }

  /// 左下角比例尺（在原授权文字上方）
  Widget _buildScaleBar() {
    final mpp = _mpp;
    if (mpp == null) return const SizedBox.shrink();
    const maxW = 76.0;
    const steps = <double>[
      5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000,
      10000, 20000, 25000, 50000, 100000, 200000, 500000, 1000000, 2000000,
    ];
    var pick = steps.first;
    for (final s in steps) {
      if (s <= mpp * maxW) {
        pick = s;
      } else {
        break;
      }
    }
    final wpx = pick / mpp;
    final label = pick >= 1000
        ? '${(pick / 1000).toStringAsFixed(pick % 1000 == 0 ? 0 : 1)} 公里'
        : '${pick.round()} 米';
    const lineColor = Color(0xE6000000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: Color(0xE6000000),
              shadows: [Shadow(color: Colors.white, blurRadius: 3)],
            )),
        const SizedBox(height: 2),
        Container(
          width: wpx.clamp(8.0, maxW),
          height: 6,
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: lineColor, width: 1.6),
              right: BorderSide(color: lineColor, width: 1.6),
              bottom: BorderSide(color: lineColor, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 定位

  /// 待执行的镜头移动
  ///
  /// ★ 这里修掉一个「第一次打开地图停在全国视角」的真 bug：
  ///   `initState` 里定位是 postFrame 就发起的，而原生地图要等
  ///   底图配置读盘 + 样式文件落地后才会创建，两者是竞速关系。
  ///   以前 `_map?.animateCamera(...)` 在 `_map == null` 时**静默丢弃**，
  ///   定位成功的坐标根本没生效，地图永远停在 initialCameraPosition
  ///   的 z4 全国视角 —— 屏幕上只有一片卫星海面，河流/钓点全部在
  ///   minzoom 门槛以下不显示，看着就像「地图坏了 / 不动了」。
  ///   现在把目标坐标缓存下来，等 onMapCreated 时再补一次。
  ({double lat, double lng})? _pendingMove;

  void _moveTo(double lat, double lng) {
    _pendingMove = (lat: lat, lng: lng);
    // 宿主页定位成功也会走这条路径（controller 补发），
    // 顺手记下「我的位置」，好把蓝点画上 —— 否则镜头对了但看不到自己在哪
    if (_myLat != lat || _myLng != lng) {
      _myLat = lat;
      _myLng = lng;
      _drawMe();
    }
    _flushPendingMove();
  }

  void _flushPendingMove() {
    final t = _pendingMove;
    final c = _map;
    if (t == null || c == null) return;
    // ★ 这里**不清空** pending —— 镜头是否真的落到位由 _landCamera 反算确认后
    //   才清。原因见 _landCamera 的注释：iOS 上在 style 加载收尾阶段调
    //   animateCamera 会被后续的 camera 重置吞掉，只调一次不可靠。
    _landCamera(t.lat, t.lng);
  }

  /// 把镜头落到目标点，并**反算屏幕中心确认真的到位**
  ///
  /// ★ iOS 真机/模拟器实测定下来的坑（v2.1.17 用集成测试抓到的）：
  ///   `onStyleLoadedCallback` 触发之后立刻 `animateCamera`，镜头会**纹丝不动**，
  ///   屏幕中心精确等于 `initialCameraPosition` 的 (34.5, 108.9) —— 也就是
  ///   style 应用的收尾阶段把 camera 重置回了创建时的值。
  ///   而 `onMapCreated`（style 还没加载）时调用，则可能被排队后又被覆盖。
  ///   两个时机单独用都不可靠，所以改成：**发起 → 等一会 → toLatLng 反算中心 →
  ///   不对就再来一次**，最多 4 轮（约 3 秒）。到位就停，不再骚扰用户。
  ///
  /// 用 `_landSeq` 做代次号：连续触发的落点请求只有最后一个有效，
  /// 避免多个重试循环互相抢镜头。
  int _landSeq = 0;

  Future<void> _landCamera(double lat, double lng) async {
    final seq = ++_landSeq;
    for (var i = 0; i < 4; i++) {
      if (!mounted || seq != _landSeq) return;
      // 第一轮稍等一下让样式收尾，之后每轮间隔 420ms
      await Future<void>.delayed(Duration(milliseconds: i == 0 ? 80 : 420));
      if (!mounted || seq != _landSeq) return;
      final c = _map;
      if (c == null) return;
      final target = CameraUpdate.newLatLngZoom(LatLng(lat, lng), 13);
      // ★ animateCamera 的返回值是 Future<bool?>，**false = 这次移动没被接受**
      //   （原生层正在应用 style / 正在渲染时会拒绝新的动画）。
      //   以前直接忽略返回值，镜头就没动，表现成「定位没反应、地图停在全国视角」。
      //   失败时退回 moveCamera：它是同步设置相机、不进动画队列，抗干扰强得多。
      var ok = false;
      try {
        ok = (await c.animateCamera(target,
                duration: Duration(milliseconds: i == 0 ? 400 : 1))) ??
            false;
      } catch (_) {}
      if (!ok) {
        try {
          await c.moveCamera(target);
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted || seq != _landSeq) return;
      if (await _cameraNear(lat, lng)) {
        _pendingMove = null;
        _updateScale(); // 镜头到位后刷新比例尺
        return;
      }
      debugPrint('[SpotMapGL] 镜头未到位，重试第 ${i + 1} 轮');
    }
    // 4 轮都没成（极慢的模拟器 / 网络卡死）：放弃重试，别一直抢用户镜头
    _pendingMove = null;
  }

  /// 屏幕中心是不是已经在目标点附近（约 1 公里内）
  Future<bool> _cameraNear(double lat, double lng) async {
    final c = _map;
    final size = _mapSize;
    if (c == null || size == null) return false;
    try {
      final center =
          await c.toLatLng(Point<double>(size.width / 2, size.height / 2));
      return (center.latitude - lat).abs() < 0.01 &&
          (center.longitude - lng).abs() < 0.01;
    } catch (_) {
      return false;
    }
  }

  /// 地图视图的真实尺寸（嵌入式 Tab 里不等于屏幕尺寸，必须从 RenderBox 取）
  Size? get _mapSize {
    try {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return box.size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _locate({bool silent = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final pos = await LocationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
      });
      _moveTo(pos.latitude, pos.longitude);
      await _drawMe();
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('定位失败，请检查定位权限（可在系统设置中开启）')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _meAdded = false;

  Future<void> _drawMe() async {
    final c = _map;
    if (c == null || !_styleReady || _myLat == null || _myLng == null) return;
    final q = _tile.project(ll.LatLng(_myLat!, _myLng!));
    final fc = _fc([
      _feature('Point', [q.longitude, q.latitude], const {}),
    ]);
    try {
      if (_meAdded) {
        await c.setGeoJsonSource('me', fc);
      } else {
        await c.addGeoJsonSource('me', fc);
        await c.addLayer(
            'me',
            'me-circle',
            CircleLayerProperties(
              circleColor:
                  '#${AppTheme.accent.value.toRadixString(16).substring(2)}',
              circleRadius: 6,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2.5,
            ));
        _meAdded = true;
      }
    } catch (_) {}
  }

  /// 点地图：命中钓点图标就进详情
  ///
  /// GeoJSON 加进去的图层没有 onLayerTapped，只能 queryRenderedFeatures 按屏幕坐标查。
  ///
  /// ★ 用 44×44 的矩形查询，不是单点查询。
  ///   图标显示尺寸约 40×52，但手指点偏几个像素就查不到，
  ///   用户体验上就是「点了没反应、进不去详情」。44pt 是 iOS/Android
  ///   一致的最小可点区域标准，正好让命中率接近 100%。
  Future<void> _onMapClick(Point<double> point) async {
    final c = _map;
    if (c == null || !_layers.spots || !_layersReady) return;
    // 用户主动点了地图 = 他在看别处了，取消还在跑的定位补镜头重试，
    // 否则第 3、4 轮会把镜头硬拽回当前位置，像被抢方向盘
    _landSeq++;
    const half = 22.0;
    final rect = Rect.fromLTRB(
        point.x - half, point.y - half, point.x + half, point.y + half);
    List feats = const [];
    try {
      feats = await c.queryRenderedFeaturesInRect(rect, ['spots-pin'], null);
      if (feats.isEmpty) {
        // 某些平台实现矩形查询不稳定，退回单点再试一次
        feats = await c.queryRenderedFeatures(point, ['spots-pin'], null);
      }
    } catch (_) {
      return;
    }
    if (feats.isEmpty) return;

    // 命中多条时（密集钓点区）取第一条能对上 id 的，避免短路失败
    for (final f in feats) {
      if (f is! Map) continue;
      final props = f['properties'];
      if (props is! Map) continue;
      final id = props['id'];
      if (id == null) continue;
      final s = _spotById[id.toString()];
      if (s == null) continue;
      if (mounted) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: s)));
      }
      return;
    }
  }

  // ---------------------------------------------------------------- UI

  /// 建图时的初始镜头
  ///
  /// ★ 如果定位比建图先完成（模拟器 / 已有定位缓存时几乎总是这样），
  ///   直接把初始镜头设成当前位置 —— 这是**零成本兜底**：镜头一开始就在
  ///   正确位置，不必跟 style 加载抢时序。真机上 GPS 冷启动通常慢于建图，
  ///   那时 initialCameraPosition 还是全国视角，靠 _landCamera 的确认重试补。
  ///
  /// ★ 结果**只算一次并缓存**：`MapLibreMap` 每次 rebuild 都会用
  ///   `initialCameraPosition.toMap()` 重建 creationParams，如果这里每次返回
  ///   新对象，等于每帧往 PlatformView 塞一份新参数（iOS 上实测会干扰相机），
  ///   而且改动前是 `const` 对象，行为必须保持一致。
  CameraPosition? _initialLocked;

  CameraPosition get _initialCamera {
    final cached = _initialLocked;
    if (cached != null) return cached;
    final t = _pendingMove;
    _initialLocked = t != null
        ? CameraPosition(target: LatLng(t.lat, t.lng), zoom: 13)
        : const CameraPosition(target: LatLng(34.5, 108.9), zoom: 4);
    return _initialLocked!;
  }

  @override
  Widget build(BuildContext context) {
    // 原生层起不来 / 后台配了 dart 内核 → 走老内核
    if (_fallback) {
      return SpotMapScreen(
        embedded: widget.embedded,
        extraSpots: widget.extraSpots,
        controller: widget.controller,
      );
    }

    return Stack(children: [
      Positioned.fill(
        child: _cfgReady
            ? MapLibreMap(
                styleString: _stylePath ?? '',
                initialCameraPosition: _initialCamera,
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                // ★★ 必须是 false。
                //   iOS 端 `mapViewRegionIsChanging` 里只要 trackCameraPosition
                //   为真，就会**每一帧**往 Dart 发一次 `camera#onMove`（带 6 个
                //   数值的相机参数）。手指拖动时等于 60 次/秒的跨平台通道往返，
                //   叠加在 platform view 的合成开销上，实测就是「一动就卡住」。
                //   我们并不需要实时相机位置：缩放按钮改用 zoomBy（增量缩放，
                //   不需要读当前 zoom），落点由 onMapClick 的原生回调给。
                trackCameraPosition: false,
                // ★★ 原生手势独占。
                //   MapLibreMap 在 iOS 是一个 Flutter PlatformView，默认所有触摸
                //   都要先过 Flutter 的手势竞技场（gesture arena）。本页被嵌在
                //   `TabBarView` 里，横向拖动会被 TabBarView 的滚动识别器抢走，
                //   地图拿到的是一个「半截」手势 —— 表现就是拖不动、双指缩放
                //   没反应、甚至手指按着不动整页像死掉。
                //   EagerGestureRecognizer 让原生 View 在触点落下时立即接管，
                //   Flutter 不再参与，拖动 / 缩放直接走原生 GL 线程。
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer()),
                },
                // 原生自带的「i」版权按钮放右下，左下留给自绘的长版权行，避免叠在一起
                attributionButtonPosition: AttributionButtonPosition.bottomRight,
                onMapCreated: (c) {
                  _map = c;
                  SpotMapGlScreen.debugOnControllerCreated?.call(c);
                  // 定位若比原生 View 先到（几乎总是如此），在这里补上镜头移动
                  _flushPendingMove();
                  _renderLayers();
                },
                onStyleLoadedCallback: () {
                  _guard?.cancel();
                  // 样式重载后旧的 source/layer 全部消失，要重新加
                  _layersReady = false;
                  _meAdded = false;
                  _spotIconReady = false; // 图标也要重新 addImage
                  _styleReady = true;
                  _flushPendingMove();
                  _renderLayers();
                },
                // 相机停下后重算比例尺（拖动过程中不算，省性能）
                onCameraIdle: _updateScale,
                onMapClick: (point, latlng) => _onMapClick(point),
              )
            : Container(
                color: const Color(0xFFDDE6EC),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
      ),

      // 比例尺（在授权文字上方）
      Positioned(
        left: 10,
        bottom: 21,
        child: IgnorePointer(child: _buildScaleBar()),
      ),

      // 版权行（合规必须显示）
      Positioned(
        left: 10,
        bottom: 6,
        right: 90,
        child: IgnorePointer(
          child: Text(
            '${_tile.attribution} · 禁钓数据据政府公开通告整理',
            style: const TextStyle(fontSize: 9.5, color: Color(0x99000000)),
          ),
        ),
      ),

      // 右侧工具条
      Positioned(
        right: 12,
        top: widget.embedded ? 64 : MediaQuery.of(context).padding.top + 96,
        child: Column(children: [
          _roundBtn(
              _layers.satellite ? Icons.satellite_alt : Icons.map_outlined,
              _layers.satellite ? '卫星图' : '路网图', () {
            setState(() => _layers.satellite = !_layers.satellite);
            _applyLayerToggles();
          }),
          const SizedBox(height: 8),
          // 用增量缩放（zoomBy）而不是 zoomTo：
          // zoomTo 需要先读到当前 zoom，而读 zoom 依赖 trackCameraPosition，
          // 那条链路正是拖动卡顿的来源。zoomBy 由原生层自己算，零读取。
          _roundBtn(Icons.add, '放大', () async {
            await _map?.animateCamera(
                CameraUpdate.zoomBy(0.9),
                duration: const Duration(milliseconds: 220));
          }),
          const SizedBox(height: 8),
          _roundBtn(Icons.remove, '缩小', () async {
            await _map?.animateCamera(
                CameraUpdate.zoomBy(-0.9),
                duration: const Duration(milliseconds: 220));
          }),
          const SizedBox(height: 8),
          _roundBtn(Icons.my_location, '定位', () => _locate()),
          const SizedBox(height: 8),
          _roundBtn(Icons.layers_outlined, '图层', _openLayers),
        ]),
      ),
    ]);
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 21, color: AppTheme.textPrimary),
          ),
        ),
      ),
    );
  }

  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void up(void Function() fn) {
          setSheet(fn);
          setState(fn);
          _applyLayerToggles();
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('图层',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 4),
            _sw(Icons.satellite_alt, '卫星影像', '星图地球卫星底图', _layers.satellite,
                (v) => up(() => _layers.satellite = v)),
            _sw(Icons.route_outlined, '路网注记', '叠加道路与地名（开着更清楚，但瓦片翻倍，建议按需打开）',
                _layers.roadLabels, (v) => up(() => _layers.roadLabels = v)),
            _sw(Icons.water_drop_outlined, '河流', '蓝色水面带', _layers.rivers,
                (v) => up(() => _layers.rivers = v)),
            _sw(Icons.waves, '湖泊水库', '蓝色填充', _layers.lakes,
                (v) => up(() => _layers.lakes = v)),
            _sw(Icons.block_outlined, '禁渔区域', '红色为禁钓区 / 禁渔期',
                _layers.noFishingZones, (v) => up(() => _layers.noFishingZones = v)),
            _sw(Icons.location_on_outlined, '钓点标记', '钓友共享的钓点', _layers.spots,
                (v) => up(() => _layers.spots = v)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_tile.describe,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF8A9099))),
            ),
          ]),
        );
      }),
    );
  }

  Widget _sw(IconData icon, String title, String sub, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, size: 20, color: AppTheme.textSecondary),
      title: Text(title, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(sub,
          style:
              const TextStyle(fontSize: 11.5, color: Color(0xFF8A9099))),
      value: value,
      activeColor: AppTheme.accent,
      onChanged: onChanged,
    );
  }
}
