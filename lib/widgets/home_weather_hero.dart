import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/home_mode.dart';
import '../services/tide_service.dart';
import '../services/weather_service.dart';
import 'weather_icon.dart';

/// 首页顶部的「钓鱼天气」大区（v46，v2.1.86 按钓法分叉）
///
/// 版式参考用户在需求里给的那张图：整块深色通栏画面，
/// 大号钓鱼指数 + 等级 + 一句建议，底部四格指标。
///
/// ★ 四格里的**第三格按钓法变**（v2.1.86 用户要求）：
///     海钓          → 潮汐（+1.2m / 涨潮）
///     台钓·路亚·钓场 → 水氧（7.4 mg/L）
///   气压那格让位给第三格 —— 气压并没有丢，上面那句建议里本来就带着
///   「气压 1015hPa 缓慢回升…」，再占一格是重复。
///   四格仍然是四格：五格在 390dp 上单格只剩 68dp，「水氧 mg/L」这种
///   标签会挤成竖排，320dp 的小屏直接溢出。
///
/// 为什么不直接用老的 [WeatherCard]：
///   老卡是白底小卡片，标题「实时天气」和「7天预报」都在卡片外面，
///   天气一挪到顶部就会和 AppBar 的深色渐变打起来（白卡浮在深色上、中间
///   还夹一条分区标题，显得很碎）。这里做成和 AppBar **同一条渐变**的
///   通栏，视觉上是一个整体。
///
/// ★ 没有数据时（[weather] 为 null）不画转圈，而是用同样的结构填「--」：
///   高度一模一样，数据回来原地替换，页面不会跳一下。
class HomeWeatherHero extends StatelessWidget {
  final FishingWeather? weather;
  final String? placeLabel;

  /// 水温（℃）：由 [WeatherService.memoryWaterTemp] 给，没有就显示湿度
  final double? waterTemp;
  final VoidCallback onTap;

  /// 当前选中的钓法：决定第三格显示潮汐还是水氧
  final HomeMode mode;

  /// 潮汐估算（仅海钓用；没拿到坐标时为 null → 第三格显示「--」）
  final TideInfo? tide;

  const HomeWeatherHero({
    super.key,
    required this.weather,
    required this.onTap,
    this.placeLabel,
    this.waterTemp,
    this.mode = HomeMode.taiDiao,
    this.tide,
  });

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final has = w != null;
    final score = has ? w.score : 0;
    final scoreColor =
        has ? AppTheme.biteScoreOnDark(score) : Colors.white.withOpacity(0.35);

    final place = (placeLabel ?? '').trim();
    final atLabel = has ? w.atLabel : '';

    // 四个指标：气温 / 水温（没有就退成湿度）/ 第三格（潮汐或水氧）/ 风力
    final third = homeThirdMetric(mode: mode, weather: weather, tide: tide);
    final metrics = <_Metric>[
      _Metric(
        has ? '${w.temperature.round()}°' : '--',
        has ? w.description : '气温',
      ),
      if (waterTemp != null && waterTemp! > 0)
        _Metric('${waterTemp!.round()}°', '水温')
      else
        _Metric(has ? '${w.humidity}%' : '--', '湿度'),
      _Metric(
        third.value,
        third.label,
        hint: mode.wantsTide ? null : oxygenFeel(w?.oxygen),
      ),
      _Metric(
          has
              ? '${_windLevel(w.windSpeed)}级${w.windDir == null ? '' : _windDir(w.windDir!)}'
              : '--',
          '风力'),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      // 直接用 AppBar 那条品牌渐变：天气区和顶栏连成一块，
      // 不在色板外另造一个近黑色（主题色板测试也会拦）
      decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 第一行：地名 + 更新时间 + 7 天预报 ——
              Row(
                children: [
                  const Icon(Icons.place, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      // 顶部定位胶囊去掉后，地名只在这里出现一次：
                      // 能取到就写地名，取不到写「当前位置」。
                      // 不再缀「· 实时天气」—— 右边就是更新时间，整块本来就是实时天气，
                      // 缀上去反而把地名挤成「当前位置 · 实时⋯」
                      place.isEmpty ? '当前位置' : place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70),
                    ),
                  ),
                  if (atLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(atLabel,
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white38)),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Text('7 天预报',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.75))),
                      const Icon(Icons.chevron_right,
                          size: 15, color: Colors.white54),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // —— 指数 + 等级 + 建议 ——
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: WeatherGlyph(
                      code: has ? w.weatherCode : 0,
                      day: has ? !w.isNightAt : true,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    has ? '$score' : '--',
                    style: TextStyle(
                      fontSize: 46,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      color: scoreColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          has ? w.fishIndex : '获取中',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: scoreColor),
                        ),
                        const Text('钓鱼指数 / 100',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white38)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                has ? w.fishAdvice : '正在获取当前位置的天气…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.white.withOpacity(0.10)),
              const SizedBox(height: 10),

              // —— 底部四格指标 ——
              Row(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0)
                      Container(
                          width: 1,
                          height: 26,
                          color: Colors.white.withOpacity(0.10)),
                    Expanded(child: _metricCell(metrics[i])),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCell(_Metric m) {
    final cell = Column(
      children: [
        Text(
          m.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          m.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, color: Colors.white38),
        ),
      ],
    );
    // 只有第三格带 hint（水氧/潮汐的一句话解读）：读屏用户听到的是
    // 「水氧 7.4 溶氧充足，鱼口活跃」，不是一个光秃秃的数字
    if (m.hint == null) return cell;
    return Semantics(label: '${m.label} ${m.value} ${m.hint}', child: cell);
  }

  /// 风速 km/h → 蒲福风级（和天气卡同一口径）
  static int _windLevel(double kmh) {
    final v = kmh;
    if (v < 1) return 0;
    if (v < 6) return 1;
    if (v < 12) return 2;
    if (v < 20) return 3;
    if (v < 29) return 4;
    if (v < 39) return 5;
    if (v < 50) return 6;
    if (v < 62) return 7;
    return 8;
  }

  /// 风向度数 → 八方位中文
  static String _windDir(int deg) {
    final d = deg.toDouble();
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final idx = ((((d % 360) + 360) % 360 + 22.5) ~/ 45) % 8;
    return names[idx];
  }
}

class _Metric {
  final String value;
  final String label;

  /// 读屏用的一句话解读（只有水氧/潮汐那格有）
  final String? hint;
  const _Metric(this.value, this.label, {this.hint});
}
