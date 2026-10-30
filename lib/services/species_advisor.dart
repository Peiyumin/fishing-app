import 'dart:math' as math;

import '../models/fishing_species.dart';

/// 一条鱼种推荐
class SpeciesPick {
  /// 鱼种名（鲫鱼 / 鲤鱼 …）
  final String name;

  /// 习性一句话（来自 [FishingSpecies.habit]，不编）
  final String habit;

  /// 匹配度 0–100
  final int match;

  /// 为什么推荐它（水温 / 时段 / 风浪三个维度里真正起了作用的那几条）
  final String why;

  /// 适合的钓法（该鱼种自己的 modes 第一条）
  final String mode;

  const SpeciesPick({
    required this.name,
    required this.habit,
    required this.match,
    required this.why,
    required this.mode,
  });
}

/// 「按鱼的习性推最适合的鱼种」（v2.1.57）
///
/// 原来的 AI 报告把目标鱼**写死成鲫鱼**，只在「适合 鲫鱼」那一个小胶囊里出现。
/// 实际上同一个水温下，16℃ 该主攻鲫鱼，26℃ 该主攻草鱼/鳙鱼，闷热低压天
/// 黄颡鱼反而靠夜口——这本来就是鱼种自身习性决定的，不能一句话糊过去。
///
/// 这里不引入任何新数据源：全部用 [FishingSpecies] 里已有的四个习性字段
/// （适温区间 optLow/optHigh、活跃时段 activeHours、喜风浪 likesWave、
/// 可钓鱼法 modes），按当前水温 / 所处小时 / 风力逐条打分，取最高的几个。
///
/// 打分口径（权重 deliberately 简单，便于解释也便于改）：
///   · 水温适配 70 分：落在适温区间内满分，每偏离 1℃ 扣 6 分（最低 0）
///   · 活跃时段 20 分：当前小时在该鱼活跃时段内满分，否则按「离最近活跃点几小时」
///     每小时扣 4 分（最低 0）——不是一刀切扣光，因为鱼口是渐变的
///   · 风浪 10 分：喜风浪的鱼在 2–4 级风里加分，怕风的鱼在 5 级以上扣分
///
/// 结果按分数降序，同分时保持 [FishingSpecies.all] 里的原始顺序（鲫鱼在前），
/// 这样不同设备上算出来的顺序完全一致。
class SpeciesAdvisor {
  const SpeciesAdvisor._();

  /// 推荐鱼种
  ///
  /// [waterTemp] 当前水温（℃，[WaterMetrics.temp]）；
  /// [hour] 当前小时 0–23；
  /// [windLevel] 蒲福风级（0–6，够判断）；
  /// [mode] 只要这个钓法能钓的鱼种（默认台钓，与报告口径一致）；
  /// [take] 最多返回几条（默认 3：一个主攻 + 两个备选，再多就不是「推荐」了）。
  static List<SpeciesPick> recommend({
    required double waterTemp,
    required int hour,
    int windLevel = 2,
    String mode = '台钓',
    int take = 3,
  }) {
    final out = <SpeciesPick>[];
    for (final sp in FishingSpecies.all) {
      // 钓法不对的鱼种直接排除（海钓鱼种不应出现在内陆水库的报告里）
      if (!sp.modes.contains(mode)) continue;
      out.add(_pick(sp, waterTemp: waterTemp, hour: hour, windLevel: windLevel));
    }
    // 稳定排序：分数高的在前，同分按原始顺序（Dart 的 sort 不保证稳定，这里带下标）
    final indexed = <MapEntry<int, SpeciesPick>>[
      for (var i = 0; i < out.length; i++) MapEntry(i, out[i]),
    ]..sort((a, b) {
        final c = b.value.match.compareTo(a.value.match);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final sorted = indexed.map((e) => e.value).toList();
    return sorted.take(math.max(1, take)).toList();
  }

  static SpeciesPick _pick(
    FishingSpecies sp, {
    required double waterTemp,
    required int hour,
    required int windLevel,
  }) {
    // ── ① 水温 70 分 ──
    double tempScore;
    final notes = <String>[];
    final t = waterTemp;
    if (t >= sp.optLow && t <= sp.optHigh) {
      tempScore = 70;
      notes.add('水温 ${t.toStringAsFixed(1)}℃ 正落在 ${sp.optLow.toStringAsFixed(0)}-'
          '${sp.optHigh.toStringAsFixed(0)}℃ 舒适区');
    } else {
      final off = t < sp.optLow ? (sp.optLow - t) : (t - sp.optHigh);
      tempScore = math.max(0.0, 70 - off * 6);
      notes.add('水温 ${t.toStringAsFixed(1)}℃ 偏离舒适区 '
          '${sp.optLow.toStringAsFixed(0)}-${sp.optHigh.toStringAsFixed(0)}℃ '
          '${off.toStringAsFixed(1)}℃');
    }

    // ── ② 活跃时段 20 分 ──
    double hourScore;
    if (sp.activeHours.contains(hour)) {
      hourScore = 20;
      notes.add('${_hhmm(hour)} 正好是它的开口时段');
    } else {
      var best = 24;
      for (final h in sp.activeHours) {
        // 环形距离（23 点与 0 点相邻），否则 23 点离 0 点会被算成 23 小时
        final d = (h - hour).abs();
        best = math.min(best, math.min(d, 24 - d));
      }
      hourScore = math.max(0.0, 20 - best * 4);
      if (best <= 2) {
        notes.add('离它的开口时段还有 $best 小时');
      }
    }

    // ── ③ 风浪 10 分 ──
    double windScore = 5; // 中性起点：无风无浪不奖不罚
    if (sp.likesWave) {
      if (windLevel >= 2 && windLevel <= 4) {
        windScore = 10;
        notes.add('$windLevel 级风正合它喜风浪的性子');
      } else if (windLevel >= 5) {
        windScore = 2;
      }
    } else if (windLevel >= 5) {
      windScore = 0;
      notes.add('$windLevel 级风偏大，它不太吃风浪');
    }

    final match = (tempScore + hourScore + windScore).round().clamp(0, 100);
    return SpeciesPick(
      name: sp.name,
      habit: sp.habit,
      match: match,
      why: notes.join(' · '),
      mode: sp.modes.isEmpty ? '台钓' : sp.modes.first,
    );
  }

  static String _hhmm(int hour) =>
      '${hour.toString().padLeft(2, '0')}:00';
}
