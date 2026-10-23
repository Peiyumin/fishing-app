import 'package:latlong2/latlong.dart';

import '../utils/coord_transform.dart';

/// 底图瓦片源
///
/// ------------------------------------------------------------
/// 三家底图可选，优先级由后台配置决定：
///
///  1. **星图地球（GEOVIS Earth / 星图云）** —— 推荐
///     中科星图数字地球合肥有限公司运营，甲测资字34100640，
///     影像审图号 GS(2026)3166号，商业图源里合规性最完整的一家。
///     全国 0.8m / 重点城市 0.5m，偏远山区乡镇也有数据（高德在野外高层级常无图）。
///     注册即送个人免费额度（1 万次/天），token 直接从控制台拿，
///     **不像天地图 2026-10-01 起要「授权申请」才能调接口**。
///
///  2. **天地图** —— 国家队，但 2026-10-01 起接口改为「授权后调用」，
///     个人自注册已无法直接拿可用 tk，需单位备案审核。
///
///  3. **高德** —— 免 key 兜底，保证地图永远能打开（GCJ-02，需纠偏）。
///
/// 坐标系差异（最容易踩的坑）：
///   - 高德瓦片：GCJ-02（火星坐标）
///   - 星图地球瓦片：CGCS2000 / WGS-84，**未加偏**（这是它的一大优势）
///   - 天地图瓦片：CGCS2000 ≈ WGS-84（厘米级差异，可直接叠加）
///   叠加物（钓点/禁钓区/水域）统一按 WGS-84 存储，
///   叠到高德底图上要先转 GCJ-02，叠到星图地球/天地图上则原样绘制。
class TileSource {
  /// 底图类型
  final TileSourceKind kind;

  /// 天地图密钥（tk）。为空时天地图不可用。
  final String tk;

  /// 星图地球 token。为空时星图地球不可用。
  final String geoToken;

  const TileSource({required this.kind, this.tk = '', this.geoToken = ''});

  /// 天地图用 subdomain 轮询（t0~t7）突破单域名并发限制
  static const List<String> _tdtSubdomains = [
    '0', '1', '2', '3', '4', '5', '6', '7'
  ];

  /// 星图地球只有 tiles1~tiles3 三个域
  static const List<String> _geoSubdomains = ['1', '2', '3'];

  /// 底图是否可用
  bool get usable {
    switch (kind) {
      case TileSourceKind.gaode:
        return true;
      case TileSourceKind.tianditu:
        return tk.trim().isNotEmpty;
      case TileSourceKind.geovisearth:
        return geoToken.trim().isNotEmpty;
    }
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

  /// 星图地球瓦片 URL 模板
  ///
  /// 官方文档：https://open.geovisearth.com/service/qa-assistance/81
  ///   影像  /base/v1/img/{z}/{x}/{y}?format=webp&tmsIds=w&token=xxx
  ///   注记  /base/v1/cia/{z}/{x}/{y}?format=png&tmsIds=w&token=xxx
  ///   矢量  /base/v1/vec/{z}/{x}/{y}?format=png&tmsIds=w&token=xxx
  /// tmsIds=w 表示球面墨卡托（u 为经纬度投影，这里不能用）；
  /// y 轴同样是左上角原点、自上而下递增，所以也不能开 tms。
  String _geoTemplate(String layer, String format) {
    return 'https://tiles{s}.geovisearth.com/base/v1/$layer/{z}/{x}/{y}'
        '?format=$format&tmsIds=w&token={token}';
  }

  /// 卫星影像底图 URL 模板
  String get satelliteTemplate {
    switch (kind) {
      case TileSourceKind.geovisearth:
        return _geoTemplate('img', 'webp');
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
      case TileSourceKind.geovisearth:
        return _geoTemplate('cia', 'png');
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
      case TileSourceKind.geovisearth:
        return _geoTemplate('vec', 'png');
      case TileSourceKind.tianditu:
        return _tdtTemplate(tdtVector);
      case TileSourceKind.gaode:
        return 'https://webst01.is.autonavi.com/appmaptile'
            '?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=7';
    }
  }

  /// 是否需要 TMS y 翻转
  ///
  /// 三家都是标准 Web Mercator（瓦片原点在左上角、y 自上而下递增），
  /// 千万不要开 tms —— 开了会把地图整个上下颠倒。
  /// （天地图官方说明：level n 的瓦片行号从 0 到 2^n-1，原点 (-180°, 90°)）
  bool get needsTms => false;

  /// 子域列表（高德固定单域，返回 null）
  List<String>? get subdomains {
    switch (kind) {
      case TileSourceKind.tianditu:
        return _tdtSubdomains;
      case TileSourceKind.geovisearth:
        return _geoSubdomains;
      case TileSourceKind.gaode:
        return null;
    }
  }

  /// 额外参数注入（密钥塞进 URL 模板的占位符）
  Map<String, String> get additionalOptions {
    switch (kind) {
      case TileSourceKind.tianditu:
        return {'tk': tk};
      case TileSourceKind.geovisearth:
        return {'token': geoToken};
      case TileSourceKind.gaode:
        return const {};
    }
  }

  /// 底图最大缩放级别
  ///
  /// 星图地球影像：13 级全球、14~18 级中国大陆（再放大就没瓦片了）；
  /// 天地图/高德给到 18 级足够钓点场景使用。
  double get maxZoom => 18;

  /// 瓦片服务真实可用的最大层级（TileLayer.maxNativeZoom 要 int）
  int get maxNativeZoom => maxZoom.toInt();

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
      case TileSourceKind.geovisearth:
        return '底图 © 星图地球 甲测资字34100640 · GS(2026)3166号';
      case TileSourceKind.tianditu:
        return '底图 © 天地图 GS(2025)1508号 · 国家地理信息公共服务平台';
      case TileSourceKind.gaode:
        return '底图 © 高德地图';
    }
  }

  /// 底图短名（图层面板里显示用）
  String get shortName {
    switch (kind) {
      case TileSourceKind.geovisearth:
        return '星图地球';
      case TileSourceKind.tianditu:
        return '天地图';
      case TileSourceKind.gaode:
        return '高德';
    }
  }

  /// 当前底图说明（图层面板底部小字）
  String get describe {
    switch (kind) {
      case TileSourceKind.geovisearth:
        return '当前底图：星图地球（GS(2026)3166号 中科星图数字地球）';
      case TileSourceKind.tianditu:
        return '当前底图：天地图（GS(2025)1508号 国家地理信息公共服务平台）';
      case TileSourceKind.gaode:
        return '当前底图：高德地图（未配置星图/天地图密钥时的兜底）';
    }
  }
}

/// 底图类型
enum TileSourceKind {
  /// 星图地球 / 星图云（推荐：注册即用，未加偏，野外覆盖好）
  geovisearth,

  /// 天地图（2026-10-01 起接口需授权，个人注册已不可直接调用）
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
