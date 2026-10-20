import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/weather_forecast.dart';
import '../services/fishing_advisor.dart';
import '../services/weather_service.dart';

/// 首页「钓鱼天气」卡片
/// 显示气温、湿度、风速、气压 + 垂钓适宜指数与建议
class WeatherCard extends StatelessWidget {
  final FishingWeather weather;

  /// 定位地名（如「禹州」），有值时显示在标题旁，让用户知道看的是哪里的天气
  final String? placeLabel;
  const WeatherCard({super.key, required this.weather, this.placeLabel});

  // 适宜指数 → 颜色
  Color _indexColor() {
    switch (weather.fishIndex) {
      case '极佳':
        return AppTheme.primary;
      case '良好':
        return AppTheme.accent;
      case '一般':
        return AppTheme.warning;
      default:
        return AppTheme.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final advice = FishingAdvisor.build(
      temp: weather.temperature,
      pressure: weather.pressure,
      windKmh: weather.windSpeed,
      weatherCode: weather.weatherCode,
      hour: DateTime.now().hour,
    );
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
                  Flexible(
                    child: Text('· $placeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.textSecondary)),
                  ),
                ],
                const Spacer(),
                // 适宜指数徽标
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _indexColor(),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('适宜：${weather.fishIndex}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
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
                _Metric('${weather.windSpeed.toStringAsFixed(0)}km/h', '风速'),
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
                    child: Text('AI 建议：${advice.headline}',
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
