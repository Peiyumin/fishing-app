import 'dart:math' as math;

import 'weather_forecast.dart';

/// ============================================================
/// 鱼种 / 钓法 / 水体指标 / 逐小时鱼情
///
/// 数据来源说明：
///  - 气温、气压、风、降雨、天气现象 = Open-Meteo 实测/预报（免费、无需 Key）；
///  - 水温、溶氧（水氧）无免费实测接口，按水文学经验模型从气温 + 气压推导；
///  - 鱼情指数 = 多维加权（气压稳定度 / 风速 / 水温适温 / 溶氧 / 潮汐 / 时段活性）
///    × 钓法权重，并叠加鱼种自身习性（适温区间、活跃时段、喜风浪、掠食性）；
///  - 海钓潮汐按朔望月月相近似（大潮 / 中潮 / 小潮），内陆钓法自动剔除该维度。
/// ============================================================

/// 当前季节（用于黄金时段默认值与适温口径）
String seasonOf(DateTime d) {
  final m = d.month;
  if (m >= 3 && m <= 5) return 'spring';
  if (m >= 6 && m <= 8) return 'summer';
  if (m >= 9 && m <= 11) return 'autumn';
  return 'winter';
}

/// 钓法：同一份天气，不同钓法的适宜度不同（权重不同、目标鱼也不同）
class FishingMode {
  final String name;
  const FishingMode(this.name);

  static const all = <FishingMode>[
    FishingMode('台钓'),
    FishingMode('路亚'),
    FishingMode('海钓'),
  ];
}

/// 鱼种：适温区间 + 习性（所属钓法 / 活跃时段 / 是否喜风浪）
class FishingSpecies {
  final String name;

  /// 适宜水温下限 / 上限（℃）
  final double optLow;
  final double optHigh;

  /// 习性一句话（用于鱼种对比 / 解读）
  final String habit;

  /// 掠食性（路亚更吃香；锋前降压反而更活跃）
  final bool predator;

  /// 可钓该鱼种的钓法（台钓 / 路亚 / 海钓）
  final List<String> modes;

  /// 一天中的活跃时段（0-23 点），用于「时段活性」维度打分
  final List<int> activeHours;

  /// 喜风浪：风浪推流能提高溶氧、聚饵，这类鱼反而要有点风
  final bool likesWave;

  const FishingSpecies(
    this.name,
    this.optLow,
    this.optHigh,
    this.habit, {
    this.predator = false,
    required this.modes,
    required this.activeHours,
    this.likesWave = false,
  });

