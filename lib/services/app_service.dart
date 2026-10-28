import '../models/app_bootstrap.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// App 启动引导数据（预览页 + 广告）
/// 由管理后台「启动预览页 / 启动广告」页面控制，公开接口无需登录
class AppService {
  /// 拉取启动内容；后端不可用时返回空（App 直接进首页，不影响使用）
  static Future<AppBootstrap> bootstrap() async {
    if (!ApiConfig.enabled) return const AppBootstrap();
    try {
      final data = jsonMap(await ApiClient.get('/app/bootstrap'));
      return AppBootstrap.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return const AppBootstrap();
    }
  }
}
