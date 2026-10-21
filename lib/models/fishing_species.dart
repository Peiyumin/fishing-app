import 'weather_forecast.dart';

/// ============================================================
/// 鱼种 / 钓法 / 水体指标 / 逐小时鱼情
///
/// 数据来源说明：
///  - 气温、气压、风、降雨、天气现象 = Open-Meteo 实测/预报（免费、无需 Key）；
///  - 水温、溶氧（水氧）无免费实测接口，按水文学经验模型从气温 + 气压推导；
///  - 鱼情指数 = 多维加权（气压稳定度 / 风速 / 水温适温 / 溶氧 / 潮汐）× 钓法权重，
///    借鉴竞品「鱼天气」indexFishData 的自研富指数思路（分维度打分 + 归一化 + 黄金时段）。
/// ============================================================

/// 当前季节（用于黄金时段默认值与适温口径）
String seasonOf(DateTime d) {
  final m = d.month;
  if (m >= 3 && m <= 5) return 'spring';
  if (m >= 6 && m <= 8) return 'summer';
  if (m >= 9 && m <= 11) return 'autumn';
  return 'winter';
}

/// 钓法：同一份天气，不同钓法的适宜度不同（权重不同）
class FishingMode {
  final String name;
  const FishingMode(this.name);

  static const all = <FishingMode>[
    FishingMode('台钓'),
    FishingMode('路亚'),
    FishingMode('海钓'),
  ];
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
  /// 水温（内陆水库滞后模型）：以「日均气温 + 1.5℃」为基准，叠加该小时相对日均的偏离
  ///   Tw ≈ 日均气温 + 1.5 + 0.30 ×（该小时气温 − 日均气温）
  ///   水体热惯性使水温变化幅度远小于气温（系数 0.30），且整体比气温高约 1.5℃（蓄热）。
  /// 溶氧：以水温对应的理论饱和溶氧乘气压修正（淡水）：
  ///   DO ≈ (14.6 − 0.39 × Tw) × (气压 / 1013.25)
  ///   再 clamp 到 4~12 mg/L（自然水体溶氧经验区间）。
  static List<WaterMetrics> derive(List<HourPoint> hours) {
    if (hours.isEmpty) return const [];
    final meanAir =
        hours.map((h) => h.temp).reduce((a, b) => a + b) / hours.length;
    final out = <WaterMetrics>[];
    for (final h in hours) {
      final waterTemp =
          ((meanAir + 1.5 + 0.30 * (h.temp - meanAir)).clamp(10.0, 27.0));
      final o2 = ((14.6 - 0.39 * waterTemp) * (h.pressure / 1013.25))
          .clamp(4.0, 12.0);
      out.add(WaterMetrics(
        double.parse(waterTemp.toStringAsFixed(1)),
        double.parse(o2.toStringAsFixed(2)),
      ));
    }
    return out;
  }
}

/// ============================================================
/// 鱼情指数引擎（多维加权，对齐竞品 indexFishData 思路）
///
/// 各维度 0-100 分，按钓法权重加权；缺失维度（内陆无潮汐）自动剔除并归一化。
/// 输出：总指数、分级、各维度分、黄金时段、分维度建议。
/// ============================================================
class FishScore {
  /// 钓法权重（维度权重之和=1）。台钓重气压/溶氧；路亚重水温；海钓重潮汐。
  static const Map<String, Map<String, double>> _weights = {
    '台钓': {
      'pressure': 0.30,
      'wind': 0.10,
      'temp': 0.25,
      'oxygen': 0.25,
      'tide': 0.10,
    },
    '路亚': {
      'pressure': 0.15,
      'wind': 0.20,
      'temp': 0.35,
      'oxygen': 0.20,
      'tide': 0.10,
    },
    '海钓': {
      'pressure': 0.10,
      'wind': 0.20,
      'temp': 0.20,
      'oxygen': 0.10,
      'tide': 0.40,
    },
  };

  /// 维度中文名（用于解析弹层）
  static const Map<String, String> dimName = {
    'pressure': '气压',
    'wind': '风',
    'temp': '水温',
    'oxygen': '溶氧',
    'tide': '潮汐',
  };

  const FishScore._();

