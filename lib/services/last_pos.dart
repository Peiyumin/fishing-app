import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上次成功定位到的坐标（WGS-84）
///
/// 为什么要有这个：钓点页的排序与距离文案全靠当前坐标。但 GPS 冷启动要
/// 几百毫秒到几秒，权限框还可能被用户拒掉 —— 那段时间里列表只能按后端
/// `ORDER BY created_at DESC` 的顺序铺，距离也不显示，看起来就是「没按
/// 远近排」。用户的原话是「要以当前定位显示，以定位点显示距离由近到远」。
///
/// 解决办法：把**上一次**的坐标存下来，下次进页面先按它排一遍（首屏就是
/// 近的在上），实时定位回来再重排一次。位置通常不会在一两天内跨越城市，
/// 这个过渡值足够准。
///
/// ★ key 与首页 `home_screen.dart` 的 `_posKey` **必须一致**：两边谁先定位
///   成功谁写，另一个下次打开就能直接读到。改 key 等于让这份缓存作废。
class LastPos {
  /// 与首页共用（首页 `_posKey` 同值）
  static const String key = 'home_last_pos';

  static double? _lat;
  static double? _lng;

  /// 内存里的值（[load] 之后可直接同步读，首帧就能用来排序）
  static double? get lat => _lat;
  static double? get lng => _lng;
  static bool get hasValue => _lat != null && _lng != null;

  /// 从磁盘读一次。已经有值就不再读（同一进程内位置变化由 [save] 覆盖）。
  ///
  /// 返回是否拿到了可用坐标。
  static Future<bool> load() async {
    if (hasValue) return true;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) return false;
      final p = raw.split(',');
      if (p.length != 2) return false;
      final la = double.tryParse(p[0]);
      final ln = double.tryParse(p[1]);
      // 0,0 是「没定位」的常见脏值，不能拿来算距离
      if (la == null || ln == null) return false;
      if (la == 0 && ln == 0) return false;
      if (la.abs() > 90 || ln.abs() > 180) return false;
      _lat = la;
      _lng = ln;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 定位成功后写入（内存 + 磁盘）
  static Future<void> save(double lat, double lng) async {
    if (lat == 0 && lng == 0) return;
    if (lat.abs() > 90 || lng.abs() > 180) return;
    _lat = lat;
    _lng = lng;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, '$lat,$lng');
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _lat = null;
    _lng = null;
  }
}
