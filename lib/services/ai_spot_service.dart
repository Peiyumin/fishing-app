import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/fishing_spot.dart';
import '../models/fishing_species.dart';
import '../models/water_body.dart';
import '../models/weather_forecast.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'spot_service.dart';
import 'weather_service.dart';

/// 一个 AI 推荐钓点
class AiSpot {
  /// 唯一 id（用于地图要素 / 列表点击对应）
  final String id;
  final String name;

  /// 推荐理由（一句话，用户能看懂）
  final String reason;
  final double lat;
  final double lng;

  /// 距离（公里）
  final double km;

  /// 垂钓指数 0-100（与天气页同一套引擎，只是加了微环境修正）
  final int score;

  /// 水体类型：河流 / 湖泊 / 水库 / 钓友钓点
  final String kind;

  /// 对应的钓点 id（钓友共享点才有，点进去能看详情）
  final String? spotId;

  const AiSpot({
    required this.id,
    required this.name,
    required this.reason,
    required this.lat,
    required this.lng,
    required this.km,
    required this.score,
    required this.kind,
    this.spotId,
  });

  /// 分数档位（与 App 其它地方一致：≥80 有口以上）
  String get grade {
    if (score >= 90) return '爆护';
    if (score >= 80) return '有口';
    if (score >= 60) return '一般';
    if (score >= 25) return '口弱';
    return '无口';
  }
}

/// 分数构成：天气基础分 + 三处微环境修正（合计 = 雷达列表上的分数）
class AiScoreParts {
  /// 天气基础分（与天气页同一个 `Bite.score` 引擎，同一小时）
  final int base;

  /// 水体类型加减分（河流 +3 / 水库 +2 / 钓友钓点 +2 / 湖泊 0）
  final int water;

  /// 迎风岸 / 背风岸（迎风 +3、大风迎风 +1、背风 -2、大风背风 -1）
  final int wind;

  /// 距离（>25km -1、>40km -3）
  final int distance;

  const AiScoreParts({
    required this.base,
    required this.water,
    required this.wind,
    required this.distance,
  });

  int get total => (base + water + wind + distance).clamp(0, 100);

  /// 带符号的展示文案（0 分也写 0，避免用户猜「为什么没这一项」）
  static String signed(int v) => v > 0 ? '＋$v' : '$v';
}

/// AI 推荐钓点
///
/// 思路：**同一片区域的天气是一样的**，所以「哪个点更适合」不能只看天气，
/// 要叠加本地微环境。这里用的四个因子都是有钓鱼依据的：
///
///  1. 水体类型：活水河持续增氧，闷热低压天比死水塘抗打；水库水深缓冲温差
///  2. 迎风岸：风把浮游生物和饵料吹向下风岸，鱼跟着走；
///     但风太大时迎风岸浪大难作钓，所以按风力分档加分
///  3. 距离：近的优先（用户明确要求「由近到远」排序）
///  4. 钓友验证：已有钓友分享的点，说明那里确实能钓到
///
/// 基础分用 `Bite.score`（与天气页同一个引擎、同一小时），
/// 所以 AI 推荐里的分数和天气预报页的数字对得上，不会各说一套。
class AiSpotService {
  static const Distance _dist = Distance();

