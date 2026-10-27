import 'fishing_species.dart';
import 'weather_forecast.dart';
import '../services/weather_service.dart';

/// 渔获时天气快照
///
/// 为什么要单独存一份：详情页原来是「打开时按当前时间重新算一遍」，
/// 于是同一条渔获早上看是 17℃，中午再看变成 19℃，指数也跟着跳 —— 用户
/// 看到的和当时拍的根本不是一回事。现在改成**发布那一刻**按「钓点坐标 +
/// 当时整点」抓一次，随帖子存进后端 `posts.weather_json`，之后永远读这份。
///
/// ⚠️ 只在发布时生成一次；任何页面都不允许在展示时重新推导。
class CatchWeather {
  /// 采集时刻（发布那一刻，用于显示「12:00 前后」）
  final DateTime at;

  final double temp; // ℃
  final int humidity; // %
  final double pressure; // hPa
  final int precipProb; // %
  final double windSpeed; // km/h
  final int windDir; // 度
  final int weatherCode; // WMO
  final String? pressureTrend; // steady / rising / falling…

  final double waterTemp; // ℃
  final double oxygen; // mg/L

  final double score; // 垂钓指数 0~100
  final String description; // 晴 / 多云…
  final String fishIndex; // 爆护 / 有口 / 口弱 / 难开口
  final String fishAdvice; // 一句话建议
  final String atLabel; // "12:00"

  const CatchWeather({
    required this.at,
    required this.temp,
    required this.humidity,
    required this.pressure,
    required this.precipProb,
    required this.windSpeed,
    required this.windDir,
    required this.weatherCode,
    this.pressureTrend,
    required this.waterTemp,
    required this.oxygen,
    required this.score,
    required this.description,
    required this.fishIndex,
    required this.fishAdvice,
    required this.atLabel,
  });

  /// 从天气包 + 时间点生成快照（发布时调用一次）
  static CatchWeather? fromBundle(WeatherBundle bundle, DateTime at) {
    if (bundle.hours.isEmpty) return null;
    final i = bundle.indexOfCurrentHour(at);
    if (i < 0 || i >= bundle.hours.length) return null;
    final h = bundle.hours[i];
    final metrics = WaterMetrics.derive(bundle.hours);
    final wm = (i < metrics.length) ? metrics[i] : null;
    final fw = FishingWeather.fromBundle(bundle);
    return CatchWeather(
      at: h.time,
      temp: h.temp,
      humidity: h.humidity,
      pressure: h.pressure,
      precipProb: h.precipProb,
      windSpeed: h.windSpeed,
      windDir: h.windDir,
      weatherCode: h.weatherCode,
      pressureTrend: h.pressureTrend,
      waterTemp: wm?.temp ?? h.temp,
      oxygen: wm?.oxygen ?? 0,
      score: fw.score.toDouble(),
      description: fw.description,
      fishIndex: fw.fishIndex,
      fishAdvice: fw.fishAdvice,
      atLabel: h.hhmm,
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        't': temp,
        'h': humidity,
        'p': pressure,
        'pp': precipProb,
        'ws': windSpeed,
        'wd': windDir,
        'code': weatherCode,
        if (pressureTrend != null) 'trend': pressureTrend,
        'wt': waterTemp,
        'ox': oxygen,
        'score': score,
        'desc': description,
        'fi': fishIndex,
        'fa': fishAdvice,
        'lbl': atLabel,
      };

  static CatchWeather? fromJson(dynamic raw) {
    if (raw == null) return null;
    Map<String, dynamic> j;
    if (raw is Map) {
      j = Map<String, dynamic>.from(raw);
    } else {
      return null;
    }
    double d(String k, [double def = 0]) {
      final v = j[k];
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? def;
    }

    int n(String k, [int def = 0]) {
      final v = j[k];
      if (v is num) return v.round();
      return int.tryParse('${v ?? ''}') ?? def;
    }

    String s(String k, [String def = '']) {
      final v = j[k];
      return v == null ? def : '$v';
    }

    return CatchWeather(
      at: DateTime.tryParse(s('at')) ?? DateTime.now(),
      temp: d('t'),
      humidity: n('h'),
      pressure: d('p', 1013),
      precipProb: n('pp'),
      windSpeed: d('ws'),
      windDir: n('wd'),
      weatherCode: n('code', 1000),
      pressureTrend: j['trend'] == null ? null : '${j['trend']}',
      waterTemp: d('wt'),
      oxygen: d('ox'),
      score: d('score', 50),
      description: s('desc'),
      fishIndex: s('fi'),
      fishAdvice: s('fa'),
      atLabel: s('lbl'),
    );
  }

  /// 还原成详情页渲染用的三个模型 —— 这样整块 UI 代码一行都不用改
  HourPoint toHourPoint() => HourPoint(
        time: at,
        temp: temp,
        humidity: humidity,
        pressure: pressure,
        precipProb: precipProb,
        precip: 0,
        windSpeed: windSpeed,
        windDir: windDir,
        weatherCode: weatherCode,
        pressureTrend: pressureTrend,
      );

  WaterMetrics toWaterMetrics() => WaterMetrics(waterTemp, oxygen);

  FishingWeather toFishingWeather() => FishingWeather(
        temperature: temp,
        humidity: humidity,
        windSpeed: windSpeed,
        windDir: windDir,
        pressure: pressure,
        weatherCode: weatherCode,
        description: description,
        fishIndex: fishIndex,
        fishAdvice: fishAdvice,
        score: score.round(),
        atLabel: atLabel,
      );
}
