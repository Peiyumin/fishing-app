import 'package:flutter/material.dart';

import '../models/member_plan.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 会员中心
class MemberService {
  static MemberCenter? _center;

  /// 会员中心文案 + 套餐列表
  static Future<({MemberCenter center, List<MemberPlan> plans})> plans() async {
    final data = jsonMap(await ApiClient.get('/member/plans'));
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
    final data = jsonMap(await ApiClient.get('/member/info'));
    return MemberInfo.fromJson(data.cast<String, dynamic>());
  }

  /// 购买：payType = points 积分 / balance 余额 / cash 现金（待后台确认）
  static Future<({bool ok, String msg, MemberInfo? info})> buy(
      String planId, String payType) async {
    final data = jsonMap(await ApiClient.post('/member/buy', {
      'planId': planId,
      'payType': payType,
    }));
    final map = data.cast<String, dynamic>();
    final rawInfo = map['info'];
    return (
      ok: jsonBool(map['ok'], fallback: true),
      msg: (map['msg'] ?? '').toString(),
      info: rawInfo is Map
          ? MemberInfo.fromJson(rawInfo.cast<String, dynamic>())
          : null,
    );
  }

  /// 会员订单列表（返回原始 map，页面按需取值）
  static Future<List<Map<String, dynamic>>> orders() async {
    final data = jsonList(await ApiClient.get('/member/orders'));
    return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// 会员图标（权益网格）
  ///
  /// ★ 原来返回的是 emoji 字符串（📍🐟💰🎖🤖🎧🛡🔔🏆⭐👑）。
  ///   emoji 靠系统彩色字体渲染，ROM 精简过或老 Android 上直接显示
  ///   小方块。改回 [IconData]：图标字体随 APK 打包，任何设备都有字形。
  static IconData perkIconOf(String key) {
    switch (key) {
      case 'nearby':
        return Icons.place;
      case 'fish':
        return Icons.set_meal;
      case 'wallet':
        return Icons.account_balance_wallet;
      case 'medal':
        return Icons.military_tech;
      case 'ai':
        return Icons.smart_toy;
      case 'service':
        return Icons.headset_mic;
      case 'shield':
        return Icons.shield;
      case 'notice':
        return Icons.notifications_active;
      case 'trophy':
        return Icons.emoji_events;
      case 'star':
        return Icons.star;
      default:
        return Icons.workspace_premium;
    }
  }

  static bool get apiEnabled => ApiConfig.enabled;
}