  /// 全部鱼种（按钓法归类，不同钓法目标鱼完全不同）
  static const all = <FishingSpecies>[
    // ───────────── 台钓（手竿/台钓，淡水杂食 & 底栖） ─────────────
    FishingSpecies('鲫鱼', 10, 26, '全年可钓，喜弱风稳气压，底钓为主',
        modes: ['台钓'], activeHours: [6, 7, 8, 9, 16, 17, 18]),
    FishingSpecies('鲤鱼', 12, 27, '底栖杂食，喜稳气压与泥底，谨慎靠边',
        modes: ['台钓'], activeHours: [5, 6, 7, 18, 19, 20, 21]),
    FishingSpecies('草鱼', 17, 31, '草食性，高温晴天中午活跃，喜安静',
        modes: ['台钓'], activeHours: [10, 11, 12, 13, 14, 15]),
    FishingSpecies('鳊鱼', 14, 28, '中层杂食，喜缓流与微风，成群索饵',
        modes: ['台钓'], activeHours: [7, 8, 9, 15, 16, 17]),
    FishingSpecies('鳙鱼', 18, 31, '滤食性，高温浮钓，喜肥水与雾化饵',
        modes: ['台钓'], activeHours: [9, 10, 11, 12, 13, 14, 15, 16]),
    FishingSpecies('青鱼', 16, 28, '大型底栖，喜深水螺蛳底，稳气压开口',
        modes: ['台钓'], activeHours: [6, 7, 8, 17, 18, 19]),
    FishingSpecies('黄颡鱼', 12, 28, '夜行性底栖，弱光开口猛，喜腥饵',
        modes: ['台钓'], activeHours: [19, 20, 21, 22, 23, 0, 1]),
    FishingSpecies('罗非鱼', 20, 32, '喜高温，南方水域常见，口重不挑饵',
        modes: ['台钓'], activeHours: [9, 10, 11, 12, 13, 14, 15, 16]),

    // ───────────── 路亚（拟饵，掠食性鱼类） ─────────────
    FishingSpecies('翘嘴鲌', 16, 29, '中上层掠食，喜风浪与晨昏窗口，追小鱼群',
        predator: true,
        modes: ['路亚'],
        activeHours: [5, 6, 7, 18, 19, 20],
        likesWave: true),
    FishingSpecies('鲈鱼', 14, 27, '结构区伏击型，晨昏与阴天开口',
        predator: true,
        modes: ['路亚'],
        activeHours: [6, 7, 8, 17, 18, 19]),
    FishingSpecies('黑鱼', 18, 30, '水草区伏击，闷热雷雨前咬口最猛',
        predator: true,
        modes: ['路亚'],
        activeHours: [8, 9, 10, 16, 17, 18]),
    FishingSpecies('鳜鱼', 15, 28, '底层伏击，喜清水与乱石结构',
        predator: true,
        modes: ['路亚'],
        activeHours: [6, 7, 18, 19, 20]),
    FishingSpecies('马口鱼', 12, 24, '溪流小型掠食，喜急流清水',
        predator: true,
        modes: ['路亚'],
        activeHours: [8, 9, 10, 14, 15, 16],
        likesWave: true),
    FishingSpecies('红尾鲌', 15, 28, '中上层成群，喜风浪推流与坝下',
        predator: true,
        modes: ['路亚'],
        activeHours: [6, 7, 17, 18, 19],
        likesWave: true),

    // ───────────── 海钓（近海 / 礁石 / 船钓） ─────────────
    FishingSpecies('黑鲷', 12, 26, '礁石区底层，喜缓流与礁缝，机警',
        modes: ['海钓'],
        activeHours: [5, 6, 7, 17, 18, 19, 20]),
    FishingSpecies('石斑鱼', 18, 29, '礁洞伏击，喜暖水与清水，涨潮靠边',
        predator: true,
        modes: ['海钓'],
        activeHours: [6, 7, 18, 19, 20]),
    FishingSpecies('海鲈', 10, 24, '河口洄游，喜流口与晨昏，追饵凶猛',
        predator: true,
        modes: ['海钓'],
        activeHours: [5, 6, 7, 17, 18, 19],
        likesWave: true),
    FishingSpecies('鲅鱼', 14, 27, '中上层高速掠食，追小鱼群，喜起流',
        predator: true,
        modes: ['海钓'],
        activeHours: [5, 6, 7, 8, 16, 17, 18],
        likesWave: true),
    FishingSpecies('鲳鱼', 18, 29, '近海中上层，喜暖流与缓风',
        modes: ['海钓'],
        activeHours: [7, 8, 9, 15, 16, 17]),
    FishingSpecies('带鱼', 12, 26, '夜间趋光，船钓/延绳为主，怕强光',
        modes: ['海钓'],
        activeHours: [19, 20, 21, 22, 23, 0, 1, 2]),
  ];

  /// 按钓法取目标鱼（结果缓存，天气页每帧取用也不产生新列表）
  static final Map<String, List<FishingSpecies>> _byMode = {
    for (final m in FishingMode.all)
      m.name: all
          .where((s) => s.modes.contains(m.name))
          .toList(growable: false),
  };

  static List<FishingSpecies> forMode(String mode) => _byMode[mode] ?? all;

  /// 某钓法下是否存在该鱼种（切换钓法时校验选中项）
  static bool inMode(String mode, String speciesName) =>
      forMode(mode).any((s) => s.name == speciesName);

