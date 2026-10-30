import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Point, pi, sin;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/no_fishing_zone.dart';
import '../models/water_body.dart';
import 'ai_radar_screen.dart';
import '../services/location_service.dart';
import '../services/map_config_service.dart';
import '../services/ai_spot_service.dart';
import '../services/ai_quota_service.dart';
import '../services/session_provider.dart';
import '../widgets/ai_quota_gate.dart';

import '../services/map_data_service.dart';
import '../services/map_tile_source.dart';
import '../services/api_config.dart';
import '../services/geo_bounds.dart';
import '../services/spot_service.dart';
import '../services/tile_health.dart';
import '../widgets/spot_pin.dart';
import 'spot_detail_screen.dart';
import 'spot_map_screen.dart' show SpotMapController, SpotMapScreen;

/// maplibre 的图层属性只吃 `'#RRGGBB'` 字符串，没法直接引用 [AppTheme] 的 Color，
/// 而这些属性又都写在 `const` 里 —— 所以只能落成字符串常量。
///
/// ★ 这里是**唯一**允许出现十六进制色值的地方，每个值都必须和 AppTheme 的
///   token 一字不差（`test/theme_palette_test.dart` 会逐条比对）。
///   以前地图图层自己一套蓝（#4FAEE8/#3FA9F5/#2E8FD0/#0B4FA8 四种），
///   禁钓区又是 #E53935/#C62828 两个自造红，AI 点是橙色 #FF8A00 ——
///   和 App 其它页面的数据蓝/警示红/荧光黄绿全都差一档，
///   同一屏里"地图上的蓝"和"App 的蓝"是两个蓝。
class _Hex {
  static const background = '#EDF1F6'; // = AppTheme.background
  static const water = '#46A0FB'; // = AppTheme.water
  static const waterDeep = '#1E5FA8'; // = AppTheme.waterDeep
  static const danger = '#F44336'; // = AppTheme.danger
  static const dangerDark = '#C62828'; // = AppTheme.dangerDark
  static const accent = '#C6FF3D'; // = AppTheme.accent
  static const white = '#FFFFFF';
}

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

  /// 原生内核就绪的超时时长（生产 15 秒；集成测试会放宽，模拟器起得慢）
  ///
  /// ★ 原来是 8 秒，实战里太紧：安卓中低端机首次创建 PlatformView
  ///   （Activity 挂载 + GL 上下文 + 样式解析 + 首帧纹理上传）经常超过 8 秒，
  ///   一超时就被判定为「内核起不来」而降级到 flutter_map 内核 ——
  ///   那正是用户截到的「地图一加载出来，按钮位置全变了」，而且降级后的
  ///   Dart 版内核逐瓦片解码贴图，拖动更卡。宁可按着白屏多等几秒，
  ///   也不要中途换一套 UI（两套内核的浮层现已对齐，但内核性能差一个量级）。
  static Duration readyTimeout = const Duration(seconds: 15);

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

  // ------------------------------------------------------------ AI 推荐钓点
  //
  // 按钮在地图底部中间，点一下按当下的温度/气压/水氧 + 水体类型
  // 算出一批值得去的位置，按「离我由近到远」排序，同时标到地图上。
  List<AiSpot> _aiSpots = const [];
  bool _aiBusy = false;

  /// AI 按钮副标题里的次数提示（v2.1.56）：「剩 2 次 / 已用完 / 会员」
  ///
  /// 免费 3 次是硬规则，直接写在按钮上看得到，比点下去才弹窗友好。
  String _aiQuotaText = '';
  bool _aiDataAdded = false;

  /// 要素顶层 id → 钓点 id
  ///
  /// ★ iOS / Android 原生「点中要素」时只回传 feature.identifier，
  ///   **不回传 properties**；而 MapLibre 的 identifier 只认 GeoJSON 顶层的
  ///   `id` 字段。所以给每个钓点要素编个号写进顶层 id，再靠这张表还原成
  ///   真正的钓点 id —— 比拿坐标反查最近点更准（密集钓点区不会选错）。
  Map<int, String> _spotNumToId = const {};

  /// 要素顶层 id → AI 推荐结果下标
  Map<int, int> _aiNumToIdx = const {};

  /// 业务图层（河湖/禁钓/钓点）是否已经加过一轮
  bool _layersReady = false;
  bool _rendering = false;

  /// 建图层期间数据又更新过 —— 建完要再刷一次 source
  bool _sourcesDirty = false;

  /// 图层添加失败的重试次数（原生层刚 ready 时偶尔会抛「style 未就绪」）
  int _renderAttempt = 0;

  /// 原生内核起不来 → 自动降级 flutter_map
  bool _fallback = false;

  /// 底图降级/异常提示（空串 = 不显示）
  String _mapNote = '';
  Timer? _guard;

  @override
  void initState() {
    super.initState();
    widget.controller?.bind(_moveTo);
    _loadData();
    _loadQuotaText();
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
        // 自检结论（首选底图在这条网络上不通时会给一句说明）
        _mapNote = MapConfigService.healthNote;
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

  /// 把一批钓点并进现有集合，然后只更新 GeoJSON source
  ///
  /// 用 `setGeoJsonSource` 而不是重建图层：重建会让整层闪一下，
  /// 而且 addLayer 在同名图层已存在时会直接抛异常。
  ///
  /// ★ v2.1.21：去掉了「没有新钓点就直接 return」这条短路。
  ///   它原本是为了省一次无意义的 source 重写，实际副作用是 —— 后台改了
  ///   钓点名称 / 位置，或者钓点数变少（被后台下架），宿主页点「刷新」
  ///   拿到的数据根本进不了地图，看着就是刷新没生效。现在只要数据有变化
  ///   就整体重写 source；完全没变化时也只是多写一次，代价可忽略。
  Future<void> _mergeSpots(List<FishingSpot> incoming) async {
    if (!mounted) return;
    final map = <String, FishingSpot>{for (final s in _spots) s.id: s};
    if (incoming.isEmpty) {
      // 后端确实返回了空列表（比如全部被下架）：地图也该跟着清空，
      // 否则会一直显示上一次的快照、点了还进详情。
      if (map.isEmpty) return;
      setState(() {
        _spots = const [];
        _spotById = const {};
      });
      await _updateSpotsSource();
      return;
    }
    for (final s in incoming) {
      if (s.lat == 0 && s.lng == 0) continue;
      map[s.id] = s; // 覆盖成最新数据（名称 / 坐标 / 简介可能在后台改过）
    }
    if (map.isEmpty) return;
    setState(() {
      _spots = map.values.toList();
      _spotById = map;
    });
    // 数据没变也照样重写一次：刷新按钮要让用户看到"确实重新画了一遍"
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
    // 摘掉要素点击回调，避免 controller 生命周期比页面长时回调打到已销毁的 State
    _map?.onFeatureTapped.remove(_onFeatureTap);
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
    // ① 水域 / 禁钓区：本地资源 + 一次轻量接口，先到位先上图
    try {
      final r = await Future.wait([
        MapDataService.waters(),
        MapDataService.zones(),
      ]);
      if (!mounted) return;
      setState(() {
        _waters = r[0] as List<WaterBody>;
        _zones = r[1] as NoFishingData;
      });
      await _refreshSources();
    } catch (_) {
      // 数据拉不到不影响底图
    }

    // ② 钓点：网络请求可能慢，单独来，回来再补一次 source 刷新
    //
    // ★ 旧写法把三份数据塞进同一个 Future.wait，**必须等最慢的钓点接口**
    //   才会一起 setState —— 网络慢的时候河湖/禁钓区跟着一起空白，
    //   用户看到的就是「图层全开但地图上什么都没有」。
    try {
      final spots = await SpotService.fetchSpots();
      if (!mounted) return;
      final map = <String, FishingSpot>{
        for (final s in spots)
          if (s.lat != 0 || s.lng != 0) s.id: s,
      };
      for (final s in widget.extraSpots) {
        if (s.lat != 0 || s.lng != 0) map[s.id] = s;
      }
      setState(() {
        _spots = map.values.toList();
        _spotById = map;
      });
      await _refreshSources();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 样式

  /// 把瓦片 URL 改写成「后端代理」地址
  ///
  /// 老安卓（5.x）系统证书库缺现代根证书，原生 MapLibre 直连 HTTPS 瓦片源
  /// 会 CERTIFICATE_VERIFY_FAILED → 整层空白。改走后端 HTTP 代理中转
  /// （服务端现代 TLS 抓取后纯 HTTP 回传），双端取图链路一致、安卓也能出图。
  ///
  /// 关键点：内层 URL 的 {z}/{x}/{y} 占位符必须保留不编码，留给 MapLibre 替换；
  /// 其余部分（协议/主机/路径前缀、query 串）整体编码进代理参数。
  String _proxyWrap(String url) {
    final base = ApiConfig.tileProxyBase; // …/api/index.php?r=/tile-proxy&url=
    final open = url.indexOf('{');
    if (open < 0) return '$base${Uri.encodeComponent(url)}';
    final close = url.lastIndexOf('}');
    final head = url.substring(0, open);
    final mid = url.substring(open, close + 1); // {z}/{x}/{y}
    final tail = url.substring(close + 1); // ?format=…&token=…（需编码）
    return '$base${Uri.encodeComponent(head)}$mid${Uri.encodeComponent(tail)}';
  }

  /// 把模板里的占位符替换成真实地址
  ///
  /// MapLibre 的 raster source **不支持 {s} 子域占位符**，
  /// 必须展开成 tiles1/2/3 三条 URL 交给原生层轮询。
  ///
  /// 每条直连地址都额外在前面放一条「后端代理」地址：优先走代理（修老安卓 +
  /// 双端一致），代理不可用时回退直连（iOS / 现代安卓更快）。
  List<String> _urls(String tpl) {
    var s = tpl;
    _tile.additionalOptions.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    List<String> direct;
    if (!s.contains('{s}')) {
      direct = [s];
    } else {
      direct = ['1', '2', '3'].map((i) => s.replaceAll('{s}', i)).toList();
    }
    final proxied = direct.map(_proxyWrap).toList();
    return [...proxied, ...direct];
  }

  // ------------------------------------------------------------ 高清范围

  /// 高清瓦片覆盖半径（公里）
  ///
  /// 用户要的加载策略：首屏先把定位点周围 50km 的高清影像准备好，
  /// 更远处只留低清概览（省流量、首屏也更快）；在这 50km 内拖动或放大，
  /// 瓦片会按视口自动加载对应级别的高清图。
  static const double hdRadiusKm = 50;

  /// 当前高清范围 [w, s, e, n]
  ///
  /// null = 还没拿到定位点，此时不给高清层加 bounds（全图都按高清走）。
  /// 宁可不省流量，也不要让用户在「不限制范围就糊」和「限制了范围结果
  /// 自己站在圈外一片糊」之间二选一。
  List<double>? _hdBounds;

  /// 记下定位点，供 [_buildStyle] 算高清圈
  ///
  /// 只在样式生成之前调用才有意义：MapLibre 的 raster source 的 `bounds`
  /// 不能原地修改，换范围只能重建样式，而 0.22.0 的控制器没有 setStyle。
  void _setHdCenter(double lat, double lng) {
    if (lat == 0 && lng == 0) return;
    _hdBounds = boundsAroundKm(lat, lng, hdRadiusKm);
  }

  String _buildStyle() {
    final hd = _hdBounds;
    return jsonEncode(<String, dynamic>{
      'version': 8,
      'sources': {
        // ---------------- 低清概览层：全球铺底 ----------------
        // 最高只到 z8。z9 以上它靠「放大 z8 瓦片」呈现 ——
        // 这正好就是用户要的「定位点 50km 之外模糊显示」，
        // 而且每屏只多 1~4 块瓦片（一块 z8 抵 256 块 z16），开销可以忽略。
        // ★ 为什么定 z8 而不是 z12：低清层如果太清晰，缩小到 100km 视野时
        //   圈内圈外一样清楚，用户根本看不出「50 公里边界」在哪，
        //   分级加载就成了看不见的摆设。
        'sat-low': {
          'type': 'raster',
          'tiles': _urls(_tile.satelliteTemplate),
          'tileSize': 256,
          'maxzoom': 8,
          'attribution': _tile.attribution,
        },
        // ---------------- 高清层：只在定位点周围 50km ----------------
        // ★ bounds 是这里的关键：MapLibre 文档明确写了
        //   「设了 bounds 之后，范围外的瓦片一律不请求」。
        //   所以高清瓦片只会在那 50km 里被拉下来，范围外由上面的低清层顶住。
        // ★ maxzoom 必须等于瓦片源真实最大级别（星图 18）。
        //   之前相机允许缩放到 22 级，超过 18 后 MapLibre 不再请求新瓦片，
        //   只是把 18 级瓦片放大 16 倍 —— 用户看到的就是「放大后不加载、
        //   一片模糊」。现在相机上限也一起压到 18（见 minMaxZoomPreference）。
        'sat': {
          'type': 'raster',
          'tiles': _urls(_tile.satelliteTemplate),
          'tileSize': 256,
          // z9 起接管（z9 的视野正好约 100km，能一眼看到 50km 那个圈）
          'minzoom': 9,
          'maxzoom': _tile.maxNativeZoom,
          if (hd != null) 'bounds': hd,
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
          'paint': {'background-color': _Hex.background},
        },
        // raster-fade-duration: 0 —— 关掉瓦片淡入动画。
        // 默认 300ms 的淡入会让原生层在瓦片刚到时反复重绘，
        // 快速拖动时叠加上一层重绘，是掉帧的隐形大头。
        {
          'id': 'sat-low',
          'type': 'raster',
          'source': 'sat-low',
          'paint': {'raster-fade-duration': 0},
        },
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
    final idx = <int, String>{};
    var n = 0;
    for (final s in _spots) {
      final q = _tile.project(ll.LatLng(s.lat, s.lng));
      n++;
      idx[n] = s.id;
      feats.add({
        'type': 'Feature',
        // ★ 顶层 id 会成为 MapLibre 的 feature.identifier —— 点击命中时
        //   原生层只把这个值送回 Dart，没有它就取不到是哪条钓点。
        'id': n,
        'properties': {'id': s.id},
        'geometry': {
          'type': 'Point',
          'coordinates': [q.longitude, q.latitude]
        },
      });
    }
    _spotNumToId = idx;
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
  ///
  /// [sourceLayer] / [filter] 是给矢量瓦片（在线河网）用的：
  /// 同一个 source 里有很多图层（water / waterway / building…），
  /// 必须指明要哪一层，再用 filter 排除海洋等不需要的要素。
  Future<void> _safeLayer(
      String source, String layer, LayerProperties props,
      {double? minzoom,
      double? maxzoom,
      String? sourceLayer,
      dynamic filter}) async {
    final c = _map;
    if (c == null) return;
    try {
      await c.addLayer(source, layer, props,
          minzoom: minzoom,
          maxzoom: maxzoom,
          sourceLayer: sourceLayer,
          filter: filter);
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
    // 在线河网（OSM 矢量瓦片）：覆盖所有有名字的河流、水体面
    // ★ 河道只保留「一层浅蓝」：深蓝描边 hydro-river-casing 已删除，
    //   原来 casing(深蓝宽) + line(浅蓝细) 叠在一起，看起来像两条河。
    // ★ v2.1.22：中心线拆成两层 ——
    //   hydro-river-major 只有 z6~10（低缩放撑走向），
    //   hydro-river-line 只画溪流/沟渠且是细线。
    //   原来单层在 z17 画 30px 实心线，就是用户说的「那根很粗的蓝色」。
    'hydro-water',
    'hydro-water-line',
    'hydro-river-major',
    'hydro-river-line',
    'hydro-lake-icon',
    'hydro-pond-icon',
    // 本地精选数据（兜底：离线 / 瓦片失败时仍能看到大江大河）
    // ★ 本地河流只有 rivers-line 一层：深蓝更宽的 rivers-casing 已删除
    //   （两层叠在一起会被看成"河道画了两条"，v2.1.21）
    'lakes-fill',
    'lakes-line',
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

  /// 河流要素集合
  List<Map<String, dynamic>> _riverFeatures() {
    final feats = <Map<String, dynamic>>[];
    for (final w in _waters) {
      if (!w.isRiver) continue;
      // ★ 河流是折线，不能闭合（见 _ring 注释）
      final coords = _ring(w.geometry, close: false);
      if (coords.length < 2) continue;
      feats.add(_feature('LineString', coords, {'n': w.name}));
    }
    return feats;
  }

  /// 湖泊 / 水库要素集合
  List<Map<String, dynamic>> _lakeFeatures() {
    final feats = <Map<String, dynamic>>[];
    for (final w in _waters) {
      if (w.isRiver) continue;
      final coords = _ring(w.geometry);
      if (coords.length < 4) continue;
      feats.add(_feature('Polygon', [coords], {'n': w.name}));
    }
    return feats;
  }

  /// 禁钓区要素集合
  List<Map<String, dynamic>> _zoneFeatures() {
    final feats = <Map<String, dynamic>>[];
    for (final z in _zones.zones) {
      if (!z.onMap || z.rings.isEmpty) continue;
      final coords = _ring(z.rings.first);
      if (coords.length < 4) continue;
      feats.add(_feature('Polygon', [coords], {
        'active': z.statusNow().active,
        'name': z.name,
      }));
    }
    return feats;
  }

  /// 数据到位后把四个 GeoJSON source 全量刷新一遍
  ///
  /// ★★ 这条修的是「图层开关只有前两个有用、河湖/禁钓区/钓点全都不显示」的真正原因：
  ///   建图和数据加载是两路并行的 ——
  ///     · 样式文件（本地磁盘）→ 地图创建 → onStyleLoaded → `_renderLayers()`
  ///     · waters.json / 禁钓区（网络）/ 钓点（网络）→ `_loadData()`
  ///   样式是本地文件，通常比网络快，于是 `_renderLayers()` 会**先**跑，
  ///   此时 `_waters` / `_zones` / `_spots` 还是空的 →
  ///   四个 source 全建成空 FeatureCollection → 图上什么也没有；
  ///   而 `_layersReady` 已被置 true，`_loadData` 事后再调 `_renderLayers()`
  ///   会被「已就绪」直接挡回去，**图层永远是空的**。
  ///   表现完全就是用户看到的：开关全开、地图上干干净净。
  Future<void> _refreshSources() async {
    final c = _map;
    if (c == null || !_styleReady) return;
    if (!_layersReady) {
      // 图层还没建好：记一笔「数据已更新」，等建好那一刻再补一次
      _sourcesDirty = true;
      await _renderLayers();
      return;
    }
    try {
      await c.setGeoJsonSource('lakes', _fc(_lakeFeatures()));
      await c.setGeoJsonSource('rivers', _fc(_riverFeatures()));
      await c.setGeoJsonSource('zones', _fc(_zoneFeatures()));
      await c.setGeoJsonSource('spots', _fc(_spotFeatures()));
      debugPrint('[SpotMapGL] source 刷新：河=${_waters.where((w) => w.isRiver).length} '
          '湖=${_waters.where((w) => !w.isRiver).length} '
          '禁钓=${_zones.zones.length} 钓点=${_spots.length}');
    } catch (_) {}
  }

  Future<void> _renderLayers() async {
    final c = _map;
    if (c == null || !_styleReady || _layersReady || _rendering) return;
    _rendering = true;
    try {
      // ---------------- 钓点图标 ----------------
      // 红色定位针 + 白色鱼形，运行时用 Canvas 画成 PNG 交给原生层当 icon
      await _ensureSpotIcon();

      // ---------------- 在线河网：所有有名字的河 ----------------
      // ★ 为什么要有这一层：
      //   本地 waters.json 只有 43 条大江 + 44 个湖（长江、黄河这个量级），
      //   城市里的市河、支流（胥江、上塘河、外城河、吴淞江…）根本不在里面。
      //   用户打开钓点地图看到的就是「开关全开了，可地图上只有一条大江」。
      //   OSM 的矢量瓦片里，苏州一个 z13 瓦片就有 19 条**有名字**的河
      //   和 245 个水体面 —— 这才是「不管大小河都有蓝色」。
      //   只取 water（水体面）和 waterway（河流中心线）两个图层，
      //   其他图层（building/road/poi）一个都不渲染，性能可控。
      // ★ 先不等结果地把 TileJSON 拉起来：画图标那点时间足够它回来，
      //   等 _safeVecSource 真正需要时基本是命中缓存，不会干等网络。
      unawaited(_resolveHydroTiles());
      await _ensureWaterIcon();
      await _safeVecSource();
      // 水体面：河 / 湖 / 水库 / 池塘，都是真实水面宽度
      // ★ 统一浅蓝：原来 river/lake 用 #2E8FD0 深蓝，配上深蓝描边后
      //   和浅蓝中心线叠成「深浅两层」——用户要的是一条浅蓝色的河。
      await _safeLayer(
        'hydro',
        'hydro-water',
        const FillLayerProperties(
          fillColor: _Hex.water,
          fillOpacity: 0.5,
        ),
        sourceLayer: 'water',
        minzoom: 4,
        // 海洋不画（不然沿海会整片变蓝，把海图盖掉）
        filter: [
          '!=',
          ['get', 'class'],
          'ocean'
        ],
      );
      await _safeLayer(
        'hydro',
        'hydro-water-line',
        const LineLayerProperties(
          lineColor: _Hex.water,
          lineWidth: 0.8,
          lineOpacity: 0.6,
        ),
        sourceLayer: 'water',
        minzoom: 6,
        filter: [
          '!=',
          ['get', 'class'],
          'ocean'
        ],
      );
      // ---------------- 河流中心线（按 class 拆两层）----------------
      // ★★ 用户截图里那根「很粗的蓝色」就是这里来的（v2.1.22 修）：
      //   原来只有一层，z14 画 16px、z17 画 30px —— 本意是给**没有水面多边形**
      //   的窄河补一条线。但 OSM 里 river / canal 在 z11 以上基本都有水面多边形，
      //   水面已经被 hydro-water 填成浅蓝（opacity 0.5），再在上面盖一条 30px、
      //   不透明度 0.8 的实心线，观感就是「浅蓝水面下压着一根粗蓝条」，
      //   而且把整条河劈成了深浅两半。
      //   现在按 class 拆开：
      //     ① hydro-river-major：河 / 运河 —— 只在 z6~10 画。
      //        低缩放时水面面积极小、只是一小块色斑，必须靠线撑出河道走向；
      //        z11 起水面多边形已经能表达真实宽度，粗线彻底退场。
      //     ② hydro-river-line：溪流 / 沟渠 / 排水沟 —— 它们在 OSM 里通常
      //        没有水面多边形，只能靠线画出来，所以任何缩放都保留，但只给细线。
      await _safeLayer(
        'hydro',
        'hydro-river-major',
        const LineLayerProperties(
          lineColor: _Hex.water,
          lineWidth: [
            'interpolate',
            ['linear'],
            ['zoom'],
            6,
            ['match', ['get', 'class'], 'river', 1.6, 1.2],
            10,
            ['match', ['get', 'class'], 'river', 3.2, 2.4],
          ],
          lineOpacity: 0.85,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        sourceLayer: 'waterway',
        minzoom: 6,
        // ★ 关键就是这一行：z11 起不再画粗线，河道只由浅蓝水面表达
        maxzoom: 11,
        // 隧道段不画（会在地面拉出一条莫名其妙的蓝线）
        filter: [
          'all',
          [
            '!=',
            ['get', 'brunnel'],
            'tunnel'
          ],
          [
            'any',
            [
              '==',
              ['get', 'class'],
              'river'
            ],
            [
              '==',
              ['get', 'class'],
              'canal'
            ],
          ],
        ],
      );
      await _safeLayer(
        'hydro',
        'hydro-river-line',
        LineLayerProperties(
          lineColor: _Hex.water,
          lineWidth: _zNum([6, 0.55, 10, 0.75, 14, 1.2, 17, 1.8]),
          lineOpacity: 0.85,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        sourceLayer: 'waterway',
        minzoom: 6,
        filter: [
          'all',
          [
            '!=',
            ['get', 'brunnel'],
            'tunnel'
          ],
          [
            'any',
            [
              '==',
              ['get', 'class'],
              'stream'
            ],
            [
              '==',
              ['get', 'class'],
              'ditch'
            ],
            [
              '==',
              ['get', 'class'],
              'drain'
            ],
          ],
        ],
      );
      // 湖泊 / 水库的图标标记（用户明确要求「水库池塘要有图标」）
      // ★ 为什么用 water_name 而不是 water：
      //   大湖（阳澄湖）在 OSM 里被切成十几块多边形，按多边形打图标会在一
      //   个湖上打出十几个图标，实测截图就是一片糊。water_name 里每个湖
      //   只有一个 Point 锚点，天然「一湖一图标」。
      // ★ 为什么关掉 allow-overlap：
      //   一个湖跨两个瓦片会有两个同坐标锚点，允许重叠就会叠成一双；
      //   关掉之后由碰撞检测自动去重，只会留一个。
      await _safeLayer(
        'hydro',
        'hydro-lake-icon',
        SymbolLayerProperties(
          iconImage: 'water-icon',
          iconSize: _zNum([
            11, 0.38 * _iconUnit,
            14, 0.44 * _iconUnit,
            17, 0.52 * _iconUnit,
          ]),
          iconAllowOverlap: false,
          iconIgnorePlacement: false,
          iconPadding: 6,
        ),
        sourceLayer: 'water_name',
        minzoom: 11,
        filter: [
          '==',
          ['geometry-type'],
          'Point'
        ],
      );
      // 池塘 / 鱼塘：OSM 里绝大多数没有名字，只能按水面多边形打图标；
      // 15 级起才标 —— 再低苏州城外的鱼塘会把整屏铺满图标。
      await _safeLayer(
        'hydro',
        'hydro-pond-icon',
        SymbolLayerProperties(
          iconImage: 'water-icon',
          iconSize: _zNum([
            15, 0.32 * _iconUnit,
            17, 0.44 * _iconUnit,
          ]),
          iconAllowOverlap: false,
          iconIgnorePlacement: false,
        ),
        sourceLayer: 'water',
        minzoom: 15,
        filter: ['==', ['get', 'class'], 'pond'],
      );

      // ---------------- 湖泊：蓝色水面 ----------------
      await _safeSource('lakes', _fc(_lakeFeatures()));
      await _safeLayer(
          'lakes',
          'lakes-fill',
          const FillLayerProperties(
              fillColor: _Hex.water,
              // ★ 不再把传 opacity 设成 0 —— 见 _applyLayerToggles 注释
              fillOpacity: 0.45),
          minzoom: 3);
      await _safeLayer(
          'lakes',
          'lakes-line',
          const LineLayerProperties(
              lineColor: _Hex.waterDeep, lineWidth: 1.6, lineOpacity: 0.9),
          minzoom: 3);

      // ---------------- 河流：单层浅蓝水面带 ----------------
      // ★★ 为什么只留一层（v2.1.21）：
      //   原来是「深蓝描边在下(rivers-casing, #0B4FA8, 更宽) +
      //   亮蓝芯在上(rivers-line, #2E8FD0, 稍窄)」两层叠出来的水面带。
      //   设计意图是"有边界的水面"，但在真机上看到的效果就是**河道画了两条**：
      //   深色那条更宽、从浅色两边露出来，像两条平行的河。再叠上在线河网
      //   (hydro-*) 之后更明显。用户明确要求"只留浅蓝色那一层"。
      //   现在：只画一层，色值与在线河网统一成 #3FA9F5，宽度沿用原外层那档
      //   （直接删掉外层而留着细芯，河道会细成一根头发，等于把图层弄没了）。
      await _safeSource('rivers', _fc(_riverFeatures()));
      await _safeLayer(
          'rivers',
          'rivers-line',
          LineLayerProperties(
            lineColor: _Hex.water,
            // ★ v2.1.22：宽度档整体收窄（原来 z12=16px / z15=30px，
            //   是一根很粗的实心蓝带，和在线那层是同一个观感问题）。
            //   本地这张表只是「离线兜底」，没有水面填充可依靠，
            //   所以保留线，但让它看起来像河，而不是像一根色块。
            lineWidth: _zNum([3, 1.4, 6, 2.4, 9, 3.8, 12, 5.4, 15, 7.5]),
            lineOpacity: 0.85,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          minzoom: 3);

      // ---------------- 禁钓区：红色 ----------------
      await _safeSource('zones', _fc(_zoneFeatures()));
      await _safeLayer(
          'zones',
          'zones-fill',
          const FillLayerProperties(
            fillColor: _Hex.danger,
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
            lineColor: _Hex.dangerDark,
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

      // ---------------- AI 推荐钓点（点按钮后才有数据） ----------------
      // 空数据先建好图层：点「AI 找钓点」时只 setGeoJsonSource，
      // 不用现场 addLayer（那种时机最容易失败）
      await _safeSource('ai-spots', _fc(const []));
      await _safeLayer(
        'ai-spots',
        'ai-spot-halo',
        CircleLayerProperties(
          circleColor: _Hex.accent,
          circleRadius: _zNum([8, 15, 14, 20]),
          circleOpacity: 0.25,
          circleBlur: 1.2,
        ),
        minzoom: 0,
      );
      await _safeLayer(
        'ai-spots',
        'ai-spot-circle',
        CircleLayerProperties(
          circleColor: _Hex.accent,
          circleRadius: _zNum([8, 10, 14, 13]),
          circleStrokeColor: _Hex.white,
          circleStrokeWidth: 2.4,
        ),
        minzoom: 0,
      );
      // ★★ v2.1.36：这里原来有一个 ai-spot-label 文字层（textField: ['get','n']，
      //   想把 AI 钓点序号画在地图上）。**已删除**，原因：
      //   MapLibre 渲染任何 `text-field` 都必须从样式里的 `glyphs`
      //   （`{fontstack}/{range}.pbf`）拉字形。本项目的样式是纯栅格瓦片
      //   （星图地球影像 + 注记），`sources` 里没有也不该有 glyphs 服务 ——
      //   于是这一层拿不到任何字形，只能画 last-resort 的 `.notdef`，
      //   也就是用户看到的**小方块**。数字也一样，和中文无关。
      //
      //   序号信息并没有丢：钓点列表按同一顺序排列，点圆点会高亮对应项，
      //   序号只是「地图上的第几个」，不值得为它引一个字体服务。
      //   要恢复「圆点里带数字」的话，正确做法是用 Flutter Canvas 画成 PNG
      //   再 `addImage`（同 spot-pin / water-icon），绝不能再用 text-field。

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
      // 建层过程中数据又到过一批 → 立刻用最新数据覆盖一次
      if (_sourcesDirty) {
        _sourcesDirty = false;
        await _refreshSources();
      }
      await _drawMe();
      _updateScale();
      // 图层一建好就安排一次探测，不等 camera idle ——
      // 有些场景（测试、冷启动后镜头本来就没动）根本不会触发 idle 事件。
      // ★ 延后 1 秒：style 才刚 ready，立刻 querySourceFeatures 在 iOS 上
      //   可能长时间不返回，把启动拖住。
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _probeHydro();
      });
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

  // ------------------------------------------------------------ 水库 / 池塘图标

  bool _waterIconReady = false;

  Future<void> _ensureWaterIcon() async {
    final c = _map;
    if (c == null || _waterIconReady) return;
    final bytes = await _buildWaterIcon();
    if (bytes == null) return;
    try {
      await c.addImage('water-icon', bytes);
    } catch (_) {
      // 同名已存在
    }
    _waterIconReady = true;
  }

  /// 蓝色圆底 + 白色双水波：一眼看出是「水体」而不是钓点
  Future<Uint8List?> _buildWaterIcon() async {
    const double s = 64;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, s, s));
    // 白色外圈：卫星影像背景很花，没有白边会糊成一团
    canvas.drawCircle(const Offset(32, 32), 29, Paint()..color = Colors.white);
    canvas.drawCircle(
        const Offset(32, 32), 25.5, Paint()..color = AppTheme.water);
    final wave = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    for (final dy in const [-6.5, 6.0]) {
      final p = Path()..moveTo(15, 32 + dy);
      for (double x = 15; x <= 49; x += 1.5) {
        p.lineTo(x, 32 + dy + 3.6 * sin((x - 15) / 34 * 2 * pi));
      }
      canvas.drawPath(p, wave);
    }
    final img = await rec.endRecording().toImage(s.round(), s.round());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd?.buffer.asUint8List();
  }

  // ------------------------------------------------------------ 在线河网源

  /// 在线河网矢量瓦片（OpenFreeMap / OpenMapTiles，全球免费、无需 key）
  ///
  /// ★ 不写死 `.../planet/20261018_080001_pt/{z}/{x}/{y}.pbf`：
  ///   他们的构建版本号每天变，写死的话过几天整层就空了。
  /// ★ 也不靠原生层去拉 TileJSON（`VectorSourceProperties(url:)`）：
  ///   iOS 集成测试实测——图层全建出来了，可 querySourceFeatures 等了 90 秒
  ///   一条要素都没有，而同一台机器上的 Dart HTTP 是通的。原生层拉 TileJSON
  ///   失败是**静默**的，日志里什么都看不到，排查全靠猜。
  ///   改成：Dart 先拉 TileJSON，拿到当前版本的 tiles 模板，再显式交给原生层。
  ///   拉失败就打印原因，本地数据兜底，行为可观测。
  static const String _hydroTileJson = 'https://tiles.openfreemap.org/planet';

  /// 已解析的瓦片模板（{z}/{x}/{y}.pbf），一次会话只拉一次
  ///
  /// 缓存的是 Future 而不是结果：并发调用（预热 + 建源）只会真的发一次请求。
  static Future<List<String>?>? _hydroTilesFuture;

  /// 在线河网是否真的可用（有瓦片数据落进来）
  ///
  /// 用它决定「用 OSM 的数据」还是「退回本地那 43 条大江」：
  /// 离线或瓦片被墙时本地数据仍然能兜住，不至于整层空白。
  bool _hydroReady = false;
  int _hydroProbe = 0;

  /// 探针是否正在跑
  ///
  /// ★ 必须有：`_renderLayers` 失败会退避重试，每次成功都会发起探测；
  ///   camera idle 也会发起。没有这个标记就会同时开好几条 channel 调用链，
  ///   把原生主线程堵住 —— iOS 上表现为 App 起来后连不上 VM service，
  ///   `flutter test` 直接卡在 loading 十几分钟没有任何输出。
  bool _hydroProbing = false;

  Future<void> _safeVecSource() async {
    final c = _map;
    if (c == null) return;
    final tiles = await _resolveHydroTiles();
    if (tiles == null) {
      // 拉不到 TileJSON：不建源，_hydroReady 保持 false → 本地数据继续顶着
      return;
    }
    try {
      await c.addSource(
        'hydro',
        VectorSourceProperties(
          tiles: tiles,
          minzoom: 0,
          maxzoom: 14,
          attribution: '水系数据 © OpenStreetMap 贡献者',
        ),
      );
    } catch (_) {
      // 已存在：重试时会走到这里，忽略
    }
  }

  /// 拉 TileJSON，取出 `tiles` 里的瓦片模板
  ///
  /// 返回 null 表示拉不到（离线 / 域名不通 / 返回体不对），调用方走本地兜底。
  Future<List<String>?> _resolveHydroTiles() {
    return _hydroTilesFuture ??= _fetchHydroTiles();
  }

  Future<List<String>?> _fetchHydroTiles() async {
    try {
      final resp = await http
          .get(Uri.parse(_hydroTileJson))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        debugPrint('[MAP] hydro tilejson HTTP ${resp.statusCode}');
        return null;
      }
      final j = jsonDecode(resp.body);
      if (j is! Map) {
        debugPrint('[MAP] hydro tilejson 不是对象');
        return null;
      }
      final raw = (j['tiles'] as List?) ?? const [];
      final tiles = raw
          .map((e) => e.toString())
          .where((e) => e.contains('{z}') && e.contains('{x}'))
          .map((e) => _proxyWrap(e)) // 在线河网也走代理（原生层直连 GTS R4 会失败）
          .toList();
      if (tiles.isEmpty) {
        debugPrint('[MAP] hydro tilejson 里没有 {z}/{x}/{y} 模板');
        return null;
      }
      debugPrint('[MAP] hydro tiles = ${tiles.first}');
      return tiles;
    } catch (e) {
      debugPrint('[MAP] hydro tilejson 失败: $e');
      return null;
    }
  }

  /// 探针：问原生层「hydro 源里到底有没有要素」
  ///
  /// 有 → 说明瓦片加载成功，可以关掉本地那套简化数据（否则长江会被
  ///      本地宽带和 OSM 真实水面画两遍，看起来有重影）
  /// 没有 → 1.2 秒后重试，最多 20 次，全程不打扰用户
  ///
  /// ★ 防重入 + 查询超时：`querySourceFeatures` 是跨 channel 调用，
  ///   style 还没真正 ready 时在 iOS 上会长时间不返回。同时开多条链
  ///   会把原生主线程堵死，所以这里既串行化，也给每次查询加 4 秒上限 ——
  ///   宁可这一轮探不到，也不能拖住 App 启动。
  Future<void> _probeHydro() async {
    if (_hydroReady) return;
    if (_hydroProbing) return;
    final c = _map;
    if (c == null) return;
    // 高德底图是加偏坐标，在线图层本来就不开，不用探
    if (_tile.isGcj02) return;
    _hydroProbing = true;
    try {
      // waterway 是河流中心线；某些视野只有湖没有河，补问 water
      final ways = await c
          .querySourceFeatures('hydro', 'waterway', null)
          .timeout(const Duration(seconds: 4), onTimeout: () => const []);
      if (ways.isNotEmpty) {
        _markHydroReady();
        return;
      }
      final water = await c
          .querySourceFeatures('hydro', 'water', null)
          .timeout(const Duration(seconds: 4), onTimeout: () => const []);
      if (water.isNotEmpty) {
        _markHydroReady();
        return;
      }
    } catch (_) {
      // 原生层还没准备好：忽略，下一轮再问
    } finally {
      _hydroProbing = false;
    }
    // 瓦片可能还没下完：1.2 秒后再问，最多 20 次（约 24 秒）
    if (_hydroProbe < 20 && mounted) {
      _hydroProbe++;
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _probeHydro();
      });
    }
  }

  void _markHydroReady() {
    if (_hydroReady) return;
    _hydroReady = true;
    _hydroProbe = 0;
    debugPrint('[MAP] hydro 在线瓦片确认可用，本地兜底退场');
    unawaited(_applyLayerToggles());
  }

  Future<Uint8List?> _buildPinIcon() async {
    const w = SpotPinPainter.unitW;
    const h = SpotPinPainter.unitH;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
    // 画法与 flutter_map 兜底内核共用同一份（widgets/spot_pin.dart）
    const SpotPinPainter().paint(canvas, const Size(w, h));
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
    // ★ sat-low 必须跟 sat 同开关，否则切到「路网」底图时
    //   低清卫星层还铺在下面，从路网图的透明缝隙里透出来。
    await _setVis('sat-low', _layers.satellite);
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
    // ★ 在线河网优先，本地数据兜底
    //
    // hydro（OSM 矢量瓦片）覆盖所有有名字的河流，本地 waters.json 只有
    // 43 条大江 —— 两者同时开会把长江画两遍（宽带 + 真实水面），出现重影。
    // 所以一旦确认瓦片真的加载成功，就关掉本地那套；离线或被墙时
    // _hydroReady 一直是 false，本地数据继续顶着，不会整层空白。
    //
    // 高德底图是 GCJ-02 加偏坐标，矢量瓦片没法逐要素纠偏（会整体偏
    // 300~500 米），这种情况只能用本地数据（本地坐标走 _tile.project 纠偏）。
    // ★ 在线图层只看「用户开关」，**不能再 && _hydroReady**
    //
    //   踩过的坑：一开始写成 `_layers.rivers && _hydroReady`，于是探针
    //   还没确认有数据时先把图层设成 visibility=none —— 而 MapLibre
    //   **不会为全隐源的源请求瓦片**，瓦片永远不来，querySourceFeatures
    //   永远 0，_hydroReady 永远是 false，图层永远隐藏，形成死锁。
    //   表现就是同一份代码在两轮 CI 里一次 68 条要素、一次 0 条（谁先跑）。
    //   现在：源在、瓦片到就画；画不出来时图层是空的不影响观感，
    //   本地兜底图层（rivers-*/lakes-*）继续顶住大江大河。
    final hydroOn = !_tile.isGcj02;

    await _setVis('hydro-water', _layers.rivers && hydroOn);
    await _setVis('hydro-water-line', _layers.rivers && hydroOn);
    // hydro-river-casing 已合并掉（不再有深蓝描边层）
    // v2.1.22：大河粗线（z6~10）+ 窄河细线（全缩放）分两个图层
    await _setVis('hydro-river-major', _layers.rivers && hydroOn);
    await _setVis('hydro-river-line', _layers.rivers && hydroOn);
    // 水库 / 湖泊 / 池塘图标归「湖泊水库」开关（用户点的是这个）
    await _setVis('hydro-lake-icon', _layers.lakes && hydroOn);
    await _setVis('hydro-pond-icon', _layers.lakes && hydroOn);

    // 本地数据是兜底：在线瓦片确认可用后就退场，避免长江被画两遍（重影）
    final hydro = _hydroReady && !_tile.isGcj02;

    await _setVis('lakes-fill', _layers.lakes && !hydro);
    await _setVis('lakes-line', _layers.lakes && !hydro);
    // rivers-casing 已删除（只留单层浅蓝 rivers-line）
    await _setVis('rivers-line', _layers.rivers && !hydro);
    await _setVis('zones-fill', _layers.noFishingZones);
    await _setVis('zones-line', _layers.noFishingZones);
    await _setVis('spots-pin', _layers.spots);
  }

  // ------------------------------------------------------------ 比例尺

  /// 相机停下：刷新比例尺 + 探一下在线河网有没有到数据
  void _onCameraIdle() {
    _updateScale();
    _probeHydro();
  }

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
  /// 底部中间的「AI 找钓点」按钮
  ///
  /// 深绿渐变胶囊 + 高亮 ✨，压在地图底部中间、全局「+」发布按钮上方。
  /// 计算中把图标换成转圈，并禁用重复点击（一次分析要拉天气，别连点）。
  Widget _buildAiButton() {
    return GestureDetector(
      onTap: _findAiSpots,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(16, 9, 18, 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D242E), Color(0xFF07080C)],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_aiBusy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppTheme.accent),
                ),
              )
            else
              const Icon(Icons.auto_awesome,
                  size: 19, color: AppTheme.accent),
            const SizedBox(width: 9),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_aiBusy ? '正在分析…' : 'AI 找钓点',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700)),
                Text(
                    _aiQuotaText.isEmpty ? 'AI SPOT' : 'AI SPOT · $_aiQuotaText',
                    style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 8,
                        height: 1.2,
                        letterSpacing: 1.4)),
              ],
            ),
            if (_aiSpots.isNotEmpty && !_aiBusy) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_aiSpots.length}',
                    style: const TextStyle(
                        // 荧光黄绿底上必须用近黑字（白字对比度只有 1.1:1）
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
    // 高清圈以定位点为心（±50km）。这一步必须在样式生成之前 ——
    // raster source 的 bounds 不能原地改，晚到就只能等下次进页面。
    _setHdCenter(lat, lng);
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

  // ------------------------------------------------------------ AI 推荐钓点

  /// 把推荐结果画到地图上（编号 1..N，与底部列表一一对应）
  Future<void> _renderAiSpots() async {
    final c = _map;
    if (c == null || !_styleReady) return;
    final feats = <Map<String, dynamic>>[];
    final idx = <int, int>{};
    for (var i = 0; i < _aiSpots.length; i++) {
      final s = _aiSpots[i];
      final q = _tile.project(ll.LatLng(s.lat, s.lng));
      idx[i + 1] = i;
      feats.add({
        'type': 'Feature',
        'id': i + 1, // 与地图上的橙色序号一致，点击时靠它反查
        'properties': {'n': '${i + 1}', 'id': s.id},
        'geometry': {
          'type': 'Point',
          'coordinates': [q.longitude, q.latitude]
        },
      });
    }
    _aiNumToIdx = idx;
    try {
      if (_aiDataAdded) {
        await c.setGeoJsonSource('ai-spots', _fc(feats));
      } else {
        await c.addGeoJsonSource('ai-spots', _fc(feats));
        _aiDataAdded = true;
      }
    } catch (_) {}
  }

  /// 拉一次次数提示（不阻断任何操作，纯粹是让按钮显示「剩 N 次」）
  Future<void> _loadQuotaText() async {
    try {
      final sp = Provider.of<SessionProvider>(context, listen: false);
      if (!sp.isLoggedIn) {
        if (mounted && _aiQuotaText.isNotEmpty) setState(() => _aiQuotaText = '');
        return;
      }
      if (sp.isMember) {
        if (mounted) setState(() => _aiQuotaText = '会员');
        return;
      }
      final q = await AiQuotaService.fetch();
      if (!mounted) return;
      setState(() => _aiQuotaText = q.canUse ? '剩 ${q.remaining} 次' : '已用完');
    } catch (_) {
      // 次数只是提示，拿不到就不显示
    }
  }

  /// 点「AI 找钓点」：定位 → 全屏雷达扫描（过程可视化）→ 回填标注
  ///
  /// ★ v2.1.49：不再「转个圈直接弹一个白色底部面板」。
  ///   现在打开雷达扫描页，扫描线转一圈、水域逐个点亮，扫完把结果列表
  ///   推上来；用户点某一条就飞过去。整个过程用户能看见 AI 在算。
  Future<void> _findAiSpots() async {
    if (_aiBusy) return;
    // ★ v2.1.56：AI 分析改成会员功能（非会员免费 3 次，用完要开会员）。
    //   闸门放在**打开雷达之前**，别等扫完了才说「次数不够」——那样用户
    //   等 15 秒动画白等一场。
    if (!await ensureAiQuota(context)) return;
    if (!mounted) return;
    setState(() => _aiBusy = true);
    try {
      var lat = _myLat;
      var lng = _myLng;
      if (lat == null || lng == null) {
        final pos = await LocationService.determinePosition()
            .timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
        if (mounted) {
          setState(() {
            _myLat = lat;
            _myLng = lng;
          });
        }
        await _drawMe();
      }
      // 走到这里 lat/lng 一定非空（要么原本就有，要么上面刚赋过）
      final useLat = lat;
      final useLng = lng;
      if (!mounted) return;

      final result = await Navigator.of(context).push<AiRadarResult>(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black.withOpacity(0.62),
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, anim, __) => FadeTransition(
            opacity: anim,
            child: AiRadarScreen(
              lat: useLat,
              lng: useLng,
              spots: _spots,
              waters: _waters,
            ),
          ),
        ),
      );
      if (!mounted || result == null) return;

      // 扫出结果才算一次（网络失败/无结果是我们的问题，不该扣用户次数）
      if (result.list.isNotEmpty) {
        final sp = Provider.of<SessionProvider>(context, listen: false);
        final r = await AiQuotaService.consume(userId: sp.userId);
        if (mounted && !r.quota.member) {
          setState(() => _aiQuotaText =
              r.quota.canUse ? '剩 ${r.quota.remaining} 次' : '已用完');
        }
      }
      if (!mounted) return;

      setState(() => _aiSpots = result.list);
      await _renderAiSpots();
      final picked = result.picked;
      if (picked != null && mounted) {
        await _landCamera(picked.lat, picked.lng);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('定位失败，请检查定位权限后再试')));
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
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
            const CircleLayerProperties(
              circleColor: _Hex.water,
              circleRadius: 6,
              circleStrokeColor: _Hex.white,
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

  /// 点中地图上的要素（钓点图钉 / AI 推荐圆标）
  ///
  /// ★ 必须接这里，不能只接 onMapClick：
  ///   iOS 与 Android 原生层都是「先做一次图层要素命中」，命中就发
  ///   `feature#onTap`，**只有没命中任何要素才发 `map#onMapClick`**。
  ///   之前只监听了 onMapClick，所以手指点在图钉上时那个回调根本不会来，
  ///   用户体验就是「点标记没反应、进不去详情」。
  void _onFeatureTap(
      dynamic id, dynamic point, dynamic latLng, dynamic layerId) {
    final lid = layerId?.toString() ?? '';
    final numId = id is num ? id.toInt() : int.tryParse('$id');

    // AI 推荐圆标：先飞过去，如果这条对应某个钓友共享钓点，再进详情
    if (lid.startsWith('ai-spot')) {
      final i = numId == null ? null : _aiNumToIdx[numId];
      if (i == null || i < 0 || i >= _aiSpots.length) return;
      final s = _aiSpots[i];
      _landCamera(s.lat, s.lng);
      final sid = s.spotId;
      if (sid == null) return;
      final spot = _spotById[sid];
      if (spot != null && mounted) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)));
      }
      return;
    }

    // 钓点图钉
    if (lid == 'spots-pin') {
      final sid = numId == null ? null : _spotNumToId[numId];
      final s = sid == null ? null : _spotById[sid];
      if (s != null && mounted) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: s)));
      }
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
                // ★★ 缩放上限必须等于瓦片源的真实最大级别（星图 18）。
                //   不设的话原生默认允许到 22 级，而瓦片只到 18 级 ——
                //   超过 18 之后 MapLibre **不会再请求任何新瓦片**，
                //   只是把 18 级图放大 2 的 4 次方 = 16 倍，
                //   表现就是你看到的「越放大越糊、而且一直在转圈不加载」。
                //   压到 18 之后，镜头会停在"最后一级真图"上，永远是清晰的。
                minMaxZoomPreference: MinMaxZoomPreference(
                  3.0,
                  _tile.maxNativeZoom.toDouble(),
                ),
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
                  // ★ 要素点击走独立通道（见 _onFeatureTap 注释）：
                  //   原生层命中图层要素时只发 feature#onTap，不发 onMapClick。
                  c.onFeatureTapped.add(_onFeatureTap);
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
                onCameraIdle: _onCameraIdle,
                onMapClick: (point, latlng) => _onMapClick(point),
              )
            : Container(
                color: AppTheme.divider,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
      ),

      // AI 找钓点：底部中间（压在全局「+」发布按钮上方，两者不重叠）
      Positioned(
        left: 0,
        right: 0,
        bottom: 88,
        child: Center(child: _buildAiButton()),
      ),

      // 比例尺（在授权文字上方）
      Positioned(
        left: 10,
        bottom: 21,
        child: IgnorePointer(child: _buildScaleBar()),
      ),

      // 底图降级提示：首选那家在当前网络打不开时，别让用户以为「地图坏了」
      if (_mapNote.isNotEmpty)
        Positioned(
          left: 12,
          right: 12,
          top: (widget.embedded
                  ? 64.0
                  : MediaQuery.of(context).padding.top + 96) -
              4,
          child: IgnorePointer(
            ignoring: false,
            child: GestureDetector(
              onTap: () => setState(() => _mapNote = ''),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xE607080C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.swap_horiz,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_mapNote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.3,
                            color: Colors.white)),
                  ),
                  const Icon(Icons.close, size: 13, color: Colors.white54),
                ]),
              ),
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
            // OSM 数据（在线河网）必须署名，这是 ODbL 的硬要求
            '${_tile.attribution} · 水系©OpenStreetMap · 禁钓数据来自政府通告',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                      fontSize: 11, color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 10),
            // 底图线路自检：WiFi / 移动网络对比时，把逐家的结果直接摆出来
            _NetCheckRow(current: _tile.shortName),
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
              const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
      value: value,
      activeColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }
}

