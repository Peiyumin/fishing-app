import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_bootstrap.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// App 启动引导数据（预览页 + 广告）
/// 由管理后台「启动预览页 / 启动广告」页面控制，公开接口无需登录
class AppService {
  AppService._();

  /// 上次成功拉到 / 本机缓存里的启动配置（内存镜像）
  static AppBootstrap? _memo;

  /// 缓存是否新鲜（超过 [ttl] 就当作过期，宁可等一次接口也不要放隔夜广告）
  static DateTime? _cachedAt;
  static const Duration ttl = Duration(hours: 6);

  static const String _kCache = 'boot_cache_v1';
  static const String _kCacheAt = 'boot_cache_v1_at';

  /// 启动页阶段预热：只读本机缓存，**不联网**
  ///
  /// ★ v2.1.89：用户反馈「打开 App 会卡一会儿才进界面」。放行链路上唯一
  ///   依赖网络的就是这个启动配置接口（原来是 800ms 硬等）。启动广告 /
  ///   预览页本来就是「有就看、没有就直接进」的可选项，完全没必要为了
  ///   它把每次冷启动都拖住半个多秒 —— 现在先用上次的缓存放行，新数据
  ///   在后台拉，下次启动生效。
  static Future<void> warmUp() async {
    if (_memo != null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final at = sp.getInt(_kCacheAt) ?? 0;
      if (at == 0) return;
      final raw = sp.getString(_kCache);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      _memo = AppBootstrap.fromJson(Map<String, dynamic>.from(j));
      _cachedAt = DateTime.fromMillisecondsSinceEpoch(at);
    } catch (_) {
      // 缓存坏了当作没有，走一次网络
    }
  }

  /// 新鲜的内存缓存（启动放行直接用它，不再等接口）
  static AppBootstrap? get cached {
    final at = _cachedAt;
    if (_memo == null || at == null) return null;
    if (DateTime.now().difference(at) > ttl) return null;
    return _memo;
  }

  /// 拉取启动内容；后端不可用时返回空（App 直接进首页，不影响使用）
  static Future<AppBootstrap> bootstrap() async {
    if (!ApiConfig.enabled) return const AppBootstrap();
    try {
      final data = jsonMap(await ApiClient.get('/app/bootstrap'));
      final boot = AppBootstrap.fromJson(Map<String, dynamic>.from(data));
      _memo = boot;
      _cachedAt = DateTime.now();
      _saveCache(data);
      return boot;
    } catch (_) {
      return cached ?? const AppBootstrap();
    }
  }

  /// 测试用：把内存缓存清掉（静态状态会跨用例残留）
  @visibleForTesting
  static void resetForTest() {
    _memo = null;
    _cachedAt = null;
  }

  /// 存缓存（失败不影响启动：最多下次还是等一次接口）
  static void _saveCache(Map<String, dynamic> data) {
    SharedPreferences.getInstance().then((sp) async {
      await sp.setString(_kCache, jsonEncode(data));
      await sp.setInt(_kCacheAt, DateTime.now().millisecondsSinceEpoch);
    }).catchError((_) {});
  }
}
