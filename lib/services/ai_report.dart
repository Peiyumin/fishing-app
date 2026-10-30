import 'dart:math' as math;

import '../models/fishing_species.dart';
import '../models/weather_forecast.dart';
import 'ai_spot_service.dart';
import 'species_advisor.dart';

/// AI 分析报告的图标语义（纯数据层不依赖 Flutter，映射在 UI 里做）
enum AiIcon {
  weather,
  temp,
  water,
  wind,
  pressure,
  oxygen,
  humidity,
  climate,
  coast,
  road,
  fish,
  evidence,
  time,
  gear,
  bait,
  spot,
  warn,
}

/// 一条「依据」指标（当日天气那一排小格子）
class AiMetric {
  final AiIcon icon;
  final String label;
  final String value;
  const AiMetric(this.icon, this.label, this.value);
}

/// 黄金小时
class AiGold {
  final String hhmm;
  final int score;
  const AiGold(this.hhmm, this.score);
}

/// 「为什么选这里」的一条
class AiReason {
  final AiIcon icon;
  final String title;
  final String tag;
  final String body;
  const AiReason(this.icon, this.title, this.tag, this.body);
}

/// 评分构成的一条
class AiScorePart {
  final String label;
  final int value;
  final String note;
  const AiScorePart(this.label, this.value, this.note);
}

/// 「怎么钓」的一条
class AiTactic {
  final AiIcon icon;
  final String title;
  final String body;
  const AiTactic(this.icon, this.title, this.body);
}

/// AI 分析报告（v2.1.56）
///
/// 口径：**全部用真实数据算**，不编排名、不写不存在的路名。
/// 分数与雷达列表同源（[AiSpotService.scoreParts]），避免「列表 84、详情 82」。
class AiReport {
  final int score;
  final String grade;

  /// 主攻鱼种名（= [picks] 第一条，保留给只想要一个名字的地方用）
  final String species;

  /// 按鱼种习性推荐出来的鱼种（v2.1.57，从高到低，默认 3 条）
  ///
  /// 以前这里只有一个写死的「鲫鱼」：26℃ 的水还是让你钓鲫鱼，明显不对。
  /// 现在由 [SpeciesAdvisor] 按水温 / 时段 / 风浪逐条打分。
  final List<SpeciesPick> picks;

  final String mode;
  final String headline;
  final String windowText;
  final String dateTag;
  final String distanceText;
  final List<AiGold> golden;
  final List<AiMetric> metrics;
  final List<AiReason> reasons;
  final List<AiTactic> tactics;
  final List<AiScorePart> parts;

  /// 有天气数据时才有的「气压/水温」原始值（详情页顶部大号展示用）
  final double? waterTemp;
  final double? oxygen;
  final int? pressure;

  const AiReport({
    required this.score,
    required this.grade,
    required this.species,
    this.picks = const [],
    required this.mode,
    required this.headline,
    required this.windowText,
    required this.dateTag,
    required this.distanceText,
    required this.golden,
    required this.metrics,
    required this.reasons,
    required this.tactics,
    required this.parts,
    this.waterTemp,
    this.oxygen,
    this.pressure,
  });

  static String gradeOf(int score) {
    if (score >= 90) return '爆护';
    if (score >= 80) return '有口';
    if (score >= 60) return '一般';
    if (score >= 25) return '口弱';
    return '无口';
  }

  /// 目标鱼：默认鲫鱼（台钓口径，与天气页指数一致）
  static FishingSpecies get targetSpecies => FishingSpecies.all.first;
  static FishingMode get targetMode => FishingMode.all.first;