  /// 生成推荐列表（按距离由近到远排序）
  ///
  /// [spots] 钓友共享的钓点，[waters] 本地河湖数据（用来在河边补候选点）。
  /// [maxKm] 超出这个距离的点不再推荐（默认 60km，开车 1 小时内）。
  static Future<List<AiSpot>> recommend({
    required double lat,
    required double lng,
    required List<FishingSpot> spots,
    required List<WaterBody> waters,
    double maxKm = 60,
    int limit = 12,
  }) async {
    // 天气拿不到也要能给建议（退化成「按距离 + 水体类型」）
    WeatherBundle? bundle;
    try {
      bundle = await WeatherService.fetchForecast(lat, lng)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      bundle = null;
    }

    final now = DateTime.now();
    final HourPoint? h = bundle?.hourNear(now);
    final metrics = bundle == null ? const <WaterMetrics>[] : WaterMetrics.derive(bundle.hours);
    var wi = -1;
    if (bundle != null) wi = bundle.indexOfHourNear(now);
    final w = (wi >= 0 && wi < metrics.length)
        ? metrics[wi]
        : WaterMetrics(
            ((bundle?.curTemp ?? 20) * 0.8 + 4).clamp(2.0, 32.0), 7.0);

    // 基础分：天气本身有多适合钓鱼（全区域相同）
    final base = h != null
        ? Bite.score(
            h: h,
            w: w,
            sp: FishingSpecies.all.first,
            mode: FishingMode.all.first,
          )
        : 55;

    final windMs = h?.windMs ?? ((bundle?.curWindSpeed ?? 8) / 3.6);
    final windFrom = h?.windDir ?? bundle?.curWindDir ?? 0;

    final out = <AiSpot>[];

    // ---------------- 候选 1：钓友共享钓点 ----------------
    for (final s in spots) {
      final km = _dist.as(
        LengthUnit.Kilometer,
        LatLng(lat, lng),
        LatLng(s.lat, s.lng),
      );
      if (km > maxKm) continue;
      final bearing = _bearing(lat, lng, s.lat, s.lng);
      final sc = _tune(
        base: base,
        kind: '钓友钓点',
        km: km,
        windMs: windMs,
        bearingFromMe: bearing,
        windFrom: windFrom,
      );
      out.add(AiSpot(
        id: 'f_${s.id}',
        name: s.name,
        lat: s.lat,
        lng: s.lng,
        km: km,
        score: sc,
        kind: '钓友钓点',
        spotId: s.id,
        reason: _reason(
          kind: '钓友钓点',
          score: sc,
          h: h,
          w: w,
          windMs: windMs,
        ),
      ));
    }

    // ---------------- 候选 2：本地河湖（每条取离我最近的点） ----------------
    for (final wb in waters) {
      final pts = wb.geometry;
      if (pts.isEmpty) continue;
      // 河流取最近顶点，湖泊取质心
      late final double plat;
      late final double plng;
      if (wb.isRiver) {
        var best = 1e18;
        var bi = 0;
        for (var i = 0; i < pts.length; i++) {
          final d = _dist.as(
            LengthUnit.Meter,
            LatLng(lat, lng),
            LatLng(pts[i].latitude, pts[i].longitude),
          );
          if (d < best) {
            best = d;
            bi = i;
          }
        }
        plat = pts[bi].latitude;
        plng = pts[bi].longitude;
      } else {
        var slat = 0.0, slng = 0.0;
        for (final p in pts) {
          slat += p.latitude;
          slng += p.longitude;
        }
        plat = slat / pts.length;
        plng = slng / pts.length;
      }

      final km = _dist.as(
        LengthUnit.Kilometer,
        LatLng(lat, lng),
        LatLng(plat, plng),
      );
      if (km > maxKm) continue;
      // 和钓友钓点在同一个位置（<300m）就不重复推荐
      if (out.any((e) => _dist.as(LengthUnit.Meter, LatLng(e.lat, e.lng),
              LatLng(plat, plng)) <
          300)) {
        continue;
      }

      final kind = wb.isRiver ? '河流' : (wb.kindLabel.contains('水库') ? '水库' : '湖泊');
      final bearing = _bearing(lat, lng, plat, plng);
      final sc = _tune(
        base: base,
        kind: kind,
        km: km,
        windMs: windMs,
        bearingFromMe: bearing,
        windFrom: windFrom,
      );
      out.add(AiSpot(
        id: 'w_${wb.id}',
        name: wb.isRiver ? '${wb.name}（近岸）' : wb.name,
        lat: plat,
        lng: plng,
        km: km,
        score: sc,
        kind: kind,
        reason: _reason(kind: kind, score: sc, h: h, w: w, windMs: windMs),
      ));
    }

    // ---------------- 按距离由近到远 ----------------
    out.sort((a, b) => a.km.compareTo(b.km));
    if (out.length > limit) return out.sublist(0, limit);
    return out;
  }

  /// 微环境修正
  static int _tune({
    required int base,
    required String kind,
    required double km,
    required double windMs,
    required double bearingFromMe,
    required int windFrom,
  }) =>
      scoreParts(
        base: base,
        kind: kind,
        km: km,
        windMs: windMs,
        bearingFromMe: bearingFromMe,
        windFrom: windFrom,
      ).total;

