import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/ai_spot.dart';
import '../models/fishing_spot.dart';
import '../models/no_fishing_zone.dart';
import '../models/water_body.dart';
import '../services/fish_service.dart';
import '../services/location_service.dart';
import '../services/cached_tile_provider.dart';
import '../services/map_config_service.dart';
import '../services/map_data_service.dart';
import '../services/map_tile_source.dart';
import '../services/spot_service.dart';
import '../services/weather_service.dart';
import '../utils/coord_transform.dart';
import '../widgets/spot_pin.dart';
import 'spot_detail_screen.dart';

/// 钓点地图（v2.1.9 新增，v2.1.10 升级底图与图层面板）
/// ------------------------------------------------------------
/// 参照主流钓鱼 App 的「钓点地图」做的全屏地图：
///  - 底图：天地图卫星影像（合规白名单内，视觉等同参考 App 的「星图地球 GS」）
///    天地图需 tk 密钥（后台「系统设置 → 站点设置」配置），
///    没配置时自动回退免 key 的高德卫星图，地图永远能打开。
///  - 蓝色图层：全国主要江河（折线）+ 湖泊水库（多边形），43 江 44 湖
///  - 红色图层：全国禁钓区 / 禁渔期（33 处，含禁钓时间段与法律依据，
///    数据整理自农业农村部等政府部门公开通告，后台可维护）
///  - 钓点标记（后端 /spots）+ 底部统计（水域/钓点/渔获）
///  - 搜索（水域/钓点/禁钓区）、图层面板、禁钓区名录、AI 找钓点
///
/// 坐标系：数据统一存 WGS-84；叠到高德底图要转 GCJ-02，叠到天地图原样绘制。
/// 见 [TileSource.project]。
///
/// 两种用法：
///  - `SpotMapScreen()`：独立全屏地图页（底部导航「地图」Tab 已删除，此入口保留给
///    「附近钓点 → 更多」等外部跳转）
///  - `SpotMapScreen(embedded: true)`：嵌入钓点页「野钓钓点」Tab，
///    顶部搜索条与底部统计条由外层负责，地图本体一样
class SpotMapScreen extends StatefulWidget {
  /// 是否嵌入模式（嵌入时不自带搜索栏 / 底部统计条）
  final bool embedded;

  /// 嵌入模式下额外的钓点标记（钓点页自己拉的野钓点）
  final List<FishingSpot> extraSpots;

  /// 外部定位联动用（钓点页拿到定位后调用 [SpotMapController.moveToLocation]）
  final SpotMapController? controller;

  /// 测试专用：为 true 时不加载底图瓦片。
  /// widget 测试环境没有网络，瓦片请求会抛 ClientException 污染断言；
  /// 关掉底图后仍能完整验证浮层 / 图层面板的布局。生产代码恒为 false。
  static bool testSkipTiles = false;

  const SpotMapScreen({
    super.key,
    this.embedded = false,
    this.extraSpots = const [],
    this.controller,
  });

  @override
  State<SpotMapScreen> createState() => _SpotMapScreenState();
}

/// 地图对外操作接口（供宿主页联动定位）
class SpotMapController {
  /// 把地图移到某个 WGS-84 坐标
  void Function(double lat, double lng)? _move;

  /// 地图还没挂载时先缓存目标坐标
  ///
  /// ★ 修的是「打开野钓钓点后不显示当前位置」的真 bug：
  ///   宿主钓点页在 initState 就发起定位，而第 2 个 Tab（野钓钓点）要等
  ///   TabBarView 真正渲染时才会构建地图，此时 `_move` 还是 null ——
  ///   定位坐标被**直接丢掉**，等用户切到地图 Tab 时宿主页不会再定位第二次，
  ///   于是地图永远停在全国视角 z4，看着就像「没定位、地图是废的」。
  ///   现在把坐标缓存下来，地图一挂载（bind）立刻补走一次。
  ({double lat, double lng})? _pending;

  /// 地图移动到指定坐标（宿主页定位成功后调用）
  void moveToLocation(double lat, double lng) {
    final f = _move;
    if (f == null) {
      _pending = (lat: lat, lng: lng);
      return;
    }
    f(lat, lng);
  }

  /// 地图实现挂载时绑定（flutter_map / 原生 GL 两套实现都用这个）
  void bind(void Function(double lat, double lng) move) {
    _move = move;
    final p = _pending;
    if (p != null) {
      _pending = null;
      move(p.lat, p.lng); // 补上挂载前错过的定位
    }
  }

  /// 地图实现卸载时解绑（不清 pending：切 Tab 回来还要再补一次）
  void unbind() => _move = null;
}

