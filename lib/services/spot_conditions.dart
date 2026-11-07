import 'dart:math' as math;

import '../models/fishing_species.dart';
import '../models/weather_forecast.dart';
import 'ai_spot_service.dart';

/// 推荐指数的一条构成（黑卡底部那行「推荐指数 72 ＝ 天气 66 ＋ 水域 3 …」）
class SpotConditionPart {
  final String label;
  final int value;
  const SpotConditionPart(this.label, this.value);
}

/// 一个「能钓」的时间窗（最佳出钓时间下面那两张卡）
class SpotTimeWindow {
  /// 起止小时（含端点），24 小时制
  final int start;
  final int end;

  /// 这个窗口里的最高指数
  final int score;

  const SpotTimeWindow(this.start, this.end, this.score);

  /// 「0-14 时」/「17 时」（只有一个小时时不写成 17-17）
  String get range => start == end ? '$start 时' : '$start-$end 时';

  @override
  String toString() => 'SpotTimeWindow($range, $score)';
}

/// 钓点详情页的「合不合适」数据（v2.1.83）
///
/// 为什么单拉一个纯计算类：
///   1. 详情页要显示推荐指数、24 小时色条、最佳时段，全是同一条口径算出来的；
///      写在 build 里既没法单测，也会和 AI 详情页的评分慢慢走偏；
///   2. 这里**不 import Flutter**，可以在 `flutter test` 里直接喂一份假天气断言，
///      不用起界面。
///
/// 口径与全站一致：基础分走 [Bite.score]（和天气页、首页指数同一个引擎），
/// 微环境修正走 [AiSpotService.scoreParts]（和 AI 雷达列表同一个函数）——
/// 因此「AI 雷达给 78 分的地点」点进详情页不会突然变成 85。
class SpotConditions {
  /// 推荐指数（0-100）
  final int score;

  /// 档位：优秀 / 良好 / 一般 / 口弱 / 难钓
  final String grade;

  /// 分数构成（天气 / 水域 / 风岸 / 距离），相加 = [score]
  final List<SpotConditionPart> parts;

  /// 今日气温区间（℃）
  final double tempMin;
  final double tempMax;

  /// 今日风级区间（蒲福风级）
  final int windMin;
  final int windMax;

  /// 今日主要天气现象（「小雨」「多云」…）
  final String weatherText;

  /// 当前这一小时的气温 / 风级（「现在去合不合适」那两格用的就是它）
  final double nowTemp;
  final int nowWindLevel;

  /// 当前小时的水温 / 溶氧（AI 正文里用）
  final double waterTemp;
  final double oxygen;

  /// 今日气压区间（hPa）
  final int pressureMin;
  final int pressureMax;

  /// 24 小时逐时指数，下标 = 小时；-1 表示这个点没有数据
  final List<int> hourly;

  /// 当前小时（画 24 小时色条上那根红线）
  final int nowHour;

  /// 能钓的时间窗，按开始时间排序（第 1 个是「最佳」，第 2 个是「次佳」）
  final List<SpotTimeWindow> windows;

  /// 「今日建议」一句话
  final String advice;

  /// AI 分析正文（真数据拼出来的段落，不是套话）
  final String aiText;

  const SpotConditions({
    required this.score,
    required this.grade,
    required this.parts,
    required this.tempMin,
    required this.tempMax,
    required this.windMin,
    required this.windMax,
    required this.weatherText,
    required this.nowTemp,
    required this.nowWindLevel,
    required this.waterTemp,
    required this.oxygen,
    required this.pressureMin,
    required this.pressureMax,
    required this.hourly,
    required this.nowHour,
    required this.windows,
    required this.advice,
    required this.aiText,
  });

  /// 最佳窗口（没有就 null）
  SpotTimeWindow? get best => windows.isEmpty ? null : windows.first;

  /// 次佳窗口
  SpotTimeWindow? get second => windows.length > 1 ? windows[1] : null;

  /// 档位（与首页天气条、AI 详情页的用词保持一致）
  static String gradeOf(int s) {
    if (s >= 85) return '优秀';
    if (s >= 70) return '良好';
    if (s >= 50) return '一般';
    if (s >= 30) return '口弱';
    return '难钓';
  }

  /// 钓点类型 → [AiSpotService.scoreParts] 认的水体类型
  ///
  /// venue（本地钓场/收费塘）按湖泊算：静水、水温跟气温走，低压天最先闷。
  /// wild（钓友自己标的野钓点）按「钓友钓点」算：有人实地钓过，加 2 分。
  static String kindKey(String kind) {
    switch (kind) {
      case 'wild':
        return '钓友钓点';
      case 'venue':
        return '湖泊';
      default:
        return '湖泊';
    }
  }