  /// 分数构成（v2.1.56）
  ///
  /// 抽出来是为了让「AI 分析报告 · 评分」页能把每一项**加减了几分**如实列出来。
  /// 原来只有 [_tune] 一个总分，报告页只能重新实现一遍公式 —— 两处一旦
  /// 走偏，雷达列表显示 84、详情页显示 82，用户立刻发现「AI 自相矛盾」。
  /// 现在两边共用这一个函数，改权重只有一处。
  static AiScoreParts scoreParts({
    required int base,
    required String kind,
    required double km,
    required double windMs,
    required double bearingFromMe,
    required int windFrom,
  }) {
    // ① 水体类型
    var water = 0;
    switch (kind) {
      case '河流':
        water = 3; // 活水持续增氧，闷热天比死水抗打
        break;
      case '水库':
        water = 2; // 水深大，温差缓冲好
        break;
      case '钓友钓点':
        water = 2; // 有人验证过能出鱼
        break;
      default:
        water = 0; // 湖泊不加不减
    }

    // ② 迎风岸 / 背风岸
    //    风从钓点那个方向吹过来（即钓点在上风岸）→ 饵料和浮游生物被吹向
    //    我们这一岸，鱼跟着过来。但 5 级以上的风迎风岸浪太大，反而难钓。
    final diff = ((bearingFromMe - windFrom + 540) % 360 - 180).abs();
    final windy = windMs >= 8.0; // 8 m/s ≈ 5 级
    var wind = 0;
    if (diff < 60) {
      wind = windy ? 1 : 3;
    } else if (diff > 120) {
      wind = windy ? -1 : -2;
    }

    // ③ 距离：太远性价比低（只轻微扣分，排序仍以距离为主）
    var distance = 0;
    if (km > 40) {
      distance = -3;
    } else if (km > 25) {
      distance = -1;
    }

    return AiScoreParts(
      base: base,
      water: water,
      wind: wind,
      distance: distance,
    );
  }

  /// 推荐理由：把当下真正起作用的几个量说出来
  static String _reason({
    required String kind,
    required int score,
    required HourPoint? h,
    required WaterMetrics w,
    required double windMs,
  }) {
    final parts = <String>[];
    if (h != null) {
      final trend = FishScore.trendCn(h.pressureTrend);
      parts.add('气压 ${h.pressure.toStringAsFixed(0)}hPa${trend.isEmpty ? '' : '·$trend'}');
      parts.add('水温 ${w.temp.toStringAsFixed(1)}℃');
      parts.add('溶氧 ${w.oxygen.toStringAsFixed(1)}');
      parts.add('风 ${_beaufort(windMs)}级');
    } else {
      parts.add('水温 ${w.temp.toStringAsFixed(1)}℃');
      parts.add('暂无实时天气');
    }
    final tail = switch (kind) {
      '河流' => '活水增氧',
      '水库' => '水深稳温',
      '钓友钓点' => '钓友验证',
      _ => '水面平稳',
    };
    parts.add(tail);
    if (score >= 80) {
      return '${parts.join(' · ')} —— 条件到位，值得跑一趟';
    }
    if (score >= 60) {
      return '${parts.join(' · ')} —— 可以去，主攻早晚';
    }
    return '${parts.join(' · ')} —— 条件一般，就近试试';
  }

  /// 蒲福风级（只取到 6 级，够判断）
  static int _beaufort(double ms) {
    if (ms < 0.3) return 0;
    if (ms < 1.6) return 1;
    if (ms < 3.4) return 2;
    if (ms < 5.5) return 3;
    if (ms < 8.0) return 4;
    if (ms < 10.8) return 5;
    return 6;
  }

  /// 从 A 看 B 的方位角（0=北，顺时针）
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

  /// 距离展示：<1km 用米，否则一位小数的公里
  static String kmText(double km) {
    if (km < 1) return '${(km * 1000).round()}m';
    return '${km.toStringAsFixed(1)}km';
  }

  /// 某个坐标的天气（AI 详情页用）
  ///
  /// ★ 必须是**钓点坐标**的天气，不是我的位置：5 公里外的水库风向就可能变了，
  ///   用我的位置算「迎风岸」会把结论说反。
  static Future<WeatherBundle?> weatherAt(double lat, double lng) async {
    try {
      return await WeatherService.fetchForecast(lat, lng)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  /// 反馈 / 报错（AI 详情页底部「反馈」）
  ///
  /// 有对应钓点 id → 走原来的钓点报错（后台能在钓点报错列表里看到）；
  /// AI 从水域数据里挑出来的点没有 id → 走 `/ai/spot-report`，
  /// 落到独立表里，不会污染钓点库。
  static Future<void> report({
    required AiSpot spot,
    required String reason,
    String note = '',
  }) async {
    final id = spot.spotId;
    if (id != null && id.isNotEmpty) {
      await SpotService.reportSpot(
        spotId: id,
        spotName: spot.name,
        reason: reason,
        note: note.isEmpty ? null : note,
      );
      return;
    }
    if (!ApiConfig.enabled) return;
    await ApiClient.post('/ai/spot-report', {
      'name': spot.name,
      'lat': spot.lat,
      'lng': spot.lng,
      'kind': spot.kind,
      'reason': reason,
      'note': note,
    });
  }
}
