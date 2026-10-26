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

  /// 最低耐受水氧（mg/L）—— 不同鱼种对缺氧的耐受力差异极大：
  ///   鲫鱼/黑鱼/罗非能忍 3.5~4.2，草鱼/青鱼要 5 以上，
  ///   清水掠食鱼（马口、鳜鱼）低于 6 就基本不追饵。
  /// 原先统一按 6mg/L 判满分，等于把「缺氧」这个最关键的限制因子抹掉了。
  static const Map<String, double> _minDo = {
    '鲫鱼': 4.2, '鲤鱼': 4.5, '草鱼': 5.2, '鳊鱼': 4.8, '鳙鱼': 4.5,
    '青鱼': 5.0, '黄颡鱼': 4.0, '罗非鱼': 3.8,
    '翘嘴鲌': 5.6, '鲈鱼': 5.6, '黑鱼': 3.4, '鳜鱼': 6.2,
    '马口鱼': 6.6, '红尾鲌': 5.8,
    '黑鲷': 5.2, '石斑鱼': 5.8, '海鲈': 5.6, '鲅鱼': 6.0,
    '鲳鱼': 5.4, '带鱼': 5.4,
  };

  /// 该鱼种开口所需的最低水氧（mg/L）
  double get minDo => _minDo[name] ?? 5.0;

  /// 适温区间中点（水温打分的最高点）
  double get optMid => (optLow + optHigh) / 2;

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

/// 水体指标（水温 / 水氧）
class WaterMetrics {
  /// 水温 ℃
  final double temp;

  /// 水氧（溶解氧）mg/L
  final double oxygen;

  const WaterMetrics(this.temp, this.oxygen);

  /// 由逐小时气温/风/气压序列推导水温与水氧。
  ///
  /// 水温（水体热惯性模型）：
  ///   以「前后约 30 小时气温的距离加权均值」为平衡气温 Te（越近权重越大），
  ///   水温 = Te + 1.2（蓄热） + 0.22 ×（该小时气温 − Te），
  ///   并把日变化幅度限制在 ±2.4℃ —— 真实水体一天只摆动 1~3℃，
  ///   远小于气温的 8~15℃，这也解释了为什么水温曲线比气温平缓。
  ///
  /// 水氧：先算该水温下的淡水饱和溶氧
  ///   DOsat = 14.652 − 0.41022T + 0.007991T² − 0.000077774T³
  /// 再乘饱和比（风浪增氧、气压升高增氧、夜间藻类呼吸耗氧）：
  ///   ratio = 0.74 + 0.14×(风速/6) + 0.06×(气压−1013)/20 − 0.05×夜间
  /// 结果限制在 2~14mg/L。
  static List<WaterMetrics> derive(List<HourPoint> hours) {
    if (hours.isEmpty) return const [];
    final out = <WaterMetrics>[];
    for (var i = 0; i < hours.length; i++) {
      final h = hours[i];
      final te = _eqAir(hours, i);
      final swing = (0.22 * (h.temp - te)).clamp(-2.4, 2.4);
      final tw = (te + 1.2 + swing).clamp(1.0, 34.0);

      final doSat = 14.652 -
          0.41022 * tw +
          0.007991 * tw * tw -
          0.000077774 * tw * tw * tw;
      final night = (h.time.hour < 6 || h.time.hour >= 22) ? 1.0 : 0.0;
      final ratio = (0.74 +
              0.14 * (h.windMs.clamp(0.0, 6.0) / 6.0) +
              0.06 * ((h.pressure - 1013) / 20).clamp(-1.0, 1.0) -
              0.05 * night)
          .clamp(0.62, 0.95);
      final o2 = (doSat * ratio).clamp(2.0, 14.0);

      out.add(WaterMetrics(
        double.parse(tw.toStringAsFixed(1)),
        double.parse(o2.toStringAsFixed(2)),
      ));
    }
    return out;
  }

  /// 第 i 小时的水体平衡气温：取 i-24 ~ i+6 小时的距离加权均值
  /// （水体响应滞后于气温，且过去的影响大于未来）
  static double _eqAir(List<HourPoint> hours, int i) {
    double wsum = 0, acc = 0;
    for (var j = i - 24; j <= i + 6; j++) {
      if (j < 0 || j >= hours.length) continue;
      final w = 1.0 / (1.0 + (j - i).abs() * 0.15);
      wsum += w;
      acc += hours[j].temp * w;
    }
    return wsum > 0 ? acc / wsum : hours[i].temp;
  }
}

