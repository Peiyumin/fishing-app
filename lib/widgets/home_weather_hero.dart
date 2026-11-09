import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/home_mode.dart';
import '../services/tide_service.dart';
import '../services/weather_service.dart';
import 'weather_icon.dart';

/// 首页顶部的「钓鱼天气」大区（v46，v2.1.86 按钓法分叉，v2.1.87 重排首行）
///
/// 版式参考用户在需求里给的那张图：整块深色通栏画面，
/// 大号钓鱼指数 + 等级 + 一句建议，底部四格指标。
///
/// ★ v2.1.87 首行改版（用户要求）：
///     定位（放大到 21pt）在左、指数（58pt 斜体）在右，去掉「7 天预报 >」。
///     原来是「左上小字地名 + 中间 46pt 数字 + 右上 7 天预报」三处分散，
///     现在是「左边在哪、右边几分」两栏，视线一次落定。
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

  /// ★ v2.1.90：嵌在首页头部大块里用（首页改版，头部与卡片整体滚动）。
  ///
  /// 为 true 时**不画自己的 headerGradient、也不留底部 8px 外距**，
  /// 由外层 `HomeHeaderBlock` 画一次渐变把「标题 + 分类 + 天气」包成一整块。
  /// 理由同 `HomeTopBar.embedded`：对角渐变各画一次会在接缝处断层。
  final bool flat;

  const HomeWeatherHero({
    super.key,
    required this.weather,
    required this.onTap,
    this.placeLabel,
    this.waterTemp,
    this.mode = HomeMode.taiDiao,
    this.tide,
    this.flat = false,
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

    // ★ 窄屏（320dp 的 SE/小屏安卓）：首行「21pt 地名 + 58pt 斜体数字 + 等级列」
    //   在 320 上只剩 288 可用宽，用 58 会顶出去 4~9px。这里不是把布局改两套，
    //   只是把三个字号各降一档（58→52 / 15→14 / 11→10），结构、对齐完全不变。
    final narrow = MediaQuery.sizeOf(context).width < 340;
    final scoreSize = narrow ? 52.0 : 58.0;

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
      margin: flat ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      // 直接用 AppBar 那条品牌渐变：天气区和顶栏连成一块，
      // 不在色板外另造一个近黑色（主题色板测试也会拦）
      // flat 时交给外层 HomeHeaderBlock 画，避免对角渐变在两块里各起一次头
      decoration: flat
          ? null
          : const BoxDecoration(gradient: AppTheme.headerGradient),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 第一行：定位（放大）↔ 今日指数（靠右、斜体大号）——
              //
              // v2.1.87 按用户要求重排这一块：
              //   ① 地名从「左上角 13pt 小字」挪到指数左边，字号 13 → 21：
              //      「我在哪 + 这里几分」要一眼同时看到，不该一个在角上一个在中间；
              //   ② 「7 天预报 >」整条删掉 —— 点这块天气区本来就进天气页，
              //      那个箭头只是在右上角多开一个入口；
              //   ③ 指数整体靠右贴容器右缘，数字 46 → 58 且改**斜体**：
              //      斜体 + 极紧字距让三位数抱成一团，比同字号的正体更「跳」。
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左：定位 + 更新时间（Expanded 把右边的指数推到贴边）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ★ v2.1.88：地名前的定位小图标删掉，只留名字。
                        //   21pt 的字配上 16px 的图钉，图钉只占位不传递信息，
                        //   反倒把地名往右挤了 20px。地名本身就是「我在哪」。
                        Text(
                          // 能取到就写地名（县/区级），取不到写「当前位置」。
                          // 不缀「· 实时天气」：右边就是更新时间，整块本来就是实时天气。
                          place.isEmpty ? '当前位置' : place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            // ★ v2.1.91：21 → 17（用户要求「定位名字小一点」）。
                            //   顶栏「渔报」放大到 40 之后，地名再保持 21 会和
                            //   标题抢视觉重心；17 刚好是「次要信息」的量级，
                            //   也比右边的 58pt 指数低一整个层级，三个元素
                            //   的大小关系才立得住。
                            fontSize: narrow ? 15.5 : 17,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: Colors.white,
                          ),
                        ),
                        if (atLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text('更新 $atLabel',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.white38)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 右：天气图标 + 大号斜体指数 + 等级
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: WeatherGlyph(
                            code: has ? w.weatherCode : 0,
                            day: has ? !w.isNightAt : true,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          has ? '$score' : '--',
                          style: TextStyle(
                            fontSize: scoreSize,
                            height: 0.95,
                            fontWeight: FontWeight.w900,
                            // ★ 斜体：用户要求的「数字斜体、要突出」
                            fontStyle: FontStyle.italic,
                            // 斜体自带右倾，字距再紧 -2.5 才不会散成一排
                            letterSpacing: -2.5,
                            color: scoreColor,
                            // 深色底上给一层淡投影，把数字从渐变里「拔」出来
                            shadows: const [
                              Shadow(
                                  color: Color(0x59000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            // 整块贴右缘：等级和「钓鱼指数 / 100」都右对齐
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                has ? w.fishIndex : '获取中',
                                style: TextStyle(
                                    fontSize: narrow ? 14 : 15,
                                    fontWeight: FontWeight.w700,
                                    color: scoreColor),
                              ),
                              // 窄屏把「钓鱼指数」缩成「指数」：省的 2 个字正好
                              // 换回地名不被截断（320 上地名最长也就 6~8 字）
                              Text(narrow ? '指数 / 100' : '钓鱼指数 / 100',
                                  style: TextStyle(
                                      fontSize: narrow ? 10 : 11,
                                      color: Colors.white38)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
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
