import '../models/badge.dart';
import '../models/profile_config.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 「我的」页配置 + 徽章（后台可配置）
///
/// 两个接口都做了兜底：后端没升级 / 断网时返回内置默认值，
/// 页面照常渲染，不会白屏。
class ProfileService {
  /// 我的页板块配置（菜单 / 服务宫格 / 智能条 / 底部卡片）
  static Future<ProfilePageConfig> fetchConfig() async {
    if (!ApiConfig.enabled) return ProfilePageConfig.defaults;
    try {
      final data = await ApiClient.get('/profile/config');
      if (data is Map) {
        return ProfilePageConfig.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // 老后端没有这个接口：直接用默认配置
    }
    return ProfilePageConfig.defaults;
  }

  /// 徽章：返回 (全部, 我获得的)
  static Future<({List<BadgeItem> all, List<BadgeItem> mine})>
      fetchBadges() async {
    if (!ApiConfig.enabled) {
      return (all: const <BadgeItem>[], mine: const <BadgeItem>[]);
    }
    try {
      final data = await ApiClient.get('/badges');
      if (data is Map) {
        List<BadgeItem> parse(dynamic raw) {
          if (raw is! List) return const [];
          return raw
              .whereType<Map>()
              .map((m) => BadgeItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }

        return (all: parse(data['all']), mine: parse(data['mine']));
      }
    } catch (_) {}
    return (all: const <BadgeItem>[], mine: const <BadgeItem>[]);
  }
}
