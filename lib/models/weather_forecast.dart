import 'package:flutter/material.dart';

import '../app_theme.dart';

/// ============================================================
/// 天气预报数据模型（对接 Open-Meteo 免费接口，无需 API Key）
/// 支持：7 天日报 + 逐小时（温度/湿度/气压/降雨概率/降雨量/风/紫外线）
/// 并基于气象参数计算「垂钓指数」(0-100)
/// ============================================================

/// WMO 天气代码 → 中文 + 图标（供全 App 复用）
class Wmo {
  static const Map<int, String> _text = {
    0: '晴', 1: '少云', 2: '多云', 3: '阴',
    45: '雾', 48: '雾凇',
    51: '小毛雨', 53: '毛雨', 55: '大毛雨',
    56: '冻毛雨', 57: '强冻毛雨',
    61: '小雨', 63: '中雨', 65: '大雨',
    66: '冻雨', 67: '强冻雨',
    71: '小雪', 73: '中雪', 75: '大雪', 77: '雪粒',
    80: '阵雨', 81: '强阵雨', 82: '暴雨',
    85: '阵雪', 86: '强阵雪',
    95: '雷暴', 96: '雷暴伴冰雹', 99: '强雷暴伴冰雹',
  };

  static String text(int? code) => _text[code] ?? '未知';

  /// 天气图标颜色（与素材图一致：晴=金黄、云=灰蓝、雨=蓝、雪=浅蓝、雷=紫）
  /// 同一套颜色同时用于首页卡片和天气页，避免「晴天却是青色太阳」
  static Color color(int? code, {bool day = true}) {
    switch (code) {
      case 0:
        return const Color(0xFFF5A623); // 晴：暖金黄
      case 1:
        return day ? const Color(0xFFF5A623) : const Color(0xFF7C8FA6);
      case 2:
        return const Color(0xFF8FA3B8); // 多云：浅灰蓝
      case 3:
        return const Color(0xFF6B7F94); // 阴：深灰蓝
      case 45:
      case 48:
        return const Color(0xFF9AA7B3); // 雾
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
      case 61:
      case 63:
      case 66:
      case 67:
      case 80:
      case 65:
      case 82:
        return const Color(0xFF4A90D9); // 雨：蓝
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return const Color(0xFF7FB3D5); // 雪：浅蓝
      case 95:
      case 96:
      case 99:
        return const Color(0xFF8E7CC3); // 雷：紫
      default:
        return const Color(0xFF9AA7B3);
    }
  }

  static IconData icon(int? code, {bool day = true}) {
    switch (code) {
      case 0:
        return day ? Icons.wb_sunny : Icons.wb_sunny_outlined;
      case 1:
        // 少云：日间带云的太阳（Material 没有标准「多云带阳」，用 outline 区分）
        return day ? Icons.wb_sunny_outlined : Icons.nightlight_round;
      case 2:
        return Icons.cloud_outlined;
      case 3:
        return Icons.cloud;
      case 45:
      case 48:
        return Icons.foggy;
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
      case 61:
      case 63:
      case 66:
      case 67:
      case 80:
        return Icons.grain;
      case 65:
      case 82:
        return Icons.shower;
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return Icons.ac_unit;
      case 95:
      case 96:
      case 99:
        return Icons.thunderstorm_outlined;
      default:
        return Icons.help_outline;
    }
  }
}

/// 风向（度数）→ 中文方位
String windDirText(num? deg) {
  if (deg == null) return '--';
  const dirs = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  final d = ((deg % 360) + 360) % 360;
  final idx = ((d + 22.5) / 45).floor() % 8;
  return dirs[idx];
}

/// 单个小时的天气
class HourPoint {
  final DateTime time;
  final double temp; // ℃
  final int humidity; // %
  final double pressure; // hPa
  final int precipProb; // %
  final double precip; // mm
  final double windSpeed; // km/h
  final int windDir; // 度
  final double? uv; // 紫外线
  final int weatherCode;

  const HourPoint({
    required this.time,
    required this.temp,
    required this.humidity,
    required this.pressure,
    required this.precipProb,
    required this.precip,
    required this.windSpeed,
    required this.windDir,
    this.uv,
    required this.weatherCode,
  });

  String get hhmm => '${time.hour.toString().padLeft(2, '0')}:00';

  /// 风速 km/h → m/s（图片用 m/s）
  double get windMs => windSpeed / 3.6;

  int get fishIndex => FishIndex.hourly(this);
}

