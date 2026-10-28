import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart' show LocationAccuracy;

import '../services/location_service.dart';
import 'json_num.dart';

/// 逆地编码：经纬度 → 中文地址 / 地级市名
///
/// 使用 BigDataCloud 免费客户端接口（免 Key、无配额限制、国内可达）。
/// 不用 Nominatim：国内 DNS 污染严重（解析到无关 IP，请求必然超时）。
class GeoNames {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  static String? _cachedCity;
  static String? _cachedAddress;

  /// 「纬度, 经度」字符串 → 中文地名的进程内缓存（历史动态里存的是坐标，避免重复请求）
  static final Map<String, String> _coordCache = {};

  /// 判断一个定位字符串是否为坐标（如「34.141, 113.461」）
  static bool isCoordinate(String? s) {
    if (s == null) return false;
    final t = s.trim();
    if (t.isEmpty) return false;
    final parts = t.split(RegExp(r'[,，\s]+'));
    if (parts.length != 2) return false;
    final a = double.tryParse(parts[0]);
    final b = double.tryParse(parts[1]);
    if (a == null || b == null) return false;
    return a >= -90 && a <= 90 && b >= -180 && b <= 180;
  }

  /// 把任意定位字符串解析成中文地名（格式「市·区县」，地级市不带「市」字）。
  /// - 已是地名 → 原样返回
  /// - 是坐标「lat, lng」→ 逆地编码；失败降级为坐标原文
  static Future<String> resolveName(String raw) async {
    final t = raw.trim();
    if (!isCoordinate(t)) return t;

    if (_coordCache.containsKey(t)) return _coordCache[t]!;

    final parts = t.split(RegExp(r'[,，\s]+'));
    final lat = double.parse(parts[0]);
    final lng = double.parse(parts[1]);
    final r = await reverse(lat, lng);

    final name = _shortName(r);
    final out = (name.isEmpty) ? t : name;
    if (name.isNotEmpty) _coordCache[t] = out;
    return out;
  }

  /// 坐标 → 「市·区县」短地名（发布页「获取定位」用）
  static Future<String> nameForPosition(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}';
    if (_coordCache.containsKey(key)) return _coordCache[key]!;
    final r = await reverse(lat, lng);
    final name = _shortName(r);
    final out = name.isEmpty ? key : name;
    _coordCache[key] = out;
    return out;
  }

  /// 从 reverse 结果提取「市(去市字)·区县」。
  /// 例：city=许昌市 + locality=禹州市 → 「许昌·禹州市」
  /// 直辖市（city==locality）→ 只输出一次，不重复。
  static String _shortName(Map<String, dynamic>? r) {
    if (r == null) return '';
    final city = (r['city'] ?? '').toString().trim();
    final locality = (r['locality'] ?? '').toString().trim();

    // 直辖市/市辖区：city 与 locality 同名，只留一个并去掉「市」字
    if (city.isNotEmpty && (locality.isEmpty || locality == city)) {
      return _stripCitySuffix(city);
    }
    if (city.isEmpty) {
      // 没有地级市（直辖市区县/海外）→ 只用区县
      return locality;
    }
    return '${_stripCitySuffix(city)}·$locality';
  }

  /// 去掉地级市末尾的「市」字（许昌市 → 许昌）。
  /// 「市辖区」「县级市」等不以「市」结尾的名称原样返回。
  static String _stripCitySuffix(String name) {
    if (name.length <= 1) return name;
    if (!name.endsWith('市')) return name;
    return name.substring(0, name.length - 1);
  }

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
          final level = jsonInt(a['adminLevel']) ?? 0;
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

      return {
        'city': city,
        'display': display,
        'locality': (json['locality'] ?? '').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  /// 清除缓存（手动刷新定位时用）
  static void clearCache() {
    _cachedCity = null;
    _cachedAddress = null;
    _coordCache.clear();
  }
}
