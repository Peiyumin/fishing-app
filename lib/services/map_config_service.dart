import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

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
  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    if (!ApiConfig.enabled) return;
    try {
      // ApiClient 已自动拆出后端的 data 字段
      final cfg = await ApiClient.get('/app/map-config') as Map?;
      if (cfg != null) {
        _geoToken = (cfg['geovisearthToken'] ?? '').toString().trim();
        _tk = (cfg['tiandituTk'] ?? '').toString().trim();
        _prefer = (cfg['prefer'] ?? 'auto').toString().trim().toLowerCase();
        final e = (cfg['engine'] ?? 'gl').toString().trim().toLowerCase();
        _engine = e == 'dart' ? 'dart' : 'gl';
      }
    } catch (_) {
      // 后台不可达：保持空密钥 → 使用高德兜底
    }
  }
}