  /// 全部鱼种名（渔获发布页「钓到了什么」用，跨钓法）
  static List<String> get allNames =>
      all.map((s) => s.name).toList(growable: false);
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
/// 鱼情指数引擎（多维加权 + 鱼种习性）
///
/// 各维度 0-100 分，按钓法权重加权；缺失维度（内陆无潮汐）自动剔除并归一化。
/// 输出：总指数、分级、各维度分、黄金时段、分维度建议。
/// ============================================================
class FishScore {
  /// 钓法权重（维度权重之和=1）。
  ///   台钓重气压稳定与溶氧（底栖鱼怕缺氧）；
  ///   路亚重水温与时段（掠食鱼靠窗口期）；
  ///   海钓重潮汐（起流才有鱼）。
  static const Map<String, Map<String, double>> _weights = {
    '台钓': {
      'pressure': 0.26,
      'wind': 0.10,
      'temp': 0.24,
      'oxygen': 0.22,
      'tide': 0.08,
      'time': 0.10,
    },
    '路亚': {
      'pressure': 0.13,
      'wind': 0.17,
      'temp': 0.30,
      'oxygen': 0.15,
      'tide': 0.08,
      'time': 0.17,
    },
    '海钓': {
      'pressure': 0.08,
      'wind': 0.16,
      'temp': 0.17,
      'oxygen': 0.08,
      'tide': 0.36,
      'time': 0.15,
    },
  };

  /// 维度中文名（用于解析弹层）
  static const Map<String, String> dimName = {
    'pressure': '气压',
    'wind': '风',
    'temp': '水温',
    'oxygen': '溶氧',
    'tide': '潮汐',
    'time': '时段',
  };

  const FishScore._();

  /// 气压维度分：稳定中高压（1005~1018）最适；缓降(锋前)短时促口，陡降(变天)大幅扣分。
  /// 掠食性鱼类对锋前降压更敏感（+12），也更扛得住骤降（−10 而不是 −18）。
  static int? pressureScore(double? p, String trend, {bool predator = false}) {
    if (p == null) return null;
    var s = _band(p, 1005, 1018, 985, 1035);
    if (trend == 'falling_slow') {
      s += predator ? 12 : 8;
    } else if (trend == 'falling_fast') {
      s -= predator ? 10 : 18;
    } else if (trend == 'rising') {
      s -= 4;
    }
    return s.clamp(0, 100).round();
  }

