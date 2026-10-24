import 'dart:math' show cos, pi;

/// 地理包围盒工具
///
/// 只做纯计算、不碰地图 SDK —— 这样「50km 圈到底算得对不对」可以放进
/// 普通单元测试，而不是只能上真机看截图才能确认。

/// 以 [lat], [lng] 为心、[km] 公里为半径，算出经纬度包围盒
///
/// 返回 `[west, south, east, north]`，就是 MapLibre / GeoJSON 的
/// `bounds` 顺序（西南角 → 东北角）。
///
/// ★ 经度必须按纬度收缩：同样的经度差，越靠近极地对应的地面距离越短。
///   赤道上 1° 经度 ≈ 111.32km，到 60°N 只剩 ≈ 55.66km。
///   不收缩的话，北纬 60° 的「50km 圈」会被拉成一条窄长条，
///   东西方向实际覆盖到 100km，高清瓦片就白拉了。
///
/// ★ 纬度接近 ±90° 时 cos 趋近 0，会把经度半径炸到无穷大，
///   所以 cos 下限钳在 0.05（约 87°），结果再整体夹回合法经纬度。
List<double> boundsAroundKm(double lat, double lng, double km) {
  const kmPerDegLat = 111.32;
  final dLat = km / kmPerDegLat;
  final cosL = cos(lat * pi / 180).abs().clamp(0.05, 1.0);
  final dLng = (km / (kmPerDegLat * cosL)).clamp(0.0, 179.0);
  return <double>[
    (lng - dLng).clamp(-180.0, 180.0),
    (lat - dLat).clamp(-85.0, 85.0),
    (lng + dLng).clamp(-180.0, 180.0),
    (lat + dLat).clamp(-85.0, 85.0),
  ];
}