/// ============================================================
/// 鱼情指数引擎（多维加权 + 鱼种习性 + 短板约束）
///
/// 设计原则（这是「为什么别家显示不宜、我们显示爆护」的修正）：
///  1. 每个维度都要能拉开差距 —— 不再出现「气压 1005 就满分、水氧 ≥6 就满分」，
///     否则大部分小时所有维度都接近 100，均值自然全天爆护。
///  2. 维度上限 95 而非 100 —— 现实里不存在完美条件。
///  3. 加权均值后叠加「短板惩罚」：任何一项低于 62 分都会显著拖累整体，
///     因为均值会把「水氧极差」这种致命问题稀释掉。
///  4. 一票否决：雷暴 / 严重缺氧 / 水温远离适温，直接压低到对应上限。
///
/// 分值口径（与 App 内标签一致）：
///   ≥90 爆护 · 80~89 有口 · 25~79 口弱 · <25 无口
/// ============================================================
class FishScore {
  /// 钓法权重（维度权重之和=1）。
  ///   台钓重水氧与水温（底栖鱼怕缺氧、对水温敏感）；
  ///   路亚重水温与时段（掠食鱼靠窗口期）；
  ///   海钓重潮汐（起流才有鱼）。
  static const Map<String, Map<String, double>> _weights = {
    '台钓': {
      'pressure': 0.17,
      'temp': 0.22,
      'oxygen': 0.20,
      'wind': 0.09,
      'weather': 0.13,
      'stable': 0.06,
      'time': 0.13,
    },
    '路亚': {
      'pressure': 0.11,
      'temp': 0.26,
      'oxygen': 0.14,
      'wind': 0.15,
      'weather': 0.12,
      'stable': 0.05,
      'time': 0.17,
    },
    '海钓': {
      'pressure': 0.06,
      'temp': 0.15,
      'oxygen': 0.08,
      'wind': 0.13,
      'weather': 0.10,
      'stable': 0.05,
      'time': 0.12,
      'tide': 0.31,
    },
  };

  /// 维度中文名（用于解析弹层）
  static const Map<String, String> dimName = {
    'pressure': '气压',
    'temp': '水温',
    'oxygen': '水氧',
    'wind': '风',
    'weather': '天气',
    'stable': '温差',
    'time': '时段',
    'tide': '潮汐',
  };

  const FishScore._();

  /// 气压维度分：海平面气压 1013~1022hPa 最稳（95），
  /// 低压（<1006）与强高压（>1030）都压口；再按 3 小时变压修正：
  ///   缓降 = 锋前短时促口（+4）；急降 = 变天停口（−12）；骤升 = 冷锋后不适应（−8）。
  static int? pressureScore(double? p, String trend) {
    if (p == null) return null;
    var s = _interp(p, const [
      [980, 40], [992, 54], [1000, 64], [1006, 74],
      [1012, 85], [1018, 92], [1024, 88], [1030, 78], [1040, 62],
    ]);
    switch (trend) {
      case 'falling_fast':
        s -= 12;
        break;
      case 'falling_slow':
        s += 4;
        break;
      case 'rising_fast':
        s -= 8;
        break;
      case 'rising':
        s -= 1;
        break;
      default:
        s += 2;
    }
    return s.clamp(0, 95).round();
  }

  /// 风维度分：2~4m/s 最适（推流增氧、聚饵又不影响观漂）；
  /// 无风（<0.6）闷、水氧难循环；6m/s 以上明显压口；10m/s 以上基本没法钓。
  /// 喜风浪的鱼（翘嘴/鲅鱼/马口/海鲈）最适风速右移约 1.4 倍。
  static int? windScore(double? windMs, {bool likesWave = false}) {
    if (windMs == null) return null;
    final v = likesWave ? windMs * 0.72 : windMs;
    return _interp(v, const [
      [0, 68], [0.6, 78], [1.2, 85], [2.2, 92], [3.5, 95],
      [5.0, 86], [6.5, 72], [8.0, 56], [10, 38], [14, 20],
    ]).round();
  }

