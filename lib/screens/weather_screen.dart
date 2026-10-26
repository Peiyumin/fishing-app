import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/fishing_species.dart';
import '../models/fish.dart';
import '../models/weather_forecast.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/fish_service.dart';
import '../services/tide_service.dart';
import '../utils/geo_names.dart';
import '../widgets/location_prompt.dart';
import '../widgets/app_refresh.dart';

/// 天气页调色板 —— 深墨绿水面，不是深蓝夜空
///
/// 原来这套是「深空蓝 + 荧光黄绿」，和 App 其余部分的湖绿浅底完全是两个世界：
/// 从首页点进天气，像跳进了另一个产品。现在底色走 [AppTheme.ink*] 的深绿阶，
/// 高亮从荧光黄绿换成湖绿亮阶，暖金统一到 [AppTheme.star]，气压箭头从
/// 危险红改成暖橙（气压上升对钓鱼不是「错误」，用红色是误读）。
class _Pal {
  static const bg0 = Color(0xFF08130F); // 页面最底
  static const bg1 = AppTheme.inkBg; // 深水面
  static const card = AppTheme.inkSurface; // 卡面
  static const cardAlt = AppTheme.inkSurfaceAlt; // 交替行
  static const line = AppTheme.inkLine; // 分隔线
  static const head = AppTheme.inkHead; // 表头
  static const txt = AppTheme.inkText; // 主文字
  static const muted = AppTheme.inkMuted; // 次要文字
  static const gold = AppTheme.star; // 暖金（全站唯一暖色）
  static const accent = Color(0xFF4CC3D9); // 水蓝（气温/湿度）
  static const green = Color(0xFF6BD1A2); // 湖绿亮阶（口好）
  static const lime = AppTheme.inkHi; // 高亮（指数/选中）
  static const amber = AppTheme.warning; // 橙
  static const rise = Color(0xFFE8A67A); // 气压上升：暖橙，别用危险红
  static const fall = Color(0xFF5FD3AE);
}

/// 小数小时 → 「HH:mm」（如 6.7 → 06:42）
String _hm(double hourDouble) {
  final total = (hourDouble * 60).round();
  final hh = (total ~/ 60) % 24;
  final mm = total % 60;
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// 黄金时段显示串（如 "05:00-08:00"）→ 覆盖小时集合（含跨零点窗口）
Set<int> _goldenHoursFrom(List<String> windows) {
  final s = <int>{};
  for (final w in windows) {
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(w);
    if (m == null) continue;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(3)!);
    if (b > a) {
      for (var h = a; h < b; h++) {
        s.add(h % 24);
      }
    } else {
      for (var h = a; h < 24; h++) {
        s.add(h);
      }
      for (var h = 0; h < b; h++) {
        s.add(h);
      }
    }
  }
  return s;
}

/// 当天日出 / 日落时刻（返回本地小时小数，如 6.7 表示 06:42）。
/// NOAA 简化太阳位置算法，与天文年历偏差约 ±2 分钟，做图标/标识足够。
/// 高纬度极昼 / 极夜（cosω0 越界）兜底返回 (6, 18)。
(double, double) _sunTimes(DateTime date, double lat, double lng) {
  double rad(double d) => d * math.pi / 180;
  // 当天 00:00（UT）的儒略日；n 为「距 2000-01-01 的天数」，向上取整
  final midnightUtc = DateTime.utc(date.year, date.month, date.day);
  final jd = midnightUtc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  final n = (jd - 2451545.0 + 0.0008).ceil();
  final jStar = n - lng / 360.0; // 该经度的平太阳正午
  final m = rad((357.5291 + 0.98560028 * jStar) % 360);
  final c = 1.9148 * math.sin(m) +
      0.0200 * math.sin(2 * m) +
      0.0003 * math.sin(3 * m);
  final lambda = rad((m * 180 / math.pi + c + 180 + 102.9372) % 360);
  final jTransit =
      2451545.0 + jStar + 0.0053 * math.sin(m) - 0.0069 * math.sin(2 * lambda);
  final delta = math.asin(math.sin(lambda) * math.sin(rad(23.44)));
  final cosOmega = (math.sin(rad(-0.83)) - math.sin(rad(lat)) * math.sin(delta)) /
      (math.cos(rad(lat)) * math.cos(delta));
  if (cosOmega.isNaN || cosOmega > 1 || cosOmega < -1) return (6.0, 18.0);
  final omega = math.acos(cosOmega) * 180 / math.pi;
  double localH(double j) => ((j - 2440587.5) * 24.0 + 8.0) % 24.0;
  return (localH(jTransit - omega / 360.0), localH(jTransit + omega / 360.0));
}

