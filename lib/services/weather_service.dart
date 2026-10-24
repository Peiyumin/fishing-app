import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fishing_species.dart';
import '../models/weather_forecast.dart';

/// 钓鱼天气服务
/// 数据源：Open-Meteo 免费接口（无需 API Key）
///
/// 关键设计：
///  1. **双模型集合**：同时取 ECMWF/GFS 混合的 best_match 与
///     中国气象局 GRAPES（cma_grapes_global），气温与气压各取一半。
///     单模型夜间可偏差 3℃ 以上（实测同时刻 GFS 16.8 / ECMWF 15.4 / CMA 13.7），
///     等权平均能明显压掉这种系统偏差，也更贴近国内天气软件的口径。
///  2. **统一「当前值」口径**：当前气温/气压一律取逐时集合里最接近现在的那一小时，
///     保证首页卡、天气页顶部、AI 弹层与逐时表看到的是同一个数。
///  3. 每次成功拉取写本地缓存，20 分钟内有效；过期即视为无缓存，强制刷新，
///     避免重新打开 App 时显示几小时前的旧实况。
class WeatherService {
  static const String _base = 'https://api.open-meteo.com/v1/forecast';

  /// 复用同一个连接（省掉每次 TLS 握手，冷启动快 200~400ms）
  static final http.Client _client = http.Client();

  /// 单次请求上限：超时就走缓存兜底，绝不让页面一直转圈
  static const Duration _timeout = Duration(seconds: 8);

  static const String _curCacheKey = 'wx_current_v1';
  static const String _fcCacheKey = 'wx_forecast_v1';

  /// 缓存有效期（分钟）：超过则视为过期，强制重新拉取，避免显示过时实况。
  static const int _cacheTtlMinutes = 20;

  /// 缓存是否仍在有效期内（20 分钟内）。无效 / 缺时间戳一律视为过期。
  static bool _isFresh(Map<String, dynamic> m) {
    final ts = m['ts'];
    if (ts is! int) return false;
    final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
    return ageMs <= _cacheTtlMinutes * 60 * 1000;
  }

  /// 测试专用：非空时替代真实的网络拉取，避免测试环境联网超时。
  static Future<WeatherBundle> Function(double lat, double lng)?
      testForecastOverride;