class _SpotMapScreenState extends State<SpotMapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();

  // 数据
  List<WaterBody> _waters = const [];
  NoFishingData _zones = NoFishingData.empty;
  List<FishingSpot> _spots = const [];
  int _catchCount = 0;
  bool _loading = true;

  // 我的位置（WGS-84）
  double? _myLat;
  double? _myLng;
  bool _locating = false;

  // 视图状态（图层开关统一放在 _layers，避免两套状态不同步）
  double _zoom = 4;

  // 图层开关（对应参考 App 的「图层」面板）
  MapLayerState _layers = MapLayerState();

  // 底图：星图地球 > 天地图 > 高德（优先级由后台配置决定，取不到自动降级）
  TileSource _tile = const TileSource(kind: TileSourceKind.gaode);

  // 瓦片提供器（磁盘缓存 + 内置离线包），三种图层各一个，不能每帧新建，
  // 否则 TileLayer 会认为提供器变了，把所有瓦片重新加载一遍
  late final CachedTileProvider _imgProvider = CachedTileProvider(
      layer: 'img', onNetworkFail: _onTileFail, onTileOk: _onTileOk);
  late final CachedTileProvider _vecProvider = CachedTileProvider(
      layer: 'vec', onNetworkFail: _onTileFail, onTileOk: _onTileOk);
  late final CachedTileProvider _ciaProvider = CachedTileProvider(
      layer: 'cia', onNetworkFail: _onTileFail, onTileOk: _onTileOk);

  /// 看门狗：进入地图 15 秒还没有任何一块瓦片成功，就认为当前底图这条线不通
  Timer? _watchdog;
  bool _gotAnyTile = false;

  // 是否已从星图/天地图降级到高德（一个会话只降一次）
  bool _degraded = false;

  // 搜索
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;

  // AI 找钓点
  bool _aiLoading = false;
  AiSpotRec? _aiRec;

  // 详情面板
  WaterBody? _selWater;
  NoFishingZone? _selZone;

  // 高德瓦片（与野钓卫星地图同源；卫星=8 + 路网标注=6 叠加）
  // 天地图底图见 TileSource（密钥从后台配置拉，取不到自动回退高德）
  static const _waterColor = Color(0xFF1565C0);
  static const _waterFill = Color(0x591E88E5);
  static const _zoneColor = Color(0xFFE5484D);
  static const _zoneFill = Color(0x26E5484D);

  @override
  void initState() {
    super.initState();
    // 瓦片缓存目录 + 内置离线包探测（后台跑，不阻塞首帧）
    unawaited(CachedTileProvider.init());
    _watchdog = Timer(const Duration(seconds: 15), () {
      if (mounted && !_gotAnyTile) _onTileFail();
    });
    _load();
    _searchCtrl.addListener(_onSearchChanged);
    // 宿主页（钓点页）联动定位：把内部移动能力挂到 controller 上
    widget.controller?._move = _moveToLocation;
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(silent: true));
    // 底图密钥：后台「系统设置 → 地图底图」配置
    // 有星图地球 token 用星图，其次天地图 tk，都没有用高德免 key 底图
    MapConfigService.load().then((_) {
      if (!mounted) return;
      setState(() => _tile = MapConfigService.source);
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    widget.controller?._move = null;
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 连续多个瓦片加载失败 → 说明当前底图这条线不通（配额用完 / 被限流 / 断网），
  /// 直接降到免 key 的高德，避免整屏空瓦片还一直重试拖慢 UI。
  void _onTileOk() {
    if (_gotAnyTile) return;
    _gotAnyTile = true;
    _watchdog?.cancel();
  }

  void _onTileFail() {
    if (!mounted || _degraded) return;
    if (_tile.kind == TileSourceKind.gaode) return;
    _degraded = true;
    setState(() => _tile = const TileSource(kind: TileSourceKind.gaode));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('星图地球连不上（可能是今日配额用完），已自动切换到高德底图'),
      duration: Duration(seconds: 3),
    ));
  }

  /// 移到某个 WGS-84 坐标（底图是天地图时原样绘制，高德时转 GCJ-02）
  void _moveToLocation(double lat, double lng) {
    final p = _tile.project(LatLng(lat, lng));
    try {
      _mapController.move(p, 12.5);
    } catch (_) {
      // 地图尚未挂载
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      MapDataService.waters(),
      MapDataService.zones(),
      SpotService.fetchSpots(),
      MapDataService.stats(),
    ]);
    if (!mounted) return;
    setState(() {
      _waters = results[0] as List<WaterBody>;
      _zones = results[1] as NoFishingData;
      _spots = (results[2] as List<FishingSpot>)
          .where((s) => s.lat != 0 && s.lng != 0)
          .toList();
      _catchCount = (results[3] as Map<String, int>?)?['catches'] ?? 0;
      _loading = false;
    });
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
      _moveToLocation(pos.latitude, pos.longitude);
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('定位失败，请检查定位权限（可在系统设置中开启）')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ------------------------------------------------------------ 搜索

  void _onSearchChanged() {
    // 输入变化时刷新搜索结果列表（TextField 由外层 setState 重建）
    setState(() {});
  }

  void _exitSearch() {
    setState(() {
      _searching = false;
    });
    _searchCtrl.clear();
    _searchFocus.unfocus();
  }

  // ------------------------------------------------------------ 地图点击命中

  void _handleMapTap(TapPosition pos, LatLng point) {
    final ctx = _mapKey.currentContext;
    if (ctx == null) return;
    final cam = MapCamera.maybeOf(ctx);
    if (cam == null) return;
    final p = pos.relative ?? pos.global;

    if (_layers.noFishingZones) {
      for (final z in _zones.zones) {
        if (!z.onMap) continue;
        for (final ring in z.rings) {
          if (_pointInPolygon(p, ring.map(cam.getOffsetFromOrigin).toList())) {
            setState(() {
              _selZone = z;
              _selWater = null;
            });
            return;
          }
        }
      }
    }
    if ((_layers.lakes || _layers.rivers)) {
      for (final w in _waters) {
        if (w.isRiver) {
          // 折线：命中判定为到线段的距离
          final pts = w.geometry.map(cam.getOffsetFromOrigin).toList();
          if (_distToPolyline(p, pts) < 14) {
            setState(() {
              _selWater = w;
              _selZone = null;
            });
            return;
          }
        } else if (_pointInPolygon(
            p, w.geometry.map(cam.getOffsetFromOrigin).toList())) {
          setState(() {
            _selWater = w;
            _selZone = null;
          });
          return;
        }
      }
    }
    setState(() {
      _selWater = null;
      _selZone = null;
    });
  }

  static bool _pointInPolygon(Offset p, List<Offset> poly) {
    if (poly.length < 3) return false;
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i];
      final b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  static double _distToPolyline(Offset p, List<Offset> pts) {
    if (pts.isEmpty) return double.infinity;
    var best = double.infinity;
    for (var i = 0; i < pts.length - 1; i++) {
      final d = _distToSegment(p, pts[i], pts[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final vx = b.dx - a.dx;
    final vy = b.dy - a.dy;
    final wx = p.dx - a.dx;
    final wy = p.dy - a.dy;
    final len2 = vx * vx + vy * vy;
    if (len2 == 0) return (p - a).distance;
    var t = (wx * vx + wy * vy) / len2;
    t = t.clamp(0.0, 1.0);
    final dx = a.dx + t * vx - p.dx;
    final dy = a.dy + t * vy - p.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  // ------------------------------------------------------------ AI 找钓点

  Future<void> _aiFindSpots() async {
    final lat = _myLat ?? 30.25;
    final lng = _myLng ?? 120.17;
    setState(() => _aiLoading = true);
    Map<String, dynamic>? wx;
    try {
      final w = await WeatherService.fetch(lat, lng);
      wx = {
        'temp': w.temperature,
        'pressure': w.pressure,
        'wind': w.windSpeed,
        'text': w.description,
        'fishIndex': w.fishIndex,
      };
    } catch (_) {}
    // 就近取 8 个水域（湖泊优先，河流按中心距离）
    final near = [..._waters]
      ..sort((a, b) => CoordTransform.distanceMeters(lat, lng, a.center.latitude, a.center.longitude)
          .compareTo(CoordTransform.distanceMeters(lat, lng, b.center.latitude, b.center.longitude)));
    final top = near.take(8).map((w) {
      final d = CoordTransform.distanceMeters(
          lat, lng, w.center.latitude, w.center.longitude);
      return {
        'name': w.name,
        'distKm': (d / 1000).toStringAsFixed(1),
        'desc': w.desc,
        'kind': w.isRiver ? '江河' : w.kindLabel,
      };
    }).toList();
    try {
      final rec = await FishService.spotAi({
        'lat': lat,
        'lng': lng,
        'waters': top,
        if (wx != null) 'weather': wx,
      });
      if (!mounted) return;
      setState(() {
        _aiRec = rec;
        _aiLoading = false;
      });
      _showAiSheet();
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('AI 找钓点失败：请到后台「运营配置 → AI 设置」检查模型配置')));
    }
  }

  void _showAiSheet() {
    final rec = _aiRec;
    if (rec == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      isScrollControlled: true,
      builder: (_) => _AiSheet(rec: rec, onPick: _flyToWater),
    );
  }

  void _flyToWater(String name) {
    WaterBody? found;
    for (final e in _waters) {
      if (e.name == name) {
        found = e;
        break;
      }
    }
    final w = found;
    if (w == null) return;
    final g = CoordTransform.wgs84ToGcj02(w.center.latitude, w.center.longitude);
    _mapController.move(LatLng(g[0], g[1]), 9.5);
    setState(() => _selWater = w);
  }

  // ------------------------------------------------------------ 面板

  /// 图层面板（v2.1.10 重做，参照参考 App 的三段式布局）
  ///
  ///   ① 底图图层 BASE MAP  —— 卫星地图 / 矢量地图 缩略卡片 + 天地图历史影像（VIP 标识）
  ///   ② 地图设置 SETTINGS   —— 路网图层 / 中心十字星 / 禁渔区域
  ///   ③ 水域图层 SHOW       —— 河流 / 湖泊 / 钓点
  void _showLayerPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF2F4F7),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void up(void Function(MapLayerState) fn) {
            setLocal(() {});
            setState(() => fn(_layers));
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.4,
            maxChildSize: 0.94,
            expand: false,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
              children: [
                // 标题栏
                Row(children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('图层',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1D21))),
                      SizedBox(height: 2),
                      Text('LAYERS',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
                const SizedBox(height: 14),

                // ① 底图图层
                _panelCard(children: [
                  _panelTitle('底图图层', 'BASE MAP'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _baseMapCard(
                        label: '卫星地图',
                        sub: '${_tile.shortName}影像',
                        icon: Icons.satellite_alt,
                        selected: _layers.satellite,
                        onTap: () => up((l) => l.satellite = true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _baseMapCard(
                        label: '矢量地图',
                        sub: '${_tile.shortName}路网',
                        icon: Icons.map_outlined,
                        selected: !_layers.satellite,
                        onTap: () => up((l) => l.satellite = false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 历史影像：需要额外资质，标 VIP 占位
                    Expanded(
                      child: Opacity(
                        opacity: 0.55,
                        child: _baseMapCard(
                          label: '历史影像',
                          sub: 'VIP',
                          icon: Icons.history,
                          selected: false,
                          vip: true,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      '历史影像为高级功能，需要开通后开放')),
                            );
                          },
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    _tile.describe,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  // 瓦片统计：缓存命中越多越省流量，也说明离线缓存确实在工作
                  Text(
                    '瓦片 ${CachedTileProvider.statLine}'
                    '${CachedTileProvider.hasBundledTiles ? ' · 含内置包' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ]),

                // ② 地图设置
                _panelCard(children: [
                  _panelTitle('地图设置', 'SETTINGS'),
                  const SizedBox(height: 4),
                  _layerSwitch(
                    icon: Icons.route_outlined,
                    title: '路网图层',
                    subtitle: '叠加道路与地名注记',
                    value: _layers.roadLabels,
                    onChanged: (v) => up((l) => l.roadLabels = v),
                  ),
                  _layerSwitch(
                    icon: Icons.add_location_alt_outlined,
                    title: '中心十字星',
                    subtitle: '在屏幕中心显示定位十字',
                    value: _layers.crosshair,
                    onChanged: (v) => up((l) => l.crosshair = v),
                  ),
                  _layerSwitch(
                    icon: Icons.block_outlined,
                    title: '禁渔区域',
                    subtitle: '红色为禁钓区 / 禁渔期',
                    value: _layers.noFishingZones,
                    danger: true,
                    onChanged: (v) => up((l) => l.noFishingZones = v),
                  ),
                ]),

                // ③ 水域图层
                _panelCard(children: [
                  _panelTitle('水域图层', 'SHOW'),
                  const SizedBox(height: 4),
                  _layerSwitch(
                    icon: Icons.water_drop_outlined,
                    title: '河流',
                    subtitle: '显示河流水系（蓝色）',
                    value: _layers.rivers,
                    onChanged: (v) => up((l) => l.rivers = v),
                  ),
                  _layerSwitch(
                    icon: Icons.water_outlined,
                    title: '湖泊',
                    subtitle: '显示湖泊水体（蓝色）',
                    value: _layers.lakes,
                    onChanged: (v) => up((l) => l.lakes = v),
                  ),
                  _layerSwitch(
                    icon: Icons.place_outlined,
                    title: '钓点图层',
                    subtitle: '显示钓友共享的钓点标记',
                    value: _layers.spots,
                    onChanged: (v) => up((l) => l.spots = v),
                  ),
                  _layerSwitch(
                    icon: Icons.label_outline,
                    title: '水域名称',
                    subtitle: '在水域上标注名称',
                    value: _layers.waterLabels,
                    onChanged: (v) => up((l) => l.waterLabels = v),
                  ),
                ]),

                const SizedBox(height: 12),
                const Text(
                  '蓝色水域与红色禁钓区为参考图层，禁钓规定以现场标识牌及当地通告为准。',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 面板外层卡片（参考 App 的圆角白底分组）
  Widget _panelCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// 面板分组标题（中文 + 英文小字）
  Widget _panelTitle(String cn, String en) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        // CrossAxisAlignment.baseline 必须配 textBaseline，否则直接断言崩溃
        textBaseline: TextBaseline.alphabetic,
        children: [
      Text(cn,
          style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1D21))),
      const SizedBox(width: 6),
      Text(en,
          style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary)),
    ]);
  }

  /// 底图缩略卡片
  Widget _baseMapCard({
    required String label,
    required String sub,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool vip = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5EC) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon,
                size: 26,
                color: selected ? AppTheme.primary : const Color(0xFF9AA1AA)),
            if (vip)
              Positioned(
                right: -14,
                top: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3F46),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('VIP',
                      style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFFD666))),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppTheme.primaryDark : const Color(0xFF3A3F46))),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: AppTheme.textSecondary)),
        ]),
      ),
    );
  }

  /// 图层开关行（图标 + 标题 + 副标题 + 开关）
  Widget _layerSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool danger = false,
  }) {
    final color = danger ? AppTheme.danger : AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: danger
                ? AppTheme.danger.withOpacity(0.10)
                : AppTheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1D21))),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: color,
        ),
      ]),
    );
  }

  Widget _switchRow(
      String label, bool value, Color color, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: color,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
    );
  }

  void _showDirectory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      isScrollControlled: true,
      builder: (_) => DefaultTabController(
        length: 3,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2))),
            const TabBar(
              labelColor: AppTheme.primary,
              indicatorColor: AppTheme.primary,
              tabs: [
                Tab(text: '禁钓区名录'),
                Tab(text: '禁渔期制度'),
                Tab(text: '垂钓规范'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _zoneListTab(),
                _ruleListTab(),
                _tipsTab(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _zoneListTab() {
    final zones = _zones.zones;
    if (zones.isEmpty) {
      return const Center(child: Text('暂无禁钓区数据'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      itemCount: zones.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final z = zones[i];
        final st = z.statusNow();
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
              z.kind == ZoneKind.waterSource || z.kind == ZoneKind.noFishing
                  ? Icons.block
                  : Icons.warning_amber_rounded,
              color: AppTheme.danger),
          title: Text(z.name,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${z.kindLabel} · ${z.region}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text('禁钓时间：${z.period}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                Row(children: [
                  _statusChip(st),
                  if (z.onMap) ...[
                    const SizedBox(width: 6),
                    const Text('已上图',
                        style: TextStyle(
                            fontSize: 10.5, color: AppTheme.textSecondary)),
                  ],
                ]),
              ],
            ),
          ),
          isThreeLine: true,
          onTap: () {
            Navigator.pop(context);
            if (z.onMap && z.center != null) {
              final g = CoordTransform.wgs84ToGcj02(
                  z.center!.latitude, z.center!.longitude);
              _mapController.move(LatLng(g[0], g[1]), 7.5);
            }
            setState(() => _selZone = z);
          },
        );
      },
    );
  }

  Widget _statusChip(ZoneStatus st) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: st.active ? AppTheme.dangerLight : const Color(0xFFEFF2F1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(st.label,
          style: TextStyle(
              fontSize: 10.5,
              color: st.active ? AppTheme.danger : AppTheme.textSecondary,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _ruleListTab() {
    final rules = _zones.seasonRules;
    if (rules.isEmpty) return const Center(child: Text('暂无禁渔期数据'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      itemCount: rules.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = rules[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(r.scope,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600))),
                if (r.mdWindow != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: r.activeNow
                          ? AppTheme.dangerLight
                          : const Color(0xFFEFF2F1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(r.activeNow ? '进行中' : '未开始/已结束',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: r.activeNow
                                ? AppTheme.danger
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 3),
              Text('禁渔时间：${r.period}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textPrimary, height: 1.45)),
              const SizedBox(height: 2),
              Text(r.note,
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                      height: 1.45)),
              const SizedBox(height: 3),
              Text('依据：${r.law}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              if (r.source.isNotEmpty)
                GestureDetector(
                  onTap: () => _openSource(r.source),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text('查看来源 ›',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.accent)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tipsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        for (final t in _zones.tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline,
                  size: 15, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(t,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textPrimary,
                          height: 1.5))),
            ]),
          ),
        const Divider(),
        const SizedBox(height: 8),
        const Text('休闲垂钓规范（长江流域，各地参照执行）',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final t in const [
          '原则上只允许「一人一杆、一线、一钩（单钩）」，禁止多线多钩、长线多钩、单线多钩',
          '禁止使用探鱼设备、视频装置等辅助钓鱼设备',
          '禁止使用船艇、排筏等水上漂浮物进行垂钓',
          '禁止使用含有毒有害物质的钓饵、窝料、添加剂及鱼虾类活体饵料',
          '误捕误钓幼体及禁捕品种，必须及时放回原水体',
          '严格禁止休闲垂钓渔获物买卖交易，有交易行为的视同非法捕捞',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.primary)),
                  Expanded(
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textPrimary,
                              height: 1.45))),
                ]),
          ),
        const SizedBox(height: 6),
        Text('依据：《关于加强和规范长江流域垂钓管理工作的通知》（长渔发〔2020〕12号）',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ------------------------------------------------------------ 详情面板

  void _showWaterSheet(WaterBody w) {
    final d = (_myLat != null && _myLng != null)
        ? CoordTransform.distanceMeters(
            _myLat!, _myLng!, w.center.latitude, w.center.longitude)
        : null;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppTheme.accentLight,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(w.isRiver ? '江河' : w.kindLabel,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.accentDark,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            if (d != null)
              Text('距我约 ${CoordTransform.formatDistance(d)}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary)),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(w.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(w.subLabel,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(w.desc,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.55)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final g = CoordTransform.wgs84ToGcj02(
                      w.center.latitude, w.center.longitude);
                  _mapController.move(LatLng(g[0], g[1]), 9.5);
                },
                icon: const Icon(Icons.my_location, size: 17),
                label: const Text('在地图上查看'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openSource(
                      'https://www.amap.com/search?query=${Uri.encodeComponent(w.name)}');
                },
                icon: const Icon(Icons.navigation_outlined, size: 17),
                label: const Text('导航前往'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showZoneSheet(NoFishingZone z) {
    final st = z.statusNow();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(z.kindLabel,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.dangerDark,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              _statusChip(st),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(z.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(z.region,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.schedule, '禁钓时间段', z.period),
            _infoRow(Icons.waves, '垂钓规定', z.fishing),
            _infoRow(Icons.gavel_outlined, '政策依据', z.law),
            if (st.hint.isNotEmpty) _infoRow(Icons.error_outline, '当前提示', st.hint),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(10)),
              child: const Text(
                  '以上内容整理自政府部门公开通告，仅供参考；请以现场标识牌和当地最新通告为准，遵守禁钓规定。',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textPrimary,
                      height: 1.5)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openSource(z.source),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('查看政策来源'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (z.center != null) {
                      final g = CoordTransform.wgs84ToGcj02(
                          z.center!.latitude, z.center!.longitude);
                      _mapController.move(LatLng(g[0], g[1]), 8.5);
                    }
                  },
                  child: const Text('定位到该区域'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
            width: 74,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary))),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textPrimary,
                  height: 1.5)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ 图层构建

  /// 几何缓存：43 江 + 44 湖 + 33 禁钓区的坐标投影很吃 CPU（高德底图还要
  /// 逐点做 GCJ-02 纠偏），每帧重算会直接把拖动帧率拖死。这里只在
  /// 「数据 / 底图 / 图层开关 / 缩放跨过标注阈值」变化时才重算一次。
  List<Polygon> _lakeCache = const [];
  List<Polyline> _riverCache = const [];
  List<Polygon> _zoneCache = const [];
  List<Marker> _markerCache = const [];
  String _layerSig = '';

  String _computeLayerSig() => [
        _tile.kind.name,
        _layers.lakes,
        _layers.rivers,
        _layers.noFishingZones,
        _layers.spots,
        _layers.waterLabels,
        _zoom >= 5.5,
        _zoom >= 6,
        _waters.length,
        _zones.zones.length,
        _spots.length,
        widget.extraSpots.length,
        _myLat,
        _myLng,
      ].join('|');

  /// 在 build 开头调用；签名没变就直接复用缓存
  void _syncLayerCache() {
    final sig = _computeLayerSig();
    if (sig == _layerSig) return;
    _layerSig = sig;
    _lakeCache = _buildLakePolygons();
    _riverCache = _buildRiverLines();
    _zoneCache = _buildZonePolygons();
    _markerCache = _buildMarkers();
  }

  List<Polygon> get _lakePolygons => _lakeCache;
  List<Polyline> get _riverLines => _riverCache;
  List<Polygon> get _zonePolygons => _zoneCache;
  List<Marker> get _markers => _markerCache;

  List<Polygon> _buildLakePolygons() {
    if (!_layers.lakes) return const [];
    return _waters.where((w) => !w.isRiver).map((w) {
      final pts = _tile.projectAll(w.geometry);
      return Polygon(
        points: pts,
        color: _waterFill,
        borderColor: _waterColor,
        borderStrokeWidth: w.level <= 1 ? 2.2 : 1.4,
        label: _zoom >= 5.5 && _layers.waterLabels ? w.name : null,
        labelStyle: const TextStyle(
            fontSize: 11,
            color: Color(0xFF0B4F8A),
            fontWeight: FontWeight.w600),
      );
    }).toList();
  }

  List<Polyline> _buildRiverLines() {
    if (!_layers.rivers) return const [];
    // 宽度随缩放变化：全国视野是细线，城市/街道视野是实心水面带
    //
    // ★ 单层浅蓝，不再画深蓝描边（v2.1.21）：
    //   原来 `borderStrokeWidth + borderColor` 会在外面套一圈更深的蓝，
    //   加上填充色就是"一条河两种蓝"，看着像画了两条。这里与原生内核的
    //   rivers-line 对齐成同一个色值 #3FA9F5。
    final zt = ((_zoom - 3) / 13).clamp(0.0, 1.0);
    return _waters.where((w) => w.isRiver).map((w) {
      final pts = _tile.projectAll(w.geometry);
      // ★ v2.1.22：宽度档整体收窄（原来 base 24/15 在 z15 时约 29px，
      //   就是用户说的「很粗的蓝色」）。这个内核是离线兜底、没有水面填充，
      //   所以线要比原生那层略粗一点，但不能粗成色块。
      final base = w.level <= 1 ? 9.0 : 6.0;
      return Polyline(
        points: pts,
        strokeWidth: base * (0.45 + 0.75 * zt),
        color: const Color(0xCC3FA9F5),
      );
    }).toList();
  }

  List<Polygon> _buildZonePolygons() {
    if (!_layers.noFishingZones) return const [];
    return _zones.zones.where((z) => z.onMap && z.rings.isNotEmpty).map((z) {
      final st = z.statusNow();
      final fill = st.active ? _zoneFill : const Color(0x14E5484D);
      final border = st.active ? _zoneColor : const Color(0x88E5484D);
      return Polygon(
        points: _tile.projectAll(z.rings.first),
        color: fill,
        borderColor: border,
        borderStrokeWidth: 1.4,
        isDotted: !st.active,
        label: _zoom >= 6 ? _shortZoneName(z.name) : null,
        labelStyle: const TextStyle(
            fontSize: 10.5,
            color: Color(0xFFB71C1C),
            fontWeight: FontWeight.w600),
      );
    }).toList();
  }

  static String _shortZoneName(String name) {
    final i = name.indexOf('（');
    return i > 0 ? name.substring(0, i) : name;
  }

  List<Marker> _buildMarkers() {
    final list = <Marker>[];
    if (_layers.spots) {
      // 钓点：地图页自己拉的 + 嵌入时外层传入的（钓点页野钓点）
      final Map<String, FishingSpot> all = {
        for (final s in _spots) s.id: s,
      };
      for (final s in widget.extraSpots) {
        all[s.id] = s;
      }
      for (final s in all.values) {
        list.add(Marker(
          point: _tile.project(LatLng(s.lat, s.lng)),
          width: 32,
          height: 42,
          // 针尖对准坐标点：flutter_map 的 alignment 描述「整个 widget 相对
          // 这个点的位置」，topCenter = widget 整体在点上方，正好让针尖落地点
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SpotDetailScreen(spot: s))),
            child: const SpotPin(),
          ),
        ));
      }
    }
    if (_zoom >= 5.5 && _layers.waterLabels) {
      for (final w in _waters) {
        list.add(Marker(
          point: _tile.project(w.center),
          width: 92,
          height: 20,
          child: GestureDetector(
            onTap: () => setState(() => _selWater = w),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(w.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF0B4F8A),
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ));
      }
    }
    // 我的位置
    if (_myLat != null && _myLng != null) {
      list.add(Marker(
        point: _tile.project(LatLng(_myLat!, _myLng!)),
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
        ),
      ));
    }
    return list;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // 河湖/禁钓区坐标投影只在数据或底图变化时算一次，拖动时直接复用
    _syncLayerCache();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // 嵌入模式（钓点页「野钓钓点」Tab）没有系统状态栏留白，
    // 顶部安全区由外层 Scaffold 处理；提示条已改成左侧竖条，顶部不再需要让位
    final topInset = widget.embedded ? 8.0 : MediaQuery.of(context).padding.top + 8;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // ---------------- 地图 ----------------
        Builder(builder: (ctx) {
          // 记录地图内部 context 供坐标命中判定使用
          WidgetsBinding.instance.addPostFrameCallback((_) {});
          return KeyedSubtree(
            key: _mapKey,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(34.5, 108.9),
                initialZoom: 4,
                minZoom: 3,
                maxZoom: _tile.maxZoom,
                backgroundColor: AppTheme.divider,
                onPositionChanged: (position, _) {
                  final z = position.zoom ?? _zoom;
                  if ((z >= 5.5) != (_zoom >= 5.5) || (z >= 6) != (_zoom >= 6)) {
                    setState(() => _zoom = z);
                  } else {
                    _zoom = z;
                  }
                },
                onTap: _handleMapTap,
              ),
              children: [
                // 底图：星图地球 / 天地图 / 高德（由后台配置决定）
                if (!SpotMapScreen.testSkipTiles)
                TileLayer(
                  urlTemplate: _layers.satellite
                      ? _tile.satelliteTemplate
                      : _tile.vectorTemplate,
                  // 三家都是左上角原点的标准 XYZ，不能开 tms（开了会上下颠倒）
                  tms: _tile.needsTms,
                  subdomains: _tile.subdomains ?? const ['a', 'b', 'c'],
                  additionalOptions: _tile.additionalOptions,
                  userAgentPackageName: 'com.chuidiaoquan.app',
                  // 磁盘缓存 + 内置离线包：第二次进来直接读本地，不再走网络
                  tileProvider: _layers.satellite ? _imgProvider : _vecProvider,
                  // 只保留视野周边一圈（默认 2 圈），少留 60% 解码纹理，省内存不卡顿
                  keepBuffer: 1,
                  // 不留视野外的「预加载圈」，少请求一批瓦片
                  panBuffer: 0,
                  maxNativeZoom: _tile.maxNativeZoom,
                ),
                // 路网标注叠加层（可关）
                if (_layers.roadLabels && !SpotMapScreen.testSkipTiles)
                  TileLayer(
                    urlTemplate: _tile.labelTemplate,
                    tms: _tile.needsTms,
                    subdomains: _tile.subdomains ?? const ['a', 'b', 'c'],
                    additionalOptions: _tile.additionalOptions,
                    userAgentPackageName: 'com.chuidiaoquan.app',
                    tileProvider: _ciaProvider,
                    keepBuffer: 1,
                    maxNativeZoom: _tile.maxNativeZoom,
                  ),
                if ((_layers.lakes || _layers.rivers)) ...[
                  PolygonLayer(polygons: _lakePolygons),
                  PolylineLayer(polylines: _riverLines),
                ],
                if (_layers.noFishingZones)
                  PolygonLayer(polygons: _zonePolygons, polygonLabels: true),
                MarkerLayer(markers: _markers),
                // 中心十字星（可关）
                if (_layers.crosshair) const _CrosshairOverlay(),
              ],
            ),
          );
        }),

        // ---------------- 顶部：搜索 + 图层/名录 ----------------
        //
        // ★★ 嵌入模式（钓点页「野钓钓点」Tab）**不画这一行**。
        //   原来这里无条件画「图层 / 禁钓名录」两个圆钮，而原生 MapLibre
        //   内核（spot_map_gl.dart）没有这两个钮 —— 两套内核的浮层位置完全
        //   不同。原生 View 起得慢时会自动降级到本页，用户看到的就是
        //   「地图一加载出来，按钮全换位置了」。现在两个钮并入右侧竖排
        //   工具条（与原生内核同序同位），嵌入模式下这里保持空白。
        if (!widget.embedded)
          Positioned(
            top: topInset,
            left: 12,
            right: 12,
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 8)
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onTap: () => setState(() => _searching = true),
                      decoration: InputDecoration(
                        hintText: '搜水域、钓点、禁钓区',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                        prefixIcon: const Icon(Icons.search,
                            size: 20, color: AppTheme.textSecondary),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _exitSearch),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _roundBtn(Icons.layers_outlined, '图层', _showLayerPanel),
                const SizedBox(width: 8),
                _roundBtn(
                    Icons.verified_user_outlined, '禁钓名录', _showDirectory),
              ]),
              if (_searching && _searchCtrl.text.trim().isNotEmpty)
                _searchResults(),
            ]),
          ),

        // ---------------- 右侧工具栏 ----------------
        //
        // ★★ 与原生 MapLibre 内核**逐项对齐**：卫星 / 放大 / 缩小 / 定位 / 图层，
        //   嵌入模式 top=64，非嵌入 top=状态栏+140。
        //   位置、按钮顺序、按钮数量以前两套内核各不相同，一旦降级切内核，
        //   用户看到的就是整排按钮平移、还多两个少两个。
        Positioned(
          right: 12,
          top: widget.embedded ? 64 : MediaQuery.of(context).padding.top + 140,
          child: Column(children: [
            _roundBtn(
                _layers.satellite ? Icons.satellite_alt : Icons.map_outlined,
                _layers.satellite ? '卫星图' : '路网图',
                () => setState(() => _layers.satellite = !_layers.satellite)),
            const SizedBox(height: 8),
            _roundBtn(Icons.add, '放大',
                () => _mapController.move(_mapController.center, _zoom + 1)),
            const SizedBox(height: 8),
            _roundBtn(Icons.remove, '缩小',
                () => _mapController.move(_mapController.center, _zoom - 1)),
            const SizedBox(height: 8),
            _roundBtn(Icons.my_location, '定位', () => _locate()),
            const SizedBox(height: 8),
            _roundBtn(Icons.layers_outlined, '图层', _showLayerPanel),
          ]),
        ),

        // ---------------- 底部：统计 + AI（嵌入模式由钓点页承担）----------------
        if (!widget.embedded)
          Positioned(
            left: 12,
            right: 12,
            bottom: bottomInset + 14,
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: _statCard(Icons.water, '${_waters.length}', '水域'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(Icons.place, '${_spots.length}', '钓点'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(Icons.pets, _catchCount > 0 ? '$_catchCount' : '—', '渔获'),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _aiLoading ? null : _aiFindSpots,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _aiLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome, size: 20),
                  label: Text(_aiLoading ? 'AI 分析中…' : 'AI 找钓点',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_tile.attribution} · 禁钓数据据政府公开通告整理（2026-10）',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ]),
          ),

        // ---------------- 嵌入模式：AI 胶囊 + 版权行 ----------------
        //
        // ★★ 位置和样式按原生内核（spot_map_gl.dart）来：
        //   AI 胶囊 bottom=88（给底部「+」发布按钮和导航栏让位），
        //   版权行 bottom=6、单行省略、半透明黑字。
        //   原来这里是「bottom=10 + 白色带阴影两行文字」，降级后既压住
        //   底部导航，颜色也从黑变白，看起来像换了个页面。
        if (widget.embedded) ...[
          Positioned(
            left: 0,
            right: 0,
            bottom: 88,
            child: _aiCapsule(),
          ),
          Positioned(
            left: 10,
            bottom: 6,
            right: 90,
            child: IgnorePointer(
              child: Text(
                '${_tile.attribution} · 禁钓数据据政府公开通告整理（2026-10）',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: Color(0x99000000)),
              ),
            ),
          ),
        ],

        // ---------------- 选中详情 ----------------
        if (_selWater != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: widget.embedded ? 132 : bottomInset + 14,
            child: _selectedWaterCard(_selWater!),
          ),
        if (_selZone != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: widget.embedded ? 132 : bottomInset + 14,
            child: _selectedZoneCard(_selZone!),
          ),

        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
                minHeight: 2.5, color: AppTheme.primary),
          ),
      ]),
    );
  }

  Widget _selectedWaterCard(WaterBody w) {
    final d = (_myLat != null && _myLng != null)
        ? CoordTransform.distanceMeters(
            _myLat!, _myLng!, w.center.latitude, w.center.longitude)
        : null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AppTheme.accentLight,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.water, color: AppTheme.accentDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                    d != null
                        ? '${w.subLabel} · 距我约 ${CoordTransform.formatDistance(d)}'
                        : w.subLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showWaterSheet(w),
            child: const Text('详情'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _selWater = null),
          ),
        ]),
      ),
    );
  }

  Widget _selectedZoneCard(NoFishingZone z) {
    final st = z.statusNow();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AppTheme.dangerLight,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.block, color: AppTheme.danger),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_shortZoneName(z.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${st.label} · ${z.period}',
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showZoneSheet(z),
            child: const Text('规定'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _selZone = null),
          ),
        ]),
      ),
    );
  }

  /// AI 找钓点胶囊（参考 App 的深色圆角胶囊 + 绿色星光图标）
  Widget _aiCapsule() {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: _aiLoading ? null : _aiFindSpots,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xE6101A12),
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38,
                    blurRadius: 10,
                    offset: Offset(0, 3))
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppTheme.inkHi,
                  shape: BoxShape.circle,
                ),
                child: _aiLoading
                    ? const Padding(
                        padding: EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF101A12)),
                      )
                    : const Icon(Icons.auto_awesome,
                        size: 14, color: Color(0xFF101A12)),
              ),
              const SizedBox(width: 8),
              Text(_aiLoading ? '分析中…' : 'AI 找钓点',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(width: 6),
              const Text('AI SPOT',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppTheme.inkHi)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: AppTheme.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ]),
    );
  }

  // ------------------------------------------------------------ 搜索结果

  Widget _searchResults() {
    final q = _searchCtrl.text.trim();
    final hits = <_SearchHit>[];
    for (final w in _waters) {
      if (w.name.contains(q) || w.basin.contains(q)) {
        hits.add(_SearchHit(
            title: w.name,
            sub: w.isRiver ? '江河 · ${w.basin}' : '${w.kindLabel} · ${w.area}',
            icon: Icons.water,
            color: AppTheme.accent,
            onTap: () {
              _exitSearch();
              final g = CoordTransform.wgs84ToGcj02(
                  w.center.latitude, w.center.longitude);
              _mapController.move(LatLng(g[0], g[1]), 9.5);
              setState(() => _selWater = w);
            }));
      }
    }
    for (final z in _zones.zones) {
      if (z.name.contains(q) || z.region.contains(q)) {
        hits.add(_SearchHit(
            title: z.name,
            sub: '${z.kindLabel} · ${z.region}',
            icon: Icons.block,
            color: AppTheme.danger,
            onTap: () {
              _exitSearch();
              if (z.onMap && z.center != null) {
                final g = CoordTransform.wgs84ToGcj02(
                    z.center!.latitude, z.center!.longitude);
                _mapController.move(LatLng(g[0], g[1]), 8);
              }
              setState(() => _selZone = z);
            }));
      }
    }
    for (final s in _spots) {
      if (s.name.contains(q) || s.address.contains(q)) {
        hits.add(_SearchHit(
            title: s.name,
            sub: s.kindLabel,
            icon: Icons.place,
            color: AppTheme.primary,
            onTap: () {
              _exitSearch();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SpotDetailScreen(spot: s)));
            }));
      }
    }
    final list = hits.take(20).toList();
    if (list.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: const Text('没有找到相关内容',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 52),
        itemBuilder: (_, i) {
          final h = list[i];
          return ListTile(
            dense: true,
            leading: Icon(h.icon, color: h.color, size: 20),
            title: Text(h.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(h.sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            onTap: h.onTap,
          );
        },
      ),
    );
  }
}

