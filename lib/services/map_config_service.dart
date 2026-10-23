import '../services/api_client.dart';
import '../services/api_config.dart';

/// 地图底图配置服务（v2.1.10）
///
/// ------------------------------------------------------------
/// 后台「系统设置 → 站点设置」里配置天地图密钥（tk），
/// App 拉取 GET /app/map-config 拿到后使用天地图底图。
///
/// 拿不到 / 后台不可用时，地图会自动回退到免 key 的高德卫星图，
/// 保证「地图永远能打开」，不会因为一个密钥没配就白屏。
class MapConfigService {
  MapConfigService._();

  static String _tk = '';
  static bool _loaded = false;

  /// 天地图密钥（空 = 不可用）
  static String get tiandituTk => _tk;

  /// 是否已拿到天地图配置
  static bool get hasTianditu => _tk.isNotEmpty;

  /// 拉取配置（幂等，只拉一次）
  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    if (!ApiConfig.enabled) return;
    try {
      // ApiClient 已自动拆出后端的 data 字段
      final cfg = await ApiClient.get('/app/map-config') as Map?;
      if (cfg != null) {
        _tk = (cfg['tiandituTk'] ?? '').toString().trim();
      }
    } catch (_) {
      // 后台不可达：保持空 tk → 使用高德兜底
    }
  }
}
