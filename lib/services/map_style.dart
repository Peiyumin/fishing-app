import 'map_tile_source.dart';
import 'offline_tiles.dart';

/// 底图样式（MapLibre style JSON）的唯一生成入口
///
/// 从 `spot_map_gl.dart` 里抽出来，是为了能被单测直接验证 —— 样式一旦
/// 拼错（少个 source、层级顺序反了、随包层没接上），在真机上只会表现为
/// 「地图一片灰」，靠肉眼看截图根本分不清是哪一步坏的。
///
/// 图层自下而上：
///   bg        纯底色（瓦片没到时先铺这个，不闪白）
///   sat-low   在线低清概览（z≤8）—— 兜底：万一本机读不了随包瓦片
///   sat-off   随包低清（z≤8，file:// 本机文件）—— **秒出图靠它**
///   sat       在线高清（z9~18，定位点 50km 内）
///   vec       矢量路网（默认关闭）
///   cia       注记（z≥10 才请求）
Map<String, dynamic> buildRasterStyle({
  required TileSource tile,

  /// 把 URL 模板展开成多条（注入 token、拆子域、加后端代理）
  required List<String> Function(String template) urls,

  /// 高清层覆盖范围 [west,south,east,north]；null = 不限制
  List<double>? hdBounds,

  /// 随包瓦片模板（`file://…/{z}/{x}/{y}.webp`）；null = 没有随包底图
  String? offlineTemplate,

  /// 随包瓦片最高层级
  int offlineMaxZoom = OfflineTiles.maxZoom,

  /// 底色（= `_Hex.background`，必须由调用方传入）
  ///
  /// 不在这里写默认值：十六进制字符串只允许出现在地图色表里，
  /// 否则 `theme_palette_test` 抓不到、调色板一改就跟不上。
  required String background,
}) {
  return <String, dynamic>{
    'version': 8,
    'sources': {
      // ---------------- 低清概览层：全球铺底 ----------------
      // 最高只到 z8。z9 以上它靠「放大 z8 瓦片」呈现 ——
      // 这正好就是用户要的「定位点 50km 之外模糊显示」，
      // 而且每屏只多 1~4 块瓦片（一块 z8 抵 256 块 z16），开销可以忽略。
      // ★ 为什么定 z8 而不是 z12：低清层如果太清晰，缩小到 100km 视野时
      //   圈内圈外一样清楚，用户根本看不出「50 公里边界」在哪，
      //   分级加载就成了看不见的摆设。
      //
      // ★ v2.1.89：这一层上面再压一层**随包瓦片**（sat-off）。
      //   在线这层留着当兜底：万一某台机器读不了本机的 file:// 瓦片，
      //   也不至于在 z8 以下纯灰屏。
      'sat-low': {
        'type': 'raster',
        'tiles': urls(tile.satelliteTemplate),
        'tileSize': 256,
        'maxzoom': 8,
        'attribution': tile.attribution,
      },
      if (offlineTemplate != null)
        'sat-off': {
          'type': 'raster',
          'tiles': [offlineTemplate],
          'tileSize': 256,
          'maxzoom': offlineMaxZoom,
          'attribution': tile.attribution,
        },
      // ---------------- 高清层：只在定位点周围 50km ----------------
      // ★ bounds 是这里的关键：MapLibre 文档明确写了
      //   「设了 bounds 之后，范围外的瓦片一律不请求」。
      //   所以高清瓦片只会在那 50km 里被拉下来，范围外由下面的低清层顶住。
      // ★ maxzoom 必须等于瓦片源真实最大级别（星图 18）。
      //   之前相机允许缩放到 22 级，超过 18 后 MapLibre 不再请求新瓦片，
      //   只是把 18 级瓦片放大 16 倍 —— 用户看到的就是「放大后不加载、
      //   一片模糊」。现在相机上限也一起压到 18（见 minMaxZoomPreference）。
      'sat': {
        'type': 'raster',
        'tiles': urls(tile.satelliteTemplate),
        'tileSize': 256,
        // z9 起接管（z9 的视野正好约 100km，能一眼看到 50km 那个圈）
        'minzoom': 9,
        'maxzoom': tile.maxNativeZoom,
        if (hdBounds != null) 'bounds': hdBounds,
      },
      'vec': {
        'type': 'raster',
        'tiles': urls(tile.vectorTemplate),
        'tileSize': 256,
        'maxzoom': tile.maxNativeZoom,
      },
      'cia': {
        'type': 'raster',
        'tiles': urls(tile.labelTemplate),
        'tileSize': 256,
        'maxzoom': tile.maxNativeZoom,
      },
    },
    'layers': [
      {
        'id': 'bg',
        'type': 'background',
        'paint': {'background-color': background},
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
      // 随包瓦片压在在线低清层**上面**：本地读盘是毫秒级，先出图；
      // 在线那层慢半拍盖上来也完全看不出来（同一家影像、同一个层级）。
      if (offlineTemplate != null)
        {
          'id': 'sat-off',
          'type': 'raster',
          'source': 'sat-off',
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
  };
}
