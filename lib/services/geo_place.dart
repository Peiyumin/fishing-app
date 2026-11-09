import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart' show LocationAccuracy;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'location_service.dart';
import '../utils/text_safe.dart';
import '../utils/json_num.dart';
import '../utils/zh_hans.dart';

/// 中文地名（由经纬度反查得到）
///
/// 字段含义（以河南禹州为例）：
///   province 河南省 / city 许昌市 / district 禹州市 / street 钧台街道
///   short    禹州（首页顶部那种窄位置只显示这一个词）
///   display  河南省许昌市禹州市钧台街道（详情页/发布页显示完整地址）
class GeoPlace {
  final String province;
  final String city;
  final String district;
  final String street;
  final String short;
  final String display;

  const GeoPlace({
    this.province = '',
    this.city = '',
    this.district = '',
    this.street = '',
    this.short = '',
    this.display = '',
  });

  static const GeoPlace empty = GeoPlace();

  bool get isEmpty => display.isEmpty && short.isEmpty;

  /// 最合适的「一句地址」：有完整地址用完整地址，否则用短名兜底
  String get bestAddress => display.isNotEmpty ? display : short;

  /// 首页顶部显示词：优先区县（禹州），其次地级市（许昌），最后省
  String get label => short.isNotEmpty
      ? short
      : (city.isNotEmpty ? city : (province.isNotEmpty ? province : ''));

  Map<String, dynamic> toJson() => {
        'province': province,
        'city': city,
        'district': district,
        'street': street,
        'short': short,
        'display': display,
      };

  /// ★ 全部字段过 [safeText]：地名来自第三方地名接口，偶发把 UTF-8 从
  ///   中间截断（如「禹州市」截成「禹州\uFFFD」），不净化就会在首页顶部
  ///   的定位胶囊里显示成一个小方块。
  ///
  /// ★ v2.1.89：再统一过一遍 [ZhHans.toSimplified]。第三方地名库对部分
  ///   县市返回繁体（湖南「漢壽縣」），后端 `/geo/reverse` 也是同一套数据。
  ///   在这里做唯一出口，缓存里的旧值、后端返回、直连兜底三条路一起治。
  factory GeoPlace.fromJson(Map<String, dynamic> j) => GeoPlace(
        province: _cn(j['province']),
        city: _cn(j['city']),
        district: _cn(j['district']),
        street: _cn(j['street']),
        short: _cn(j['short']),
        display: _cn(j['display']),
      );

  /// 净化 + 转简体（顺序不能反：先修掉半截 UTF-8，再逐字换简体）
  static String _cn(Object? v) => ZhHans.toSimplified(safeText(v));

  // ── 缓存 ──
  static const String _cacheKey = 'geo_place_v1';
  static const String _cacheTimeKey = 'geo_place_v1_at';
  static const Duration _cacheTtl = Duration(hours: 12);

  static GeoPlace? _memo;

  /// 内存里已有的地名（没解析过就是 null）
  ///
  /// 首页 initState 用它**同步**取值：启动页阶段已经 [warmUp] 过，
  /// 首帧就能把地址画出来，不用等一次 await 后再 setState 补一帧。
  static GeoPlace? get memo => _memo;

  /// 启动页阶段预热：只读本地缓存（12h 内有效），不碰 GPS、不联网
  ///
  /// ★ 为什么要在启动页做：用户的要求是「进首页定位地址就要显示出来」。
  ///   以前首页 initState 里 `_loadPlace()` 才去读缓存，读盘是异步的，
  ///   首帧地名是空的，要过一两帧才蹦出来。
  static Future<void> warmUp() async {
    if (_memo != null && !_memo!.isEmpty) return;
    try {
      final cached = await _readCache();
      if (cached != null) _memo = cached;
    } catch (_) {
      // 预热失败不影响启动，首页仍会自己再试一次
    }
  }

  /// 当前定位的地名（进程内缓存 + 本地磁盘缓存 12 小时）
  ///
  /// [refresh] 为 true 时忽略缓存重新解析（用户手动点定位时用）。
  static Future<GeoPlace?> current({bool refresh = false}) async {
    if (!refresh && _memo != null && !_memo!.isEmpty) return _memo;

    if (!refresh) {
      final cached = await _readCache();
      if (cached != null) {
        _memo = cached;
        return cached;
      }
    }

    try {
      final pos = await LocationService.determinePosition(
          accuracy: LocationAccuracy.medium);
      final place = await reverse(pos.latitude, pos.longitude);
      if (place != null && !place.isEmpty) {
        _memo = place;
        await _writeCache(place);
        return place;
      }
      return _memo;
    } on LocationException {
      // 没有定位权限时，退回上次缓存的地名（首页仍能显示城市名）
      return _memo ?? await _readCache();
    } catch (_) {
      return _memo ?? await _readCache();
    }
  }

