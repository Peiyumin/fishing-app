import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/weather_service.dart';

/// 首页「钓鱼天气」卡片
/// 显示气温、湿度、风速、气压 + 垂钓适宜指数与建议
class WeatherCard extends StatelessWidget {
  final FishingWeather weather;
  const WeatherCard({super.key, required this.weather});

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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny, color: AppTheme.accent),
                const SizedBox(width: 6),
                const Text('钓鱼天气',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
              child: Text('💡 ${weather.fishAdvice}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.primary)),
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
