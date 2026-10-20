import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_forecast.dart';

/// 钓鱼天气服务
/// 使用 Open-Meteo 免费接口（无需 API Key）：实时气温、湿度、风速、气压
/// 并基于气象数据给出一个简单的「垂钓适宜指数」
///
/// 关键设计：本服务把每次成功拉取的结果写入本地缓存。
/// 首页 / 天气页打开时先读缓存「秒显」上一次的数据，再后台刷新最新值，
/// 网络差或断网时也能看到上次天气，不会白屏或反复转圈。
class WeatherService {
  static const String _base = 'https://api.open-meteo.com/v1/forecast';

  static const String _curCacheKey = 'wx_current_v1';
  static const String _fcCacheKey = 'wx_forecast_v1';

  /// 拉取当前天气（成功后写缓存）
  ///
  /// `cloud_cover` 与 `precipitation` 是校正天气现象的关键：
  /// 全球模式常在「实际没下雨」时也给 drizzle 代码，只看 weather_code 会把
  /// 晴天报成「小毛雨」。用实测降水量 + 云量回推天气现象，才与中央气象台一致。
  static Future<FishingWeather> fetch(double lat, double lng) async {
    final uri = Uri.parse(
      '$_base?latitude=$lat&longitude=$lng'
      '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,pressure_msl,'
      'weather_code,precipitation,cloud_cover',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('天气获取失败：${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = json['current'] as Map<String, dynamic>;
    final w = FishingWeather.fromOpenMeteo(cur);
    await _saveCache(_curCacheKey, {
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'current': cur,
    });
    return w;
  }

  /// 读当前天气缓存（无缓存 / 解析失败返回 null）
  static Future<FishingWeather?> readCachedCurrent() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_curCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final cur = m['current'];
      if (cur is! Map) return null;
      return FishingWeather.fromOpenMeteo(Map<String, dynamic>.from(cur));
    } catch (_) {
      return null;
    }
  }

  /// 读 7 天预报缓存（无缓存返回 null）
  static Future<WeatherBundle?> readCachedForecast() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_fcCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final j = m['json'];
      if (j is! Map) return null;
      final lat = (m['lat'] as num?)?.toDouble() ?? 0;
      final lng = (m['lng'] as num?)?.toDouble() ?? 0;
      return WeatherBundle.fromOpenMeteo(
          lat, lng, Map<String, dynamic>.from(j));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCache(String key, Map<String, dynamic> data) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, jsonEncode(data));
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  /// 拉取 7 天预报 + 逐小时（温度/湿度/气压/降雨概率/降雨量/风/紫外线）
  static Future<WeatherBundle> fetchForecast(double lat, double lng) async {
    final uri = Uri.parse(
      '$_base?latitude=$lat&longitude=$lng'
      '&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,'
      'wind_speed_10m,wind_direction_10m,pressure_msl'
      '&hourly=temperature_2m,relative_humidity_2m,precipitation,'
      'precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m,'
      'pressure_msl,uv_index,cloud_cover'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,'
      'precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,'
      'uv_index_max,sunrise,sunset'
      '&timezone=auto&forecast_days=7',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('天气获取失败：${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final bundle = WeatherBundle.fromOpenMeteo(lat, lng, json);
    await _saveCache(_fcCacheKey, {
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'json': json,
    });
    return bundle;
  }
}

class FishingWeather {
  final double temperature; // ℃
  final int humidity; // %
  final double windSpeed; // km/h
  final double pressure; // hPa
  final int weatherCode; // WMO 天气代码
  final String description; // 天气文字
  final String fishIndex; // 垂钓适宜：极佳 / 良好 / 一般 / 不宜
  final String fishAdvice; // 一句话建议

  const FishingWeather({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.pressure,
    required this.weatherCode,
    required this.description,
    required this.fishIndex,
    required this.fishAdvice,
  });

  factory FishingWeather.fromOpenMeteo(Map<String, dynamic> cur) {
    final temp = (cur['temperature_2m'] as num).toDouble();
    final hum = (cur['relative_humidity_2m'] as num).toInt();
    final wind = (cur['wind_speed_10m'] as num).toDouble();
    final pres = (cur['pressure_msl'] as num).toDouble();
    final rawCode = (cur['weather_code'] as num).toInt();
    final precip = (cur['precipitation'] as num?)?.toDouble() ?? 0;
    final cloud = (cur['cloud_cover'] as num?)?.toDouble();

    // 天气现象校正：没有实测降水时，不采信模式给出的「毛雨/小雨」代码，
    // 改用云量回推（晴 / 少云 / 多云 / 阴），与中央气象台发布的实况一致。
    final code = WeatherCodeFix.adjust(
      code: rawCode,
      precipMm: precip,
      cloudCover: cloud,
    );

    // —— 简化版垂钓适宜指数（生产可接更专业的鱼情模型）——
    // 气压 1005-1025 且 风速 < 20 且 非暴雨/雷暴 → 适宜
    String index;
    String advice;
    if (code >= 95) {
      index = '不宜';
      advice = '雷暴天气，切勿出钓，注意安全';
    } else if (pres >= 1005 && pres <= 1025 && wind < 20) {
      index = '极佳';
      advice = '气压稳定、风小，鱼口活跃，快去爆护';
    } else if (wind < 30) {
      index = '良好';
      advice = '天气尚可，避开迎风口下竿';
    } else {
      index = '一般';
      advice = '风偏大，建议选避风湾子';
    }

    return FishingWeather(
      temperature: temp,
      humidity: hum,
      windSpeed: wind,
      pressure: pres,
      weatherCode: code,
      description: _wmoText(code),
      fishIndex: index,
      fishAdvice: advice,
    );
  }

  // WMO 天气代码 → 中文描述
  static String _wmoText(int code) {
    const map = {
      0: '晴',
      1: '少云',
      2: '多云',
      3: '阴',
      45: '雾',
      48: '雾凇',
      51: '小毛毛雨',
      53: '毛毛雨',
      55: '大毛毛雨',
      61: '小雨',
      63: '中雨',
      65: '大雨',
      71: '小雪',
      73: '中雪',
      75: '大雪',
      80: '阵雨',
      81: '强阵雨',
      82: '暴雨',
      95: '雷暴',
      96: '雷暴伴冰雹',
    };
    return map[code] ?? '未知';
  }
}