/// 底图线路自检行（图层面板底部）
///
/// 用户反馈「WiFi 下地图不加载、只看到高德底图」。这条自检把三家底图的
/// **实测结果**（通了多久、失败原因）直接写在面板里 —— 换个网络再点一次，
/// 就能当场看出是「星图在这条网被拦」还是「整条网都出不去」。
class _NetCheckRow extends StatefulWidget {
  final String current;
  const _NetCheckRow({required this.current});

  @override
  State<_NetCheckRow> createState() => _NetCheckRowState();
}

class _NetCheckRowState extends State<_NetCheckRow> {
  bool _busy = false;
  List<TileHealthResult> _results = const [];

  @override
  void initState() {
    super.initState();
    // 打开面板时先把上一次的结论亮出来，不想等就点「重新检测」
    _results = MapConfigService.lastProbe;
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final r = await MapConfigService.runDiagnostics();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_tethering,
                  size: 15, color: AppTheme.violet),
              const SizedBox(width: 5),
              const Text('底图线路自检',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('当前：${widget.current}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const Spacer(),
              if (_busy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.6))
              else
                TextButton(
                  onPressed: _run,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('重新检测', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (_results.isEmpty && !_busy)
            const Padding(
              padding: EdgeInsets.only(top: 2, left: 20),
              child: Text('点「重新检测」测一下这台手机当前网络能不能拉到底图',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ),
          for (final r in _results)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 20),
              child: Row(
                children: [
                  Icon(r.ok ? Icons.check_circle : Icons.error_outline,
                      size: 12,
                      color: r.ok ? AppTheme.primary : AppTheme.danger),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      r.ok ? '${r.name} · ${r.ms} ms' : '${r.name} · ${r.detail}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: r.ok
                              ? AppTheme.textSecondary
                              : AppTheme.danger),
                    ),
                  ),
                ],
              ),
            ),
          if (_results.isNotEmpty && !_results.first.ok && _results.any((r) => r.ok))
            const Padding(
              padding: EdgeInsets.only(top: 5, left: 20),
              child: Text('首选底图在这条网络上不通，已自动改用能通的那家（回退本页再进生效）',
                  style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
            ),
        ],
      ),
    );
  }
}
