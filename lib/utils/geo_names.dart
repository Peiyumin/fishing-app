import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart' show LocationAccuracy;

import '../services/location_service.dart';

/// 逆地编码：经纬度 → 中文地址 / 地级市名
///
/// 使用 BigDataCloud 免费客户端接口（免 Key、无配额限制、国内可达）。
/// 不用 Nominatim：国内 DNS 污染严重（解析到无关 IP，请求必然超时）。
class GeoNames {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  static String? _cachedCity;
  static String? _cachedAddress;

  /// 当前定位的地级市名（如「武汉市」「杭州市」）。
  /// 同城 Tab 依据；成功后进程内缓存，避免反复请求。
  static Future<String?> currentCity() async {
    if (_cachedCity != null) return _cachedCity;
    try {
      final pos = await LocationService.determinePosition(
          accuracy: LocationAccuracy.medium);
      final r = await reverse(pos.latitude, pos.longitude);
      final city = r?['city'] as String?;
      if (city != null && city.isNotEmpty) {
        _cachedCity = city;
        return _cachedCity;
      }
    } catch (_) {}
    return null;
  }

  /// 当前定位的中文详细地址（如「湖北省武汉市洪山区狮子山街道…」），进程内缓存。
  static Future<String?> currentAddress() async {
    if (_cachedAddress != null) return _cachedAddress;
    try {
      final pos = await LocationService.determinePosition(
          accuracy: LocationAccuracy.high);
      final r = await reverse(pos.latitude, pos.longitude);
      final display = r?['display'] as String?;
      if (display != null && display.isNotEmpty) {
        _cachedAddress = display;
        return _cachedAddress;
      }
    } catch (_) {}
    return null;
  }

  /// BigDataCloud 逆地编码。
  /// 返回：
  ///   { city: 武汉市, display: 湖北省武汉市洪山区狮子山街道… }
  /// 失败返回 null（调用方自行降级）。
  static Future<Map<String, dynamic>?> reverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client'
          '?latitude=$lat&longitude=$lng&localityLanguage=zh');
      final req = await _http.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await res.transform(utf8.decoder).join());
      if (json is! Map) return null;

      // 地级市：city 字段就是行政区划里的地级市（如 武汉市）
      final city = (json['city'] ?? '').toString();

      // 详细地址：从行政层级里取 省(4) → 市(5) → 区县(6) → 街道(8) 拼接
      String display = '';
      final admin = json['localityInfo']?['administrative'];
      if (admin is List) {
        final parts = <String>[];
        for (final a in admin) {
          if (a is! Map) continue;
          final level = (a['adminLevel'] as num?)?.toInt() ?? 0;
          final name = (a['name'] ?? '').toString().trim();
          // 跳过国家(2)；层级 4/5/6/8 = 省/市/区县/街道
          if (level == 4 || level == 5 || level == 6 || level == 8) {
            if (name.isNotEmpty &&
                name != 'None' &&
                (parts.isEmpty || parts.last != name)) {
              parts.add(name);
            }
          }
        }
        display = parts.join('');
      }
      // 兜底：直接用 locality（区县级）
      if (display.isEmpty) display = (json['locality'] ?? '').toString();

      return {'city': city, 'display': display};
    } catch (_) {
      return null;
    }
  }

  /// 清除缓存（手动刷新定位时用）
  static void clearCache() {
    _cachedCity = null;
    _cachedAddress = null;
  }
}