  /// 气压维度分：稳定中高压（1005~1018）最适；缓降(锋前)短时促口 +8，陡降(变天) −18，回升 −4
  static int? pressureScore(double? p, String trend) {
    if (p == null) return null;
    var s = _band(p, 1005, 1018, 985, 1035);
    if (trend == 'falling_slow') {
      s += 8;
    } else if (trend == 'falling_fast') {
      s -= 18;
    } else if (trend == 'rising') {
      s -= 4;
    }
    return s.clamp(0, 100).round();
  }

  /// 风维度分：1~3 级（1.6~5.4 m/s）最佳，过大过小衰减
  static int? windScore(double? windMs) {
    if (windMs == null) return null;
    return _band(windMs, 1.6, 5.4, 0, 10.8).round();
  }

  /// 水温维度分：落在鱼种适温区间满分，越界按容差线性衰减
  static int? waterTempScore(double? t, double idealLow, double idealHigh,
      [double? tolLow, double? tolHigh]) {
    if (t == null) return null;
    final lo = tolLow ?? (idealLow - 12);
    final hi = tolHigh ?? (idealHigh + 8);
    return _band(t, idealLow, idealHigh, lo, hi).round();
  }

  /// 溶氧维度分：≥6mg/L 满分；≤3mg/L 低分；中间线性
  static int? oxygenScore(double? doMgL) {
    if (doMgL == null) return null;
    if (doMgL >= 6) return 100;
    if (doMgL <= 3) return 10;
    return (((doMgL - 3) / 3) * 90 + 10).clamp(0, 100).round();
  }

  /// 潮汐维度分：起流 > 转向 > 平流（内陆无潮汐时返回 null → 自动剔除）
  static int? tideScore(String? phase) {
    if (phase == null || phase.isEmpty) return null;
    const m = {'flowing': 95, 'turning': 80, 'slack': 60};
    return m[phase] ?? 70;
  }

  /// 在 [idealLow,idealHigh] 内得 100，线性衰减到 [tolLow,tolHigh] 处为 0
  static double _band(double v, double idealLow, double idealHigh,
      double tolLow, double tolHigh) {
    if (v >= idealLow && v <= idealHigh) return 100;
    if (v < idealLow) {
      final span = idealLow - tolLow;
      return span <= 0 ? 0 : (100 - ((idealLow - v) / span) * 100).clamp(0, 100);
    }
    final span = tolHigh - idealHigh;
    return span <= 0 ? 0 : (100 - ((v - idealHigh) / span) * 100).clamp(0, 100);
  }

  /// 气压变化趋势（基于逐小时气压序列）
  static String trendFor(List<double> pres, int i) {
    if (i < 0 || i >= pres.length) return 'steady';
    final next = (i + 1 < pres.length) ? pres[i + 1] : pres[i];
    final d = next - pres[i];
    if (d < -0.8) return 'falling_fast';
    if (d < -0.25) return 'falling_slow';
    if (d > 0.35) return 'rising';
    return 'steady';
  }

  /// 多维加权打分结果
  static FishScoreResult compute({
    required String method,
    required double pressure,
    required String pressureTrend,
    required double windMs,
    required double waterTemp,
    required double dissolvedOxygen,
    required String season,
    String? tidePhase, // 内陆传 null
    required FishingSpecies sp,
  }) {
    final w = _weights[method] ?? _weights['台钓']!;
    final dim = <String, int?>{
      'pressure':
          pressureScore(pressure, pressureTrend),
      'wind': windScore(windMs),
      'temp': waterTempScore(
          waterTemp, sp.optLow, sp.optHigh),
      'oxygen': oxygenScore(dissolvedOxygen),
      'tide': tideScore(tidePhase),
    };

    double wsum = 0, acc = 0;
    for (final k in w.keys) {
      final v = dim[k];
      if (v != null) {
        wsum += w[k]!;
        acc += v * w[k]!;
      }
    }
    final indexScore = wsum > 0 ? (acc / wsum).round() : null;
    final grade = _gradeOf(indexScore);
    final advice = _advice(dim, windDirText: null, season: season);
    return FishScoreResult(
      indexScore: indexScore,
      grade: grade,
      dim: dim,
      advice: advice,
    );
  }

