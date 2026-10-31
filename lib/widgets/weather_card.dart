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

  /// 分数 → 颜色：**直接复用天气页那一档**（[AppTheme.biteScore]）。
  ///
  /// v2.1.62：这里原来是另一套（≥80 近黑 / ≥60 暖金 / ≥40 橙 / 其余红），
  /// 且把颜色当作**填充色**、分数写白字；天气页则是同色系的**文字色**。
  /// 同一个 85 分 → 首页黑胶囊白字、天气页黄绿数字，用户反馈「两边颜色
  /// 不一致」。现在判档与色值都只有一个来源，改一处分处同步。
  static Color scoreColor(int s) => AppTheme.biteScore(s);

  @override
  Widget build(BuildContext context) {
    final score = weather.score;
    return Card(
      // v2.1.62：左右 12 → pagePad（和宫格/钓点/瀑布流同一条边线），
      // 上下 8 → 4（上面紧接分区标题，标题自己还带 4pt 下边距）
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.pagePad, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // ★ v2.1.62：左组整体进 Expanded，去掉原来的 Spacer。
                //   320dp 窄屏 + 长地名（「黔东南苗族侗族自治州」）时，
                //   图标 + 标题 + 地名 + 时段 + 指数胶囊加起来会超过一行，
                //   RenderFlex 直接溢 60pt。左组进 Expanded 后，地名自己
                //   省略号截断，右侧的指数胶囊永远钉在卡片右缘。
                //   （旧写法用 ConstrainedBox 定宽 84，只能是「够用就够用」，
                //    窄屏必炸；这里的地名改用 Flexible，有多宽用多宽。）
                Expanded(
                  child: Row(
                    children: [
                      // 图标与颜色都跟着当前天气走：晴=金黄太阳，阴=灰蓝云，雨=蓝雨点
                      Icon(
                        Wmo.icon(weather.weatherCode),
                        size: 22,
                        color: Wmo.color(weather.weatherCode),
                      ),
                      const SizedBox(width: 6),
                      Text('钓鱼天气',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      if (placeLabel != null && placeLabel!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('· $placeLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textSecondary)),
                        ),
                      ],
                    ],
                  ),
                ),
                // 时段标签：明确这是哪一小时的数据，和天气页对得上
                if (weather.atLabel.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(weather.atLabel,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(width: 5),
                ],
                // 垂钓指数：直接显示分数，贴右侧显示
                //
                // v2.1.62：改成和天气页一样的「浅色底 + 同色数字」——
                // 数字用 AppTheme.biteScore(score)，和天气页顶部「指数 85」
                // 一字不差地同色；底只垫 12% 的同色，白卡上不抢眼。
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.biteScoreSoft(score),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('垂钓指数',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5,
                              height: 1.1)),
                      const SizedBox(width: 4),
                      Text('$score',
                          style: TextStyle(
                              color: scoreColor(score),
                              fontSize: 13.5,
                              height: 1.1,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
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
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
      ],
    );
  }
}