  /// 经纬度 → 中文地名
  ///
  /// 优先问自己的后端（服务器在国内、有库级缓存，稳定且快），
  /// 后端不可用时直连 BigDataCloud 兜底。
  static Future<GeoPlace?> reverse(double lat, double lng) async {
    // ① 自建后端
    if (ApiConfig.enabled) {
      try {
        final data = await ApiClient.get('/geo/reverse', {
          'lat': lat.toStringAsFixed(6),
          'lng': lng.toStringAsFixed(6),
        });
        if (data is Map) {
          final p = GeoPlace.fromJson(Map<String, dynamic>.from(data));
          if (!p.isEmpty) return p;
        }
      } catch (_) {
        // 落到直连
      }
    }
    // ② 直连 BigDataCloud
    return _reverseDirect(lat, lng);
  }

  /// 直连 BigDataCloud（免 Key）；解析规则与后端保持一致
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6);

  static Future<GeoPlace?> _reverseDirect(double lat, double lng) async {
    try {
      // ★ localityLanguage 必须是 **zh-Hans**：传 `zh` 时这套库对部分县市
      //   会回繁体（实测湖南汉寿：`zh` → 漢壽縣，`zh-Hans` → 汉寿县，
      //   `zh-CN` 也仍是繁体）。后端那边还是 `zh`，所以显示前另有
      //   [ZhHans] 兜底，两处都要。
      final uri = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client'
          '?latitude=$lat&longitude=$lng&localityLanguage=zh-Hans');
      final req = await _http.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final raw =
          await res.transform(const Utf8Decoder(allowMalformed: true)).join();
      final j = jsonDecode(raw);
      if (j is! Map) return null;

      // 第三方接口偶尔返回半截 UTF-8 → 解码后是 U+FFFD，一律清掉
      // （再过一遍简体：直连虽然已经要了 zh-Hans，仍可能给繁体）
      final province = _cn(j['principalSubdivision']);
      final city = _cn(j['city']);
      final district = _cn(j['locality']);

      var street = '';
      final admin = j['localityInfo']?['administrative'];
      if (admin is List) {
        for (final a in admin) {
          if (a is! Map) continue;
          if (jsonInt(a['adminLevel']) == 8) {
            final nm = _cn(a['name']);
            if (nm.isNotEmpty && nm.toLowerCase() != 'none') {
              street = nm;
              break;
            }
          }
        }
      }

      final parts = <String>[];
      for (final p in [province, city, district, street]) {
        if (p.isEmpty) continue;
        if (parts.isNotEmpty && parts.last == p) continue;
        parts.add(p);
      }

      String shortName = '';
      if (district.isNotEmpty) {
        shortName = district.replaceFirst(RegExp(r'市$'), '');
      } else if (city.isNotEmpty) {
        shortName = city.replaceFirst(RegExp(r'市$'), '');
      } else {
        shortName = province.replaceFirst(RegExp(r'(省|自治区)$'), '');
      }

      final place = GeoPlace(
        province: province,
        city: city,
        district: district,
        street: street,
        short: shortName,
        display: parts.join(),
      );
      return place.isEmpty ? null : place;
    } catch (_) {
      return null;
    }
  }

  static Future<GeoPlace?> _readCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final at = sp.getInt(_cacheTimeKey) ?? 0;
      if (at == 0) return null;
      if (DateTime.now().millisecondsSinceEpoch - at > _cacheTtl.inMilliseconds) {
        return null;
      }
      final raw = sp.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final p = GeoPlace.fromJson(Map<String, dynamic>.from(j));
      return p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(GeoPlace p) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cacheKey, jsonEncode(p.toJson()));
      await sp.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  /// 清缓存（用户切换城市/手动刷新定位时调用）
  static void clearCache() {
    _memo = null;
    SharedPreferences.getInstance().then((sp) {
      sp.remove(_cacheKey);
      sp.remove(_cacheTimeKey);
    });
  }
}
