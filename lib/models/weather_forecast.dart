import 'dart:math' as math;

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
    51: '毛毛雨', 53: '小雨', 55: '小雨',
    56: '冻雨', 57: '冻雨',
    61: '小雨', 63: '中雨', 65: '大雨',
    66: '冻雨', 67: '强冻雨',
    71: '小雪', 73: '中雪', 75: '大雪', 77: '雪粒',
    80: '阵雨', 81: '强阵雨', 82: '暴雨',
    85: '阵雪', 86: '强阵雪',
    95: '雷暴', 96: '雷暴伴冰雹', 99: '强雷暴伴冰雹',
  };

  static String text(int? code) => _text[code] ?? '未知';

  /// 天气图标颜色（晴=暖金、云=中性灰绿、雨=蓝、雪=浅蓝、雷=紫）
  ///
  /// 同一套颜色同时用于首页卡片和天气页，避免「晴天却是青色太阳」。
  /// 雨/雪/雷保留蓝紫系 —— 这是天气图标的世界通用惯例，改成绿色反而读不懂；
  /// 但阴、多云、雾原来是灰蓝（带明显蓝调），在湖绿的深底和浅底上都显脏，
  /// 这里换成中性灰绿，跟主色同族又不抢眼。晴的暖金统一到 [AppTheme.star]。
  static Color color(int? code, {bool day = true}) {
    switch (code) {
      case 0:
        // 晴：日间暖金黄，夜间月白（配月亮图标，避免「夜里一个大金太阳」）
        return day ? AppTheme.star : const Color(0xFFAFC3E2);
      case 1:
        return day ? AppTheme.star : const Color(0xFF7C8FA6);
      case 2:
        return const Color(0xFF93A69B); // 多云：中性灰绿
      case 3:
        return const Color(0xFF75897D); // 阴：深灰绿
      case 45:
      case 48:
        return const Color(0xFF9DAEA4); // 雾
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
        return const Color(0xFF9DAEA4);
    }
  }

  static IconData icon(int? code, {bool day = true}) {
    switch (code) {
      case 0:
        // 晴：日间太阳，夜间月亮（用户口径：晚 7 点至日出为止算夜间）
        return day ? Icons.wb_sunny : Icons.nightlight_round;
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

/// 气压变化趋势（基于逐小时气压序列的 3 小时变压）：陡降/缓降/急升/回升/平稳
///
/// 为什么用 3 小时而不是相邻小时：气象上「3 小时变压」才是判断天气系统过境的
/// 标准量，相邻小时差 0.3~0.5hPa 属于正常日变化，用它判「回升」会天天判涨。
String _trendFor(List<double> pres, int i) {
  if (i < 0 || i >= pres.length) return 'steady';
  final j = math.max(0, i - 3);
  final d = pres[i] - pres[j];
  if (i - j < 2) return 'steady'; // 序列开头不足 3 小时，不判趋势
  if (d <= -3.0) return 'falling_fast';
  if (d <= -1.0) return 'falling_slow';
  if (d >= 2.0) return 'rising_fast';
  if (d >= 0.8) return 'rising';
  return 'steady';
}

/// 3 小时变压（hPa，正=上升）
double _delta3h(List<double> pres, int i) {
  if (i <= 0 || i >= pres.length) return 0;
  final j = math.max(0, i - 3);
  return pres[i] - pres[j];
}

/// 天气现象校正
///
/// 全球数值模式（ECMWF / GFS / GRAPES）在「实际并未下雨」时也常给出
/// drizzle（51/53/55）或小雨代码，直接展示就会把晴天报成「小毛雨」，
/// 与中央气象台发布的实况差距很大。
/// 这里用**实测降水量 + 云量**回推天气现象，口径贴近中国气象局：
///   降水 ≥ 0.1mm  → 认为确实在下，保留原代码
///   降水 < 0.1mm  → 按云量重新判定：<10% 晴 / <30% 少云 / <70% 多云 / 其余 阴
class WeatherCodeFix {
  static bool isWetCode(int code) =>
      (code >= 51 && code <= 67) ||
      (code >= 80 && code <= 82) ||
      (code >= 85 && code <= 86);

  /// 云量 → 天气代码（中国气象局口径：晴 <10%，少云 <30%，多云 <70%，阴 ≥70%）
  static int? byCloud(double? cloudCover) {
    if (cloudCover == null) return null;
    if (cloudCover < 10) return 0;
    if (cloudCover < 30) return 1;
    if (cloudCover < 70) return 2;
    return 3;
  }

  static int adjust({
    required int code,
    required double precipMm,
    double? cloudCover,
    double rainThreshold = 0.1,
  }) {
    if (code >= 95) return code; // 雷暴：极端天气提示优先，不做降级
    if (code == 45 || code == 48) return code; // 雾 / 雾凇：与云量无关，保留
    if (precipMm >= rainThreshold) return code; // 确实在下雨/雪，采信模式给的现象
    // 没有实测降水：以云量为准重新判定（云量比模式给的天气代码可靠得多）
    return byCloud(cloudCover) ?? code;
  }
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
  final double? cloudCover; // 云量 %（用于天气现象校正）
  final String? pressureTrend; // 气压趋势：rising/rising_fast/falling_slow/falling_fast/steady

  /// 3 小时变压（hPa，正=上升）—— 判断锋前缓降 / 变天急降的关键量
  final double? pressureDelta3h;

  /// 当天昼夜温差（℃）—— 温差越大，水温波动越大、鱼越难适应
  final double? dayRange;

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
    this.cloudCover,
    this.pressureTrend,
    this.pressureDelta3h,
    this.dayRange,
  });

  String get hhmm => '${time.hour.toString().padLeft(2, '0')}:00';

  /// 风速 km/h → m/s（图片用 m/s）
  double get windMs => windSpeed / 3.6;
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

  DaySummary copyWith({
    int? weatherCode,
    double? tempMax,
    double? tempMin,
  }) =>
      DaySummary(
        date: date,
        weatherCode: weatherCode ?? this.weatherCode,
        tempMax: tempMax ?? this.tempMax,
        tempMin: tempMin ?? this.tempMin,
        precipSum: precipSum,
        precipProbMax: precipProbMax,
        windSpeedMax: windSpeedMax,
        windDirDom: windDirDom,
        uvMax: uvMax,
        sunrise: sunrise,
        sunset: sunset,
      );
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
  final int curPrecipProb; // 当前小时降雨概率 %

  /// 「当前」这一组数据对应的整点时刻（如 2026-10-24 13:00）。
  ///
  /// 页面上要把这个时间显示出来，用户才知道看到的是哪一小时的数据；
  /// 也为空表示没有逐时数据、退化成了 current 实况。
  final DateTime? curHour;
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
    required this.curPrecipProb,
    this.curHour,
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

  /// 取某一天 [day]、某一自然小时 [hour] 的逐小时数据（用于「按时间段」显示天气）
  HourPoint? hourAt(DateTime day, int hour) {
    for (final h in hours) {
      if (h.time.year == day.year &&
          h.time.month == day.month &&
          h.time.day == day.day &&
          h.time.hour == hour) {
        return h;
      }
    }
    return null;
  }

  /// 取某一天「对应时间段」的逐小时数据：
  /// 以 [refHour]（打开页面时的当前小时）为时间段基准 ——
  /// 今天取真实当前小时、未来几天取同一小时，保证 7 天显示 / AI 判断
  /// 都锚定在同一时段，而不是用「全天聚合」代表当天天气。
  HourPoint? dayRefHour(DateTime day, int refHour) {
    final h = hourAt(day, refHour);
    if (h != null) return h;
    // 兜底：取当天最接近 refHour 的那一小时
    final dayHours = hoursOf(day);
    if (dayHours.isEmpty) return null;
    dayHours.sort((a, b) =>
        (a.time.hour - refHour).abs().compareTo((b.time.hour - refHour).abs()));
    return dayHours.first;
  }

  /// 「当前时段」的唯一定义：与给定时刻绝对时间最近的那一小时。
  ///
  /// 首页天气卡和天气页顶部卡都必须用这一小时，否则会出现
  /// 「首页 26.3℃ / 指数 78」而「天气页 25.8℃ / 指数 82」这种自相矛盾 ——
  /// 因为过去首页用 current 实况、天气页指数用逐时整点，两个数据源混着用。
  /// 返回下标（配 metrics 用），找不到返回 -1。
  int indexOfHourNear(DateTime at) {
    if (hours.isEmpty) return -1;
    var best = -1;
    var bestDiff = 1 << 30;
    for (var i = 0; i < hours.length; i++) {
      final d = hours[i].time.difference(at).inMinutes.abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    return best;
  }

  /// 与 [indexOfHourNear] 配套：直接取那一小时的数据
  HourPoint? hourNear(DateTime at) {
    final i = indexOfHourNear(at);
    return i >= 0 ? hours[i] : null;
  }

  /// 「当前所在的那一小时」下标（v2.1.21）
  ///
  /// ★★ 和 [indexOfHourNear] 不是一回事，别再混用：
  ///   - indexOfHourNear = **绝对时间最近**：20:35 会挑到 21:00 —— 一个**还没发生**
  ///     的时段，卡上就会写「21:00」而外面明明才 20:35；
  ///   - indexOfCurrentHour = **你所处的那一小时**：20:35 → 20:00。
  ///
  ///   跨整点前后半小时的错位，正是「首页和天气页各显示一个时段、数字对不上」
  ///   的来源之一（两边一个用了 now、一个用了拉包时刻，再叠上这个偏移就彻底乱了）。
  ///   现在首页卡和天气页当前卡统一走这个口径。
  int indexOfCurrentHour(DateTime at) {
    final t = DateTime(at.year, at.month, at.day, at.hour);
    final exact = hours.indexWhere((h) => h.time == t);
    if (exact >= 0) return exact;
    // 序列里没有这一小时（数据缺行 / 时区差异）才退回"最近"
    return indexOfHourNear(t);
  }

  /// 当前所在那一小时的数据（找不到返回 null）
  HourPoint? hourCurrent(DateTime at) {
    final i = indexOfCurrentHour(at);
    return i >= 0 ? hours[i] : null;
  }

  /// 第二模型（CMA）逐时序列 → {时间: [气温, 气压]}
  static Map<DateTime, List<double>> _seriesOf(Map<String, dynamic>? j) {
    final out = <DateTime, List<double>>{};
    final h = j?['hourly'];
    if (h is! Map) return out;
    final times = (h['time'] as List?) ?? const [];
    final tKey = h.containsKey('temperature_2m_cma_grapes_global')
        ? 'temperature_2m_cma_grapes_global'
        : 'temperature_2m';
    final pKey = h.containsKey('pressure_msl_cma_grapes_global')
        ? 'pressure_msl_cma_grapes_global'
        : 'pressure_msl';
    final ts = h[tKey], ps = h[pKey];
    if (ts is! List || ps is! List) return out;
    for (var i = 0; i < times.length && i < ts.length && i < ps.length; i++) {
      final t = DateTime.tryParse(times[i].toString());
      final a = ts[i], b = ps[i];
      if (t == null || a is! num || b is! num) continue;
      out[t] = [a.toDouble(), b.toDouble()];
    }
    return out;
  }

  /// 解析 Open-Meteo /v1/forecast 响应
  ///
  /// [ensembleJson]：第二次请求得到的 CMA（中国气象局 GRAPES）逐时序列。
  /// 单靠 ECMWF/GFS 时，夜间气温与国内软件能差 3℃ 以上（实测同一时刻
  /// 2026-10-23 03:45 杭州：GFS 16.8℃ / ECMWF 15.4℃ / CMA 13.7℃），
  /// 所以这里把两套模型等权平均，明显减小单模型系统偏差。
  factory WeatherBundle.fromOpenMeteo(
    double lat,
    double lng,
    Map<String, dynamic> json, {
    Map<String, dynamic>? ensembleJson,
  }) {
    final cur = json['current'] as Map<String, dynamic>?;
    final hourly = json['hourly'] as Map<String, dynamic>?;
    final daily = json['daily'] as Map<String, dynamic>?;

    // 第二模型（CMA）逐时序列：时间 → [气温, 气压]
    final ens = _seriesOf(ensembleJson);

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
    // 先取出气压序列，便于算逐时趋势
    final presArr = List<double>.generate(hTimes.length, (i) {
      final v = at(hourly, 'pressure_msl', i);
      return v == null ? 1013.0 : v.toDouble();
    });
    // 当天最高 / 最低气温（用于「温差」维度）
    final dayMax = <String, double>{};
    final dayMin = <String, double>{};
    for (var i = 0; i < hTimes.length; i++) {
      final t = DateTime.tryParse(hTimes[i].toString());
      final v = at(hourly, 'temperature_2m', i);
      if (t == null || v == null) continue;
      final k = '${t.year}-${t.month}-${t.day}';
      final d = v.toDouble();
      final hi = dayMax[k], lo = dayMin[k];
      dayMax[k] = hi == null || d > hi ? d : hi;
      dayMin[k] = lo == null || d < lo ? d : lo;
    }

    final List<HourPoint> hours = [];
    for (var i = 0; i < hTimes.length; i++) {
      final t = DateTime.tryParse(hTimes[i].toString());
      if (t == null) continue;
      var temp = (at(hourly, 'temperature_2m', i) ?? 0).toDouble();
      var pres = (at(hourly, 'pressure_msl', i) ?? 0).toDouble();
      final e = ens[t];
      if (e != null) {
        temp = (temp + e[0]) / 2;
        pres = (pres + e[1]) / 2;
      }
      final k = '${t.year}-${t.month}-${t.day}';
      final hi = dayMax[k], lo = dayMin[k];
      hours.add(HourPoint(
        time: t,
        temp: temp,
        humidity: (at(hourly, 'relative_humidity_2m', i) ?? 0).round(),
        pressure: pres,
        precipProb: (at(hourly, 'precipitation_probability', i) ?? 0).round(),
        precip: (at(hourly, 'precipitation', i) ?? 0).toDouble(),
        windSpeed: (at(hourly, 'wind_speed_10m', i) ?? 0).toDouble(),
        windDir: (at(hourly, 'wind_direction_10m', i) ?? 0).round(),
        uv: at(hourly, 'uv_index', i)?.toDouble(),
        weatherCode: (at(hourly, 'weather_code', i) ?? 0).round(),
        cloudCover: at(hourly, 'cloud_cover', i)?.toDouble(),
        pressureTrend: _trendFor(presArr, i),
        pressureDelta3h: _delta3h(presArr, i),
        dayRange: (hi != null && lo != null) ? hi - lo : null,
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

    // —— 用逐小时数据校正「今日温度区间」与「天气现象」——
    // 中央气象台的「今天最低」= 今夜到明晨的最低温；而 Open-Meteo 的
    // temperature_2m_min 是整个自然日（含已经过去的清晨）的最低值，
    // 两者能差 4-5℃，这就是之前「13.3~24.0」与官方「24/9」差很大的原因。
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final dayHours = hours
          .where((h) =>
              h.time.year == d.date.year &&
              h.time.month == d.date.month &&
              h.time.day == d.date.day)
          .toList();
      if (dayHours.isEmpty) continue;

      // 1) 天气现象校正：无实测降水时按云量回推，避免「晴天报成小毛雨」
      final pSum = dayHours.fold<double>(0, (a, h) => a + h.precip);
      final clouds =
          dayHours.map((h) => h.cloudCover).whereType<double>().toList();
      final meanCloud =
          clouds.isEmpty ? null : clouds.reduce((a, b) => a + b) / clouds.length;
      final code = WeatherCodeFix.adjust(
        code: d.weatherCode,
        precipMm: pSum,
        cloudCover: meanCloud,
        // 日报是全天累计降水，0.2mm 这种量级在体感上等于没下，
        // 所以日尺度用 0.5mm 作为「真的会下雨」的门槛
        rainThreshold: 0.5,
      );

      var tMax = d.tempMax;
      var tMin = d.tempMin;

      // 2) 今日温度：最高取当日逐小时最大值；最低取今晚 20:00 → 次日 08:00
      if (i == 0) {
        tMax = dayHours.map((h) => h.temp).reduce((a, b) => a > b ? a : b);
        final nightStart = DateTime(d.date.year, d.date.month, d.date.day, 20);
        final nightEnd = nightStart.add(const Duration(hours: 12));
        final nightTemps = hours
            .where(
                (h) => !h.time.isBefore(nightStart) && h.time.isBefore(nightEnd))
            .map((h) => h.temp)
            .toList();
        if (nightTemps.isNotEmpty) {
          tMin = nightTemps.reduce((a, b) => a < b ? a : b);
        }
      }

      days[i] = d.copyWith(weatherCode: code, tempMax: tMax, tempMin: tMin);
    }

    // 当前实况的天气现象也校正一次（云量取时间上最近的一小时）
    final curPrecipV = (cur?['precipitation'] as num?)?.toDouble() ?? 0;
    final curPrecipProbV =
        (cur?['precipitation_probability'] as num?)?.round() ?? 0;
    // 当前实况：统一取「逐时集合」里最接近现在的那一小时。
    // 这样首页卡 / 天气页顶部 / AI 弹层三处的气温气压完全一致，
    // 也是用户能对照逐时表核对的同一个数。
    var curCodeV = (cur?['weather_code'] as num?)?.round() ?? 0;
    HourPoint? nearest;
    if (hours.isNotEmpty) {
      final nowH = DateTime.now();
      var bestMin = 1 << 30;
      for (final h in hours) {
        final diff = h.time.difference(nowH).inMinutes.abs();
        if (diff < bestMin) {
          bestMin = diff;
          nearest = h;
        }
      }
      if (nearest != null) {
        curCodeV = WeatherCodeFix.adjust(
          code: nearest.weatherCode,
          precipMm: nearest.precip,
          cloudCover: nearest.cloudCover,
        );
      }
    }

    final curTempV = nearest?.temp ??
        (cur?['temperature_2m'] as num?)?.toDouble() ??
        0;
    final curPresV = nearest?.pressure ??
        (cur?['pressure_msl'] as num?)?.toDouble() ??
        0;

    // ★ 时段统一（v2.1.19）：所有「当前」字段一律取自同一个整点 [nearest]。
    //
    // 之前只有气温和气压取了整点，湿度 / 风速 / 风向 / 降水概率 / 天气现象
    // 仍在用 current（分钟级实况），结果同一张「当前」卡里混了两个时段：
    // 卡上写「小雨、湿度 88%、风 12km/h」，而垂钓指数是按那一小时的
    // 「多云、湿度 76%、风 8km/h」算的 —— 用户看到的天气和分数对不上。
    // 现在全部对齐到同一小时，天气页顶部卡、首页天气卡、逐时表高亮行
    // 和垂钓指数用的是同一组数字。
    return WeatherBundle(
      lat: lat,
      lng: lng,
      curTemp: curTempV,
      curHumidity: nearest?.humidity ??
          (cur?['relative_humidity_2m'] as num?)?.round() ??
          0,
      curPressure: curPresV,
      curWindSpeed: nearest?.windSpeed ??
          (cur?['wind_speed_10m'] as num?)?.toDouble() ??
          0,
      curWindDir: nearest?.windDir ??
          (cur?['wind_direction_10m'] as num?)?.round() ??
          0,
      curPrecip: nearest?.precip ?? curPrecipV,
      curCode: curCodeV,
      curPrecipProb: nearest?.precipProb ?? curPrecipProbV,
      curHour: nearest?.time,
      hours: hours,
      days: days,
    );
  }
}
