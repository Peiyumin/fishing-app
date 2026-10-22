import '../models/member_plan.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 会员中心
class MemberService {
  static MemberCenter? _center;

  /// 会员中心文案 + 套餐列表
  static Future<({MemberCenter center, List<MemberPlan> plans})> plans() async {
    final data = await ApiClient.get('/member/plans') as Map;
    final map = data.cast<String, dynamic>();
    final center = MemberCenter.fromJson(
        (map['center'] as Map?)?.cast<String, dynamic>() ?? const {});
    final list = (map['plans'] as List?) ?? const [];
    final plans = list
        .map((e) => MemberPlan.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    _center = center;
    return (center: center, plans: plans);
  }

  static MemberCenter get fallbackCenter => _center ?? const MemberCenter();

  static Future<MemberInfo> info() async {
    final data = await ApiClient.get('/member/info') as Map;
    return MemberInfo.fromJson(data.cast<String, dynamic>());
  }

  /// 购买：payType = points 积分 / balance 余额 / cash 现金（待后台确认）
  static Future<({bool ok, String msg, MemberInfo? info})> buy(
      String planId, String payType) async {
    final data = await ApiClient.post('/member/buy', {
      'planId': planId,
      'payType': payType,
    }) as Map;
    final map = data.cast<String, dynamic>();
    final rawInfo = map['info'];
    return (
      ok: (map['ok'] as bool?) ?? true,
      msg: (map['msg'] ?? '').toString(),
      info: rawInfo is Map
          ? MemberInfo.fromJson(rawInfo.cast<String, dynamic>())
          : null,
    );
  }

  /// 会员订单列表（返回原始 map，页面按需取值）
  static Future<List<Map<String, dynamic>>> orders() async {
    final data = await ApiClient.get('/member/orders') as List;
    return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// 会员图标（权益网格）
  static String perkIconOf(String key) {
    switch (key) {
      case 'nearby':
        return '📍';
      case 'fish':
        return '🐟';
      case 'wallet':
        return '💰';
      case 'medal':
        return '🎖';
      case 'ai':
        return '🤖';
      case 'service':
        return '🎧';
      case 'shield':
        return '🛡';
      case 'notice':
        return '🔔';
      case 'trophy':
        return '🏆';
      case 'star':
        return '⭐';
      default:
        return '👑';
    }
  }

  static bool get apiEnabled => ApiConfig.enabled;
}
