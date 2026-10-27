import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机登录过的账号（设置 - 历史账号）
///
/// 「本机 30 天内登录过的账号」：只存本机，不上服务器。
/// 存的是登录接口原样返回的那份数据（token / 昵称 / 头像 / 会员信息），
/// 所以点「切换」时可以不用再输一次密码 —— token 失效时才要求重新登录。
class AccountHistory {
  /// 登录接口返回的原始字段（token 在里面）
  final Map<String, dynamic> data;
  final DateTime lastAt;

  const AccountHistory({required this.data, required this.lastAt});

  String get userId => (data['id'] ?? '').toString();
  String get nickname {
    final n = (data['nickname'] ?? '').toString();
    return n.isEmpty ? '钓友' : n;
  }

  String get phone => (data['phone'] ?? '').toString();
  String get token => (data['token'] ?? '').toString();
  String? get avatar {
    final a = (data['avatar'] ?? '').toString();
    return a.isEmpty ? null : a;
  }

  /// 手机号打码
  String get maskedPhone {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  /// 相对时间：刚刚 / 3 小时前 / 2 天前 / 5 天前
  String get lastText {
    final d = DateTime.now().difference(lastAt);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  Map<String, dynamic> toJson() => {'data': data, 'at': lastAt.toIso8601String()};

  static AccountHistory? fromJson(dynamic j) {
    if (j is! Map) return null;
    final d = j['data'];
    if (d is! Map) return null;
    DateTime at;
    try {
      at = DateTime.parse((j['at'] ?? '').toString());
    } catch (_) {
      at = DateTime.now();
    }
    return AccountHistory(
      data: Map<String, dynamic>.from(d),
      lastAt: at,
    );
  }
}

class AccountHistoryStore {
  static const _k = 'login_history_accounts';

  /// 保留天数（「本机 30 天内登录过的账号」）
  static const int keepDays = 30;

  /// 最多保留几个（再多列表就太长了）
  static const int maxCount = 6;

  /// 读取：过滤掉超过 30 天的，按最近登录排序
  static Future<List<AccountHistory>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null || raw.isEmpty) return const [];
    List<dynamic> arr;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      arr = decoded;
    } catch (_) {
      return const [];
    }
    final deadline = DateTime.now().subtract(const Duration(days: keepDays));
    final out = <AccountHistory>[];
    for (final e in arr) {
      final a = AccountHistory.fromJson(e);
      if (a == null) continue;
      if (a.userId.isEmpty || a.token.isEmpty) continue;
      if (a.lastAt.isBefore(deadline)) continue;
      out.add(a);
    }
    out.sort((x, y) => y.lastAt.compareTo(x.lastAt));
    return out;
  }

  /// 登录 / 注册成功后记一笔（同一账号只留最新一条）
  static Future<void> remember(Map<String, dynamic> loginData) async {
    final id = (loginData['id'] ?? '').toString();
    final token = (loginData['token'] ?? '').toString();
    if (id.isEmpty || token.isEmpty) return;

    final list = List<AccountHistory>.from(await load());
    list.removeWhere((a) => a.userId == id);
    list.insert(0, AccountHistory(data: loginData, lastAt: DateTime.now()));
    await _write(list.take(maxCount).toList());
  }

  static Future<void> remove(String userId) async {
    final list = List<AccountHistory>.from(await load());
    list.removeWhere((a) => a.userId == userId);
    await _write(list);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }

  static Future<void> _write(List<AccountHistory> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}
