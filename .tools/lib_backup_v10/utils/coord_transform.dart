import 'dart:math' as math;

/// 坐标系转换工具
///
/// 背景：高德/腾讯卫星瓦片使用 GCJ-02 火星坐标系，
/// 而手机 GPS（geolocator）在国内通常返回 WGS-84 坐标，
/// 两者在中国境内有 50~500 米偏移。把 WGS-84 钓点直接画到
/// 高德卫星图上会整体偏掉，因此显示前必须转换。
///
/// 数据存储统一用 WGS-84（后端/详情页回显），
/// 仅在高德瓦片上叠加 marker 前转成 GCJ-02。
class CoordTransform {
  const CoordTransform._();

  static const double _pi = math.pi;
  static const double _a = 6378245.0; // 克拉索夫斯基椭球长半轴
  static const double _ee = 0.00669342162296594323; // 偏心率平方

  static double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (160.0 * math.sin(y / 12.0 * _pi) + 320 * math.sin(y * _pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * _pi) + 300.0 * math.sin(x / 30.0 * _pi)) * 2.0 / 3.0;
    return ret;
  }

  static bool _outOfChina(double lat, double lng) {
    return lat < 0.8333 || lat > 55.0167 || lng < 72.004 || lng > 137.8347;
  }

  /// WGS-84（GPS 原始坐标）→ GCJ-02（高德/腾讯地图坐标）
  /// 返回 [lat, lng]；境外坐标原样返回
  static List<double> wgs84ToGcj02(double lat, double lng) {
    if (_outOfChina(lat, lng)) return [lat, lng];
    var dLat = _transformLat(lng - 105.0, lat - 35.0);
    var dLng = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * _pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * _pi);
    return [lat + dLat, lng + dLng];
  }

  /// GCJ-02 → WGS-84（粗略反向：迭代修正，用于把高德上拾取的坐标存回 WGS-84）
  static List<double> gcj02ToWgs84(double lat, double lng) {
    if (_outOfChina(lat, lng)) return [lat, lng];
    var lat0 = lat, lng0 = lng;
    for (var i = 0; i < 5; i++) {
      final g = wgs84ToGcj02(lat0, lng0);
      lat0 += lat - g[0];
      lng0 += lng - g[1];
    }
    return [lat0, lng0];
  }

  /// 两个 WGS-84 坐标间的地表距离（米，Haversine）
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // 地球半径（米）
    final dLat = (lat2 - lat1) * _pi / 180.0;
    final dLng = (lng2 - lng1) * _pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * _pi / 180.0) *
            math.cos(lat2 * _pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// 距离的人性化显示：<1km 用米，否则用公里
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}