  /// 生成报告
  ///
  /// [bundle] 为「该钓点坐标」的天气（不是我的位置 —— 5 公里外的水库
  /// 风向可能就变了）；拿不到就退化成只有水域/距离依据的版本。
  static AiReport build({
    required AiSpot spot,
    WeatherBundle? bundle,
    required double myLat,
    required double myLng,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    // ★ v2.1.57：基础分用的目标鱼固定为鲫鱼（与雷达列表一致），
    //   报告正文里「主攻」哪条鱼由下面的习性推荐决定。若这里改用推荐鱼种，
    //   同一份天气会算出另一个基础分，列表与详情又会打架。
    var sp = targetSpecies;
    final mode = targetMode;

    // ★ 和雷达列表用**同一套取小时口径**（hourNear / indexOfHourNear）。
    //   列表扫描时走的是「最近整点」，报告原来走的是「当前整点」：
    //   9:48 扫描取 10:00、详情取 9:00，两边水温/气压不同 → 列表 64、详情 74。
    final idx = bundle == null ? -1 : bundle.indexOfHourNear(now);
    final HourPoint? h =
        (bundle != null && idx >= 0 && idx < bundle.hours.length)
            ? bundle.hours[idx]
            : null;
    final metricsAll =
        bundle == null ? const <WaterMetrics>[] : WaterMetrics.derive(bundle.hours);
    final WaterMetrics w = (idx >= 0 && idx < metricsAll.length)
        ? metricsAll[idx]
        : WaterMetrics(((bundle?.curTemp ?? 20) * 0.8 + 4).clamp(2.0, 32.0), 7.0);

    final base = h != null ? Bite.score(h: h, w: w, sp: sp, mode: mode) : 55;
    final windMs = h?.windMs ?? ((bundle?.curWindSpeed ?? 8) / 3.6);
    final windFrom = h?.windDir ?? bundle?.curWindDir ?? 0;
    final bearing = _bearing(myLat, myLng, spot.lat, spot.lng);
    var parts = AiSpotService.scoreParts(
      base: base,
      kind: spot.kind,
      km: spot.km,
      windMs: windMs,
      bearingFromMe: bearing,
      windFrom: windFrom,
    );
    // ★ 详情页分数必须与雷达列表**完全一致**。
    //   列表那个数字是扫描那一刻算好后存进 [AiSpot.score] 的，详情页再算一遍
    //   只要有一项输入不同（取到的小时、风、天气刷新过）就会差几分 ——
    //   用户看到「列表 64 / 详情 74」只会觉得 AI 在瞎编。
    //   所以这里始终以列表分数为准：把差额并进「天气基础分」，
    //   四项相加恰好等于列表那个数，评分页依然能如实展示每一项加减了几分。
    final rest = parts.water + parts.wind + parts.distance;
    parts = AiScoreParts(
      base: (spot.score - rest).clamp(0, 100),
      water: parts.water,
      wind: parts.wind,
      distance: parts.distance,
    );
    // 最终得分直接用列表分数（不拿 parts.total 反算，避免 clamp 之后差 1 分）
    final total = spot.score;

    // ★ 按鱼种习性推荐（v2.1.57）：水温 / 时段 / 风浪三个维度打分
    final picks = SpeciesAdvisor.recommend(
      waterTemp: w.temp,
      hour: now.hour,
      windLevel: AiSpotService.beaufortOf(windMs),
      mode: mode.name,
    );
    if (picks.isNotEmpty) sp = _speciesByName(picks.first.name);

    // ── 黄金小时：今天 5:00~20:00 里指数最高的 3 个小时 ──
    final today = bundle == null ? const <HourPoint>[] : bundle.hoursOf(now);
    final dayMetrics = today.isEmpty ? const <WaterMetrics>[] : WaterMetrics.derive(today);
    final scored = <AiGold>[];
    for (var i = 0; i < today.length; i++) {
      final hh = today[i].time.hour;
      if (hh < 5 || hh > 20) continue;
      final sc = Bite.score(
        h: today[i],
        w: i < dayMetrics.length ? dayMetrics[i] : w,
        sp: sp,
        mode: mode,
      );
      scored.add(AiGold(today[i].hhmm, sc));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final golden = scored.take(3).toList()
      ..sort((a, b) => a.hhmm.compareTo(b.hhmm));

    final windowText = golden.isEmpty
        ? '暂无逐时数据'
        : (golden.length >= 2
            ? '${golden.first.hhmm} / ${golden[1].hhmm} 更稳'
            : '${golden.first.hhmm} 更稳');

    final distText = AiSpotService.kmText(spot.km);
    final dateTag = '${now.month}-${now.day}';

    // ── 当日天气那一排 ──
    final metrics = <AiMetric>[];
    if (h != null) {
      metrics.add(AiMetric(AiIcon.weather, '天气', Wmo.text(h.weatherCode)));
      metrics.add(AiMetric(AiIcon.temp, '气温', '${h.temp.toStringAsFixed(1)}℃'));
    }
    metrics.add(AiMetric(AiIcon.water, '水温', '${w.temp.toStringAsFixed(1)}℃'));
    if (h != null) {
      metrics.add(AiMetric(
        AiIcon.wind,
        '风',
        windLevelText(h.windSpeed, h.windDir),
      ));
      final trend = FishScore.trendCn(h.pressureTrend);
      metrics.add(AiMetric(
        AiIcon.pressure,
        '气压',
        '${h.pressure.toStringAsFixed(0)}hPa${trend.isEmpty ? '' : '·$trend'}',
      ));
    }
    metrics.add(AiMetric(AiIcon.oxygen, '溶氧', '${w.oxygen.toStringAsFixed(1)}mg/L'));
    if (h != null) {
      metrics.add(AiMetric(AiIcon.humidity, '湿度', '${h.humidity}%'));
    }

    // ── 为什么选这里 ──
    final reasons = <AiReason>[];

    // ① 天气变化
    if (h != null && today.isNotEmpty) {
      var tmin = today.first.temp, tmax = today.first.temp;
      var pmin = today.first.pressure, pmax = today.first.pressure;
      for (final x in today) {
        tmin = math.min(tmin, x.temp);
        tmax = math.max(tmax, x.temp);
        pmin = math.min(pmin, x.pressure);
        pmax = math.max(pmax, x.pressure);
      }
      var wmin = dayMetrics.isEmpty ? w.temp : dayMetrics.first.temp;
      var wmax = wmin;
      for (final m in dayMetrics) {
        wmin = math.min(wmin, m.temp);
        wmax = math.max(wmax, m.temp);
      }
      final inRange = w.temp >= sp.optLow && w.temp <= sp.optHigh;
      reasons.add(AiReason(
        AiIcon.climate,
        '天气变化',
        dateTag,
        '今天${Wmo.text(h.weatherCode)}，气温 ${tmin.toStringAsFixed(1)}~'
            '${tmax.toStringAsFixed(1)}℃，水温 ${wmin.toStringAsFixed(1)}~'
            '${wmax.toStringAsFixed(1)}℃，'
            '${inRange ? '正落在${sp.name}${sp.optLow.toStringAsFixed(0)}-${sp.optHigh.toStringAsFixed(0)}℃适宜区间' : '偏离${sp.name}适宜水温，鱼口会偏散'}；'
            '气压 ${pmin.toStringAsFixed(0)}~${pmax.toStringAsFixed(0)}hPa，'
            '变化 ${(pmax - pmin).toStringAsFixed(1)}hPa。',
      ));
    } else {
      reasons.add(const AiReason(AiIcon.climate, '天气变化', '暂无数据',
          '这一带暂时拿不到逐时天气，下面的分数只按水域类型和距离给出，仅供参考。'));
    }

    // ② 水域特点
    reasons.add(AiReason(
      AiIcon.coast,
      '水域特点',
      spot.kind,
      switch (spot.kind) {
        '河流' => '活水河道，持续走水带来增氧和饵料，闷热低压天比死水塘抗打；'
            '主攻桥墩、弯子、回水湾这些流速骤降的位置。',
        '水库' => '水库水深大，昼夜温差被水体缓冲，鱼层相对稳定；'
            '选铧尖、老河道、被风的大湾子，深浅交界处最容易聚鱼。',
        '钓友钓点' => '这里已有钓友实地作钓并共享过位置，属于被验证过的点；'
            '岸边地形和进出路线都成熟，适合直接开钓。',
        _ => '静水湖面，水温跟随气温缓慢变化，风浪起时下风岸聚饵；'
            '优先找草边、进水口和深浅交界的斜坡。',
      },
    ));

    // ③ 道路可达
    final minutes = (spot.km / 35 * 60).round();
    reasons.add(AiReason(
      AiIcon.road,
      '道路可达',
      '距我 $distText',
      '直线距离 $distText，正常路况约 $minutes 分钟车程'
          '${spot.km <= 5 ? '，属于就近可去的范围' : (spot.km > 25 ? '，跑一趟成本不低，建议连钓半天以上' : '，一小时生活圈内')}。'
          '到岸后注意别把车停在村民进出通道上。',
    ));

    // ④ 鱼种匹配
    reasons.add(AiReason(
      AiIcon.fish,
      '鱼种匹配',
      '${sp.name}·${mode.name}',
      '${sp.habit}。当前水温 ${w.temp.toStringAsFixed(1)}℃、溶氧 '
          '${w.oxygen.toStringAsFixed(1)}mg/L，'
          '${w.oxygen >= 5 ? '溶氧充足，鱼活性正常' : '溶氧偏低，鱼容易上浮，建议钓浮或找活水'}。',
    ));

    // ⑤ 钓点证据
    reasons.add(AiReason(
      AiIcon.evidence,
      spot.spotId != null && spot.spotId!.isNotEmpty ? '钓点证据' : '识别依据',
      spot.spotId != null && spot.spotId!.isNotEmpty ? '钓友共享点' : 'AI 水域识别',
      spot.spotId != null && spot.spotId!.isNotEmpty
          ? '这个点来自钓友地图上的公开钓点，坐标和名称都是人工填过的；'
              '雷达把它和实时天气叠加后给出了 ${parts.total} 分。'
          : '这个点由 AI 从周边河湖水域数据里挑出来，取的是离你最近的一段岸线/水面中心；'
              '没有人工验证过，第一次去建议先观察 10 分钟再下竿。',
    ));

    // ── 怎么钓 ──
    final season = _season(now.month);
    final tactics = <AiTactic>[
      AiTactic(
        AiIcon.spot,
        '钓位怎么选',
        switch (spot.kind) {
          '河流' => '找弯子内侧、桥墩背流面、支流汇入口，水流由急转缓的地方最聚鱼。',
          '水库' => '铧尖和深浅交界的斜坡优先，风大就退到被风湾子里，别硬顶风口。',
          '钓友钓点' => '先站到这个点位上，看岸边有没有老钓位痕迹（踩实的土、饵料袋），跟着老钓位开。',
          _ => '草边、进出水口、下风岸。水草洞和草缝是鲫鱼巡游路线，别打在亮水中间。',
        },
      ),
      AiTactic(
        AiIcon.gear,
        '线组搭配',
        '${sp.name}为主：主线 1.0~1.2 号、子线 0.6~0.8 号、3~4 号袖钩，'
            '浮漂吃铅 1.2~1.8g。水温低、口轻时再降一档，子线到 0.4 号。',
      ),
      AiTactic(
        AiIcon.bait,
        '饵料与窝料',
        season == '秋'
            ? '秋季转凉，腥香饵为主（腥 6 香 4），窝料用酒米少量多次，一次一两把，'
                '半小时补一次，别一次倒半袋把鱼喂饱。'
            : (season == '夏'
                ? '夏季水温高，本味/清香为主，少腥；窝料用小米加少量商品饵，'
                    '打窝后等 20 分钟再下竿。'
                : '水温低，浓腥为主，饵团开小、开软，红虫/蚯蚓是保底选择。'),
      ),
      AiTactic(
        AiIcon.time,
        '时段安排',
        golden.isEmpty
            ? '没有逐时数据时按常规节奏：天亮后 1 小时、日落前 2 小时各守一轮。'
            : '今天最好的三个时段是 ${golden.map((g) => '${g.hhmm}（${g.score}分）').join('、')}，'
                '重点守第一段，人少、鱼靠边、光线弱。',
      ),
      AiTactic(
        AiIcon.warn,
        '注意事项',
        '${windLevelText(h?.windSpeed ?? 0, h?.windDir ?? 0)}，'
            '${(h?.windSpeed ?? 0) >= 29 ? '风力偏大，注意人身安全，别站在陡坎和高岸边' : '风浪不大，正常作钓即可'}。'
            '临走把垃圾带走；禁钓区、饮用水源保护区不要下竿。',
      ),
    ];

    // ── 评分构成 ──
    final scoreParts = <AiScorePart>[
      AiScorePart(
        '天气基础分',
        parts.base,
        bundle == null
            ? '当前拿不到逐时天气，沿用扫描时的分数'
            : '气压 / 水温 / 溶氧 / 风 / 时段综合，与扫描列表同一时刻',
      ),
      AiScorePart(
        '水体类型',
        parts.water,
        switch (spot.kind) {
          '河流' => '活水增氧，闷热天更抗打',
          '水库' => '水深稳温，鱼层稳定',
          '钓友钓点' => '有钓友实地验证过',
          _ => '静水湖面，不加不减',
        },
      ),
      AiScorePart(
        '风向岸线',
        parts.wind,
        parts.wind > 0
            ? '此处处在迎风岸，饵料和浮游生物被吹过来'
            : (parts.wind < 0 ? '处在背风岸，聚饵条件一般' : '侧风，基本不影响'),
      ),
      AiScorePart(
        '距离成本',
        parts.distance,
        spot.km > 40
            ? '超过 40 公里，跑一趟成本偏高'
            : (spot.km > 25 ? '25 公里以上，略扣分' : '就近可去，不减分'),
      ),
    ];

    final headline = switch (total) {
      >= 85 => '今天这一片里最值得先试的一号位，条件基本到位。',
      >= 75 => '值得跑一趟，重点守黄金时段。',
      >= 60 => '可以去，别抱太高期望，主攻早晚。',
      _ => '条件一般，路过可以试试，专程跑一趟不划算。',
    };

    return AiReport(
      score: total,
      grade: gradeOf(total),
      species: sp.name,
      picks: picks,
      mode: mode.name,
      headline: headline,
      windowText: windowText,
      dateTag: dateTag,
      distanceText: distText,
      golden: golden,
      metrics: metrics,
      reasons: reasons,
      tactics: tactics,
      parts: scoreParts,
      waterTemp: w.temp,
      oxygen: w.oxygen,
      pressure: h?.pressure.round(),
    );
  }

  /// 按名字取回鱼种定义（找不到就退回默认目标鱼，不让报告整个挂掉）
  static FishingSpecies _speciesByName(String name) {
    for (final s in FishingSpecies.all) {
      if (s.name == name) return s;
    }
    return FishingSpecies.all.first;
  }

  static String _season(int month) {    if (month >= 3 && month <= 5) return '春';
    if (month >= 6 && month <= 8) return '夏';
    if (month >= 9 && month <= 11) return '秋';
    return '冬';
  }

  /// 从 A 看 B 的方位角（0=北，顺时针），与 AiSpotService 同一算法
  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dl = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }
}