  /// 水温维度分：适温区间中点 95 分、区间边缘 80 分，
  /// 越界后每偏离 1℃ 扣 8.5 分（4℃ 外就只剩 46 分）。
  /// 原实现给了 12℃ 的宽容区，等于「水温 5~34℃ 都满分」，严重高估。
  static int? waterTempScore(double? t, double low, double high) {
    if (t == null) return null;
    final center = (low + high) / 2;
    final half = math.max(1.0, (high - low) / 2);
    if (t >= low && t <= high) {
      return (80 + 15 * (1 - (t - center).abs() / half)).round().clamp(0, 95);
    }
    final excess = t < low ? low - t : t - high;
    return (80 - 8.5 * excess).clamp(0, 95).round();
  }

  /// 水氧维度分：按目标鱼种的最低需求折算（相对值），而不是固定 6mg/L。
  ///   达到 1.5 倍需求 → 91 分；刚好卡在需求线 → 72 分；
  ///   只有需求的 70% → 32 分（浮头、基本停口）。
  static int? oxygenScore(double? doMgL, {double need = 5.0}) {
    if (doMgL == null) return null;
    final r = doMgL / need;
    return _interp(r, const [
      [0.5, 12], [0.7, 32], [0.85, 52], [1.0, 72], [1.2, 84], [1.5, 91], [2.0, 95],
    ]).round();
  }

  /// 天气维度分：稳定阴天/多云最利于开口；小雨好、大雨差、雷暴一票否决；
  /// 夏季高温晴天正午再扣热应激，冬季严寒扣开口。
  static int? weatherScore({
    required int code,
    required int precipProb,
    required double airTemp,
    required int hour,
  }) {
    var s = _wxBase(code);
    if (precipProb >= 85) {
      s -= 10;
    } else if (precipProb >= 65) {
      s -= 5;
    }
    if (airTemp >= 33 && hour >= 11 && hour <= 16) {
      s -= 22;
    } else if (airTemp >= 30 && hour >= 11 && hour <= 16) {
      s -= 10;
    } else if (airTemp <= 2) {
      s -= 8;
    }
    return s.clamp(0, 95).round();
  }

  static int _wxBase(int code) {
    if (code >= 95) return 10;
    if (code == 65 || code == 82) return 30;
    if (code == 67) return 26;
    if (code == 81) return 48;
    if (code == 63) return 62;
    if (code == 55) return 70;
    if (code == 61 || code == 80) return 82;
    if (code == 51 || code == 53) return 84;
    if (code == 45 || code == 48) return 74;
    if (code == 71 || code == 73) return 52;
    if (code == 75 || code == 85 || code == 86) return 34;
    switch (code) {
      case 0:
        return 82;
      case 1:
        return 87;
      case 2:
        return 90;
      case 3:
        return 88;
    }
    return 80;
  }

  /// 温差（稳定性）维度分：昼夜温差越大，水温波动越大，鱼需要反复适应，
  /// 开口窗口被压缩到早晚两头。≤6℃ 最稳，≥15℃ 明显压口。
  static int? stabilityScore(double? dayRange) {
    if (dayRange == null) return null;
    return _interp(dayRange, const [
      [4, 93], [6, 89], [8, 84], [10, 78], [12, 70], [15, 59], [18, 48], [22, 38],
    ]).round();
  }

  /// 潮汐维度分：起流 > 转向 > 平流（内陆无潮汐时返回 null → 自动剔除）
  static int? tideScore(String? phase) {
    if (phase == null || phase.isEmpty) return null;
    const m = {'flowing': 95, 'turning': 80, 'slack': 60};
    return m[phase] ?? 70;
  }

  /// 时段活性分：按鱼种活跃时段打分（0 距离最高，±1h、±2h、±3h 递减）。
  /// 上限 94 —— 时段只是机会窗口，不能单独把总分推到爆护。
  static int timeScore(int hour, FishingSpecies sp) {
    final h = ((hour % 24) + 24) % 24;
    var best = 12;
    for (final a in sp.activeHours) {
      final raw = (h - a).abs();
      final dist = math.min(raw, 24 - raw);
      if (dist < best) best = dist;
    }
    if (best == 0) return 94;
    if (best == 1) return 80;
    if (best == 2) return 62;
    if (best == 3) return 46;
    return 34;
  }

  /// 海钓潮汐分（月相近似）。
  ///   朔（新月）/ 望（满月）附近为大潮，潮差大、起流强 → 鱼口好；
  ///   上/下弦附近为小潮，流缓 → 鱼口一般。
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

