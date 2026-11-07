import '../services/tide_service.dart';
import '../services/weather_service.dart';
import 'fishing_species.dart';

/// 首页顶部的钓法分类（v2.1.86）
///
/// 用户需求：标题下面加「台钓 / 路亚 / 钓场 / 海钓」四个分类，
/// 点了以后**下面的天气要跟着变** —— 海钓看潮汐，其余三种看水氧。
///
/// 为什么单独立一个枚举、而不是直接复用 [FishingMode]：
///   ① `FishingMode` 只有三种（台钓/路亚/海钓），用户要的「钓场」不在里面；
///      钓场（收费塘）在打分上和台钓是同一套权重，但**标签必须分开显示**，
///      否则用户点了「钓场」看到的是「台钓」，会以为没生效。
///   ② 首页要的不只是「钓法名」，还有「第三格该显示潮汐还是水氧」这条 UI 规则，
///      这条规则不该塞进打分模型里。
enum HomeMode {
  taiDiao('台钓', '台钓', wantsTide: false),
  luYa('路亚', '路亚', wantsTide: false),
  chang('钓场', '台钓', wantsTide: false),
  haiDiao('海钓', '海钓', wantsTide: true);

  const HomeMode(this.label, this.scoreMode, {required this.wantsTide});

  /// tab 上显示的字
  final String label;

  /// 传给 `Bite` / `FishScore` 的钓法名（钓场 = 台钓那套权重）
  final String scoreMode;

  /// true → 天气第三格显示**潮汐**；false → 显示**水氧**
  final bool wantsTide;

  /// 打分用的钓法对象
  FishingMode get fishingMode => FishingMode(scoreMode);

  /// 存本地用的键（标签中文字符串就行，改文案会丢一次偏好，可接受）
  String get key => label;

  /// 从本地存的值还原；认不出来就回台钓（别因为一条脏数据把首页卡住）
  static HomeMode fromKey(String? k) {
    for (final m in values) {
      if (m.label == k) return m;
    }
    return taiDiao;
  }
}

/// 天气通栏「第三格」的内容：海钓=潮汐，台钓/路亚/钓场=水氧
///
/// 单独抽成纯函数是为了能直接单测（不用渲染整个首页）：
///   · 海钓且没拿到坐标/潮汐 → 「--」
///   · 水氧是 null（老缓存没这个键）→ 「--」，**绝不写成 0**
class HomeHeroMetric {
  final String value;
  final String label;
  const HomeHeroMetric(this.value, this.label);
}

HomeHeroMetric homeThirdMetric({
  required HomeMode mode,
  required FishingWeather? weather,
  TideInfo? tide,
}) {
  if (mode.wantsTide) {
    if (tide == null) return const HomeHeroMetric('--', '潮汐');
    // "+1.2m 涨潮" → 数值与潮态分开摆：上面大字是潮高，下面小字是潮态
    final parts = tide.display.split(' ');
    final h = parts.isNotEmpty ? parts.first : tide.display;
    final state = parts.length > 1 ? parts.sublist(1).join(' ') : tide.state;
    return HomeHeroMetric(h, '潮汐 $state');
  }
  final ox = weather?.oxygen;
  if (ox == null) return const HomeHeroMetric('--', '水氧 mg/L');
  return HomeHeroMetric(ox.toStringAsFixed(1), '水氧 mg/L');
}

/// 水氧的一句话人话解读（挂在格子上方/无障碍标签用）
String oxygenFeel(double? ox) {
  if (ox == null) return '暂无水氧数据';
  if (ox >= 7.5) return '溶氧充足，鱼口活跃';
  if (ox >= 5.5) return '溶氧正常，正常作钓';
  if (ox >= 4.0) return '溶氧偏低，主攻浅水草边';
  return '溶氧不足，鱼容易离底上浮';
}
