import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_species.dart';
import '../models/weather_forecast.dart';

/// 一条 AI 垂钓建议（由天气多因子规则推导，离线可用、不依赖任何大模型服务）
class FishingAdvice {
  /// 0-100 综合适宜度
  final int score;

  /// 极佳 / 良好 / 一般 / 不宜
  final String level;

  /// 一句话总评（头条）
  final String headline;

  /// 分条建议（已按重要度排序，取前若干条）
  final List<String> tips;

  final Color color;

  const FishingAdvice({
    required this.score,
    required this.level,
    required this.headline,
    required this.tips,
    required this.color,
  });
}

/// AI 垂钓顾问：把「坐标所在天气 + 气压 + 风 + 温差 + 降雨 + 紫外线 + 时段」
/// 综合成可直接照着做的作钓建议。
///
/// 说明：这里用的是「气象多因子规则引擎」而不是联网大模型 ——
/// 好处是永远可用、离线也能出结果、响应是毫秒级，适合放在 App 里。
/// 所有参数都是可选的，缺哪个就跳过与该因子相关的建议。
class FishingAdvisor {
  static FishingAdvice build({
    required double temp,
    required double pressure,
    required double windKmh,
    double? tempMin,
    double? tempMax,
    int? windDirDeg,
    int? rainProb,
    double? rainMm,
    double? uv,
    int weatherCode = 0,
    int? hour,
  }) {
    // 与天气页同一套多维引擎：气温→估算水温、水氧按饱和溶氧折算，
    // 目标鱼默认鲫鱼（台钓最常见）。这样首页指数与天气页不会互相打脸。
    final h = hour ?? DateTime.now().hour;
    final windMs = windKmh / 3.6;
    final waterTemp = (temp * 0.8 + 4).clamp(2.0, 32.0);
    final doSat = 14.652 -
        0.41022 * waterTemp +
        0.007991 * waterTemp * waterTemp -
        0.000077774 * waterTemp * waterTemp * waterTemp;
    final res = FishScore.computeRaw(
      method: '台钓',
      airTemp: temp,
      pressure: pressure,
      windMs: windMs,
      waterTemp: waterTemp,
      dissolvedOxygen: (doSat * 0.78).clamp(2.0, 14.0),
      weatherCode: weatherCode,
      precipProb: rainProb ?? 0,
      hour: h,
      dayRange: (tempMin != null && tempMax != null) ? tempMax - tempMin : null,
      sp: FishingSpecies.all.first,
    );
    final score = res.indexScore ?? 50;
    final level = FishScore.gradeOf(score);
    final color = score >= 90
        ? AppTheme.primary
        : (score >= 80
            ? AppTheme.primaryLight
            : (score >= 45 ? AppTheme.accent : AppTheme.danger));

    final tips = <String>[];
    final reasons = <String>[];

    // —— 雷暴一票否决，优先提示安全 ——
    if (weatherCode >= 95) {
      tips.add('⛈ 当前有雷暴，切勿出钓，安全第一！');
      reasons.add('雷暴');
    }

    // —— 气压（海平面气压：1013~1022 才是舒适区）——
    if (pressure >= 1013 && pressure <= 1022) {
      tips.add('气压 ${pressure.toStringAsFixed(0)}hPa 稳在舒适区，水体携氧足，鱼活性好。');
      reasons.add('气压稳');
    } else if (pressure < 1000) {
      tips.add('气压偏低（${pressure.toStringAsFixed(0)}hPa），鱼易上浮、吃口轻，建议钓深水、放慢节奏，或改天再战。');
      reasons.add('气压低');
    } else if (pressure < 1013) {
      tips.add('气压略低（${pressure.toStringAsFixed(0)}hPa），鱼口可能变轻，建议小钩细线、用活饵诱鱼。');
    } else if (pressure > 1025) {
      tips.add('气压偏高（${pressure.toStringAsFixed(0)}hPa），鱼口可能偏轻，宜钓深、钓远。');
    }

    // —— 风 ——
    final dirTxt = windDirDeg == null ? '' : windDirText(windDirDeg);
    if (windMs < 2) {
      tips.add('风力很小（${windMs.toStringAsFixed(1)}m/s），水面平静，注意隐蔽、轻手轻脚，避免惊鱼。');
    } else if (windMs <= 4) {
      final d = dirTxt.isEmpty ? '' : '，$dirTxt风';
      tips.add('微风 ${windMs.toStringAsFixed(1)}m/s$d，下风口水氧高、食物聚集，优先钓迎风岸。');
      reasons.add('微风');
    } else if (windMs <= 6) {
      tips.add('风力较大（${windMs.toStringAsFixed(1)}m/s），选避风湾子、加重铅坠，注意安全。');
    } else {
      tips.add('大风（${windMs.toStringAsFixed(1)}m/s），不建议出钓；若坚持，务必选背风深水区。');
      reasons.add('风大');
    }

    // —— 温差 ——
    if (tempMin != null && tempMax != null) {
      final range = tempMax - tempMin;
      if (range >= 12) {
        tips.add('昼夜温差 ${range.toStringAsFixed(0)}℃，早晚是黄金窗口，中午鱼口偏弱，建议早出晚归。');
        reasons.add('温差大');
      } else if (range <= 6) {
        tips.add('昼夜温差小（${range.toStringAsFixed(0)}℃），全天鱼口相对稳定，可放心守钓。');
      }
    }

    // —— 降雨 ——
    if (rainProb != null) {
      if (rainProb >= 70) {
        tips.add('降雨概率 ${rainProb}%，雨前/雨后是爆护窗口，但要注意防雷、防滑、防涨水。');
        reasons.add('有雨');
      } else if (rainProb >= 40) {
        tips.add('可能有阵雨（${rainProb}%），备好雨具，雨后 1-2 小时往往是好时机。');
      }
    }

    // —— 温度带 ——
    if (temp < 5) {
      tips.add('水温很低，鱼活性差，守深水向阳处、用腥饵慢钓，别频繁抛竿。');
      reasons.add('低温');
    } else if (temp < 12) {
      tips.add('水温偏低，选背风向阳的深水区，饵料偏腥，钓底为主。');
    } else if (temp <= 26) {
      tips.add('水温适宜（${temp.toStringAsFixed(0)}℃），鱼口活跃，正常作钓即可。');
      reasons.add('水温适宜');
    } else if (temp > 30) {
      tips.add('水温偏高，鱼多躲进深水/阴凉处，建议早晨和傍晚出钓。');
      reasons.add('高温');
    }

    // —— 紫外线 ——
    if (uv != null && uv >= 7) {
      tips.add('紫外线较强（UV ${uv.toStringAsFixed(1)}），注意防晒，尽量早晚作钓。');
    }

    // —— 时段 ——
    if (hour != null) {
      if ((hour >= 5 && hour <= 9) || (hour >= 16 && hour <= 19)) {
        tips.add('当前 ${hour} 点正值鱼类觅食高峰，抓住窗口期下竿。');
      } else if (hour >= 11 && hour <= 14) {
        tips.add('正午时段鱼口通常偏弱，可休息或改钓深水。');
      } else if (hour >= 22 || hour <= 4) {
        tips.add('夜间作钓注意保暖与照明，大鱼多在夜深人静时靠边。');
      }
    }

    // —— 通用钓位建议 ——
    tips.add('钓位优先选水草边、洄湾、进出水口，这些地方水氧与食物更充足。');

    // —— 头条 ——
    final reasonTxt = reasons.isEmpty ? '' : '（${reasons.take(2).join('、')}）';
    final String headline;
    if (weatherCode >= 95) {
      headline = '雷暴天气，安全第一，建议暂停出钓。';
    } else if (score >= 90) {
      headline = '鱼情爆护级$reasonTxt，抓住窗口赶紧下竿！';
    } else if (score >= 80) {
      headline = '有口$reasonTxt，选对钓位与钓法能连竿。';
    } else if (score >= 45) {
      headline = '鱼口偏弱$reasonTxt，建议放低预期、主攻早晚窗口。';
    } else {
      headline = '开口很差$reasonTxt，建议改期或换目标鱼。';
    }

    return FishingAdvice(
      score: score,
      level: level,
      headline: headline,
      tips: tips.take(5).toList(),
      color: color,
    );
  }
}