  /// 风维度分：喜风浪的鱼（翘嘴/鲅鱼/马口）最佳风速更高；静水鱼（鲫鱼/鲤鱼）怕大风。
  static int? windScore(double? windMs, {bool likesWave = false}) {
    if (windMs == null) return null;
    if (likesWave) return _band(windMs, 2.5, 6.5, 0, 12.0).round();
    return _band(windMs, 1.0, 4.5, 0, 10.8).round();
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

  /// 时段活性分：按鱼种活跃时段打分（0 距离 100，±1h 76，±2h 54，±3h 38，其余 26）
  /// 例如鲫鱼晨昏靠边、黄颡/带鱼夜行、草鱼夏天中午活跃 —— 同一小时不同鱼种分数不同。
  static int timeScore(int hour, FishingSpecies sp) {
    final h = ((hour % 24) + 24) % 24;
    var best = 12;
    for (final a in sp.activeHours) {
      final raw = (h - a).abs();
      final dist = math.min(raw, 24 - raw);
      if (dist < best) best = dist;
    }
    if (best == 0) return 100;
    if (best == 1) return 76;
    if (best == 2) return 54;
    if (best == 3) return 38;
    return 26;
  }

  /// 海钓潮汐分（月相近似）。
  ///   朔（新月）/ 望（满月）附近为大潮，潮差大、起流强 → 鱼口好；
  ///   上/下弦附近为小潮，流缓 → 鱼口一般。
  /// 用朔望月 29.53059 天周期从已知新月时刻推算，无需潮汐站数据。
  static int seaTideScore(DateTime t) {
    const synodic = 29.530588853;
    final base = DateTime.utc(2000, 1, 6, 18, 14); // 已知新月
    final days = t.toUtc().difference(base).inMinutes / 1440.0;
    var phase = (days / synodic) % 1.0;
    if (phase < 0) phase += 1.0;
    final d = math.min(math.min(phase, 1 - phase), (phase - 0.5).abs());
    return (100 - d / 0.25 * 54).round().clamp(40, 100);
  }

  /// 潮汐名（大潮 / 中潮 / 小潮），用于弹层展示
  static String seaTideName(DateTime t) {
    const synodic = 29.530588853;
    final base = DateTime.utc(2000, 1, 6, 18, 14);
    final days = t.toUtc().difference(base).inMinutes / 1440.0;
    var phase = (days / synodic) % 1.0;
    if (phase < 0) phase += 1.0;
    final d = math.min(math.min(phase, 1 - phase), (phase - 0.5).abs());
    if (d <= 0.06) return '大潮';
    if (d <= 0.14) return '中潮';
    return '小潮';
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
    required FishingSpecies sp,
    required DateTime at,
    String? tidePhase, // 内陆传 null
  }) {
    final w = _weights[method] ?? _weights['台钓']!;
    final isSea = method == '海钓';
    final dim = <String, int?>{
      'pressure': pressureScore(pressure, pressureTrend, predator: sp.predator),
      'wind': windScore(windMs, likesWave: sp.likesWave),
      'temp': waterTempScore(waterTemp, sp.optLow, sp.optHigh),
      'oxygen': oxygenScore(dissolvedOxygen),
      // 海钓：按月相推大/中/小潮；内陆钓法无潮汐 → null，自动剔除并归一化
      'tide': tidePhase != null
          ? tideScore(tidePhase)
          : (isSea ? seaTideScore(at) : null),
      'time': timeScore(at.hour, sp),
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
    final advice = _advice(
      dim,
      sp: sp,
      method: method,
      at: at,
      season: seasonOf(at),
    );
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

  /// 分维度建议（挑最拖后腿的两项 + 鱼种习性提示）
  static String _advice(
    Map<String, int?> dim, {
    required FishingSpecies sp,
    required String method,
    required DateTime at,
    required String season,
  }) {
    final tips = <String>[];
    final weak = dim.entries
        .where((e) => e.value != null && e.value! < 60)
        .toList()
      ..sort((a, b) => a.value!.compareTo(b.value!));

    if (weak.any((e) => e.key == 'pressure')) {
      tips.add(sp.predator
          ? '气压在变，掠食鱼锋前会抓一口，抓住降压前的窗口'
          : '气压波动大，鱼口易不稳，宜钓底守稳、少换点');
    }
    if (weak.any((e) => e.key == 'wind')) {
      tips.add(sp.likesWave
          ? '风偏小，${sp.name}不太靠边，可主动找浪区与迎风岸'
          : '风偏大，注意安全与观漂，优先选背风湾');
    }
    if (weak.any((e) => e.key == 'oxygen')) {
      tips.add('溶氧偏低，鱼易上浮，宜钓浮或抓早晚口');
    }
    if (weak.any((e) => e.key == 'temp')) {
      tips.add('水温偏离${sp.name}适温（${sp.optLow.toStringAsFixed(0)}~'
          '${sp.optHigh.toStringAsFixed(0)}℃），活性下降，钓深或换目标鱼');
    }
    if (weak.any((e) => e.key == 'tide')) {
      tips.add('潮汐偏弱，等起流再打窝，平流期口稀');
    }
    if (weak.any((e) => e.key == 'time')) {
      final hh = sp.activeHours.take(3).map((h) => '$h:00').join(' / ');
      tips.add('当前不在${sp.name}活跃窗口，建议 $hh 前后再下竿');
    }
    // 掠食鱼补一条用饵提示，台钓补一条打窝提示
    if (tips.length < 2) {
      if (sp.predator) {
        tips.add('$method以${sp.name}为目标，优先搜结构边、陡坎与回流区');
      } else if (method == '台钓') {
        tips.add('${sp.name}靠窝子留鱼，少量多次补窝比一次打重窝更稳');
      }
    }
    if (tips.isEmpty) {
      tips.add('综合条件佳，把握黄金时段出钓');
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
  static List<String> defaultWindows(String season) => _defaultWindows(season);
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
      sp: sp,
      at: h.time,
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
        sp: sp,
        at: h.time,
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
