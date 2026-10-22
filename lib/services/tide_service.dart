import 'dart:math' as math;

/// 潮汐估算（半日潮近似模型）
///
/// 说明：真实潮汐依赖潮汐表 / 谐波常数（每个港口不同），离线 App 无法精确还原。
/// 这里用「半日潮 12.4206 小时周期 + 经度相位修正 + 朔望月大小潮调制」给出
/// 相对潮高与涨退趋势，足够钓鱼人判断当前是否在「起流 / 平潮」，并据此选钓时。
/// 结果标注为「估算」，不与专业潮汐表等值。
class TideService {
  /// 半日潮平均周期（小时）
  static const double _semidiurnal = 12.4206;

  /// 计算某时刻、某经纬度的潮汐状态（估算）。
  ///
  /// [lat]/[lng] 为定位坐标；[t] 为本地时间（用小时 + 经度的地方时差合成相位）。
  static TideInfo at(double lat, double lng, DateTime t) {
    final hours = t.hour + t.minute / 60 + t.second / 3600;
    // 经度相位：每 15° 经度 = 1 小时地方时差，叠加到潮时基准上。
    final phase = ((hours + lng / 15) / _semidiurnal) * 2 * math.pi;
    final cosP = math.cos(phase);
    final sinP = math.sin(phase);
    final rising = -sinP > 0; // cos 的导数 = -sin，>0 即涨潮
    final state = _state(cosP);
    // 振幅受朔望月大小潮调制（大潮振幅大、小潮振幅小），相对潮高以平均海面为 0。
    final amp = 1.6 * _springNeap(t);
    final heightM = cosP * amp;
    return TideInfo(
      heightM: heightM,
      state: state,
      rising: rising,
      amp: amp,
    );
  }

  /// 接近高/低潮极值时为「平潮（憩潮）」，其余按导数判断涨/退。
  static String _state(double cosP) {
    if (cosP.abs() > 0.9) return '平潮';
    return cosP > 0 ? '退潮' : '涨潮';
  }

  /// 大小潮调制系数：朔（新月）/ 望（满月）附近为大潮（→1.0），
  /// 上/下弦附近为小潮（→0.5）。
  static double _springNeap(DateTime t) {
    const synodic = 29.530588853;
    final base = DateTime.utc(2000, 1, 6, 18, 14); // 已知新月时刻
    final days = t.toUtc().difference(base).inMinutes / 1440.0;
    var phase = (days / synodic) % 1.0;
    if (phase < 0) phase += 1.0;
    final d = math.min(math.min(phase, 1 - phase), (phase - 0.5).abs());
    return (1.0 - d / 0.25 * 0.5).clamp(0.5, 1.0);
  }
}

/// 某一时刻、某一地点的潮汐估算结果
class TideInfo {
  /// 相对潮高（米），0 = 平均海面；正为高、负为低
  final double heightM;

  /// 潮态：涨潮 / 退潮 / 平潮
  final String state;

  /// 是否处于涨潮阶段
  final bool rising;

  /// 当前振幅（米），受大小潮调制
  final double amp;

  const TideInfo({
    required this.heightM,
    required this.state,
    required this.rising,
    required this.amp,
  });

  /// 显示用：如「+1.2m 涨潮」「-0.8m 退潮」
  String get display =>
      '${heightM >= 0 ? '+' : ''}${heightM.toStringAsFixed(1)}m $state';
}