  /// 分段线性插值（pts 必须按 x 升序）
  static double _interp(double v, List<List<num>> pts) {
    if (v <= pts.first[0]) return pts.first[1].toDouble();
    for (var i = 1; i < pts.length; i++) {
      if (v <= pts[i][0]) {
        final a = pts[i - 1], b = pts[i];
        final span = (b[0] - a[0]).toDouble();
        if (span <= 0) return b[1].toDouble();
        final t = (v - a[0]) / span;
        return a[1] + (b[1] - a[1]) * t;
      }
    }
    return pts.last[1].toDouble();
  }

  /// 气压趋势中文（用于解读文案）
  static String trendCn(String? trend) {
    switch (trend) {
      case 'falling_fast':
        return '3 小时内急降';
      case 'falling_slow':
        return '缓慢下降';
      case 'rising_fast':
        return '快速回升';
      case 'rising':
        return '缓慢回升';
      default:
        return '基本平稳';
    }
  }

  /// 多维加权打分（唯一入口：传一个小时的完整气象 + 水体指标）
  static FishScoreResult compute({
    required String method,
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    String? tidePhase, // 内陆传 null
  }) {
    final weights = _weights[method] ?? _weights['台钓']!;
    final isSea = method == '海钓';
    final dim = <String, int?>{
      'pressure': pressureScore(h.pressure, h.pressureTrend ?? 'steady'),
      'temp': waterTempScore(w.temp, sp.optLow, sp.optHigh),
      'oxygen': oxygenScore(w.oxygen, need: sp.minDo),
      'wind': windScore(h.windMs, likesWave: sp.likesWave),
      'weather': weatherScore(
        code: h.weatherCode,
        precipProb: h.precipProb,
        airTemp: h.temp,
        hour: h.time.hour,
      ),
      'stable': stabilityScore(h.dayRange),
      'time': timeScore(h.time.hour, sp),
      // 海钓：按月相推大/中/小潮；内陆钓法无潮汐 → null，自动剔除并归一化
      'tide': tidePhase != null
          ? tideScore(tidePhase)
          : (isSea ? seaTideScore(h.time) : null),
    };

    double wsum = 0, acc = 0;
    var minV = 100;
    for (final k in weights.keys) {
      final v = dim[k];
      if (v == null) continue;
      wsum += weights[k]!;
      acc += v * weights[k]!;
      if (v < minV) minV = v;
    }
    var score = wsum > 0 ? acc / wsum : 50.0;

    // 短板惩罚：任何一项低于 62 分都在拖后腿，按差距线性加重
    if (minV < 62) score -= (62 - minV) * 0.55;

    // 一票否决 / 硬上限（再好的其它条件也救不回来）
    if (h.weatherCode >= 95) score = math.min(score, 22);
    // 大风：7 级以上观漂困难、抛投失准，8 级以上基本没法钓
    if (h.windMs >= 9) {
      score = math.min(score, 58);
    } else if (h.windMs >= 7) {
      score = math.min(score, 72);
    }
    final o2 = dim['oxygen'];
    if (o2 != null && o2 < 45) score = math.min(score, 55);
    final tw = dim['temp'];
    if (tw != null && tw < 45) score = math.min(score, 52);

    final indexScore = score.round().clamp(0, 96);

    return FishScoreResult(
      indexScore: indexScore,
      grade: gradeOf(indexScore),
      dim: dim,
      advice: _advice(dim, h: h, w: w, sp: sp, method: method),
      positives: _positives(dim, h: h, w: w, sp: sp),
      negatives: _negatives(dim, h: h, w: w, sp: sp),
    );
  }

  /// 用「裸参数」打分 —— 首页天气卡 / 水印相机这类没有完整 HourPoint 的场景，
  /// 仍走同一套算法，避免出现「首页说极佳、天气页说口弱」两套口径。
  static FishScoreResult computeRaw({
    required String method,
    required double airTemp,
    required double pressure,
    required double windMs,
    required double waterTemp,
    required double dissolvedOxygen,
    required int weatherCode,
    required FishingSpecies sp,
    String pressureTrend = 'steady',
    int precipProb = 0,
    int hour = 12,
    double? dayRange,
    DateTime? at,
  }) {
    final h = HourPoint(
      time: at ?? DateTime(2000, 1, 1, hour),
      temp: airTemp,
      humidity: 60,
      pressure: pressure,
      precipProb: precipProb,
      precip: 0,
      windSpeed: windMs * 3.6,
      windDir: 0,
      weatherCode: weatherCode,
      pressureTrend: pressureTrend,
      dayRange: dayRange,
    );
    return compute(
      method: method,
      h: h,
      w: WaterMetrics(waterTemp, dissolvedOxygen),
      sp: sp,
    );
  }

