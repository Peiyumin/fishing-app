import 'weather_forecast.dart';

/// ============================================================
/// 鱼种 / 钓法 / 水体指标 / 逐小时鱼情
///
/// 数据来源说明：
///  - 气温、气压、风、降雨、天气现象 = Open-Meteo 实测/预报；
///  - 水温、溶氧（水氧）无免费实测接口，按水文学经验模型从气温序列推导
///    （水体热惯性 → 水温滞后于气温；溶氧随水温、风浪、气压、日照变化）；
///  - 鱼情指数 = 气象适宜度 × 鱼种适温匹配 × 溶氧 × 时段活性 × 钓法修正。
/// ============================================================

/// 钓法：同一份天气，不同钓法的适宜度不同
class FishingMode {
  final String name;
  const FishingMode(this.name);

  static const all = <FishingMode>[
    FishingMode('台钓'),
    FishingMode('路亚'),
    FishingMode('海钓'),
  ];

  /// 钓法修正分（-12 ~ +9）
  int adjust(HourPoint h, FishingSpecies sp) {
    switch (name) {
      case '路亚':
        // 路亚主攻掠食鱼，喜风浪与阴天，暴雨/大雾影响抛投与视线
        var a = sp.predator ? 7 : -9;
        if (h.windSpeed > 6 && h.windSpeed < 28) a += 3;
        if (h.precip >= 2) a -= 4;
        if (h.weatherCode == 45 || h.weatherCode == 48) a -= 3;
        return a;
      case '海钓':
        // 海钓最怕大风，风大直接压分
        if (h.windSpeed > 20) return -12;
        if (h.windSpeed > 12) return -5;
        if (h.windSpeed < 6) return 2;
        return 0;
      default: // 台钓：喜静水、稳气压
        var a = 0;
        if (h.windSpeed < 12) a += 3;
        if (h.windSpeed > 25) a -= 8;
        if (h.precipProb > 70) a -= 3;
        return a;
    }
  }
}

/// 鱼种：适宜水温区间 + 习性
class FishingSpecies {
  final String name;

  /// 适宜水温下限 / 上限（℃）
  final double optLow;
  final double optHigh;

  /// 习性一句话（用于鱼种对比 / 解读）
  final String habit;

  /// 掠食性（路亚更吃香）
  final bool predator;

  const FishingSpecies(
    this.name,
    this.optLow,
    this.optHigh,
    this.habit, {
    this.predator = false,
  });

  static const all = <FishingSpecies>[
    FishingSpecies('鲫鱼', 10, 26, '全年可钓，喜弱风稳气压，底钓为主'),
    FishingSpecies('翘嘴鲌', 16, 29, '中上层掠食，喜风浪与晨昏窗口', predator: true),
    FishingSpecies('鳙鱼', 18, 31, '滤食性，高温浮钓，喜肥水'),
    FishingSpecies('鲤鱼', 12, 27, '底栖杂食，喜稳气压与泥底'),
    FishingSpecies('白条', 14, 30, '表层小鱼，喜明亮活跃，成群抢食'),
    FishingSpecies('草鱼', 17, 31, '草食性，高温晴天中午活跃'),
  ];
}

/// 水体指标（水温 / 溶氧）
class WaterMetrics {
  /// 水温 ℃
  final double temp;

  /// 溶氧 mg/L
  final double oxygen;

  const WaterMetrics(this.temp, this.oxygen);

  /// 由逐小时气温序列推导水温与溶氧。
  ///
  /// 水温：对气温做指数平滑，模拟水体热惯性（变化远比气温平缓），
  ///       再叠加日照导致的白天表层升温、夜间回落；
  /// 溶氧：以水温对应的饱和溶氧为基准打折（自然水体通常 70%~85% 饱和），
  ///       风浪增氧、气压升高提升溶解量、白天藻类光合作用产氧、凌晨耗氧。
  static List<WaterMetrics> derive(List<HourPoint> hours) {
    final out = <WaterMetrics>[];
    double? wt;
    for (final h in hours) {
      // 初值：略高于气温（水体蓄热）
      wt = wt == null ? h.temp + 2.0 : wt * 0.82 + h.temp * 0.18;

      final hr = h.time.hour;
      final solar = (hr >= 10 && hr <= 16)
          ? 0.8
          : ((hr >= 20 || hr <= 5) ? -0.6 : 0.0);
      final waterTemp = (wt + solar).clamp(-2.0, 38.0);

      // 饱和溶氧经验式（淡水，1 atm）
      final sat = 14.62 - 0.4105 * waterTemp + 0.007991 * waterTemp * waterTemp;
      var o2 = sat * 0.76;
      o2 += (h.windSpeed / 3.6).clamp(0.0, 8.0) * 0.055; // 风浪增氧
      o2 += (h.pressure - 1013) * 0.012; // 气压
      if (hr >= 9 && hr <= 17) o2 += 0.35; // 白天光合作用
      if (hr <= 5) o2 -= 0.35; // 凌晨呼吸耗氧

      out.add(WaterMetrics(
        double.parse(waterTemp.toStringAsFixed(1)),
        double.parse(o2.clamp(2.0, 13.0).toStringAsFixed(2)),
      ));
    }
    return out;
  }
}

/// 逐小时鱼情评分 + 有口判定
class Bite {
  /// 鱼情指数 0-100
  static int score({
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    required FishingMode mode,
  }) {
    // ① 气象适宜度（气压/风/降雨/气温/极端天气）
    final base = h.fishIndex;

    // ② 鱼种适温匹配度：落在适温区间内满分，越界线性扣分
    double fit = 100;
    if (w.temp < sp.optLow) fit -= (sp.optLow - w.temp) * 7;
    if (w.temp > sp.optHigh) fit -= (w.temp - sp.optHigh) * 7;
    fit = fit.clamp(0, 100);

    // ③ 溶氧匹配度：3.5mg/L 以下几乎不开口，8mg/L 以上满分
    final o2 = ((w.oxygen - 3.5) / 4.5 * 100).clamp(0, 100);

    double s = base * 0.45 + fit * 0.38 + o2 * 0.17;

    // ④ 时段活性：晨昏高峰、正午低谷、深夜回落
    final hr = h.time.hour;
    if (hr >= 5 && hr <= 8) {
      s += 5;
    } else if (hr >= 16 && hr <= 19) {
      s += 4;
    } else if (hr >= 11 && hr <= 14) {
      s -= 5;
    } else if (hr >= 22 || hr <= 3) {
      s -= 3;
    }

    // ⑤ 掠食鱼在风浪天更活跃
    if (sp.predator && h.windSpeed > 8) s += 4;

    // ⑥ 钓法修正
    s += mode.adjust(h, sp);

    return s.clamp(0, 100).round();
  }

  /// 有口 / 爆护 / 无口
  static String label(int score) {
    if (score >= 78) return '爆护';
    if (score >= 45) return '有口';
    return '无口';
  }

  /// 鱼情图标数量（1-3）
  static int fishCount(int score) {
    if (score >= 78) return 3;
    if (score >= 45) return 2;
    return 1;
  }
}
