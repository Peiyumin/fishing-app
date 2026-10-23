import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Point;

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
      _guard = Timer(SpotMapGlScreen.readyTimeout, () {
        if (!mounted || _styleReady) return;
        // MapLibreMap 从树上摘掉后它内部的 controller 会被自己释放，
        // 这里必须置空，否则页面 dispose 时再 dispose 一次会抛异常。
        setState(() {
          _map = null;
          _fallback = true;
        });
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(silent: true));
  }

  @override
  void dispose() {
    _guard?.cancel();
    widget.controller?.unbind();
    _map?.dispose();
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
  List<List<double>> _ring(List<ll.LatLng> pts) {
    final out = <List<double>>[];
    for (final p in pts) {
      final q = _tile.project(p);
      out.add([q.longitude, q.latitude]);
    }
    if (out.isNotEmpty &&
        (out.first[0] != out.last[0] || out.first[1] != out.last[1])) {
      out.add(out.first);
    }
    return out;
  }

  Future<void> _renderLayers() async {
    final c = _map;
    if (c == null || !_styleReady || _layersReady || _rendering) return;
    _rendering = true;
    try {
      final lakes = <Map<String, dynamic>>[];
      final rivers = <Map<String, dynamic>>[];
      for (final w in _waters) {
        final coords = _ring(w.geometry);
        if (coords.length < 2) continue;
        if (w.isRiver) {
          rivers.add(_feature('LineString', coords, const {}));
        } else if (coords.length >= 4) {
          lakes.add(_feature('Polygon', [coords], const {}));
        }
      }

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

      final spots = <Map<String, dynamic>>[];
      for (final s in _spots) {
        final q = _tile.project(ll.LatLng(s.lat, s.lng));
        spots.add(_feature('Point', [q.longitude, q.latitude], {'id': s.id}));
      }

      await c.addGeoJsonSource('lakes', _fc(lakes));
      await c.addLayer(
          'lakes',
          'lakes-fill',
          FillLayerProperties(
              fillColor: '#1E88E5',
              fillOpacity: _layers.lakes ? 0.32 : 0.0),
          // 全国视角下几十个湖泊只是几个像素点，画了也看不见，
          // 却要占着原生层的绘制批次；6 级以下交给地图瓦片自带的蓝色水面。
          minzoom: 6);
      await c.addLayer(
          'lakes',
          'lakes-line',
          LineLayerProperties(
              lineColor: '#1565C0',
              lineWidth: 1.2,
              lineOpacity: _layers.lakes ? 0.85 : 0.0),
          minzoom: 6);

      await c.addGeoJsonSource('rivers', _fc(rivers));
      await c.addLayer(
          'rivers',
          'rivers-line',
          LineLayerProperties(
              lineColor: '#1E88E5',
              lineWidth: 4.5,
              lineOpacity: _layers.rivers ? 0.5 : 0.0),
          minzoom: 6);

      await c.addGeoJsonSource('zones', _fc(zones));
      await c.addLayer(
          'zones',
          'zones-fill',
          FillLayerProperties(
              fillColor: '#E5484D',
              fillOpacity: _layers.noFishingZones ? 0.14 : 0.0),
          minzoom: 5);
      await c.addLayer(
          'zones',
          'zones-line',
          LineLayerProperties(
              lineColor: '#E5484D',
              lineWidth: 1.4,
              lineDasharray: const [3, 2],
              lineOpacity: _layers.noFishingZones ? 0.85 : 0.0),
          minzoom: 5);

      await c.addGeoJsonSource('spots', _fc(spots));
      await c.addLayer(
          'spots',
          'spots-circle',
          CircleLayerProperties(
              circleColor: '#E5484D',
              circleRadius: 5.5,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2,
              circleOpacity: _layers.spots ? 1.0 : 0.0),
          minzoom: 4);

      _layersReady = true;
      await _drawMe();
    } catch (_) {
      // 图层加失败不影响底图
    } finally {
      _rendering = false;
    }
  }

  Future<void> _setVis(String layer, bool on) async {
    try {
      await _map?.setLayerVisibility(layer, on);
    } catch (_) {}
  }

  Future<void> _applyLayerToggles() async {
    if (!_layersReady) return;
    await _setVis('sat', _layers.satellite);
    await _setVis('vec', !_layers.satellite);
    // 矢量路网图本身自带地名，再叠注记等于白跑一倍瓦片却看不出差别；
    // 只有卫星模式才需要注记层。
    await _setVis('cia', _layers.roadLabels && _layers.satellite);
    await _setVis('lakes-fill', _layers.lakes);
    await _setVis('lakes-line', _layers.lakes);
    await _setVis('rivers-line', _layers.rivers);
    await _setVis('zones-fill', _layers.noFishingZones);
    await _setVis('zones-line', _layers.noFishingZones);
    await _setVis('spots-circle', _layers.spots);
  }

  // ---------------------------------------------------------------- 定位

  void _moveTo(double lat, double lng) {
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 13));
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

  /// 点地图：命中钓点圆圈就进详情
  ///
  /// GeoJSON 加进去的 circle 图层没有 onCircleTapped（那是 AnnotationManager
  /// 才有的回调），只能 queryRenderedFeatures 按屏幕坐标查。
  Future<void> _onMapClick(Point<double> point) async {
    final c = _map;
    if (c == null) return;
    try {
      final feats = await c.queryRenderedFeatures(point, ['spots-circle'], null);
      if (feats.isEmpty) return;
      final f = feats.first;
      final props = (f is Map) ? f['properties'] : null;
      final id = (props is Map) ? props['id'] : null;
      final s = id == null ? null : _spotById[id.toString()];
      if (s != null && mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: s)));
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- UI

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
                initialCameraPosition: const CameraPosition(
                  target: LatLng(34.5, 108.9),
                  zoom: 4,
                ),
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                trackCameraPosition: true,
                // 原生自带的「i」版权按钮放右下，左下留给自绘的长版权行，避免叠在一起
                attributionButtonPosition: AttributionButtonPosition.bottomRight,
                onMapCreated: (c) {
                  _map = c;
                  SpotMapGlScreen.debugOnControllerCreated?.call(c);
                  _renderLayers();
                },
                onStyleLoadedCallback: () {
                  _guard?.cancel();
                  // 样式重载后旧的 source/layer 全部消失，要重新加
                  _layersReady = false;
                  _meAdded = false;
                  _styleReady = true;
                  _renderLayers();
                },
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
          _roundBtn(Icons.add, '放大', () async {
            final z = _map?.cameraPosition?.zoom;
            if (z != null) {
              await _map?.animateCamera(CameraUpdate.zoomTo((z + 1).clamp(3, 18)));
            }
          }),
          const SizedBox(height: 8),
          _roundBtn(Icons.remove, '缩小', () async {
            final z = _map?.cameraPosition?.zoom;
            if (z != null) {
              await _map?.animateCamera(CameraUpdate.zoomTo((z - 1).clamp(3, 18)));
            }
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
