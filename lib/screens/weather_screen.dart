import 'package:flutter/material.dart';

import '../app_theme.dart';

import '../models/weather_forecast.dart';
import '../services/fishing_advisor.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../widgets/location_prompt.dart';

/// 天气预报独立页：7 天 + 逐小时（气压/温差/降雨概率/风向风速/紫外线/垂钓指数）
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  WeatherBundle? _bundle;
  bool _loading = true;
  String? _error;
  int _selected = 0; // 选中的日期索引（0=今天）
  int _metricTab = 0; // 0天气 1风 2大气压 3垂钓指数
  static const _metricNames = ['天气', '风', '大气压', '垂钓指数'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // ① 先读缓存秒显（断网/弱网也能看上次预报）
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
        _loading = _bundle == null; // 已有缓存时不再转圈
        _error = null;
      });
    }

    double lat = 30.2741, lng = 120.1551; // 默认：杭州
    try {
      final pos = await LocationService.determinePosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } on LocationException catch (e) {
      // 权限被拒时引导授权；GPS 未开/超时等用默认坐标
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
      // 有缓存时保留缓存，不把整页变成错误页
      if (mounted && _bundle == null) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('天气预报'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _bundle == null || _bundle!.days.isEmpty
                  ? const Center(child: Text('暂无天气数据'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _buildBody(_bundle!),
                    ),
    );
  }

  Widget _buildBody(WeatherBundle b) {
    final day = b.days[_selected];
    final dayHours = b.hoursOf(day.date);
    final s = _DayStats.compute(b, _selected);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _DateTabs(
          days: b.days,
          selected: _selected,
          onSelect: (i) => setState(() => _selected = i),
        ),
        _SummaryCard(day: day, stats: s, isToday: _selected == 0, bundle: b),
        const SizedBox(height: 10),
        _MetricTabs(
          names: _metricNames,
          selected: _metricTab,
          onSelect: (i) => setState(() => _metricTab = i),
        ),
        _SparklineCard(
          hours: dayHours,
          metric: _metricTab,
          day: day,
        ),
        _HourTable(hours: dayHours),
      ],
    );
  }
}

// ============================================================
// 日期选项卡（今天/明天/周X + MM-DD）
// ============================================================
class _DateTabs extends StatelessWidget {
  final List<DaySummary> days;
  final int selected;
  final ValueChanged<int> onSelect;
  const _DateTabs(
      {required this.days, required this.selected, required this.onSelect});

