import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/fishing_species.dart';
import '../models/weather_forecast.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/geo_names.dart';
import '../widgets/location_prompt.dart';

/// 深空配色（对齐钓鱼天气参考稿）
class _Pal {
  static const bg0 = Color(0xFF070D19);
  static const bg1 = Color(0xFF0C1730);
  static const card = Color(0xFF111D33);
  static const cardAlt = Color(0xFF0E1828);
  static const line = Color(0xFF1E2C46);
  static const head = Color(0xFF12354B);
  static const txt = Color(0xFFE9F0FA);
  static const muted = Color(0xFF7F93AE);
  static const gold = Color(0xFFF3C860);
  static const accent = Color(0xFF54C8DE);
  static const green = Color(0xFF7CE58C);
  static const lime = Color(0xFFD8E86A);
  static const amber = Color(0xFFF2C24B);
  static const rise = Color(0xFFFF7A6B);
  static const fall = Color(0xFF5FD3AE);
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
    if (_bundle == null) {
      final cached = await WeatherService.readCachedForecast();
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

    double lat = 30.2741, lng = 120.1551; // 默认：杭州
    try {
      final pos = await LocationService.determinePosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } on LocationException catch (e) {
      if (e.type == LocationErrorType.permissionDenied && mounted) {
        LocationPrompt.showError(context, e);
      }
    } catch (_) {
      // 用默认坐标
    }
    try {
      final b = await WeatherService.fetchForecast(lat, lng);
      if (mounted) {
        setState(() {
          _bundle = b;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _bundle == null) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    return RefreshIndicator(
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
          nowHour: dayIdx == 0 ? DateTime.now().hour : null,
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
    final day = b.days[_selected.clamp(0, b.days.length - 1)];
    final h = b.dayRefHour(day.date, _refHour);
    final i = h == null ? -1 : b.hours.indexOf(h);
    final metrics = WaterMetrics.derive(b.hours);
    final w = i >= 0 ? metrics[i] : WaterMetrics(b.curTemp, 7.0);

    final at = h?.time ??
        DateTime(day.date.year, day.date.month, day.date.day, _refHour);
    final result = FishScore.compute(
      method: mode.name,
      pressure: h?.pressure ?? b.curPressure,
      pressureTrend: h?.pressureTrend ?? 'steady',
      windMs: (h?.windMs) ?? (b.curWindSpeed / 3.6),
      waterTemp: w.temp,
      dissolvedOxygen: w.oxygen,
      sp: sp,
      at: at,
    );

    final idxOf = <DateTime, int>{
      for (var k = 0; k < b.hours.length; k++) b.hours[k].time: k
    };
    final gw = _goldenForDay(b, day.date, sp, mode, metrics, idxOf);

    final dim = result.dim;
    final score = result.indexScore ?? 0;
    final grade = result.grade;

    // 维度分条（内陆无潮汐 → tide 为 null，自动不展示）
    final bars = <Widget>[];
    for (final key in ['pressure', 'wind', 'temp', 'oxygen', 'tide', 'time']) {
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
                _kvPlain('溶氧', '${w.oxygen.toStringAsFixed(2)} mg/L'),
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
      const SizedBox(height: 16),
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
              color: Color(0xFFBBC9DC), fontSize: 12.5, height: 1.6)),
      const SizedBox(height: 11),
      const Text(
          '依据：气压稳定度 · 风 · 水温适温 · 溶氧 · 时段活性 · 潮汐（海钓）'
          ' · 鱼种习性（离线多维规则引擎）',
          style: TextStyle(color: _Pal.muted, fontSize: 10)),
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
          '综合「气象适宜度 × 鱼种适温 × 溶氧 × 时段活性 × 钓法」得出的 0~100 分。'
          '78 分以上为爆护，45 分以上为有口，低于 45 分基本无口。'),
      _explainItem('气温 / 气压',
          '来自 Open-Meteo 实测与预报。气压下方的箭头是逐小时升降：'
          '↑ 上升（鱼活性转好），↓ 下降（鱼易上浮、吃口变轻）。'),
      _explainItem('风',
          '数字为风速 km/h，下方标签是风力等级与风向。微风（1~3 级）最利于作钓，'
          '大风会压口且影响抛投。'),
      _explainItem('水温',
          '无免费实测接口，按「水体热惯性」从气温序列推算：水温变化远比气温平缓，'
          '白天表层略升、夜间回落。不同鱼种适温区间不同。'),
      _explainItem('水氧（溶氧）',
          '同样按水文学经验模型估算：水温越低饱和溶氧越高，风浪增氧、气压升高提升溶解量，'
          '白天藻类光合作用产氧、凌晨耗氧。低于 4mg/L 鱼基本不开口。'),
      _explainItem('有口 / 爆护 / 无口',
          '把上面所有因子折算成一句结论，直接告诉你这一小时值不值得下竿。'),
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
                    color: Color(0xFFBBC9DC), fontSize: 12, height: 1.55)),
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
class _NowCard extends StatelessWidget {
  final WeatherBundle bundle;
  final List<WaterMetrics> metrics;
  final FishingSpecies sp;
  final FishingMode mode;
  const _NowCard({
    required this.bundle,
    required this.metrics,
    required this.sp,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    // 取与当前时刻最近的一小时，作为水温/溶氧与评分的依据
    int best = -1;
    var bestDiff = 1 << 30;
    final now = DateTime.now();
    for (var i = 0; i < bundle.hours.length; i++) {
      final d = bundle.hours[i].time.difference(now).inMinutes.abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    final h = best >= 0 ? bundle.hours[best] : null;
    final w = best >= 0 ? metrics[best] : WaterMetrics(bundle.curTemp, 7.0);
    final prev = best > 0 ? bundle.hours[best - 1] : null;
    final score = h == null
        ? (FishScore.compute(
            method: mode.name,
            pressure: bundle.curPressure,
            pressureTrend: 'steady',
            windMs: bundle.curWindSpeed / 3.6,
            waterTemp: w.temp,
            dissolvedOxygen: w.oxygen,
            sp: sp,
            at: DateTime.now(),
          ).indexScore ??
            bundle.currentFishIndex)
        : Bite.score(h: h, w: w, sp: sp, mode: mode);

    final pres = bundle.curPressure;
    final pDelta = prev == null ? 0.0 : pres - prev.pressure;
    final wind = bundle.curWindSpeed;

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
              Icon(Wmo.icon(bundle.curCode),
                  size: 38, color: Wmo.color(bundle.curCode)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(bundle.curTemp.toStringAsFixed(1),
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
                  Text('当前 · ${Wmo.text(bundle.curCode)}',
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
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(
                label: '气压 (hPa)',
                value: pres.toStringAsFixed(0),
                extra: _trendText(pDelta, fontSize: 9),
              ),
              _Stat(
                label: '风',
                value: '${windDirText(bundle.curWindDir)} ${_beaufort(wind)}级',
              ),
              _Stat(label: '水温', value: '${w.temp.toStringAsFixed(1)}℃'),
              _Stat(label: '溶氧', value: w.oxygen.toStringAsFixed(2)),
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
                        colors: [Color(0xFF3B4A67), Color(0xFF26324C)],
                      )
                    : null,
                color: sel ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? const Color(0xFF9FB0CB) : _Pal.line,
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
                        color: sel ? Colors.white : const Color(0xFFB9C7DA),
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
                      color: i == selected ? _Pal.gold : _Pal.muted,
                      fontSize: i == selected ? 16 : 14,
                      fontWeight:
                          i == selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: i == selected ? 18 : 0,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: _Pal.gold,
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
                color: sel ? _Pal.gold.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? _Pal.gold : _Pal.line,
                  width: sel ? 1.1 : 1,
                ),
              ),
              child: Text(
                species[i].name,
                style: TextStyle(
                  color: sel ? _Pal.gold : const Color(0xFFB9C7DA),
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
                      Color(0xFFE5484D),
                      Color(0xFFF2C24B),
                      Color(0xFF7CE58C)
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
  const _HourTable({required this.rows, this.nowHour});

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
            child: const Row(
              children: [
                _Th('时间', _fTime),
                _Th('天气', _fWx),
                _Th2('气温', '°C', _fTemp),
                _Th2('气压', 'hPa', _fPres),
                _Th2('风', 'km/h', _fWind),
                _Th2('水温', '°C', _fWater),
                _Th2('水氧', 'mg/L', _fO2),
                _Th2('指数', '鱼情', _fScore),
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
    final isDay = h.time.hour >= 6 && h.time.hour < 18;
    final isNow = nowHour != null && h.time.hour == nowHour;

    // 气温冷热标签
    Widget? tempTag;
    if (h.temp < 15) {
      tempTag = _miniTag('冷', const Color(0xFFFF8A7A));
    } else if (h.temp > 28) {
      tempTag = _miniTag('热', _Pal.amber);
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

    // 溶氧升降
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
        color: isNow
            ? const Color(0xFF17324A)
            : (i.isEven ? Colors.transparent : const Color(0x08FFFFFF)),
        border: const Border(
          bottom: BorderSide(color: _Pal.line, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          _Td(
            flex: _fTime,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tl.$1,
                    maxLines: 1,
                    style: const TextStyle(
                        color: _Pal.muted, fontSize: 8.5, height: 1.1)),
                const SizedBox(height: 1),
                Text(tl.$2,
                    maxLines: 1,
                    style: const TextStyle(
                        color: _Pal.txt,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.1)),
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
            child: Column(
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
          style: const TextStyle(color: Color(0xFFCBDAEA), fontSize: 10)),
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
              style: const TextStyle(color: Color(0xFFCBDAEA), fontSize: 10)),
          Text(sub,
              style: const TextStyle(color: Color(0xFF7F93AE), fontSize: 7.5)),
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
  if (s >= 78) return _Pal.green;
  if (s >= 60) return _Pal.lime;
  if (s >= 45) return _Pal.amber;
  return _Pal.muted;
}

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
