import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// AI 分析次数（v2.1.56）
///
/// 规则（用户定的）：AI 找钓点是**会员功能**，非会员免费 3 次，
/// 用完必须开通会员才能继续用。会员不限次数。
///
/// 计数放在服务端（`ai_scan_usage` 表），因为换手机 / 重装 App 不能清零。
/// 后端还没升级时（接口 404）退回本地计数，这样「3 次」的体验不会因为
/// 一次漏传升级包就完全失效 —— 但本地计数只能防自己，防不住重装。
class AiQuota {
  final int used;
  final int limit;
  final bool member;

  const AiQuota({required this.used, required this.limit, required this.member});

  int get remaining => member ? 999 : (limit - used).clamp(0, limit);
  bool get canUse => member || remaining > 0;

  static const AiQuota demo = AiQuota(used: 0, limit: 3, member: false);

  factory AiQuota.fromJson(Map<String, dynamic> j) => AiQuota(
        used: jsonInt(j['used']) ?? 0,
        limit: jsonInt(j['limit']) ?? 3,
        member: jsonBool(j['member'], fallback: false),
      );

  /// 「本账号还能免费用 N 次」——会员给的是另一句文案
  String get hint => member
      ? '会员不限次数'
      : (canUse ? '免费还剩 $remaining 次' : '免费次数已用完');
}

class AiQuotaService {
  static AiQuota? _cache;

  static AiQuota get cached => _cache ?? AiQuota.demo;

  static String _localKey(String? userId) => 'ai_scan_used_${userId ?? 'guest'}';

  /// 查询当前剩余次数（[refresh] = true 时不走内存缓存）
  static Future<AiQuota> fetch({bool refresh = false, String? userId}) async {
    if (!refresh && _cache != null) return _cache!;
    if (ApiConfig.enabled) {
      try {
        final data = jsonMap(await ApiClient.get('/ai/quota'));
        final q = AiQuota.fromJson(Map<String, dynamic>.from(data));
        _cache = q;
        return q;
      } catch (_) {
        // 后端未升级 / 网络异常 → 本地兜底（不阻断用户）
      }
    }
    final local = await _localGet(userId);
    _cache = local;
    return local;
  }

  /// 消耗一次（扫描成功后才调用）
  ///
  /// 返回的 `ok=false` 表示服务端判定已经用完（并发/多端同时点的兜底）；
  /// [msg] 是给用户看的话。
  static Future<({bool ok, AiQuota quota, String msg})> consume(
      {String? userId}) async {
    if (ApiConfig.enabled) {
      try {
        final data = jsonMap(await ApiClient.post('/ai/consume', const {}));
        final q = AiQuota.fromJson(Map<String, dynamic>.from(data));
        _cache = q;
        return (ok: true, quota: q, msg: '');
      } on ApiException catch (e) {
        // 403 = 已经用完（服务端拒绝），不是网络问题，必须如实拦下
        if (e.status == 403) {
          final q = await fetch(refresh: true, userId: userId);
          return (ok: false, quota: q, msg: e.message);
        }
      } catch (_) {
        // 落到本地计数
      }
    }
    final q = await _localBump(userId);
    return (
      ok: q.canUse || q.member,
      quota: q,
      msg: q.canUse || q.member ? '' : '免费次数已用完，开通会员后不限次数',
    );
  }

  /// 本地记账（后端不可用时的兜底），上限就是 limit
  static Future<AiQuota> _localGet(String? userId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final used = sp.getInt(_localKey(userId)) ?? 0;
      return AiQuota(used: used.clamp(0, 3), limit: 3, member: false);
    } catch (_) {
      return AiQuota.demo;
    }
  }

  static Future<AiQuota> _localBump(String? userId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = sp.getInt(_localKey(userId)) ?? 0;
      final next = (cur + 1).clamp(0, 3);
      await sp.setInt(_localKey(userId), next);
      return AiQuota(used: next, limit: 3, member: false);
    } catch (_) {
      return AiQuota.demo;
    }
  }

  /// 退出登录 / 换账号时清内存缓存
  static void clearCache() => _cache = null;
}