  /// 由天气包算出详情页要的全部数据
  ///
  /// [bundle] 必须是**这个钓点坐标**的天气（不是我的位置）——
  /// 判断「去那里合不合适」，用的当然是那里的天气。
  /// 拿不到天气（null / 当天没有逐时数据）时返回 null，页面显示占位而不是画假数字。
  static SpotConditions? of({
    required WeatherBundle? bundle,
    required String kind,
    required double km,
    required double bearingFromMe,
    DateTime? at,
  }) {
    if (bundle == null) return null;
    final now = at ?? DateTime.now();
    final today = bundle.hoursOf(now);
    if (today.isEmpty) return null;

    final metrics = WaterMetrics.derive(today);
    final sp = FishingSpecies.all.first;
    final mode = FishingMode.all.first;

    WaterMetrics waterAt(int i) => i >= 0 && i < metrics.length
        ? metrics[i]
        : WaterMetrics((bundle.curTemp * 0.8 + 4).clamp(2.0, 32.0), 7.0);

    // ── 逐时指数（24 小时色条）──
    final hourly = List<int>.filled(24, -1);
    for (var i = 0; i < today.length; i++) {
      final hh = today[i].time.hour;
      if (hh < 0 || hh > 23) continue;
      hourly[hh] = Bite.score(h: today[i], w: waterAt(i), sp: sp, mode: mode);
    }

    // ── 当前这一小时 ──
    var ci = today.indexWhere((h) => h.time.hour == now.hour);
    if (ci < 0) ci = 0;
    final cur = today[ci];
    final wCur = waterAt(ci);

    final base = Bite.score(h: cur, w: wCur, sp: sp, mode: mode);
    final parts4 = AiSpotService.scoreParts(
      base: base,
      kind: kindKey(kind),
      km: km,
      windMs: cur.windMs,
      bearingFromMe: bearingFromMe,
      windFrom: cur.windDir,
    );
    final score = parts4.total.clamp(0, 100);

    // ── 今日区间 ──
    var tmin = today.first.temp, tmax = today.first.temp;
    var pmin = today.first.pressure, pmax = today.first.pressure;
    var wmin = 12, wmax = 0;
    for (final h in today) {
      tmin = math.min(tmin, h.temp);
      tmax = math.max(tmax, h.temp);
      pmin = math.min(pmin, h.pressure);
      pmax = math.max(pmax, h.pressure);
      final lv = beaufortLevel(h.windSpeed);
      wmin = math.min(wmin, lv);
      wmax = math.max(wmax, lv);
    }
    var wtMin = waterAt(0).temp, wtMax = wtMin;
    for (var i = 0; i < today.length; i++) {
      final t = waterAt(i).temp;
      wtMin = math.min(wtMin, t);
      wtMax = math.max(wtMax, t);
    }

    final windows = _windows(hourly);
    final weatherText = Wmo.text(cur.weatherCode);

    return SpotConditions(
      score: score,
      grade: gradeOf(score),
      parts: [
        SpotConditionPart('天气', parts4.base),
        SpotConditionPart('水域', parts4.water),
        SpotConditionPart('风岸', parts4.wind),
        SpotConditionPart('距离', parts4.distance),
      ],
      tempMin: tmin,
      tempMax: tmax,
      windMin: wmin,
      windMax: wmax,
      weatherText: weatherText,
      nowTemp: cur.temp,
      nowWindLevel: beaufortLevel(cur.windSpeed),
      waterTemp: wCur.temp,
      oxygen: wCur.oxygen,
      pressureMin: pmin.round(),
      pressureMax: pmax.round(),
      hourly: hourly,
      nowHour: now.hour,
      windows: windows,
      advice: _advice(score: score, weather: weatherText, best: windows),
      aiText: _aiText(
        kind: kind,
        weather: weatherText,
        tmin: tmin,
        tmax: tmax,
        wtMin: wtMin,
        wtMax: wtMax,
        oxygen: wCur.oxygen,
        pmin: pmin.round(),
        pmax: pmax.round(),
        windows: windows,
      ),
    );
  }

