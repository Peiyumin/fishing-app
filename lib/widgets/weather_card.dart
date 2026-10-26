import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/weather_forecast.dart';
import '../services/weather_service.dart';

/// 首页「钓鱼天气」卡片
/// 显示气温、湿度、风力（几级什么风）、气压 + 垂钓适宜指数与建议
///
/// ★ 时段口径（v2.1.19）：温度 / 湿度 / 风 / 气压 / 天气现象 / 垂钓指数
///   全部来自同一个整点（[FishingWeather.atLabel] 就是那个小时），
///   与天气页顶部卡、逐时表「现在」那一行完全一致。
///   之前首页自己用 FishingAdvisor 另算一套分数，天气页用 Bite 引擎，
///   同一时刻能差 5~8 分，用户会以为数据错了。
class WeatherCard extends StatelessWidget {
  final FishingWeather weather;

  /// 定位地名（如「禹州」），有值时显示在标题旁，让用户知道看的是哪里的天气
  final String? placeLabel;
  const WeatherCard({super.key, required this.weather, this.placeLabel});

  /// 分数 → 颜色：四档语义分级（≥80 爆护 / ≥60 有口 / ≥40 一般 / 其余口差）
  ///
  /// 一律走 [AppTheme] 的语义色，别在页面里自己调一版绿金橙红 ——
  /// 之前首页卡和天气页各有一套，同一个 72 分在两边是两个不同的橙色。
  /// 深底页面要用亮一阶（见 weather_screen 的 _Pal），那是有意的：深底上
  /// 这四色直接铺会发闷，但**色相和档位保持一致**。
  static Color scoreColor(int s) {
    if (s >= 80) return AppTheme.primary;
    if (s >= 60) return AppTheme.star;
    if (s >= 40) return AppTheme.warning;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    final score = weather.score;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 图标与颜色都跟着当前天气走：晴=金黄太阳，阴=灰蓝云，雨=蓝雨点
                Icon(
                  Wmo.icon(weather.weatherCode),
                  size: 22,
                  color: Wmo.color(weather.weatherCode),
                ),
                const SizedBox(width: 6),
                Text('钓鱼天气',
                    style:
                        const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (placeLabel != null && placeLabel!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  // 注意：这里不能用 Flexible —— Flexible 会和下面的 Spacer
                  // 平分剩余空间，把「垂钓指数」顶到中间去。用定宽盒子后，
                  // 剩余空间全归 Spacer，指数胶囊才会紧贴卡片右侧。
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 84),
                    child: Text('· $placeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.textSecondary)),
                  ),
                ],
                const Spacer(),
                // 时段标签：明确这是哪一小时的数据，和天气页对得上
                if (weather.atLabel.isNotEmpty) ...[
                  Text(weather.atLabel,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(width: 6),
                ],
                // 垂钓指数：直接显示分数，贴右侧显示
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor(score),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('垂钓指数：$score',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 四项指标
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Metric('${weather.temperature.toStringAsFixed(0)}℃',
                    weather.description),
                _Metric('${weather.humidity}%', '湿度'),
                // ★ 风只报「几级 + 什么风」，不再写 km/h（v2.1.36 全站统一口径）
                _Metric(
                    '${beaufortLevel(weather.windSpeed)}级',
                    weather.windDir == null
                        ? '风力'
                        : '${windDirText(weather.windDir)}风'),
                _Metric(weather.pressure.toStringAsFixed(0), '气压hPa'),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 15, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('AI 建议：${weather.fishAdvice}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.primary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