  /// 总分 → 分级（与 Bite.label 口径一致）
  static String gradeOf(int? s) {
    if (s == null) return '—';
    if (s >= 90) return '爆护';
    if (s >= 80) return '有口';
    if (s >= 45) return '口弱';
    return '难开口';
  }

  /// 有利因素（带具体数值，供「AI 解析」逐条展示）
  static List<String> _positives(
    Map<String, int?> dim, {
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
  }) {
    final out = <String>[];
    final p = dim['pressure'];
    if (p != null && p >= 85) {
      out.add('气压 ${h.pressure.toStringAsFixed(0)}hPa ${trendCn(h.pressureTrend)}，水体携氧条件好');
    }
    final t = dim['temp'];
    if (t != null && t >= 88) {
      out.add('水温 ${w.temp.toStringAsFixed(1)}℃ 正处${sp.name}适温 ${sp.optLow.toStringAsFixed(0)}~${sp.optHigh.toStringAsFixed(0)}℃ 核心区');
    }
    final ox = dim['oxygen'];
    if (ox != null && ox >= 85) {
      out.add('水氧 ${w.oxygen.toStringAsFixed(1)}mg/L，是${sp.name}需求（${sp.minDo.toStringAsFixed(1)}）的 ${(w.oxygen / sp.minDo * 100).round()}%，开口欲望强');
    }
    final wd = dim['wind'];
    if (wd != null && wd >= 85) {
      out.add('${windLevelText(h.windSpeed, h.windDir)}，刚好推流聚饵又不影响观漂');
    }
    final wx = dim['weather'];
    if (wx != null && wx >= 85) {
      out.add('${Wmo.text(h.weatherCode)}天光照平稳，鱼不惊慌、愿意靠边');
    }
    final st = dim['stable'];
    if (st != null && st >= 85 && h.dayRange != null) {
      out.add('昼夜温差 ${h.dayRange!.toStringAsFixed(0)}℃，水温稳定，全天口相对连贯');
    }
    final tm = dim['time'];
    if (tm != null && tm >= 80) {
      out.add('${h.time.hour} 点正处${sp.name}觅食窗口');
    }
    return out;
  }

  /// 不利因素（带具体数值）
  static List<String> _negatives(
    Map<String, int?> dim, {
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
  }) {
    final out = <String>[];
    final p = dim['pressure'];
    if (p != null && p < 78) {
      out.add('气压 ${h.pressure.toStringAsFixed(0)}hPa（${trendCn(h.pressureTrend)}）偏低，水体携氧差，鱼易离底上浮、吃口变轻');
    }
    final ox = dim['oxygen'];
    if (ox != null && ox < 78) {
      out.add('水氧 ${w.oxygen.toStringAsFixed(1)}mg/L 只到${sp.name}需求（${sp.minDo.toStringAsFixed(1)}）的 ${(w.oxygen / sp.minDo * 100).round()}%，开口欲望被压制');
    }
    final t = dim['temp'];
    if (t != null && t < 78) {
      final over = w.temp > sp.optHigh
          ? '高出适温上限 ${(w.temp - sp.optHigh).toStringAsFixed(1)}℃'
          : '低于适温下限 ${(sp.optLow - w.temp).toStringAsFixed(1)}℃';
      out.add('水温 ${w.temp.toStringAsFixed(1)}℃ $over，${sp.name}活性下降');
    }
    final wd = dim['wind'];
    if (wd != null && wd < 72) {
      out.add(sp.likesWave
          ? '风力 ${beaufortLevel(h.windSpeed)} 级偏小，水面太静，${sp.name}不聚边、追饵不积极'
          : '风力 ${beaufortLevel(h.windSpeed)} 级偏大，观漂困难、鱼受惊躲深水');
    }
    final wx = dim['weather'];
    if (wx != null && wx < 72) {
      out.add('${Wmo.text(h.weatherCode)}${h.precipProb >= 65 ? '、降水概率 ${h.precipProb}%' : ''}，对开口不利');
    }
    final st = dim['stable'];
    if (st != null && st < 78 && h.dayRange != null) {
      out.add('昼夜温差 ${h.dayRange!.toStringAsFixed(0)}℃，水温波动大，鱼要花时间适应');
    }
    final tm = dim['time'];
    if (tm != null && tm < 62) {
      final hh = sp.activeHours.take(3).map((x) => '$x 点').join('、');
      out.add('${h.time.hour} 点不在${sp.name}觅食窗口（$hh 前后更稳）');
    }
    return out;
  }