/// 一天的天气汇总
class DaySummary {
  final DateTime date;
  final int weatherCode;
  final double tempMax;
  final double tempMin;
  final double precipSum; // mm
  final int precipProbMax; // %
  final double windSpeedMax; // km/h
  final int windDirDom; // 度
  final double? uvMax;
  final String? sunrise; // ISO
  final String? sunset;

  const DaySummary({
    required this.date,
    required this.weatherCode,
    required this.tempMax,
    required this.tempMin,
    required this.precipSum,
    required this.precipProbMax,
    required this.windSpeedMax,
    required this.windDirDom,
    this.uvMax,
    this.sunrise,
    this.sunset,
  });

  /// 昼夜温差
  double get tempRange => tempMax - tempMin;

  int get fishIndex => FishIndex.daily(this);
}

/// 一次天气预报请求的完整数据
class WeatherBundle {
  final double lat;
  final double lng;
  // 当前实况
  final double curTemp;
  final int curHumidity;
  final double curPressure;
  final double curWindSpeed;
  final int curWindDir;
  final double curPrecip;
  final int curCode;
  // 全部逐小时（7×24）与 7 天日报
  final List<HourPoint> hours;
  final List<DaySummary> days;

  const WeatherBundle({
    required this.lat,
    required this.lng,
    required this.curTemp,
    required this.curHumidity,
    required this.curPressure,
    required this.curWindSpeed,
    required this.curWindDir,
    required this.curPrecip,
    required this.curCode,
    required this.hours,
    required this.days,
  });

  DaySummary get today => days.isNotEmpty ? days.first : _emptyDay;

  static final DaySummary _emptyDay = DaySummary(
    date: DateTime.now(),
    weatherCode: 0,
    tempMax: 0,
    tempMin: 0,
    precipSum: 0,
    precipProbMax: 0,
    windSpeedMax: 0,
    windDirDom: 0,
  );

  /// 取某一天（按自然日）的逐小时
  List<HourPoint> hoursOf(DateTime day) {
    return hours
        .where((h) =>
            h.time.year == day.year &&
            h.time.month == day.month &&
            h.time.day == day.day)
        .toList();
  }

  /// 当日垂钓指数（用当前实况算）
  int get currentFishIndex => FishIndex.score(
        pressure: curPressure,
        windKmh: curWindSpeed,
        precipProb: today.precipProbMax,
        temp: curTemp,
        code: curCode,
      );

