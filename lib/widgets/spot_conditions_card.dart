import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/weather_forecast.dart';
import '../services/spot_conditions.dart';
import '../services/weather_service.dart';

/// 钓点详情页的「AI 分析」黑卡（v2.1.83）
///
/// 版式照用户给的参考图：近黑卡片 + 荧光绿 ✦ 标题 + 一段真数据拼出来的分析，
/// 底部一行「推荐指数 72 ＝ 天气 66 ＋ 水域 3 ＋ 风岸 2 ＋ 距离 1」。
///
/// 为什么分数要拆开写：
///   只给一个 72，用户没法判断该不该信。把四项摊开，「天气一般但水域加分」
///   和「天气好但太远扣分」是两种完全不同的情况，用户自己就能决定去不去。
class SpotAiCard extends StatelessWidget {
  final SpotConditions? data;

  /// 天气还没回来时显示骨架文字（高度差得不多，数据回来不会跳）
  final bool loading;

  const SpotAiCard({super.key, required this.data, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.inkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: AppTheme.accent),
              const SizedBox(width: 6),
              const Text(
                'AI 分析',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (d != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Text(
                    d.grade,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            d?.aiText ??
                (loading
                    ? '正在按这个点的天气算今天的鱼口…'
                    : '暂时拿不到这个点的逐时天气，指数只按水域类型和距离给出，仅供参考。'),
            style: TextStyle(
              fontSize: 13,
              height: 1.72,
              color: Colors.white.withOpacity(d == null ? 0.55 : 0.86),
            ),
          ),
          if (d != null) ...[
            const SizedBox(height: 12),
            _scoreLine(d),
          ],
        ],
      ),
    );
  }

  /// 「推荐指数 72 ＝ 天气 66 ＋ 水域 3 ＋ 风岸 2 ＋ 距离 1」
  Widget _scoreLine(SpotConditions d) {
    final parts = d.parts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      // 两行：一行「推荐指数 76」，一行四项构成。
      // 硬塞一行的话 30 来个字会在「距离 0」处折行，看起来像排版坏了。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: '推荐指数 ',
                  style: TextStyle(fontSize: 11.5, color: Colors.white60),
                ),
                TextSpan(
                  text: '${d.score}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                  ),
                ),
                TextSpan(
                  text: ' 分 · ${d.grade}',
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            parts.map((p) => '${p.label} ${p.value}').join(' ＋ '),
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

/// 钓点详情页的「现在去合不合适」白卡（v2.1.83）
///
/// 从上到下：档位 → 你所在位置的实时天气 → 温度/风力两格 → 今日建议 →
/// 最佳出钓时间（24 小时色条 + 那根红线就是现在）→ 最佳/次佳两张时段卡。
class SpotConditionsCard extends StatelessWidget {
  final SpotConditions? data;
  final bool loading;

  /// **当前定位**的实时天气（用户要求加的「实时天气」就是这个，不是钓点的）
  final FishingWeather? myWeather;

  /// 正在取当前位置 / 天气
  final bool myLocating;

  /// 点「更新」或「开启定位」
  final VoidCallback onRefreshMyWeather;

  const SpotConditionsCard({
    super.key,
    required this.data,
    required this.myWeather,
    required this.onRefreshMyWeather,
    this.loading = false,
    this.myLocating = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(d),
          const SizedBox(height: 12),
          _myWeatherRow(),
          const SizedBox(height: 12),
          if (d != null) ...[
            _tempWind(d),
            const SizedBox(height: 10),
            _adviceBar(d),
            const SizedBox(height: 16),
            const Text(
              '最佳出钓时间',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 9),
            _hourBar(d),
            const SizedBox(height: 12),
            _windows(d),
          ] else
            _placeholder(loading),
        ],
      ),
    );
  }

  Widget _header(SpotConditions? d) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          '现在去合不合适',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 6),
        const Padding(
          padding: EdgeInsets.only(bottom: 2),
          child: Text(
            'NOW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: AppTheme.textTertiary,
            ),
          ),
        ),
        const Spacer(),
        if (d != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.biteScoreSoft(d.score),
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Text(
              '${d.score} 分',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.biteScore(d.score),
              ),
            ),
          ),
      ],
    );
  }

  /// 当前定位的实时天气（没有定位就变成「点一下开启」）
  Widget _myWeatherRow() {
    final w = myWeather;
    final text = w == null
        ? (myLocating ? '正在获取你所在位置的天气…' : '未获取定位，点这里看你所在地的实时天气')
        : '你所在位置 ${w.temperature.toStringAsFixed(1)}℃ ${w.description}'
            '${w.windDir == null ? '' : ' · ${_windDir(w.windDir!)}'}'
            '${_level(w.windSpeed)}';
    return InkWell(
      onTap: myLocating ? null : onRefreshMyWeather,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Row(
          children: [
            if (myLocating)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            else
              const Icon(Icons.my_location,
                  size: 13, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            if (!myLocating)
              const Text(
                '更新',
                style: TextStyle(fontSize: 11.5, color: AppTheme.water),
              ),
          ],
        ),
      ),
    );
  }

  /// 温度 / 风力两格
  Widget _tempWind(SpotConditions d) {
    return Row(
      children: [
        Expanded(
          child: _metricBox(
            label: '温度',
            // 区间保留 1 位：8.6-17.7 比 9-18 更像实况
            value: '${d.tempMin.toStringAsFixed(1)}-'
                '${d.tempMax.toStringAsFixed(1)}',
            unit: '℃',
            note: SpotConditions.tempFeel(d.nowTemp),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricBox(
            label: '风力',
            value: d.windMin == d.windMax
                ? '${d.windMax}'
                : '${d.windMin}-${d.windMax}',
            unit: '级',
            note: SpotConditions.windFeel(d.nowWindLevel),
          ),
        ),
      ],
    );
  }

  Widget _metricBox({
    required String label,
    required String value,
    required String unit,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 今日建议
  Widget _adviceBar(SpotConditions d) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text(
              '今日建议',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              d.advice,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 24 小时色条 + 刻度 + 当前时间红线
  Widget _hourBar(SpotConditions d) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final unit = c.maxWidth / 24;
        return Column(
          children: [
            SizedBox(
              height: 26,
              child: Stack(
                children: [
                  Row(
                    children: List.generate(24, (h) {
                      final s = d.hourly[h];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Container(
                            decoration: BoxDecoration(
                              // ★ 不按「过去 / 未来」压暗：压暗之后早上的好时段
                            //   会淡成一片浅黄，24 个方块挤在一起根本看不出
                            //   哪几个小时能钓。「现在几点」由那根红线来说。
                            color: s < 0 ? AppTheme.divider : _blockColor(s),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  // 现在这一刻的红线
                  Positioned(
                    left: (unit * (d.nowHour + .5)).clamp(0, c.maxWidth - 2),
                    top: -4,
                    bottom: -4,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                for (final h in const [0, 6, 12, 18, 24])
                  Expanded(
                    child: Text(
                      h.toString().padLeft(2, '0'),
                      textAlign: h == 0
                          ? TextAlign.left
                          : (h == 24 ? TextAlign.right : TextAlign.center),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 24 小时色条的**填充色**（不是文字色）
  ///
  /// [AppTheme.biteScore] 是白底上的文字色，直接当块色用会淡成一片浅黄 ——
  /// 24 个小方块挤在一起时完全看不出「哪几个小时能钓」。
  /// 这里用同一套分档、但取深阶：高分近黑、次高橄榄绿、中分暖黄、低分浅灰。
  static Color _blockColor(int s) {
    if (s >= 85) return AppTheme.primary; // 爆护档：近黑
    if (s >= 70) return AppTheme.accentDark; // 有口档：橄榄绿
    if (s >= 55) return AppTheme.accentMid; // 一般偏上：浅橄榄
    if (s >= 40) return AppTheme.star; // 口弱档：暖黄
    return AppTheme.divider; // 其他：浅灰
  }

  /// 最佳 / 次佳时段两卡
  Widget _windows(SpotConditions d) {
    final b = d.best;
    if (b == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: const Text(
          '今天没有明显的高分时段，鱼口会比较散。',
          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
        ),
      );
    }
    final s = d.second;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _windowCard(b, primary: true)),
          if (s != null) ...[
            const SizedBox(width: 10),
            Expanded(child: _windowCard(s, primary: false)),
          ],
        ],
      ),
    );
  }

  Widget _windowCard(SpotTimeWindow w, {required bool primary}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: primary ? AppTheme.inkBg : AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary ? '最佳 · ${w.range}' : w.range,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: primary ? Colors.white70 : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${w.score}',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: primary
                      ? AppTheme.biteScoreOnDark(w.score)
                      : AppTheme.biteScore(w.score),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '分',
                style: TextStyle(
                  fontSize: 11.5,
                  color: primary ? Colors.white54 : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholder(bool loading) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          loading ? '正在读取这个点的天气…' : '这个点暂时没有天气数据',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  /// 风级只报等级、不报 km/h —— 和天气页「东南风 3级」同一口径
  static String _level(double kmh) => ' · ${beaufortLevel(kmh)} 级';

  static String _windDir(int deg) =>
      windDirText(deg) == '--' ? '' : '${windDirText(deg)}风';
}