  /// 把 24 小时里「明显好」的连续小时挑出来，最多两个窗口
  ///
  /// 阈值取「全天最高分 - 8」和 55 里的较大值：
  ///   · 相对阈值：一天整体都不错时，不该把一堆 70 分的小时都算成「最佳」；
  ///   · 绝对下限 55：全天都烂的时候，不能硬挑一个 40 分的小时当「最佳」骗人。
  static List<SpotTimeWindow> _windows(List<int> hourly) {
    var best = -1;
    for (final v in hourly) {
      if (v > best) best = v;
    }
    if (best <= 0) return const [];
    final thr = math.max(best - 8, 55);
    if (best < thr) return const [];

    final out = <SpotTimeWindow>[];
    int? start;
    var top = 0;
    for (var h = 0; h <= 24; h++) {
      final ok = h < 24 && hourly[h] >= thr;
      if (ok) {
        start ??= h;
        top = math.max(top, hourly[h]);
      } else if (start != null) {
        out.add(SpotTimeWindow(start, h - 1, top));
        start = null;
        top = 0;
      }
    }
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (b.end - b.start).compareTo(a.end - a.start);
    });
    final picked = out.take(2).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return picked;
  }

  static String _advice({
    required int score,
    required String weather,
    required List<SpotTimeWindow> best,
  }) {
    final w = best.isEmpty ? '' : best.first.range;
    if (score >= 85) {
      return '今天条件很好，$weather，${w.isEmpty ? '全天都能钓' : '$w最合适'}，收竿就能钓';
    }
    if (score >= 70) {
      return '天气适宜，${w.isEmpty ? '按平时的时间去就行' : '挑$w去更稳'}';
    }
    if (score >= 50) {
      return '条件一般，${w.isEmpty ? '建议短时试探' : '建议只在$w出钓'}，其余时间鱼口偏散';
    }
    if (score >= 30) {
      return '鱼口偏弱，${w.isEmpty ? '想钓就做好空军的准备' : '只有$w还能试一试'}，饵料要小而活';
    }
    return '今天条件差，$weather${score < 20 ? '、气压或溶氧不合适' : ''}，建议改天再来';
  }

  static String _aiText({
    required String kind,
    required String weather,
    required double tmin,
    required double tmax,
    required double wtMin,
    required double wtMax,
    required double oxygen,
    required int pmin,
    required int pmax,
    required List<SpotTimeWindow> windows,
  }) {
    final b = StringBuffer();
    if (windows.isEmpty) {
      b.write('今天的逐时指数整体偏低，没有明显的高分窗口。');
    } else {
      final w1 = windows.first;
      b.write('建议主攻 ${w1.range}（指数 ${w1.score}）');
      if (windows.length > 1) {
        final w2 = windows[1];
        b.write('，其次 ${w2.range}（${w2.score}）');
      }
      b.write('。');
    }
    b.write('今日$weather，气温 ${_t(tmin)}-${_t(tmax)}℃，水温 ${_t(wtMin)}-${_t(wtMax)}℃，'
        '溶氧 ${oxygen.toStringAsFixed(1)}mg/L${oxygen >= 5 ? '，水体携氧充足' : '，偏低、鱼容易上浮'}，'
        '气压 $pmin-${pmax}hPa。');
    b.write(_spotAdvice(kind));
    return b.toString();
  }

  static String _spotAdvice(String kind) {
    switch (kind) {
      case 'wild':
        return '钓位优先找深浅交界、草边或回水湾，别死守光板直岸；'
            '打窝少量多次补，别一次倒满。';
      case 'venue':
        return '先问老板今天的放鱼口和常用饵，围着增氧机和下风口找鱼，'
            '正钓前半小时把窝子做好。';
      default:
        return '沿岸找有水草、有结构的一侧下竿，风浪起时打下风岸。';
    }
  }

  static String _t(double v) => v.toStringAsFixed(1);

  /// 两点间距离（公里，球面大圆距离）
  ///
  /// 详情页要拿它算「跑一趟值不值」（>25km 扣 1 分、>40km 扣 3 分，
  /// 与 AI 雷达列表同一套权重）。定位拿不到时传 0，等于不扣分。
  static double kmBetween(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  /// 从我这里看钓点的方位角（度，正北 0 顺时针）
  static double bearingBetween(
      double lat1, double lng1, double lat2, double lng2) {
    final p1 = _rad(lat1), p2 = _rad(lat2);
    final dl = _rad(lng2 - lng1);
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }

  static double _rad(double d) => d * math.pi / 180;

  /// 温度体感：给「温度」那一格做副标题（图里写的是「冷」）
  static String tempFeel(double t) {
    if (t <= 5) return '很冷';
    if (t <= 12) return '冷';
    if (t <= 20) return '凉爽';
    if (t <= 27) return '舒适';
    if (t <= 32) return '偏热';
    return '很热';
  }

  /// 风感：给「风力」那一格做副标题
  static String windFeel(int level) {
    if (level <= 1) return '几乎无风';
    if (level == 2) return '微风拂面';
    if (level == 3) return '和风';
    if (level == 4) return '风有点大';
    if (level == 5) return '风大难抛竿';
    return '大风，不建议出钓';
  }
}