  /// 解析 Open-Meteo /v1/forecast 响应
  factory WeatherBundle.fromOpenMeteo(
      double lat, double lng, Map<String, dynamic> json) {
    final cur = json['current'] as Map<String, dynamic>?;
    final hourly = json['hourly'] as Map<String, dynamic>?;
    final daily = json['daily'] as Map<String, dynamic>?;

    // 取数组字段（越界/缺失返回 null）
    num? at(Map<String, dynamic>? m, String key, int i) {
      if (m == null) return null;
      final v = m[key];
      if (v is List && i >= 0 && i < v.length && v[i] is num) {
        return v[i] as num;
      }
      return null;
    }

    // —— 逐小时 ——
    final hTimes = (hourly?['time'] as List?) ?? const [];
    final List<HourPoint> hours = [];
    for (var i = 0; i < hTimes.length; i++) {
      final t = DateTime.tryParse(hTimes[i].toString());
      if (t == null) continue;
      hours.add(HourPoint(
        time: t,
        temp: (at(hourly, 'temperature_2m', i) ?? 0).toDouble(),
        humidity: (at(hourly, 'relative_humidity_2m', i) ?? 0).round(),
        pressure: (at(hourly, 'pressure_msl', i) ?? 0).toDouble(),
        precipProb: (at(hourly, 'precipitation_probability', i) ?? 0).round(),
        precip: (at(hourly, 'precipitation', i) ?? 0).toDouble(),
        windSpeed: (at(hourly, 'wind_speed_10m', i) ?? 0).toDouble(),
        windDir: (at(hourly, 'wind_direction_10m', i) ?? 0).round(),
        uv: at(hourly, 'uv_index', i)?.toDouble(),
        weatherCode: (at(hourly, 'weather_code', i) ?? 0).round(),
      ));
    }

    // —— 逐日 ——
    final dTimes = (daily?['time'] as List?) ?? const [];
    final List<DaySummary> days = [];
    for (var i = 0; i < dTimes.length; i++) {
      final d = DateTime.tryParse('${dTimes[i]}T00:00') ??
          DateTime.now().add(Duration(days: i));
      days.add(DaySummary(
        date: d,
        weatherCode: (at(daily, 'weather_code', i) ?? 0).round(),
        tempMax: (at(daily, 'temperature_2m_max', i) ?? 0).toDouble(),
        tempMin: (at(daily, 'temperature_2m_min', i) ?? 0).toDouble(),
        precipSum: (at(daily, 'precipitation_sum', i) ?? 0).toDouble(),
        precipProbMax: (at(daily, 'precipitation_probability_max', i) ?? 0).round(),
        windSpeedMax: (at(daily, 'wind_speed_10m_max', i) ?? 0).toDouble(),
        windDirDom: (at(daily, 'wind_direction_10m_dominant', i) ?? 0).round(),
        uvMax: at(daily, 'uv_index_max', i)?.toDouble(),
        sunrise: (daily?['sunrise'] is List &&
                i < (daily!['sunrise'] as List).length)
            ? (daily['sunrise'] as List)[i]?.toString()
            : null,
        sunset: (daily?['sunset'] is List && i < (daily!['sunset'] as List).length)
            ? (daily['sunset'] as List)[i]?.toString()
            : null,
      ));
    }

    return WeatherBundle(
      lat: lat,
      lng: lng,
      curTemp: (cur?['temperature_2m'] as num?)?.toDouble() ?? 0,
      curHumidity: (cur?['relative_humidity_2m'] as num?)?.round() ?? 0,
      curPressure: (cur?['pressure_msl'] as num?)?.toDouble() ?? 0,
      curWindSpeed: (cur?['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      curWindDir: (cur?['wind_direction_10m'] as num?)?.round() ?? 0,
      curPrecip: (cur?['precipitation'] as num?)?.toDouble() ?? 0,
      curCode: (cur?['weather_code'] as num?)?.round() ?? 0,
      hours: hours,
      days: days,
    );
  }
}

/// 垂钓指数算法（0-100）：
/// 综合气压稳定性、风速、降雨概率、气温、极端天气，给出适宜度打分。
class FishIndex {
  static int score({
    required double pressure,
    required double windKmh,
    required int precipProb,
    required double temp,
    required int code,
  }) {
    double s = 100;

    // 气压：1005-1020 hPa 最稳，偏离扣分
    if (pressure < 1000) {
      s -= (1000 - pressure).clamp(0, 30) * 2.2;
    } else if (pressure < 1005) {
      s -= (1005 - pressure) * 1.2;
    } else if (pressure > 1022) {
      s -= (pressure - 1022).clamp(0, 20) * 1.0;
    }

    // 风速：<12km/h 极佳，越大越扣
    if (windKmh > 40) {
      s -= 35;
    } else if (windKmh > 25) {
      s -= 22;
    } else if (windKmh > 15) {
      s -= 10;
    } else if (windKmh > 12) {
      s -= 4;
    }

    // 降雨概率
    if (precipProb >= 80) {
      s -= 25;
    } else if (precipProb >= 50) {
      s -= 14;
    } else if (precipProb >= 30) {
      s -= 6;
    }

    // 气温：15-26℃ 最适
    if (temp < 5) {
      s -= 22;
    } else if (temp < 12) {
      s -= 10;
    } else if (temp > 33) {
      s -= 18;
    } else if (temp > 28) {
      s -= 8;
    }

    // 极端天气一票否决
    if (code >= 95) {
      s -= 60; // 雷暴
    } else if (code == 65 || code == 82 || code == 67) {
      s -= 30; // 大雨/暴雨/强冻雨
    }

    return s.clamp(0, 100).round();
  }

  static int hourly(HourPoint h) => score(
        pressure: h.pressure,
        windKmh: h.windSpeed,
        precipProb: h.precipProb,
        temp: h.temp,
        code: h.weatherCode,
      );

  static int daily(DaySummary d) => score(
        pressure: 1013, // 日报无逐时气压，取中性值，主要看风雨温
        windKmh: d.windSpeedMax,
        precipProb: d.precipProbMax,
        temp: (d.tempMax + d.tempMin) / 2,
        code: d.weatherCode,
      );

  /// 分数 → 文案
  static String label(int score) {
    if (score >= 80) return '极佳';
    if (score >= 60) return '良好';
    if (score >= 40) return '一般';
    return '不宜';
  }

  /// 分数 → 颜色
  static Color color(int score) {
    if (score >= 80) return AppTheme.primary; // 绿
    if (score >= 60) return AppTheme.accent; // 蓝
    if (score >= 40) return AppTheme.star; // 橙
    return AppTheme.danger; // 红
  }
}