  static const _weekday = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String _label(int i, DateTime d) {
    if (i == 0) return '今天';
    if (i == 1) return '明天';
    if (i == 2) return '后天';
    return _weekday[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d = days[i].date;
          final sel = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? AppTheme.accent : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? AppTheme.accent : Colors.grey.shade300,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_label(i, d),
                      style: TextStyle(
                          color: sel ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: sel ? Colors.white70 : Colors.grey,
                        fontSize: 11),
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
// 某日聚合统计（从逐小时推导，7 天通用）
// ============================================================
class _DayStats {
  final double avgHumidity;
  final double avgPressure;
  final double avgWind; // km/h
  final int domWindDir;
  final double avgUv;
  final double tempRange;
  final double rangeVsYesterday;

  _DayStats({
    required this.avgHumidity,
    required this.avgPressure,
    required this.avgWind,
    required this.domWindDir,
    required this.avgUv,
    required this.tempRange,
    required this.rangeVsYesterday,
  });

  static _DayStats compute(WeatherBundle b, int index) {
    final day = b.days[index];
    final hs = b.hoursOf(day.date);
    double avg(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, c) => a + c) / xs.length;
    final hum = avg(hs.map((h) => h.humidity.toDouble()).toList());
    final pres = avg(hs.map((h) => h.pressure).toList());
    final wind = avg(hs.map((h) => h.windSpeed).toList());
    final uvs = hs.where((h) => h.uv != null).map((h) => h.uv!).toList();
    final uv = avg(uvs);
    // 主导风向：出现最多的方位（简化为平均）
    final domDir = hs.isEmpty
        ? day.windDirDom
        : avg(hs.map((h) => h.windDir.toDouble()).toList()).round();
    final range = day.tempMax - day.tempMin;
    final prevRange = index > 0 ? b.days[index - 1].tempRange : range;
    return _DayStats(
      avgHumidity: hum,
      avgPressure: pres,
      avgWind: wind,
      domWindDir: domDir,
      avgUv: uv,
      tempRange: range,
      rangeVsYesterday: range - prevRange,
    );
  }
}

// ============================================================
// 当日概览卡片：温度区间 + 垂钓指数环 + 指标网格
// ============================================================
class _SummaryCard extends StatelessWidget {
  final DaySummary day;
  final _DayStats stats;
  final bool isToday;
  final WeatherBundle bundle;
  const _SummaryCard({
    required this.day,
    required this.stats,
    required this.isToday,
    required this.bundle,
  });

  @override
  Widget build(BuildContext context) {
    final score = isToday ? bundle.currentFishIndex : day.fishIndex;
    final hum = isToday ? bundle.curHumidity.toDouble() : stats.avgHumidity;
    final pres = isToday ? bundle.curPressure : stats.avgPressure;
    final wind = isToday ? bundle.curWindSpeed : stats.avgWind;
    final wdir = isToday ? bundle.curWindDir : stats.domWindDir;
    final uv = day.uvMax ?? stats.avgUv;
    final rainProb = day.precipProbMax;
    final rainMm = isToday ? bundle.curPrecip : day.precipSum;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // 顶部：天气图标 + 温度区间 + 垂钓指数环
            Row(
              children: [
                Icon(Wmo.icon(day.weatherCode),
                    size: 40, color: Wmo.color(day.weatherCode)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${day.tempMin.toStringAsFixed(1)}°C ~ ${day.tempMax.toStringAsFixed(1)}°C',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(Wmo.text(day.weatherCode),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                _FishRing(score: score),
              ],
            ),
            const Divider(height: 14),
            // 指标网格（3 列，紧密排布，避免大片空白）
            _MetricRow(cells: [
              _Cell('湿度', '${hum.round()}%'),
              _Cell('大气压(海平面)', '${pres.toStringAsFixed(1)} hpa'),
              _Cell('紫外线指数', uv.toStringAsFixed(1)),
            ]),
            const Divider(height: 14),
            _MetricRow(cells: [
              _Cell('风',
                  '${windDirText(wdir)} ${(wind / 3.6).toStringAsFixed(1)} m/s'),
              _Cell('温差', '${stats.tempRange.toStringAsFixed(1)}°C'),
              _Cell('温差(与昨日)',
                  '${stats.rangeVsYesterday >= 0 ? '+' : ''}${stats.rangeVsYesterday.toStringAsFixed(1)}°C'),
            ]),
            const Divider(height: 14),
            _MetricRow(cells: [
              _Cell('降雨概率', '$rainProb%'),
              _Cell('降雨量', '${rainMm.toStringAsFixed(1)}mm'),
              const SizedBox.shrink(),
            ]),
            const SizedBox(height: 12),
            // AI 多因子垂钓建议
            _AiAdviceBlock(
              advice: FishingAdvisor.build(
                temp: isToday
                    ? bundle.curTemp
                    : (day.tempMax + day.tempMin) / 2,
                tempMin: day.tempMin,
                tempMax: day.tempMax,
                pressure: pres,
                windKmh: wind,
                windDirDeg: wdir,
                rainProb: rainProb,
                rainMm: rainMm,
                uv: uv,
                weatherCode: day.weatherCode,
                hour: isToday ? DateTime.now().hour : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一行 3 个指标，等宽紧凑排布
class _MetricRow extends StatelessWidget {
  final List<Widget> cells;
  const _MetricRow({required this.cells});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [for (final c in cells) Expanded(child: c)],
    );
  }
}

/// AI 垂钓建议卡片（头条 + 分条建议）
class _AiAdviceBlock extends StatelessWidget {
  final FishingAdvice advice;
  const _AiAdviceBlock({required this.advice});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: advice.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: advice.color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: advice.color),
              const SizedBox(width: 6),
              Text('AI 垂钓建议',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: advice.color)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: advice.color,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${advice.level} · ${advice.score}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(advice.headline,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 6),
          ...advice.tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: TextStyle(
                            color: advice.color, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Colors.black87)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  const _Cell(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 3),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 垂钓指数圆环
class _FishRing extends StatelessWidget {
  final int score;
  const _FishRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = FishIndex.color(score);
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 66,
            height: 66,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('垂钓指数',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
              Text('$score',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 指标切换（天气/风/大气压/垂钓指数）
// ============================================================
class _MetricTabs extends StatelessWidget {
  final List<String> names;
  final int selected;
  final ValueChanged<int> onSelect;
  const _MetricTabs(
      {required this.names, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: List.generate(names.length, (i) {
          final sel = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.accent : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: sel ? AppTheme.accent : Colors.grey.shade300),
                ),
                alignment: Alignment.center,
                child: Text(names[i],
                    style: TextStyle(
                        color: sel ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ============================================================
// 24 小时指标走势（折线）
// ============================================================
class _SparklineCard extends StatelessWidget {
  final List<HourPoint> hours;
  final int metric;
  final DaySummary day;
  const _SparklineCard(
      {required this.hours, required this.metric, required this.day});

  (String, Color) get _meta {
    switch (metric) {
      case 1:
        return ('风速 km/h', AppTheme.accent);
      case 2:
        return ('大气压 hPa', AppTheme.violet);
      case 3:
        return ('垂钓指数', AppTheme.primary);
      default:
        return ('温度 ℃', AppTheme.warning);
    }
  }

  List<double> _values() {
    switch (metric) {
      case 1:
        return hours.map((h) => h.windSpeed).toList();
      case 2:
        return hours.map((h) => h.pressure).toList();
      case 3:
        return hours.map((h) => h.fishIndex.toDouble()).toList();
      default:
        return hours.map((h) => h.temp).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, color) = _meta;
    final vals = _values();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 4,
                    height: 14,
                    color: color,
                    margin: const EdgeInsets.only(right: 6)),
                Text('24小时$title',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              width: double.infinity,
              child: vals.length < 2
                  ? const Center(child: Text('数据不足'))
                  : CustomPaint(painter: _LinePainter(vals, color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _LinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);

    final path = Path();
    final fill = Path()..moveTo(0, size.height);
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = size.height - ((values[i] - minV) / span) * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      fill.lineTo(x, y);
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.28), color.withOpacity(0.02)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.color != color;
}

// ============================================================
// 逐小时表格：时间 | 天气 | 温度 | 大气压 | 湿度 | 降雨概率
// ============================================================
class _HourTable extends StatelessWidget {
  final List<HourPoint> hours;
  const _HourTable({required this.hours});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                _H('时间', flex: 2),
                _H('天气', flex: 2),
                _H('温度', flex: 2),
                _H('大气压', flex: 2),
                _H('湿度', flex: 2),
                _H('降雨概率', flex: 2),
              ],
            ),
          ),
          if (hours.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无逐小时数据'),
            ),
          ...hours.map((h) {
            final day = h.time.hour >= 6 && h.time.hour < 18;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  _C(h.hhmm, flex: 2, bold: true),
                  Expanded(
                    flex: 2,
                    child: Icon(Wmo.icon(h.weatherCode, day: day),
                        size: 18,
                        color: Wmo.color(h.weatherCode, day: day)),
                  ),
                  _C('${h.temp.toStringAsFixed(0)}°C', flex: 2),
                  _C('${h.pressure.toStringAsFixed(0)}', flex: 2),
                  _C('${h.humidity}%', flex: 2),
                  _C('${h.precipProb}%', flex: 2),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String text;
  final int flex;
  const _H(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _C extends StatelessWidget {
  final String text;
  final int flex;
  final bool bold;
  const _C(this.text, {this.flex = 1, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text('天气加载失败\n$message', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
