import 'package:latlong2/latlong.dart';

import '../utils/coord_transform.dart';

/// 底图瓦片源
///
/// ------------------------------------------------------------
/// 合规说明（重要）：
///   国内在线底图只能用「腾讯 / 高德 / 百度 / 天地图」四家，
///   星图地球、Mapbox、OSM 等均不在白名单内。
///   用户提到的「星图地球 GS」卫星底图，其官方底图本身就是
///   天地图（参考 App 的版权行写的就是「数据来源-天地图 GS(2025)1508号」），
///   所以这里用 **天地图** 达成完全一致的视觉效果，同时满足合规要求。
///
/// 坐标系差异（最容易踩的坑）：
///   - 高德瓦片：GCJ-02（火星坐标）
///   - 天地图瓦片：CGCS2000 ≈ WGS-84（厘米级差异，可直接叠加）
///   叠加物（钓点/禁钓区/水域）统一按 WGS-84 存储，
///   叠到高德底图上要先转 GCJ-02，叠到天地图上则原样绘制。
class TileSource {
  /// 底图类型
  final TileSourceKind kind;

  /// 天地图密钥（tk）。为空时天地图不可用。
  final String tk;

  const TileSource({required this.kind, this.tk = ''});

  /// 天地图用 subdomain 轮询（t0~t7）突破单域名并发限制
  static const List<String> _tdtSubdomains = [
    '0', '1', '2', '3', '4', '5', '6', '7'
  ];

  /// 底图是否可用
  bool get usable {
    if (kind == TileSourceKind.gaode) return true;
    return tk.trim().isNotEmpty;
  }

  /// 天地图瓦片类型常量
  static const tdtImage = 'img_w'; // 卫星影像
  static const tdtImageLabel = 'cia_w'; // 影像注记
  static const tdtVector = 'vec_w'; // 矢量路网
  static const tdtVectorLabel = 'cva_w'; // 矢量注记

  /// 天地图瓦片 URL 模板
  ///
  /// 注意 y 轴：天地图原点在左上角，y 自上而下递增，与 flutter_map
  /// 默认的 XYZ 规则完全一致，**不能**加 tms:true（否则整图上下颠倒）。
  String _tdtTemplate(String type) {
    return 'https://t{s}.tianditu.gov.cn/DataServer'
        '?T=$type&x={x}&y={y}&l={z}&tk={tk}';
  }

  /// 卫星影像底图 URL 模板
  String get satelliteTemplate {
    switch (kind) {
      case TileSourceKind.tianditu:
        return _tdtTemplate(tdtImage);
      case TileSourceKind.gaode:
        return 'https://webst01.is.autonavi.com/appmaptile'
            '?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=8';
    }
  }

  /// 注记（路网/地名）叠加层 URL 模板
  String get labelTemplate {
    switch (kind) {
      case TileSourceKind.tianditu:
        return _tdtTemplate(tdtImageLabel);
      case TileSourceKind.gaode:
        return 'https://webst01.is.autonavi.com/appmaptile'
            '?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=6';
    }
  }

  /// 矢量（路网）底图 URL 模板
  String get vectorTemplate {
    switch (kind) {
      case TileSourceKind.tianditu:
        return _tdtTemplate(tdtVector);
      case TileSourceKind.gaode:
        return 'https://webst01.is.autonavi.com/appmaptile'
            '?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=7';
    }
  }

  /// 是否需要 TMS y 翻转
  ///
  /// 两家都是标准 Web Mercator（瓦片原点在左上角、y 自上而下递增），
  /// 千万不要开 tms —— 开了会把地图整个上下颠倒。
  /// （天地图官方说明：level n 的瓦片行号从 0 到 2^n-1，原点 (-180°, 90°)）
  bool get needsTms => false;

  /// 天地图子域列表（高德固定单域，返回 null）
  List<String>? get subdomains {
    if (kind == TileSourceKind.tianditu) return _tdtSubdomains;
    return null;
  }

  /// 额外参数注入（天地图需要把 tk 塞进模板）
  Map<String, String> get additionalOptions {
    if (kind == TileSourceKind.tianditu) return {'tk': tk};
    return const {};
  }

  /// 当前底图坐标系是否是 GCJ-02（高德）——决定叠加物要不要纠偏
  bool get isGcj02 => kind == TileSourceKind.gaode;

  /// WGS-84 点 → 当前底图坐标系
  LatLng project(LatLng wgs84) {
    if (!isGcj02) return wgs84;
    final g = CoordTransform.wgs84ToGcj02(wgs84.latitude, wgs84.longitude);
    return LatLng(g[0], g[1]);
  }

  /// WGS-84 点列表 → 当前底图坐标系
  List<LatLng> projectAll(List<LatLng> pts) =>
      isGcj02 ? pts.map(project).toList() : pts;

  /// 底图版权署名（合规要求必须显示）
  String get attribution {
    switch (kind) {
      case TileSourceKind.tianditu:
        return '底图 © 天地图 GS(2025)1508号 · 国家地理信息公共服务平台';
      case TileSourceKind.gaode:
        return '底图 © 高德地图';
    }
  }
}

/// 底图类型
enum TileSourceKind {
  /// 天地图（合规首选，视觉等同参考 App 的「星图地球 GS」）
  tianditu,

  /// 高德（免 key 兜底）
  gaode,
}

/// 地图图层开关状态
///
/// 对应参考 App 的「图层」面板：
///   底图图层 / 地图设置 / 水域图层 / 钓点图层
class MapLayerState {
  /// 卫星底图（关掉 = 矢量路网图）
  bool satellite;

  /// 路网标注叠加层
  bool roadLabels;

  /// 中心十字星
  bool crosshair;

  /// 禁钓区图层
  bool noFishingZones;

  /// 河流图层
  bool rivers;

  /// 湖泊图层
  bool lakes;

  /// 钓点图层
  bool spots;

  /// 水域名称标注
  bool waterLabels;

  MapLayerState({
    this.satellite = true,
    this.roadLabels = true,
    this.crosshair = false,
    this.noFishingZones = true,
    this.rivers = true,
    this.lakes = true,
    this.spots = true,
    this.waterLabels = true,
  });

  MapLayerState copyWith({
    bool? satellite,
    bool? roadLabels,
    bool? crosshair,
    bool? noFishingZones,
    bool? rivers,
    bool? lakes,
    bool? spots,
    bool? waterLabels,
  }) {
    return MapLayerState(
      satellite: satellite ?? this.satellite,
      roadLabels: roadLabels ?? this.roadLabels,
      crosshair: crosshair ?? this.crosshair,
      noFishingZones: noFishingZones ?? this.noFishingZones,
      rivers: rivers ?? this.rivers,
      lakes: lakes ?? this.lakes,
      spots: spots ?? this.spots,
      waterLabels: waterLabels ?? this.waterLabels,
    );
  }
}
