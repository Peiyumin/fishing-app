import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_layout.dart';
import '../utils/json_num.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 首页装修（分类导航 + 广告位 + 宫格列数）
///
/// 策略：**先用缓存、再刷新**
///   1. 启动时同步读 [memory]（上一次解析好的），首页第一帧就能画出真实宫格，
///      不会先闪一下默认的 10 个图标再跳成后台配的；
///   2. 后台拉 `/home/layout` 成功后覆盖内存 + 写 SharedPreferences；
///   3. 接口失败（没网 / 后端还没升级）就用缓存，连缓存都没有就用
///      [HomeLayout.fallback]，所以首页**永远有东西可点**。
class HomeService {
  static const _cacheKey = 'home_layout_v1';

  static HomeLayout? _memory;

  /// 同步可读的当前布局（首页 initState 直接取，避免首帧空白）
  static HomeLayout? get memory => _memory;

  /// 上次拉取是否失败（调试/测试用）
  static bool lastFailed = false;

  /// 读本地缓存（启动时先调这个，再调 [refresh]）
  static Future<HomeLayout?> loadCache() async {
    if (_memory != null) return _memory;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      _memory = HomeLayout.fromJson(Map<String, dynamic>.from(map));
      return _memory;
    } catch (_) {
      return null;
    }
  }

  /// 拉后台配置；失败时保持现有布局不变
  static Future<HomeLayout> refresh() async {
    if (!ApiConfig.enabled) return _memory ?? HomeLayout.fallback;
    try {
      final data = jsonMap(await ApiClient.get('/home/layout'));
      final layout = HomeLayout.fromJson(Map<String, dynamic>.from(data));
      _memory = layout;
      lastFailed = false;
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_cacheKey, jsonEncode(layout.toJson()));
      } catch (_) {
        // 存缓存失败不影响本次展示
      }
      return layout;
    } catch (_) {
      lastFailed = true;
      return _memory ?? HomeLayout.fallback;
    }
  }

  /// 当前布局（缓存 → 兜底），不发请求
  static HomeLayout get current => _memory ?? HomeLayout.fallback;

  /// 仅测试用：重置内存态
  static void resetForTest() {
    _memory = null;
    lastFailed = false;
  }
}