  /// 第二模型（中国气象局 GRAPES）逐时温压序列。
  /// 拿不到时返回 null，主流程自动退化为单模型，不影响可用性。
  static Future<Map<String, dynamic>?> _fetchCma(
    double lat,
    double lng, {
    int days = 7,
  }) async {
    try {
      final uri = Uri.parse(
        '$_base?latitude=$lat&longitude=$lng'
        '&hourly=temperature_2m,pressure_msl'
        '&models=cma_grapes_global'
        '&forecast_days=$days&timezone=auto',
      );
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 拉取当前天气（成功后写缓存）
  ///
  /// `cloud_cover` 与 `precipitation` 是校正天气现象的关键：
  /// 全球模式常在「实际没下雨」时也给 drizzle 代码，只看 weather_code 会把
  /// 晴天报成「小毛雨」。用实测降水量 + 云量回推天气现象，才与中央气象台一致。
  static Future<FishingWeather> fetch(double lat, double lng) async {
    // ★★ 与天气页共用同一个 7 天 bundle（v2.1.21）
    //
    //   以前这里单独发一次 `forecast_days=1` 的请求，于是首页和天气页拿到的是
    //   **两份不同的逐时序列**（不同请求、不同天数）：
    //     · 同一小时的湿度 / 风速在两次请求里可能差一点；
    //     · 更关键的是水温 —— WaterMetrics 的热惯性模型吃的是"过去若干小时"
    //       的序列，24 小时 vs 168 小时算出来的水温不同，垂钓指数跟着差好几分。
    //   用户把首页「垂钓指数 82」和天气页「74」一对照，就认定数据错了。
    //   现在只保留一个数据源：一次 7 天请求 → 首页和天气页都从它派生。
    final bundle = await fetchForecast(lat, lng);
    final w = FishingWeather.fromBundle(bundle);
    await _saveCache(_curCacheKey, {
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'w': w.toJson(),
    });
    return w;
  }

  /// 读当前天气缓存（无缓存 / 解析失败 / 已过期返回 null）
  static Future<FishingWeather?> readCachedCurrent({bool allowStale = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_curCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!allowStale && !_isFresh(m)) return null; // 过期缓存不返回，触发重新拉取
      final w = m['w'];
      if (w is! Map) return null;
      return FishingWeather.fromJson(Map<String, dynamic>.from(w));
    } catch (_) {
      return null;
    }
  }

  /// 读 7 天预报缓存（无缓存返回 null）
  static Future<WeatherBundle?> readCachedForecast({bool allowStale = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_fcCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!allowStale && !_isFresh(m)) return null; // 过期缓存不返回，触发重新拉取
      final j = m['json'];
      if (j is! Map) return null;
      final lat = (m['lat'] as num?)?.toDouble() ?? 0;
      final lng = (m['lng'] as num?)?.toDouble() ?? 0;
      final cma = m['cma'];
      return WeatherBundle.fromOpenMeteo(
        lat,
        lng,
        Map<String, dynamic>.from(j),
        ensembleJson:
            cma is Map ? Map<String, dynamic>.from(cma) : null,
      );
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
    if (testForecastOverride != null) {
      return testForecastOverride!(lat, lng);
    }
    final cmaF = _fetchCma(lat, lng);
    final uri = Uri.parse(
      '$_base?latitude=$lat&longitude=$lng'
      '&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,'
      'precipitation_probability,'
      'wind_speed_10m,wind_direction_10m,pressure_msl'
      '&hourly=temperature_2m,relative_humidity_2m,precipitation,'
      'precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m,'
      'pressure_msl,uv_index,cloud_cover'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,'
      'precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,'
      'uv_index_max,sunrise,sunset'
      '&timezone=auto&forecast_days=7',
    );
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('天气获取失败：${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final cma = await cmaF;
    final bundle = WeatherBundle.fromOpenMeteo(lat, lng, json,
        ensembleJson: cma);
    await _saveCache(_fcCacheKey, {
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'json': json,
      'cma': cma,
    });
    return bundle;
  }

  /// 读上次缓存里的坐标（不看有效期）
  ///
  /// 用途：天气页可以「先用上次的坐标立刻拉一次」，不必干等 GPS。
  /// 定位回来后如果差得远，再补一次请求。
  static Future<(double, double)?> readCachedLocation() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_fcCacheKey) ?? sp.getString(_curCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final lat = m['lat'];
      final lng = m['lng'];
      if (lat is num && lng is num) return (lat.toDouble(), lng.toDouble());
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// 首页 / 水印相机用的精简实况
class FishingWeather {
  final double temperature; // ℃
  final int humidity; // %
  final double windSpeed; // km/h
  final double pressure; // hPa（海平面气压）
  final int weatherCode; // WMO 天气代码
  final String description; // 天气文字
  final String fishIndex; // 爆护 / 有口 / 口弱 / 难开口
  final String fishAdvice; // 一句话建议

  /// 垂钓指数（0-100）：与天气页同一个引擎（Bite.score）、同一小时算出来，
  /// 首页直接显示这个数，不再自己另算一套，否则两页分数会互相打脸。
  final int score;

  /// 这组数据对应的整点，如 "13:00"；为空表示没有逐时数据
  final String atLabel;

  const FishingWeather({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.pressure,
    required this.weatherCode,
    required this.description,
    required this.fishIndex,
    required this.fishAdvice,
    this.score = 50,
    this.atLabel = '',
  });

  /// 由完整天气包构造。
  ///
  /// ★ 时段统一（v2.1.19）：这里的气温 / 湿度 / 风 / 气压 / 天气现象 /
  ///   垂钓指数，全部取自「与现在绝对时间最近的那一个整点」，
  ///   和天气页顶部卡、逐时表里标「现在」的那一行是同一组数字。
  factory FishingWeather.fromBundle(WeatherBundle b) {
    final now = DateTime.now();
    // ★ 用「当前所在的那一小时」（20:35 → 20:00），不是"绝对最近"
    //   （20:35 会挑到 21:00 那个还没到的时段）。天气页顶部卡用的是同一个函数，
    //   两处必须一致，否则同一时刻会显示两个时段。
    final i = b.indexOfCurrentHour(now);
    final h = i >= 0 ? b.hours[i] : null;
    // 与天气页同源的水温/水氧（热惯性模型），保证两页指数可对齐
    final metrics = WaterMetrics.derive(b.hours);
    final w = i >= 0 && i < metrics.length
        ? metrics[i]
        : WaterMetrics((b.curTemp * 0.8 + 4).clamp(2.0, 32.0), 7.0);

    final mode = FishingMode.all.first;
    final sp = FishingSpecies.all.first; // 默认目标鱼：鲫鱼

    final est = h != null
        ? Bite.compute(h: h, w: w, sp: sp, mode: mode)
        : FishScore.computeRaw(
            method: mode.name,
            airTemp: b.curTemp,
            pressure: b.curPressure,
            windMs: b.curWindSpeed / 3.6,
            waterTemp: w.temp,
            dissolvedOxygen: w.oxygen,
            weatherCode: b.curCode,
            precipProb: b.curPrecipProb,
            hour: now.hour,
            dayRange: b.today.tempRange,
            sp: sp,
          );
    final score = est.indexScore ?? 50;

    return FishingWeather(
      temperature: h?.temp ?? b.curTemp,
      humidity: h?.humidity ?? b.curHumidity,
      windSpeed: h?.windSpeed ?? b.curWindSpeed,
      pressure: h?.pressure ?? b.curPressure,
      weatherCode: h?.weatherCode ?? b.curCode,
      description: FishingWeather._wmoText(h?.weatherCode ?? b.curCode),
      fishIndex: Bite.label(score),
      fishAdvice: score >= 80
          ? '${est.positives.isEmpty ? '条件不错' : est.positives.first}，可以出钓'
          : (score >= 45
              ? '${est.negatives.isEmpty ? '条件一般' : est.negatives.first}，放低预期主攻早晚'
              : '${est.negatives.isEmpty ? '条件较差' : est.negatives.first}，建议改期'),
      score: score,
      atLabel: h == null
          ? ''
          : '${h.time.hour.toString().padLeft(2, '0')}:00',
    );
  }

  Map<String, dynamic> toJson() => {
        't': temperature,
        'h': humidity,
        'ws': windSpeed,
        'p': pressure,
        'c': weatherCode,
        'd': description,
        'fi': fishIndex,
        'fa': fishAdvice,
        'sc': score,
        'al': atLabel,
      };

  factory FishingWeather.fromJson(Map<String, dynamic> m) => FishingWeather(
        temperature: (m['t'] as num?)?.toDouble() ?? 0,
        humidity: (m['h'] as num?)?.round() ?? 0,
        windSpeed: (m['ws'] as num?)?.toDouble() ?? 0,
        pressure: (m['p'] as num?)?.toDouble() ?? 0,
        weatherCode: (m['c'] as num?)?.round() ?? 0,
        description: (m['d'] ?? '').toString(),
        fishIndex: (m['fi'] ?? '').toString(),
        fishAdvice: (m['fa'] ?? '').toString(),
        score: (m['sc'] as num?)?.round() ?? 50,
        atLabel: (m['al'] ?? '').toString(),
      );

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