class _SearchHit {
  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SearchHit(
      {required this.title,
      required this.sub,
      required this.icon,
      required this.color,
      required this.onTap});
}

/// AI 找钓点结果面板
class _AiSheet extends StatelessWidget {
  final AiSpotRec rec;
  final void Function(String name) onPick;
  const _AiSheet({required this.rec, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
          const SizedBox(width: 6),
          const Text('AI 找钓点',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (!rec.ok)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('AI 未配置',
                  style: TextStyle(
                      fontSize: 10.5, color: AppTheme.warning)),
            ),
        ]),
        const SizedBox(height: 8),
        if (rec.summary.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(rec.summary,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textPrimary,
                    height: 1.5)),
          ),
        const SizedBox(height: 8),
        if (rec.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('暂无推荐结果：请到后台「运营配置 → AI 设置」配置模型后重试',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
          ),
        for (final it in rec.items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10)),
                child: Center(
                  child: Text('${it.score.round()}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(it.reason,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                            height: 1.45)),
                    if (it.bait.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('建议：${it.bait}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onPick(it.name);
                },
                child: const Text('去看看'),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        const Text('AI 建议结合逐时天气与鱼种习性生成，仅供参考，请注意安全并遵守当地禁钓规定',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
      ]),
    );
  }
}

/// 地图中心十字星（参考 App「地图设置 → 中心十字星」图层）
class _CrosshairOverlay extends StatelessWidget {
  const _CrosshairOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CustomPaint(painter: _CrosshairPainter()),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = const Color(0xCC1E88E5)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    const r = 13.0;
    canvas.drawCircle(c, r, p);
    canvas.drawLine(Offset(c.dx - r - 6, c.dy), Offset(c.dx - r + 1, c.dy), p);
    canvas.drawLine(Offset(c.dx + r - 1, c.dy), Offset(c.dx + r + 6, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r - 6), Offset(c.dx, c.dy - r + 1), p);
    canvas.drawLine(Offset(c.dx, c.dy + r - 1), Offset(c.dx, c.dy + r + 6), p);
    canvas.drawCircle(c, 1.6, Paint()..color = const Color(0xCC1E88E5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