  /// 总分 → 分级（优 / 良 / 一般 / 不宜）
  static String _gradeOf(int? s) {
    if (s == null) return '—';
    if (s >= 85) return '优';
    if (s >= 70) return '良';
    if (s >= 50) return '一般';
    return '不宜';
  }

  static String _advice(Map<String, int?> dim,
      {String? windDirText, required String season}) {
    final tips = <String>[];
    if (dim['pressure'] != null && dim['pressure']! < 60) {
      tips.add('气压波动大，鱼口易不稳，宜钓底守稳');
    }
    if (dim['wind'] != null && dim['wind']! < 60) {
      tips.add('风偏大，注意安全与观漂，选避风湾');
    }
    if (dim['oxygen'] != null && dim['oxygen']! < 60) {
      tips.add('溶氧偏低，鱼易上浮，宜钓浮或早晚口');
    }
    if (dim['temp'] != null && dim['temp']! < 60) {
      tips.add('水温偏离适温，鱼活性下降');
    }
    if (tips.isEmpty) {
      final dir = windDirText != null ? '风向$windDirText，' : '';
      tips.add('综合条件佳，$dir把握黄金时段出钓');
    }
    return '${tips.join('；')}。';
  }

  /// 由当天逐时总分数派生黄金时段（3h 滑动窗，取高分且不重叠，最多 2 段）
  static List<String> goldenWindows(List<int> scores, {required String season}) {
    if (scores.length != 24) return _defaultWindows(season);
    const W = 3;
    final wins = <Map<String, int>>[];
    for (var i = 0; i <= 23 - W + 1; i++) {
      var sum = 0;
      for (var k = 0; k < W; k++) {
        sum += scores[i + k];
      }
      wins.add({'start': i, 'avg': (sum / W).round()});
    }
    wins.sort((a, b) => b['avg']! - a['avg']!);
    final top = <Map<String, int>>[];
    for (final w in wins) {
      if (w['avg']! < 78) break;
      if (top.any((t) => (t['start']! - w['start']!).abs() < W)) continue;
      top.add(w);
      if (top.length >= 2) break;
    }
    if (top.isEmpty) return _defaultWindows(season);
    String p(int n) => n.toString().padLeft(2, '0');
    return top
        .map((w) => '${p(w['start']!)}:00-${p(w['start']! + W)}:00')
        .toList();
  }

  static List<String> _defaultWindows(String season) {
    if (season == 'summer') return ['05:00-08:00', '17:30-20:00'];
    if (season == 'winter') return ['07:00-10:00', '14:00-16:30'];
    return ['06:00-09:00', '15:30-18:30'];
  }

  /// 公开：季节默认黄金时段（供天气页在当天数据不足时回退）
  static List<String> defaultWindows(String season) =>
      _defaultWindows(season);
}

/// FishScore.compute 的结果载体
class FishScoreResult {
  final int? indexScore;
  final String grade;
  final Map<String, int?> dim;
  final String advice;
  const FishScoreResult({
    required this.indexScore,
    required this.grade,
    required this.dim,
    required this.advice,
  });
}

/// 逐小时鱼情评分 + 有口判定（对外签名保持稳定，便于天气页直接调用）
class Bite {
  /// 鱼情指数 0-100（用 FishScore 多维引擎）
  static int score({
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    required FishingMode mode,
  }) {
    final r = FishScore.compute(
      method: mode.name,
      pressure: h.pressure,
      pressureTrend: h.pressureTrend ?? 'steady',
      windMs: h.windMs,
      waterTemp: w.temp,
      dissolvedOxygen: w.oxygen,
      season: seasonOf(h.time),
      sp: sp,
    );
    return r.indexScore ?? 50;
  }

  /// 各维度分（供 AI 解析弹层展示）
  static Map<String, int?> dimensionScores({
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    required FishingMode mode,
  }) =>
      FishScore.compute(
        method: mode.name,
        pressure: h.pressure,
        pressureTrend: h.pressureTrend ?? 'steady',
        windMs: h.windMs,
        waterTemp: w.temp,
        dissolvedOxygen: w.oxygen,
        season: seasonOf(h.time),
        sp: sp,
      ).dim;

  /// 有口 / 爆护 / 无口（沿用用户熟悉的标签；总分已升级为更准的多维引擎）
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
