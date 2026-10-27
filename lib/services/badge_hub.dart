import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/badge.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 信息流「头像后面的徽章」数据源
///
/// 为什么不塞进动态列表接口：那需要后端给每条动态各查一遍徽章（N+1），
/// 首页二三十条就会多几十次查询。这里改成**一屏一次批量请求**：
///   卡片 build 时把作者 id 丢进来 → 攒 120ms → 一次 `/users/badges?ids=a,b,c`
/// 结果按 userId 长缓存，滚动翻页也基本只多一两次请求；
/// 后端没升级（接口 404/报错）时自动停用，界面上就是不显示徽章，不会报错。
class BadgeHub {
  BadgeHub._();

  /// 每个用户已获得的徽章（最多 4 枚），命中的 id 才在表里
  static final Map<String, List<BadgeItem>> _cache = {};

  /// 已请求过但确实没有徽章 / 请求失败的 id，避免重复请求
  static final Set<String> _known = {};

  static final Set<String> _pending = {};
  static Timer? _timer;

  /// 后端不支持这个接口时置 true，之后不再发请求
  static bool _disabled = false;

  /// 上一次请求失败的时间：失败后短暂退避，**但不把作者 id 记成「已问过」**
  ///
  /// 之前的写法是 catch 里 `_known.addAll(ids)`，等于「只要失败过一次，这批人
  /// 这辈子都不会再查」——后端修好了也得杀进程重进才看得到徽章。现在改成
  /// 20 秒退避，之后还会再试。
  static DateTime? _backoffUntil;

  /// 缓存有更新就 +1，卡片监听它重建
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 一次批量最多带多少个 id（后端 limit 兜底）
  static const int _batch = 60;

  static List<BadgeItem> of(String userId) => _cache[userId] ?? const [];

  /// 卡片侧调用：登记作者 id，自动合并成一次请求
  static void warm(Iterable<String> userIds) {
    if (_disabled || !ApiConfig.enabled) return;
    final until = _backoffUntil;
    if (until != null) {
      if (DateTime.now().isBefore(until)) return;
      _backoffUntil = null;
    }
    var added = false;
    for (final id in userIds) {
      if (id.isEmpty || _known.contains(id) || _cache.containsKey(id)) continue;
      if (_pending.add(id)) added = true;
    }
    if (!added) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 120), _flush);
  }

  /// 直接覆盖某用户的徽章（个人页已经拿到 badges 时可以回填，省一次请求）
  static void seed(String userId, List<BadgeItem> badges) {
    if (userId.isEmpty || _known.contains(userId)) return;
    _cache[userId] = badges.take(4).toList();
    _known.add(userId);
    revision.value++;
  }

  static Future<void> _flush() async {
    if (_pending.isEmpty || _disabled) return;
    final ids = _pending.take(_batch).toList();
    _pending.removeAll(ids);
    try {
      final data = await ApiClient.get('/users/badges', {'ids': ids.join(',')});
      final map = (data is Map && data['users'] is Map)
          ? (data['users'] as Map).cast<String, dynamic>()
          : (data is Map ? data : <String, dynamic>{});
      var changed = false;
      for (final id in ids) {
        _known.add(id);
        final raw = map[id];
        if (raw is List && raw.isNotEmpty) {
          _cache[id] = raw
              .whereType<Map>()
              .map((m) => BadgeItem.fromJson(Map<String, dynamic>.from(m)))
              .where((b) => b.name.isNotEmpty || b.icon.isNotEmpty)
              .take(4)
              .toList();
          changed = true;
        }
      }
      if (changed) revision.value++;
    } catch (_) {
      // 404（后端还没升级）或网络抖动：不记入 _known，只退避 20 秒，
      // 之后有新卡片进来还会再试一次 —— 后端升级完不用重启 App。
      _backoffUntil = DateTime.now().add(const Duration(seconds: 20));
    }
    // 还有剩下的（超过一批）继续排队
    if (_pending.isNotEmpty) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 60), _flush);
    }
  }

  /// 退出登录 / 换账号时清空
  static void reset() {
    _cache.clear();
    _known.clear();
    _pending.clear();
    _timer?.cancel();
    _timer = null;
    _backoffUntil = null;
    _disabled = false;
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    reset();
    revision.value = 0;
  }

  @visibleForTesting
  static void debugPut(String userId, List<BadgeItem> badges) {
    _cache[userId] = badges;
    _known.add(userId);
    revision.value++;
  }
}