  /// 分维度建议：先点出最拖后腿的两项，再给可执行动作
  static String _advice(
    Map<String, int?> dim, {
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    required String method,
  }) {
    final negs = _negatives(dim, h: h, w: w, sp: sp);
    final tips = <String>[];

    final weak = dim.entries
        .where((e) => e.value != null && e.value! < 62)
        .toList()
      ..sort((a, b) => a.value!.compareTo(b.value!));

    if (weak.any((e) => e.key == 'oxygen')) {
      tips.add(sp.predator ? '水氧不足时掠食鱼会离底追氧，改钓中上层、放慢节奏' : '水氧偏低，改钓浮或抓早晚，别在静水死角死守');
    }
    if (weak.any((e) => e.key == 'pressure')) {
      tips.add(sp.predator ? '气压在变，掠食鱼锋前会抓一口，盯住降压前的 1~2 小时' : '气压不稳，鱼口易断，宜钓底守稳、少换点');
    }
    if (weak.any((e) => e.key == 'temp')) {
      tips.add('水温偏离适温，钓深一点或换耐温的目标鱼');
    }
    if (weak.any((e) => e.key == 'wind')) {
      tips.add(sp.likesWave ? '风偏小，主动找浪区、迎风岸' : '风偏大，优先背风湾、加重铅坠');
    }
    if (weak.any((e) => e.key == 'time')) {
      final hh = sp.activeHours.take(3).map((x) => '$x 点').join(' / ');
      tips.add('建议 $hh 前后再下竿');
    }
    if (tips.length < 2) {
      if (sp.predator) {
        tips.add('$method以${sp.name}为目标，优先搜结构边、陡坎与回流区');
      } else if (method == '台钓') {
        tips.add('${sp.name}靠窝子留鱼，少量多次补窝比一次打重窝更稳');
      }
    }

    final head = negs.isEmpty ? '各项条件都在${sp.name}舒适区' : negs.take(2).join('；');
    return '$head。${tips.join('；')}。';
  }

  /// 由当天逐时总分数派生黄金时段（3h 滑动窗，取 82 分以上且不重叠，最多 2 段）
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
    for (final win in wins) {
      if (win['avg']! < 82) break;
      if (top.any((t) => (t['start']! - win['start']!).abs() < W)) continue;
      top.add(win);
      if (top.length >= 2) break;
    }
    if (top.isEmpty) return _defaultWindows(season);
    String p(int n) => n.toString().padLeft(2, '0');
    return top
        .map((win) => '${p(win['start']!)}:00-${p(win['start']! + W)}:00')
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

  /// 有利 / 不利因素（带具体数值，供 AI 解析逐条展示）
  final List<String> positives;
  final List<String> negatives;

  const FishScoreResult({
    required this.indexScore,
    required this.grade,
    required this.dim,
    required this.advice,
    this.positives = const [],
    this.negatives = const [],
  });
}

/// 逐小时鱼情评分 + 档位判定（对外签名保持稳定，便于天气页直接调用）
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
      h: h,
      w: w,
      sp: sp,
    );
    return r.indexScore ?? 50;
  }

  /// 完整结果（供 AI 解析弹层展示）
  static FishScoreResult compute({
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    required FishingMode mode,
  }) =>
      FishScore.compute(method: mode.name, h: h, w: w, sp: sp);

  /// 各维度分（供 AI 解析弹层展示）
  static Map<String, int?> dimensionScores({
    required HourPoint h,
    required WaterMetrics w,
    required FishingSpecies sp,
    required FishingMode mode,
  }) =>
      FishScore.compute(method: mode.name, h: h, w: w, sp: sp).dim;

  /// 档位：80 分以下口弱、80~89 有口、90 以上爆护
  /// （25 分以下已属「浮头停口」，单列为无口，方便看出极端天气）
  static String label(int score) {
    if (score >= 90) return '爆护';
    if (score >= 80) return '有口';
    if (score >= 25) return '口弱';
    return '无口';
  }

  /// 鱼情图标数量（1-3）
  static int fishCount(int score) {
    if (score >= 90) return 3;
    if (score >= 80) return 2;
    return 1;
  }
}