/// 钓鱼天气预报：鱼种 × 钓法 × 逐小时鱼情
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  WeatherBundle? _bundle;
  bool _loading = true;
  String? _error;
  String? _city;

  int _selected = 0; // 选中的日期索引（0=今天）
  int _modeIdx = 0; // 0台钓 1路亚 2海钓
  int _spIdx = 0; // 鱼种
  int _refHour = DateTime.now().hour;

  /// 当前定位坐标（定位失败用杭州默认），供海钓潮汐估算使用
  double _lat = 30.2741;
  double _lng = 120.1551;

  @override
  void initState() {
    super.initState();
    _refHour = DateTime.now().hour;
    _load();
    // 城市名（失败不影响主流程）
    GeoNames.currentCity().then((c) {
      if (mounted && c != null && c.isNotEmpty) setState(() => _city = c);
    });
  }

  Future<void> _load() async {
    // ① 先亮缓存（哪怕已过期）：打开就有内容，不再白屏等网络
    if (_bundle == null) {
      final cached = await WeatherService.readCachedForecast(allowStale: true);
      if (cached != null && mounted) {
        setState(() {
          _bundle = cached;
          _loading = false;
        });
      }
    }
    if (mounted) {
      setState(() {
        _loading = _bundle == null;
        _error = null;
      });
    }

    // ② 有上次的坐标就立刻拉天气，不必干等 GPS（定位冷启动常常要 3~8 秒）
    final gen = ++_loadGen;
    final cachedLoc = await WeatherService.readCachedLocation();
    final hadCached = cachedLoc != null;
    if (cachedLoc != null && mounted) {
      _lat = cachedLoc.$1;
      _lng = cachedLoc.$2;
      // 不 await：让它和定位并行跑
      unawaited(_applyForecast(_lat, _lng, gen));
    }

    // ③ 定位（LocationService 内部已有 15s 上限；界面此时已经有缓存数据，
    //    所以这里等定位不会让用户干瞪眼）
    double lat = _lat, lng = _lng; // 兜底：上次坐标 / 杭州
    bool located = false;
    try {
      final pos = await LocationService.determinePosition();
      lat = pos.latitude;
      lng = pos.longitude;
      located = true;
    } on LocationException catch (e) {
      if (e.type == LocationErrorType.permissionDenied && mounted) {
        LocationPrompt.showError(context, e);
      }
    } catch (_) {
      // 超时 / 失败：用缓存坐标或默认坐标
    }

    // ④ 位置和缓存坐标差得多（>0.05°，约 5km）才重新拉一次
    final moved = !hadCached ||
        (lat - _lat).abs() > 0.05 ||
        (lng - _lng).abs() > 0.05;
    if (located && !moved) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _lat = lat;
    _lng = lng;
    // 新位置的结果才允许覆盖界面（作废前面那次缓存坐标的请求）
    final gen2 = ++_loadGen;
    await _applyForecast(lat, lng, gen2);
  }

  int _loadGen = 0;

  /// 拉一次预报并落到界面；[gen] 用于丢弃过期结果（避免后发先至覆盖）
  Future<void> _applyForecast(double lat, double lng, int gen) async {
    try {
      final b = await WeatherService.fetchForecast(lat, lng);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _bundle = b;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      if (_bundle == null) {
        setState(() => _error = e.toString());
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Pal.bg0,
      appBar: AppBar(
        backgroundColor: _Pal.bg0,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('钓鱼天气预报',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 21),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_Pal.bg0, _Pal.bg1, _Pal.bg0],
                ),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _StarPainter())),
          _content(),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading && _bundle == null) {
      return const Center(
        child: CircularProgressIndicator(color: _Pal.accent, strokeWidth: 2.5),
      );
    }
    if (_error != null && _bundle == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 54, color: _Pal.muted),
              const SizedBox(height: 12),
              Text('天气加载失败\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _Pal.muted, fontSize: 13)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _load,
                child: const Text('重试', style: TextStyle(color: _Pal.gold)),
              ),
            ],
          ),
        ),
      );
    }
    final b = _bundle;
    if (b == null || b.days.isEmpty) {
      return const Center(
        child: Text('暂无天气数据', style: TextStyle(color: _Pal.muted)),
      );
    }
    return AppRefresh(
      onRefresh: _load,
      color: _Pal.accent,
      backgroundColor: _Pal.card,
      child: _buildBody(b),
    );
  }

  Widget _buildBody(WeatherBundle b) {
    final mode = FishingMode.all[_modeIdx];
    // 目标鱼随钓法切换：台钓 / 路亚 / 海钓 各自是不同的鱼种表
    final species = FishingSpecies.forMode(mode.name);
    final sp = species[_spIdx.clamp(0, species.length - 1)];
    final metrics = WaterMetrics.derive(b.hours);
    final idxOf = <DateTime, int>{
      for (var i = 0; i < b.hours.length; i++) b.hours[i].time: i
    };

    final dayIdx = _selected.clamp(0, b.days.length - 1);
    final day = b.days[dayIdx];
    final dayHours = b.hoursOf(day.date);

    // 「现在」那一行的高亮，与顶部卡同一个下标（见 _currentHourIndex）
    final nowIdx = _currentHourIndex(b);

    final rows = <_HourRow>[];
    for (final h in dayHours) {
      final i = idxOf[h.time] ?? -1;
      final w = i >= 0 ? metrics[i] : WaterMetrics(h.temp, 7.0);
      final prev = i > 0 ? b.hours[i - 1] : null;
      final prevW = i > 0 ? metrics[i - 1] : null;
      rows.add(_HourRow(
        h: h,
        w: w,
        prev: prev,
        prevW: prevW,
        score: Bite.score(h: h, w: w, sp: sp, mode: mode),
      ));
    }

    // 黄金窗口期（当天评分最高的连续 3 小时）→ 逐时表打 ★ 标
    final gwHours =
        _goldenHoursFrom(_goldenForDay(b, day.date, sp, mode, metrics, idxOf));
    // 当天日出 / 日落时刻（本地小时数）→ 夜间图标判定 + 日升日落标识
    final (srH, ssH) = _sunTimes(day.date, _lat, _lng);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _LocationBar(city: _city),
        _NowCard(
          bundle: b,
          metrics: metrics,
          sp: sp,
          mode: mode,
          lat: _lat,
          lng: _lng,
          // 夜间口径与逐时表一致：19:00 起到次日日出前算夜间
          isNight: dayIdx == 0 &&
              (DateTime.now().hour >= 19 || DateTime.now().hour < srH),
        ),
        const SizedBox(height: 10),
        _DateStrip(
          bundle: b,
          metrics: metrics,
          idxOf: idxOf,
          sp: sp,
          mode: mode,
          selected: dayIdx,
          onSelect: (i) => setState(() => _selected = i),
        ),
        const SizedBox(height: 2),
        _ModeRow(
          selected: _modeIdx,
          onSelect: (i) => setState(() {
            _modeIdx = i;
            _spIdx = 0; // 换钓法后鱼种表不同，回到该钓法第一种鱼
          }),
        ),
        _SpeciesChips(
          species: species,
          selected: _spIdx.clamp(0, species.length - 1),
          onSelect: (i) => setState(() => _spIdx = i),
        ),
        _TitleRow(mode: mode, sp: sp),
        _ActionRow(
          onAi: () => _showAi(b, sp, mode),
          onCompare: () => _showCompare(b, sp, mode, metrics, idxOf),
          onExplain: _showExplain,
        ),
        _HourTable(
          rows: rows,
          // ★ 与顶部「当前」卡片同一口径：高亮「真·当前整点」那一行
          nowHour: dayIdx == 0 && nowIdx >= 0
              ? b.hours[nowIdx].time.hour
              : null,
          mode: mode,
          lat: _lat,
          lng: _lng,
          goldenHours: gwHours,
          sunriseH: srH,
          sunsetH: ssH,
        ),
      ],
    );
  }

  // ───────────────────────── 弹层 ─────────────────────────

  void _sheet(String title, List<Widget> body) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _Pal.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.32,
        maxChildSize: 0.92,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _Pal.txt,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: _Pal.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...body,
          ],
        ),
      ),
    );
  }

  void _showAi(WeatherBundle b, FishingSpecies sp, FishingMode mode) {
    _refHour = DateTime.now().hour; // 始终以当前小时为分析基准，保证实时
    final day = b.days[_selected.clamp(0, b.days.length - 1)];
    final h = b.dayRefHour(day.date, _refHour) ??
        (b.hours.isEmpty ? null : b.hours.first);
    final i = h == null ? -1 : b.hours.indexOf(h);
    final metrics = WaterMetrics.derive(b.hours);
    final w = i >= 0 ? metrics[i] : WaterMetrics(b.curTemp, 7.0);

    final at = h?.time ??
        DateTime(day.date.year, day.date.month, day.date.day, _refHour);
    // 判断走与逐时表完全相同的引擎：同一小时 → 同一个分，
    // 弹层里的解释就是这条分数的「为什么」。
    final result = h == null
        ? FishScore.computeRaw(
            method: mode.name,
            airTemp: b.curTemp,
            pressure: b.curPressure,
            windMs: b.curWindSpeed / 3.6,
            waterTemp: w.temp,
            dissolvedOxygen: w.oxygen,
            weatherCode: b.curCode,
            precipProb: b.curPrecipProb,
            hour: _refHour,
            dayRange: b.today.tempRange,
            sp: sp,
          )
        : FishScore.compute(method: mode.name, h: h, w: w, sp: sp);

    final idxOf = <DateTime, int>{
      for (var k = 0; k < b.hours.length; k++) b.hours[k].time: k
    };
    final gw = _goldenForDay(b, day.date, sp, mode, metrics, idxOf);

    final dim = result.dim;
    final score = result.indexScore ?? 0;
    final grade = result.grade;

    // —— AI 大模型判断入参：当前小时实况 + 当天逐时 + 鱼种习性 + 本地引擎结论 ——
    final aiHours = b
        .hoursOf(day.date)
        .map((x) => {
              'h': x.time.hour,
              't': double.parse(x.temp.toStringAsFixed(1)),
              'p': double.parse(x.pressure.toStringAsFixed(1)),
            })
        .toList();
    final aiNow = <String, dynamic>{
      'hour': _refHour,
      'airTemp': double.parse((h?.temp ?? b.curTemp).toStringAsFixed(1)),
      'pressure': double.parse((h?.pressure ?? b.curPressure).toStringAsFixed(1)),
      'pressureTrendCn': FishScore.trendCn(h?.pressureTrend),
      'humidity': h?.humidity ?? b.curHumidity,
      'windMs': double.parse(
          ((h?.windMs) ?? (b.curWindSpeed / 3.6)).toStringAsFixed(1)),
      'weatherCn': Wmo.text(h?.weatherCode ?? b.curCode),
      'precipProb': h?.precipProb ?? b.curPrecipProb,
      'waterTemp': double.parse(w.temp.toStringAsFixed(1)),
      'oxygen': double.parse(w.oxygen.toStringAsFixed(2)),
    };
    if (mode.name == '海钓') {
      aiNow['tideCn'] = TideService.at(_lat, _lng, at).display;
    }
    final aiPayload = <String, dynamic>{
      'method': mode.name,
      'season': seasonOf(day.date),
      'now': aiNow,
      'hours': aiHours,
      'species': {
        'name': sp.name,
        'habit': sp.habit,
        'optLow': sp.optLow,
        'optHigh': sp.optHigh,
        'minDo': sp.minDo,
        'likesWave': sp.likesWave,
      },
      'local': {
        'score': score,
        'grade': grade,
        'positives': result.positives,
        'negatives': result.negatives,
      },
    };

    // 维度分条（内陆无潮汐 → tide 为 null，自动不展示）
    final bars = <Widget>[];
    for (final key in [
      'pressure',
      'temp',
      'oxygen',
      'wind',
      'weather',
      'stable',
      'tide',
      'time'
    ]) {
      final v = dim[key];
      if (v == null) continue;
      bars.add(_dimBar(
        FishScore.dimName[key]!,
        v,
        // 海钓潮汐额外标注大/中/小潮，让「潮汐分」看得懂
        suffix: key == 'tide' ? FishScore.seaTideName(at) : null,
      ));
    }

    _sheet('AI 解析 · ${mode.name}·${sp.name}', [
      // 顶部：综合指数 + 分级 + 关键水体指标
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _scoreColor(score).withOpacity(0.16),
              _Pal.cardAlt,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Pal.line),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('综合鱼情指数',
                    style: TextStyle(color: _Pal.muted, fontSize: 10)),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$score',
                        style: TextStyle(
                            color: _scoreColor(score),
                            fontSize: 30,
                            height: 1,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 7),
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _scoreColor(score).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(grade,
                          style: TextStyle(
                              color: _scoreColor(score),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _kvPlain('水温', '${w.temp.toStringAsFixed(1)}℃'),
                const SizedBox(height: 8),
                if (mode.name == '海钓')
                  _kvPlain('潮汐记录', TideService.at(_lat, _lng, at).display)
                else
                  _kvPlain('水氧', '${w.oxygen.toStringAsFixed(2)} mg/L'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // 目标鱼习性（说明为什么这个鱼种今天好 / 不好）
      Text('${sp.name}：${sp.habit}',
          style: const TextStyle(
              color: _Pal.muted, fontSize: 10.5, height: 1.55)),
      const SizedBox(height: 12),
      // AI 大模型判断（点击后由后端大模型综合逐时天气 + 鱼种习性得出结论）
      _AiBitePanel(payload: aiPayload, speciesName: sp.name),
      const SizedBox(height: 14),
      // AI 判断依据：逐条列出「支撑开口 / 压制开口」的具体数据
      if (result.negatives.isNotEmpty) ...[
        Row(
          children: [
            const Icon(Icons.trending_down, size: 13, color: _Pal.amber),
            const SizedBox(width: 5),
            Text('压制开口（${result.negatives.length} 项）',
                style: const TextStyle(
                    color: _Pal.amber,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 7),
        ...result.negatives.take(4).map((t) => _aiFactor(t, false)),
        const SizedBox(height: 10),
      ],
      if (result.positives.isNotEmpty) ...[
        Row(
          children: [
            const Icon(Icons.trending_up, size: 13, color: _Pal.green),
            const SizedBox(width: 5),
            Text('支撑开口（${result.positives.length} 项）',
                style: const TextStyle(
                    color: _Pal.green,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 7),
        ...result.positives.take(4).map((t) => _aiFactor(t, true)),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 6),
      // 多维评分条
      const Text('多维评分',
          style: TextStyle(
              color: _Pal.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      ...bars,
      const SizedBox(height: 18),
      // 黄金时段
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _Pal.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Pal.gold.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wb_sunny_outlined, size: 14, color: _Pal.gold),
                SizedBox(width: 6),
                Text('黄金时段',
                    style: TextStyle(
                        color: _Pal.gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 9),
            ...gw.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      const Text('◷ ',
                          style: TextStyle(
                              color: _Pal.gold, fontWeight: FontWeight.bold)),
                      Text(g,
                          style: const TextStyle(
                              color: _Pal.txt,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const SizedBox(height: 5),
            Text(
              gw.length < 2
                  ? '当天高分窗口较少，建议参考以上时段或择日作钓'
                  : '以上为当天鱼情评分最高的连续 3 小时窗口',
              style: const TextStyle(color: _Pal.muted, fontSize: 10),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      // 分维度建议
      const Text('钓况建议',
          style: TextStyle(
              color: _Pal.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 9),
      Text(result.advice,
          style: const TextStyle(
              color: _Pal.muted, fontSize: 12.5, height: 1.6)),
      const SizedBox(height: 11),
      Text(
          '依据：气压与 3 小时变压 · 水温适温 · 水氧需求 · 风 · 天气现象 · 昼夜温差'
          '${mode.name == '海钓' ? ' · 潮汐' : ''} · ${sp.name}活跃时段'
          '（双模型气象数据 + 多维规则引擎；也可点上方让 AI 大模型再判一次）',
          style: const TextStyle(color: _Pal.muted, fontSize: 10)),
    ]);
  }

  /// 由当天逐时总分数推导黄金时段；当天数据不足（<20 小时）回退季节默认窗口
  List<String> _goldenForDay(
      WeatherBundle b,
      DateTime day,
      FishingSpecies sp,
      FishingMode mode,
      List<WaterMetrics> metrics,
      Map<DateTime, int> idxOf) {
    final arr = List<int>.filled(24, -1);
    var real = 0;
    final dayHours = b.hoursOf(day);
    for (final h in dayHours) {
      final k = idxOf[h.time] ?? -1;
      final w = k >= 0 ? metrics[k] : WaterMetrics(h.temp, 7.0);
      arr[h.time.hour] = Bite.score(h: h, w: w, sp: sp, mode: mode);
      real++;
    }
    if (real < 20) return FishScore.defaultWindows(seasonOf(day));
    for (var i = 0; i < 24; i++) {
      if (arr[i] < 0) arr[i] = 50; // 缺测小时填中性分，避免拖垮窗口均值
    }
    return FishScore.goldenWindows(arr, season: seasonOf(day));
  }

  /// 单个维度评分条
  Widget _dimBar(String name, int score, {String? suffix}) {
    final c = _scoreColor(score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(name,
                style: const TextStyle(color: _Pal.muted, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 8,
                backgroundColor: _Pal.line,
                valueColor: AlwaysStoppedAnimation(c),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text('$score',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 4),
            Text(suffix,
                style: const TextStyle(color: _Pal.muted, fontSize: 9.5)),
          ],
        ],
      ),
    );
  }

  /// AI 解析里的一条判断依据（带具体数值）
  Widget _kvPlain(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(k, style: const TextStyle(color: _Pal.muted, fontSize: 10)),
          const SizedBox(height: 3),
          Text(v,
              style: const TextStyle(
                  color: _Pal.txt,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );

  void _showCompare(
      WeatherBundle b,
      FishingSpecies sp,
      FishingMode mode,
      List<WaterMetrics> metrics,
      Map<DateTime, int> idxOf) {
    _refHour = DateTime.now().hour; // 始终以当前小时为对比基准，保证实时
    final day = b.days[_selected.clamp(0, b.days.length - 1)];
    final h = b.dayRefHour(day.date, _refHour);
    final i = h == null ? -1 : (idxOf[h.time] ?? -1);
    final w = i >= 0 ? metrics[i] : WaterMetrics(b.curTemp, 7.0);

    final list = FishingSpecies.forMode(mode.name)
        .map((s) => MapEntry(
            s,
            h == null
                ? 0
                : Bite.score(h: h, w: w, sp: s, mode: mode)))
        .toList()
      ..sort((a, b2) => b2.value.compareTo(a.value));

    _sheet('鱼种对比 · ${mode.name}', [
      Text('${mode.name}目标鱼 · 同一时段（${_refHour.toString().padLeft(2, '0')}:00）鱼情',
          style: const TextStyle(color: _Pal.muted, fontSize: 11.5)),
      const SizedBox(height: 14),
      ...list.map((e) {
        final s = e.key;
        final v = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          color: _Pal.txt,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${s.optLow.toStringAsFixed(0)}~${s.optHigh.toStringAsFixed(0)}℃',
                      style: const TextStyle(
                          color: _Pal.muted, fontSize: 10)),
                  const Spacer(),
                  Text('$v',
                      style: TextStyle(
                          color: _scoreColor(v),
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text(Bite.label(v),
                      style: TextStyle(color: _scoreColor(v), fontSize: 10.5)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v / 100,
                  minHeight: 5,
                  backgroundColor: _Pal.line,
                  valueColor: AlwaysStoppedAnimation(_scoreColor(v)),
                ),
              ),
              const SizedBox(height: 5),
              Text(s.habit,
                  style: const TextStyle(color: _Pal.muted, fontSize: 10.5)),
            ],
          ),
        );
      }),
    ]);
  }

  void _showExplain() {
    _sheet('指标解读', [
      _explainItem('指数（鱼情）',
          '综合「气压 × 水温适温 × 水氧 × 风 × 天气 × 温差 × 时段活性 × 钓法」'
          '得出的 0~100 分，并按目标鱼种的习性单独加权。\n'
          '90 分以上为爆护，80~89 分为有口，80 分以下为口弱（25 分以下基本停口）。'),
      _explainItem('为什么不是简单平均',
          '各维度先加权平均，再做「短板惩罚」：任何一项低于 62 分都会额外扣分，'
          '因为水氧极差、气压骤降这类致命问题，会被其它高分项平均掉。\n'
          '另外雷暴、严重缺氧、水温远离适温会直接压低总分上限。'),
      _explainItem('气温 / 气压',
          '气温气压为 ECMWF/GFS 与我国 CMA-GRAPES 两套模式的等权平均，'
          '比单一模式更接近国内天气软件（单模式夜间可差 3℃ 以上）。\n'
          '气压箭头是 3 小时变压：缓降多为锋前促口，急降多为变天停口，'
          '骤升（冷锋过境）鱼需要时间适应。'),
      _explainItem('风',
          '数字为风速 km/h，下方标签是风力等级与风向。2~4 级最利于作钓（推流增氧聚饵），'
          '无风闷、6 级以上压口。喜风浪的鱼（翘嘴/鲅鱼/马口）反而要有点风。'),
      _explainItem('水温',
          '无免费实测接口，按「水体热惯性」从气温序列推算：取前后约 30 小时的气温加权均值，'
          '水温日摆幅限制在 ±2.4℃ —— 真实水体一天只变化 1~3℃。\n'
          '不同鱼种适温区间不同，偏离区间每 1℃ 扣 8.5 分。'),
      _explainItem('水氧',
          '按该水温下的饱和溶氧 × 饱和比（风浪增氧、气压升高增氧、夜间藻类耗氧）估算。\n'
          '评分按目标鱼种的最低需求折算：鲫鱼 4.2mg/L 即可，鳜鱼/马口要 6mg/L 以上，'
          '不足需求的 70% 时基本浮头停口。'),
      _explainItem('口弱 / 有口 / 爆护',
          '80 分以下口弱：能钓，但别指望连竿，主攻早晚窗口；'
          '80~89 有口：正常鱼情，选对钓位能上鱼；'
          '90 分以上爆护：气压、水温、水氧、天气、时段同时到位，属于少数窗口。'),
    ]);
  }

  Widget _explainItem(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: _Pal.gold,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(body,
                style: const TextStyle(
                    color: _Pal.muted, fontSize: 12, height: 1.55)),
          ],
        ),
      );
}

// ============================================================
// 顶部定位条
// ============================================================
class _LocationBar extends StatelessWidget {
  final String? city;
  const _LocationBar({this.city});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Row(
        children: [
          const Icon(Icons.place, size: 15, color: _Pal.accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              city ?? '当前位置',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _Pal.txt,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: _Pal.muted),
        ],
      ),
    );
  }
}

// ============================================================
// 当前实况卡（顶部显示当前时间天气）
// ============================================================
/// 「当前时段」的唯一口径（v2.1.21）
///
/// ★★ 必须用「绝对时间上离现在最近的那个整点」，**不能锚 bundle.curHour**。
///
///   上一版（v2.1.20）为了修「首页 14:00 / 天气页 15:00」，把这里锚成了
///   `bundle.curHour` —— 那是**拉数据那一刻**的整点。问题在于 bundle 会被缓存：
///   18:20 拉到的包，20:40 打开天气页时仍锚在 18:00，而首页卡用的是
///   `DateTime.now()`（20:00）。于是两边又对不上了，而且这次更糟 ——
///   天气页显示的是两小时前的气温/湿度/风，垂钓指数也是按 18:00 算的。
///   用户看到的就是「首页准、天气页的当前时间不准，风力和湿度也对不上」。
///
///   逐时序列本身覆盖 7 天，任何时刻都能取到"现在"那个整点，所以锚回真·当前
///   小时既不会越界，也不会出现"标签写 20:00、数据是 18:00"的错位。
///   首页 `FishingWeather.fromBundle` 用的就是 indexOfHourNear(now)，两处同源。
int _currentHourIndex(WeatherBundle b) {
  // ★ 用 indexOfCurrentHour（20:35 → 20:00），不是 indexOfHourNear
  //   （那个在 20:30 之后会跳到 21:00，一个还没到的时段）。
  final i = b.indexOfCurrentHour(DateTime.now());
  if (i >= 0) return i;
  // 兜底：逐时序列缺失时才退回 bundle 自带的整点
  final cur = b.curHour;
  if (cur == null) return -1;
  return b.hours.indexWhere((x) => x.time == cur);
}

class _NowCard extends StatelessWidget {
  final WeatherBundle bundle;
  final List<WaterMetrics> metrics;
  final FishingSpecies sp;
  final FishingMode mode;
  final double lat;
  final double lng;

  /// 当前是否夜间（19:00 起到次日日出前）——决定大图标用太阳还是月亮
  final bool isNight;
  const _NowCard({
    required this.bundle,
    required this.metrics,
    required this.sp,
    required this.mode,
    required this.lat,
    required this.lng,
    this.isNight = false,
  });

  @override
  Widget build(BuildContext context) {
    // 取与当前时刻最近的一小时，作为水温/水氧与评分的依据
    // ★ 时段统一（v2.1.21）：见 _currentHourIndex 的注释 —— 必须锚"真·当前整点"，
    //   不能锚 bundle.curHour（那是拉包时刻，缓存后就会落后一两个小时）。
    final now = DateTime.now();
    final best = _currentHourIndex(bundle);
    final h = best >= 0 && best < bundle.hours.length
        ? bundle.hours[best]
        : null;
    final w = best >= 0 && best < metrics.length
        ? metrics[best]
        : WaterMetrics(bundle.curTemp, 7.0);
    final prev = best > 0 ? bundle.hours[best - 1] : null;
    final isSea = mode.name == '海钓';
    // 海钓：用当前定位 + 时间估算潮汐（潮高 / 涨退），替换水氧指标
    final tide = isSea ? TideService.at(lat, lng, h?.time ?? now) : null;
    // ★★ 一次性把这几个「当前」值全部落到上面选中的那一小时 h 上（v2.1.21）
    //
    //   之前是"半新半旧"：时间标签用的是 h.hhmm，但温度、天气代码、气压、
    //   风速风向全都在用 bundle.curTemp / curCode / curPressure / curWindSpeed ——
    //   那是**拉包那一刻**的值。于是缓存一过整点，卡上就会出现「20:00 的标题 +
    //   18:00 的温度/风力」，用户看到的正是"当前时间段不准、风力和湿度对不上"。
    //   现在统一取 h，h 缺失时才回退到 bundle 自带值。
    final temp = h?.temp ?? bundle.curTemp;
    final code = h?.weatherCode ?? bundle.curCode;
    final pres = h?.pressure ?? bundle.curPressure;
    final wind = h?.windSpeed ?? bundle.curWindSpeed;
    final windDir = h?.windDir ?? bundle.curWindDir;
    final hum = h?.humidity ?? bundle.curHumidity;

    final score = h == null
        ? (FishScore.computeRaw(
            method: mode.name,
            airTemp: bundle.curTemp,
            pressure: bundle.curPressure,
            windMs: bundle.curWindSpeed / 3.6,
            waterTemp: w.temp,
            dissolvedOxygen: w.oxygen,
            weatherCode: bundle.curCode,
            precipProb: bundle.curPrecipProb,
            hour: now.hour,
            dayRange: bundle.today.tempRange,
            sp: sp,
          ).indexScore ??
            50)
        : Bite.score(h: h, w: w, sp: sp, mode: mode);

    final pDelta = prev == null ? 0.0 : pres - prev.pressure;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: _Pal.card.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Pal.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Wmo.icon(code, day: !isNight),
                  size: 38, color: Wmo.color(code, day: !isNight)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(temp.toStringAsFixed(1),
                          style: const TextStyle(
                              color: _Pal.txt,
                              fontSize: 26,
                              height: 1,
                              fontWeight: FontWeight.w700)),
                      const Text('°C',
                          style: TextStyle(
                              color: _Pal.gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 标出这是哪个整点的数据：温度、天气现象、指数全部来自这一小时，
                  // 用户对照下面逐时表就能核对上（表里这一行也会高亮成「现在」）
                  Text(
                      h == null
                          ? '当前 · ${Wmo.text(code)}'
                          : '${h.hhmm} · ${Wmo.text(code)}',
                      style: const TextStyle(color: _Pal.muted, fontSize: 11)),
                ],
              ),
              const Spacer(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$score',
                      style: TextStyle(
                          color: _scoreColor(score),
                          fontSize: 24,
                          height: 1,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _scoreColor(score).withOpacity(0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(Bite.label(score),
                        style: TextStyle(
                            color: _scoreColor(score),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 3),
                  // 指数口径：同一小时、不同目标鱼/钓法分数本来就不同。
                  // 标出来，用户才不会拿首页（固定鲫鱼·台钓）比出"数据错了"的错觉。
                  Text('${sp.name} · ${mode.name}',
                      style:
                          const TextStyle(color: _Pal.muted, fontSize: 8.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 第一行：和首页「实时天气」卡**同字段、同单位**（气压 / 风 / 湿度）
          //   ★ 之前这里只有「气压 / 风(只写几级) / 水温 / 水氧」，没有湿度、
          //     风也没有具体风速 —— 用户拿首页卡过来对照，自然会觉得"少了东西"。
          Row(
            children: [
              _Stat(
                label: '气压 (hPa)',
                value: pres.toStringAsFixed(0),
                extra: _trendText(pDelta, fontSize: 9),
              ),
              _Stat(
                label:
                    '风 · ${windDirText(windDir)}${_beaufort(wind)}级',
                value: '${wind.toStringAsFixed(0)}km/h',
              ),
              _Stat(
                label: '湿度 (%)',
                value: '$hum',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：钓鱼专用指标（水温 + 水氧 / 海钓潮汐）
          Row(
            children: [
              _Stat(label: '水温', value: '${w.temp.toStringAsFixed(1)}℃'),
              if (isSea)
                _Stat(label: '潮汐记录', value: tide!.display)
              else
                _Stat(label: '水氧', value: w.oxygen.toStringAsFixed(2)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Widget? extra;
  const _Stat({required this.label, required this.value, this.extra});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: _Pal.muted, fontSize: 9),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    maxLines: 1,
                    style: const TextStyle(
                        color: _Pal.txt,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                if (extra != null) extra!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 日期胶囊（7 天）
// ============================================================
class _DateStrip extends StatelessWidget {
  final WeatherBundle bundle;
  final List<WaterMetrics> metrics;
  final Map<DateTime, int> idxOf;
  final FishingSpecies sp;
  final FishingMode mode;
  final int selected;
  final ValueChanged<int> onSelect;

  const _DateStrip({
    required this.bundle,
    required this.metrics,
    required this.idxOf,
    required this.sp,
    required this.mode,
    required this.selected,
    required this.onSelect,
  });

  static const _wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String _label(int i, DateTime d) {
    if (i == 0) return '今天';
    if (i == 1) return '明天';
    if (i == 2) return '后天';
    return _wd[d.weekday - 1];
  }

  /// 全天平均鱼情（用于胶囊下的鱼图标）
  int _dayScore(int i) {
    final hs = bundle.hoursOf(bundle.days[i].date);
    if (hs.isEmpty) return 0;
    var sum = 0;
    for (final h in hs) {
      final k = idxOf[h.time] ?? -1;
      final w = k >= 0 ? metrics[k] : WaterMetrics(h.temp, 7.0);
      sum += Bite.score(h: h, w: w, sp: sp, mode: mode);
    }
    return (sum / hs.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: bundle.days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = bundle.days[i].date;
          final sel = i == selected;
          final sc = _dayScore(i);
          final n = Bite.fishCount(sc);
          final disabled = sc < 45;

          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_Pal.head, _Pal.card],
                      )
                    : null,
                color: sel ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? _Pal.muted : _Pal.line,
                  width: sel ? 1.2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_label(i, d),
                      style: TextStyle(
                          color: sel ? Colors.white : _Pal.muted,
                          fontSize: 11,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.normal)),
                  const SizedBox(height: 3),
                  Text(
                    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: sel ? Colors.white : _Pal.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (k) => Text(
                        '🐟',
                        style: TextStyle(
                          fontSize: 8,
                          color: k < n
                              ? (disabled ? _Pal.muted : _Pal.gold)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// 钓法切换
// ============================================================
class _ModeRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _ModeRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Row(
        children: [
          for (var i = 0; i < FishingMode.all.length; i++) ...[
            GestureDetector(
              onTap: () => onSelect(i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    FishingMode.all[i].name,
                    style: TextStyle(
                      color: i == selected ? _Pal.txt : _Pal.muted,
                      fontSize: i == selected ? 16 : 14,
                      fontWeight:
                          i == selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: i == selected ? 20 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _Pal.lime,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
          ],
          const Spacer(),
          const Icon(Icons.grid_view_rounded, size: 17, color: _Pal.muted),
        ],
      ),
    );
  }
}

// ============================================================
// 鱼种 chips
// ============================================================
class _SpeciesChips extends StatelessWidget {
  /// 当前钓法下的目标鱼（台钓 / 路亚 / 海钓 各不同）
  final List<FishingSpecies> species;
  final int selected;
  final ValueChanged<int> onSelect;
  const _SpeciesChips({
    required this.species,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        itemCount: species.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? _Pal.lime.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? _Pal.lime : _Pal.line,
                  width: sel ? 1.1 : 1,
                ),
              ),
              child: Text(
                species[i].name,
                style: TextStyle(
                  color: sel ? _Pal.lime : _Pal.muted,
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// 标题 + 图例
// ============================================================
class _TitleRow extends StatelessWidget {
  final FishingMode mode;
  final FishingSpecies sp;
  const _TitleRow({required this.mode, required this.sp});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: [
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${mode.name}·${sp.name}',
                    style: const TextStyle(
                        color: _Pal.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: '逐小时钓鱼指数',
                    style: TextStyle(color: _Pal.txt, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    colors: [
                      _Pal.amber,
                      _Pal.gold,
                      _Pal.green
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              const Row(
                children: [
                  Text('宜钓指数',
                      style: TextStyle(color: _Pal.muted, fontSize: 8.5)),
                  SizedBox(width: 6),
                  Text('高', style: TextStyle(color: _Pal.green, fontSize: 8.5)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 三个功能按钮
// ============================================================
class _ActionRow extends StatelessWidget {
  final VoidCallback onAi;
  final VoidCallback onCompare;
  final VoidCallback onExplain;
  const _ActionRow({
    required this.onAi,
    required this.onCompare,
    required this.onExplain,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          _Act(icon: Icons.auto_awesome, label: 'AI解析', onTap: onAi),
          const SizedBox(width: 8),
          _Act(icon: Icons.swap_horiz, label: '鱼种对比', onTap: onCompare),
          const SizedBox(width: 8),
          _Act(icon: Icons.menu_book_outlined, label: '解读', onTap: onExplain),
        ],
      ),
    );
  }
}

class _Act extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Act({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: _Pal.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _Pal.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: _Pal.gold),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(color: _Pal.txt, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 逐小时表格
// ============================================================
class _HourRow {
  final HourPoint h;
  final WaterMetrics w;
  final HourPoint? prev;
  final WaterMetrics? prevW;
  final int score;
  const _HourRow({
    required this.h,
    required this.w,
    required this.prev,
    required this.prevW,
    required this.score,
  });
}

class _HourTable extends StatelessWidget {
  final List<_HourRow> rows;
  final int? nowHour;
  final FishingMode mode;
  final double lat;
  final double lng;

  /// 黄金窗口期覆盖的小时集合（当天评分最高的连续 3 小时窗口）
  final Set<int> goldenHours;

  /// 当天日出 / 日落时刻（本地小时数，小数，如 6.7 = 06:42）
  final double sunriseH;
  final double sunsetH;

  const _HourTable({
    required this.rows,
    this.nowHour,
    required this.mode,
    required this.lat,
    required this.lng,
    this.goldenHours = const {},
    this.sunriseH = 6.0,
    this.sunsetH = 18.0,
  });

  static const int _fTime = 28;
  static const int _fWx = 40;
  static const int _fTemp = 30;
  static const int _fPres = 34;
  static const int _fWind = 36;
  static const int _fWater = 26;
  static const int _fO2 = 30;
  static const int _fScore = 34;

  /// 逐时时间的人性化表述：返回（时段, 钟点），如（上午, 9点）（下午, 3点）。
  /// 比裸数字 00/01 更易读，又不占太宽。
  static (String, String) _timeLabel(int hour) {
    final String period;
    if (hour <= 5) {
      period = '凌晨';
    } else if (hour <= 11) {
      period = '上午';
    } else if (hour == 12) {
      period = '中午';
    } else if (hour <= 17) {
      period = '下午';
    } else {
      period = '晚上';
    }
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return (period, '$h12点');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: _Pal.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Pal.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 表头
          Container(
            color: _Pal.head,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                const _Th('时间', _fTime),
                const _Th('天气', _fWx),
                const _Th2('气温', '°C', _fTemp),
                const _Th2('气压', 'hPa', _fPres),
                const _Th2('风', 'km/h', _fWind),
                const _Th2('水温', '°C', _fWater),
                _Th2(mode.name == '海钓' ? '潮汐记录' : '水氧',
                    mode.name == '海钓' ? '潮位' : 'mg/L', _fO2),
                const _Th2('指数', '鱼情', _fScore),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('暂无逐小时数据',
                  style: TextStyle(color: _Pal.muted, fontSize: 12)),
            ),
          ...rows.asMap().entries.map((e) => _row(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _row(int i, _HourRow r) {
    final h = r.h;
    // 夜间口径：晚 19:00 起至次日日出为止（用户明确要求），
    // 日出前的小时即使 >=6 点也算夜间（冬季日出晚，天确实还没亮）
    final isDay = h.time.hour >= sunriseH && h.time.hour < 19;
    final isNow = nowHour != null && h.time.hour == nowHour;

    // 日升 / 日落标识：落在该小时行内就显示（图标 + 时刻）
    final showSunrise = sunriseH.floor() == h.time.hour;
    final showSunset = sunsetH.floor() == h.time.hour;
    final isGolden = goldenHours.contains(h.time.hour);

    // 气温冷热标签
    Widget? tempTag;
    if (h.temp < 15) {
      tempTag = _miniTag('冷', _Pal.accent); // 冷＝水蓝（用暖色标「冷」是反的）
    } else if (h.temp > 28) {
      tempTag = _miniTag('热', _Pal.amber); // 热＝暖橙
    }

    // 气压升降
    Widget presTrend;
    if (r.prev == null) {
      presTrend = const Text('—',
          style: TextStyle(color: _Pal.muted, fontSize: 8.5));
    } else {
      final d = h.pressure - r.prev!.pressure;
      final up = d >= 0;
      presTrend = Text(
        '${up ? '↑' : '↓'} ${up ? '+' : '-'}${d.abs().toStringAsFixed(1)}',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
            color: up ? _Pal.rise : _Pal.fall,
            fontSize: 8.5,
            fontWeight: FontWeight.w600),
      );
    }

    // 水氧升降
    Widget o2Trend;
    if (r.prevW == null) {
      o2Trend = const Text('—',
          style: TextStyle(color: _Pal.muted, fontSize: 8.5));
    } else {
      final d = r.w.oxygen - r.prevW!.oxygen;
      o2Trend = Text(
        '${d >= 0 ? '+' : '-'}${d.abs().toStringAsFixed(2)}',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
            color: d >= 0 ? _Pal.fall : _Pal.rise, fontSize: 8.5),
      );
    }

    final sc = r.score;
    final scColor = _scoreColor(sc);
    final tl = _timeLabel(h.time.hour);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      decoration: BoxDecoration(
        // 当前时间行：明显提亮 + 左侧湖绿竖条，下拉浏览时一眼定位「现在」
        color: isNow
            ? _Pal.head
            : (i.isEven ? Colors.transparent : const Color(0x08FFFFFF)),
        border: Border(
          bottom: const BorderSide(color: _Pal.line, width: 0.6),
          // 「现在」用湖绿亮阶，金色只留给「黄金时段」——
          // 两种含义共用一个颜色，用户就分不出哪个是「现在」哪个是「好时段」。
          left: isNow
              ? const BorderSide(color: _Pal.lime, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          _Td(
            flex: _fTime,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isNow ? '现在' : tl.$1,
                    maxLines: 1,
                    style: TextStyle(
                        color: isNow ? _Pal.gold : _Pal.muted,
                        fontSize: 8.5,
                        height: 1.1,
                        fontWeight:
                            isNow ? FontWeight.w700 : FontWeight.w400)),
                const SizedBox(height: 1),
                Text(tl.$2,
                    maxLines: 1,
                    style: TextStyle(
                        color: isNow ? _Pal.gold : _Pal.txt,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.1)),
                // 日升 / 日落标识（带具体时刻）
                if (showSunrise || showSunset) ...[
                  const SizedBox(height: 2),
                  // 时间列很窄（320dp 下仅约 39px），用 FittedBox 自动缩放，
                  // 避免「日出 06:21」把表格撑出横向溢出
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            showSunrise
                                ? Icons.wb_twilight
                                : Icons.brightness_3,
                            size: 9,
                            color: showSunrise
                                ? _Pal.gold
                                : _Pal.amber),
                        const SizedBox(width: 1),
                        Text(
                            showSunrise
                                ? '日出${_hm(sunriseH)}'
                                : '日落${_hm(sunsetH)}',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                color: showSunrise
                                    ? _Pal.gold
                                    : _Pal.amber,
                                fontSize: 7.5,
                                height: 1.1)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Td(
            flex: _fWx,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Wmo.icon(h.weatherCode, day: isDay),
                    size: 18, color: Wmo.color(h.weatherCode, day: isDay)),
                const SizedBox(height: 2),
                Text(Wmo.text(h.weatherCode),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: _Pal.muted, fontSize: 8.5)),
              ],
            ),
          ),
          _Td(
            flex: _fTemp,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(h.temp.toStringAsFixed(1),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: _Pal.txt, fontSize: 12)),
                if (tempTag != null) tempTag,
              ],
            ),
          ),
          _Td(
            flex: _fPres,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(h.pressure.toStringAsFixed(1),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: _Pal.txt, fontSize: 11)),
                const SizedBox(height: 1),
                presTrend,
              ],
            ),
          ),
          _Td(
            flex: _fWind,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${h.windSpeed.round()}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: _Pal.txt, fontSize: 12)),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _Pal.line),
                  ),
                  child: Text(
                    '${_beaufort(h.windSpeed)}级·${windDirText(h.windDir)}',
                    maxLines: 1,
                    style: const TextStyle(color: _Pal.muted, fontSize: 7.5),
                  ),
                ),
              ],
            ),
          ),
          _Td(
            flex: _fWater,
            child: Text(r.w.temp.toStringAsFixed(1),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(color: _Pal.txt, fontSize: 12)),
          ),
          _Td(
            flex: _fO2,
            child: mode.name == '海钓'
                ? _tideCell(r.h.time)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.w.oxygen.toStringAsFixed(2),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(color: _Pal.txt, fontSize: 11)),
                      const SizedBox(height: 1),
                      o2Trend,
                    ],
                  ),
          ),
          _Td(
            flex: _fScore,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 黄金窗口期标记：金色 ★ + 「黄金」小签
                if (isGolden)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: _Pal.gold.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: _Pal.gold.withOpacity(0.45)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 8, color: _Pal.gold),
                        SizedBox(width: 1),
                        Text('黄金',
                            style: TextStyle(
                                color: _Pal.gold,
                                fontSize: 7.5,
                                height: 1.1)),
                      ],
                    ),
                  ),
                Text('$sc',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        color: scColor,
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(Bite.label(sc),
                    style: TextStyle(color: scColor, fontSize: 8.5)),
                const SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    Bite.fishCount(sc),
                    (_) => const Text('🐟', style: TextStyle(fontSize: 7.5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 海钓模式下的「潮汐记录」单元格：潮高 + 涨/退/平潮
  Widget _tideCell(DateTime t) {
    final tide = TideService.at(lat, lng, t);
    final color = tide.state == '涨潮'
        ? _Pal.rise
        : (tide.state == '退潮' ? _Pal.fall : _Pal.muted);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${tide.heightM >= 0 ? '+' : ''}${tide.heightM.toStringAsFixed(1)}m',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: const TextStyle(color: _Pal.txt, fontSize: 11)),
        const SizedBox(height: 1),
        Text(tide.state,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _miniTag(String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 7.5)),
      );
}

class _Th extends StatelessWidget {
  final String text;
  final int flex;
  const _Th(this.text, this.flex);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _Pal.muted, fontSize: 10)),
    );
  }
}

class _Th2 extends StatelessWidget {
  final String main;
  final String sub;
  final int flex;
  const _Th2(this.main, this.sub, this.flex);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(main,
              style: const TextStyle(color: _Pal.muted, fontSize: 10)),
          Text(sub,
              style: const TextStyle(color: _Pal.muted, fontSize: 7.5)),
        ],
      ),
    );
  }
}

class _Td extends StatelessWidget {
  final int flex;
  final Widget child;
  const _Td({required this.flex, required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(flex: flex, child: Center(child: child));
  }
}

// ============================================================
// 工具
// ============================================================
Color _scoreColor(int s) {
  // 四档要能一眼分出高低：爆护最亮（它就是用户扫表时在找的那几行），
  // 有口次亮，口弱转橙（不是好鱼情），<45 直接降到次要文字色。
  // 原来 ≥90 用暗绿、≥80 用亮绿，两档几乎同色，等于没有分级。
  if (s >= 90) return _Pal.lime;
  if (s >= 80) return _Pal.green;
  if (s >= 45) return _Pal.amber;
  return _Pal.muted;
}

/// AI 因素条目（本地引擎与 AI 大模型面板共用）
Widget _aiFactor(String text, bool good) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(good ? '✓ ' : '! ',
              style: TextStyle(
                  color: good ? _Pal.green : _Pal.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: _Pal.muted, fontSize: 11.5, height: 1.5)),
          ),
        ],
      ),
    );

Widget _trendText(double d, {double fontSize = 9}) {
  final up = d >= 0;
  return Text(
    '${up ? '↑' : '↓'}${d.abs().toStringAsFixed(1)}',
    style: TextStyle(
        color: up ? _Pal.rise : _Pal.fall,
        fontSize: fontSize,
        fontWeight: FontWeight.w600),
  );
}

/// 蒲福风力等级（按 km/h）
int _beaufort(double kmh) {
  if (kmh < 1) return 0;
  if (kmh < 6) return 1;
  if (kmh < 12) return 2;
  if (kmh < 20) return 3;
  if (kmh < 29) return 4;
  if (kmh < 39) return 5;
  if (kmh < 50) return 6;
  if (kmh < 62) return 7;
  return 8;
}

/// 深空星点背景
class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(20261020);
    final p = Paint();
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.4 + rnd.nextDouble() * 1.2;
      p.color = Colors.white.withOpacity(0.10 + rnd.nextDouble() * 0.42);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// AI 大模型鱼口判断面板：点击后由后端大模型综合「逐时天气 + 鱼种习性」得出结论。
/// 后端未配置 AI / 网络异常时给出提示，页面下方的本地规则引擎结果不受影响。
class _AiBitePanel extends StatefulWidget {
  final Map<String, dynamic> payload;
  final String speciesName;

  const _AiBitePanel({required this.payload, required this.speciesName});

  @override
  State<_AiBitePanel> createState() => _AiBitePanelState();
}

class _AiBitePanelState extends State<_AiBitePanel> {
  bool _loading = false;
  AiBite? _res;
  String _err = '';

  Future<void> _run() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final r = await FishService.biteAi(widget.payload);
      if (!mounted) return;
      setState(() {
        _res = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 透传后端文案（如 429 限流提示），失败也有明确原因
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _loading = false;
        _err = msg.isNotEmpty ? msg : 'AI 服务暂时不可用，请稍后再试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    // —— 未请求：可点击的入口 ——
    if (r == null && !_loading) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _run,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _Pal.accent.withOpacity(0.14),
              _Pal.cardAlt,
            ]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _Pal.accent.withOpacity(0.45)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: _Pal.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI 大模型判断',
                        style: TextStyle(
                            color: _Pal.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('让大模型综合当天逐时天气与${widget.speciesName}习性，'
                        '判断当前是否开口',
                        style: const TextStyle(
                            color: _Pal.muted, fontSize: 10, height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: _Pal.muted),
            ],
          ),
        ),
      );
    }

    // —— 请求中 ——
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _Pal.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Pal.line),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _Pal.accent),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('AI 正在分析逐时天气与鱼种习性…',
                  style: TextStyle(color: _Pal.muted, fontSize: 11.5)),
            ),
          ],
        ),
      );
    }

    // —— 失败（后端未配置 / 网络异常）：提示并保留本地引擎结果 ——
    if (!r!.ok) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _Pal.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Pal.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: _Pal.amber),
                const SizedBox(width: 6),
                const Text('AI 大模型暂不可用',
                    style: TextStyle(
                        color: _Pal.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(_err.isNotEmpty ? _err : r.msg,
                style: const TextStyle(
                    color: _Pal.muted, fontSize: 10.5, height: 1.5)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _run,
                child: const Text('重试',
                    style: TextStyle(
                        color: _Pal.accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }

    // —— 成功：分数 + 结论 + 因素 + 建议 ——
    final s = r.score ?? 0;
    final c = _scoreColor(s);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          c.withOpacity(0.13),
          _Pal.cardAlt,
        ]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: _Pal.accent),
              const SizedBox(width: 6),
              const Text('AI 大模型判断',
                  style: TextStyle(
                      color: _Pal.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (r.score != null) ...[
                Text('$s',
                    style: TextStyle(
                        color: c,
                        fontSize: 20,
                        height: 1,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(r.grade,
                      style: TextStyle(
                          color: c,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          if (r.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.summary,
                style: const TextStyle(
                    color: _Pal.txt, fontSize: 12.5, height: 1.5)),
          ],
          if (r.negatives.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.trending_down, size: 13, color: _Pal.amber),
                const SizedBox(width: 5),
                Text('压制开口（${r.negatives.length} 项）',
                    style: TextStyle(
                        color: _Pal.amber,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 7),
            ...r.negatives.take(4).map((t) => _aiFactor(t, false)),
          ],
          if (r.positives.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.trending_up, size: 13, color: _Pal.green),
                const SizedBox(width: 5),
                Text('支撑开口（${r.positives.length} 项）',
                    style: TextStyle(
                        color: _Pal.green,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 7),
            ...r.positives.take(4).map((t) => _aiFactor(t, true)),
          ],
          if (r.advice.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r.advice,
                style: const TextStyle(
                    color: _Pal.muted, fontSize: 12, height: 1.55)),
          ],
          const SizedBox(height: 8),
          Text(
              '由大模型${r.model.isNotEmpty ? '（${r.model}）' : ''}综合逐时天气与鱼种习性生成，仅供参考',
              style: const TextStyle(color: _Pal.muted, fontSize: 9.5)),
        ],
      ),
    );
  }
}
