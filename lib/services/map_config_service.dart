import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import 'map_tile_source.dart';

/// 地图底图配置服务（v2.1.10 起，v2.2.0 增加星图地球）
///
/// ------------------------------------------------------------
/// 后台「系统设置 → 地图底图」里配置：
///   - geovisearth_token：星图地球 token（推荐，注册即用）
///   - tianditu_tk     ：天地图 tk（2026-10-01 起需授权，一般填不了）
///   - prefer          ：优先级 auto / geovisearth / tianditu / gaode
///
/// App 拉 GET /app/map-config 决定用哪家底图；
/// 全部拿不到时自动回退到免 key 的高德卫星图，
/// 保证「地图永远能打开」，不会因为一个密钥没配就白屏。
class MapConfigService {
  MapConfigService._();

  static String _geoToken = '';
  static String _tk = '';
  static String _prefer = 'auto';
  static String _engine = 'gl';
  static bool _loaded = false;

  /// 天地图密钥（空 = 不可用）
  static String get tiandituTk => _tk;

  /// 星图地球 token（空 = 不可用）
  static String get geovisearthToken => _geoToken;

  /// 是否已拿到天地图密钥
  static bool get hasTianditu => _tk.isNotEmpty;

  /// 是否已拿到星图地球 token
  static bool get hasGeovisearth => _geoToken.isNotEmpty;

  /// 渲染内核：'gl' = MapLibre 原生（默认，快） / 'dart' = flutter_map（老内核兜底）
  static String get engine => _engine;

  /// 是否用原生 GL 内核
  ///
  /// 只有 Android / iOS 才有 MapLibre 原生实现；桌面端、Web、以及
  /// flutter test 的宿主环境一律走老的 flutter_map，避免平台通道缺失。
  static bool get useNativeEngine {
    if (_engine == 'dart' || kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 实际应使用的底图
  ///
  /// 规则：
  ///   prefer 明确指定且对应密钥存在 → 用它
  ///   prefer=gaode              → 高德
  ///   其余（auto / 指定但没密钥）→ 星图地球 > 天地图 > 高德
  ///
  /// 星图地球排在最前，是因为天地图自 2026-10-01 起接口改为
  /// 「授权后调用」，个人自注册已拿不到可用的 tk。
  static TileSourceKind get preferredKind {
    switch (_prefer) {
      case 'gaode':
        return TileSourceKind.gaode;
      case 'geovisearth':
        if (hasGeovisearth) return TileSourceKind.geovisearth;
        break;
      case 'tianditu':
        if (hasTianditu) return TileSourceKind.tianditu;
        break;
      default:
        break;
    }
    if (hasGeovisearth) return TileSourceKind.geovisearth;
    if (hasTianditu) return TileSourceKind.tianditu;
    return TileSourceKind.gaode;
  }

  /// 当前底图（已把密钥装好，可直接给 flutter_map 用）
  static TileSource get source => TileSource(
        kind: preferredKind,
        tk: _tk,
        geoToken: _geoToken,
      );

  /// 拉取配置（幂等，只拉一次）
  ///
  /// ★★ v2.1.27 修了两件事：
  ///
  /// ① **并发调用共享同一个请求**。以前是 `if (_loaded) return;`，而 `_loaded`
  ///    表示「已经开始了」而不是「已经完成」—— 第二个调用方会立刻拿到一个
  ///    已完成的 Future，此时配置还没回来，它读到的 `MapConfigService.source`
  ///    是兜底的高德。钓点页 initState 先调一次、地图页 initState 又调一次，
  ///    几乎必然踩中，结果就是「配了星图却用高德」。
  ///
  /// ② **不让建图等网络**，见 [_restoreCache] 注释。
  static Future<void>? _inflight;

  static Future<void> load({bool force = false}) {
    if (force) return _inflight = _doLoad(force: true);
    // 有请求在路上 → 等同一个 Future。**必须先判 _inflight 再判 _loaded**：
    // _loaded 在请求发出瞬间就为 true，此时配置还没回来。
    final f = _inflight;
    if (f != null) return f;
    if (_loaded) return Future.value();
    return _inflight = _doLoad();
  }

  static Future<void> _doLoad({bool force = false}) async {
    _loaded = true;
    final hasCache = await _restoreCache();
    if (!ApiConfig.enabled) return;
    if (hasCache && !force) {
      unawaited(_refresh()); // 后台刷新，不阻塞建图
      return;
    }
    await _refresh();
  }

  static Future<void> _refresh() async {
    try {
      // ApiClient 已自动拆出后端的 data 字段
      final cfg = await ApiClient.get('/app/map-config')
          .timeout(const Duration(seconds: 5)) as Map?;
      if (cfg != null) {
        _geoToken = (cfg['geovisearthToken'] ?? '').toString().trim();
        _tk = (cfg['tiandituTk'] ?? '').toString().trim();
        _prefer = (cfg['prefer'] ?? 'auto').toString().trim().toLowerCase();
        final e = (cfg['engine'] ?? 'gl').toString().trim().toLowerCase();
        _engine = e == 'dart' ? 'dart' : 'gl';
        await _saveCache();
      }
    } catch (_) {
      // 后台不可达：保持当前配置（缓存或高德兜底）
    }
  }

  /// 上次成功拿到的配置（本机缓存）
  ///
  /// 缓存的意义不是「省一次请求」，而是**不让建图等网络**：
  /// 底图源（星图 token / 天地图 tk / 用哪套内核）必须建图前就知道，
  /// 没有缓存时这部分延迟全落在用户盯灰屏的时间上。
  static const _kCacheKey = 'map_config_v1';

  static Future<bool> _restoreCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _geoToken = (m['geovisearthToken'] ?? '').toString().trim();
      _tk = (m['tiandituTk'] ?? '').toString().trim();
      final p = (m['prefer'] ?? 'auto').toString().trim().toLowerCase();
      if (p.isNotEmpty) _prefer = p;
      _engine = m['engine'] == 'dart' ? 'dart' : 'gl';
      return true;
    } catch (_) {
      return false; // 缓存坏了就当没有，别影响建图
    }
  }

  static Future<void> _saveCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _kCacheKey,
        jsonEncode({
          'geovisearthToken': _geoToken,
          'tiandituTk': _tk,
          'prefer': _prefer,
          'engine': _engine,
        }),
      );
    } catch (_) {
      // 存不进就算了，下次继续走网络
    }
  }
}
