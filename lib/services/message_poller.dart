import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/message.dart';
import 'api_config.dart';
import 'message_service.dart';
import 'notification_service.dart';
import 'session_provider.dart';

/// 把一批新消息按类型分组（通知聚合用）
///
/// 抽成顶层函数是为了能单测：聚合规则错了会直接表现为「一次弹出十几个通知」
/// 或者「点赞通知把评论通知挤掉」，这类问题在真机上很难复现，必须靠单测锁住。
({
  Map<String, List<FeedItem>> chats,
  List<FeedItem> systems,
  List<FeedItem> comments,
  List<FeedItem> likes,
}) groupFeed(List<FeedItem> items) {
  final chats = <String, List<FeedItem>>{};
  final systems = <FeedItem>[];
  final comments = <FeedItem>[];
  final likes = <FeedItem>[];

  for (final n in items) {
    if (n.isChat) {
      chats.putIfAbsent(n.peerId, () => []).add(n);
    } else if (n.isSystem) {
      systems.add(n);
    } else if (n.type == 'like') {
      likes.add(n);
    } else {
      comments.add(n);
    }
  }
  return (
    chats: chats,
    systems: systems,
    comments: comments,
    likes: likes,
  );
}

/// 全局消息轮询器：把「纯拉模式」做到接近实时，并驱动通知。
///
/// 与旧版的区别（v2.1.17）：
///   · 以前只查未读**总数**，只能提示「你有 N 条新消息」；
///     现在走 `GET /messages/feed?since=…`，拿到**具体内容**（谁评论了什么、谁发了私信），
///     才能弹真正的通知（通知栏 + 应用内横幅）。
///   · `since` 由服务端时间推进，天然去重：同一条消息不会重复弹。
///   · 多条互动（点赞/评论）在客户端**聚合**成一条，避免刷屏。
///   · App 回到前台立即补拉一次，把后台期间错过的消息一次性提醒。
class MessagePoller {
  MessagePoller._();
  static final MessagePoller instance = MessagePoller._();

  static const _interval = Duration(seconds: 15);

  /// 全局未读总数（铃铛 / 消息中心据此显示红点）
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// 有新条目到达（已去重、未聚合）→ 用于应用内顶部横幅
  void Function(List<FeedItem> items, MsgSummary summary)? onNewItems;

  SessionProvider? _session;
  Timer? _timer;
  bool _running = false;

  /// 服务端时间游标：只拉这个时间点之后的新消息
  String _since = '';

  /// 首轮只建基线，不把历史未读当成「新消息」弹出来
  bool _baselineDone = false;

  /// 在 main() 里把全局登录态挂上来，并随登录态自动启停。
  void attach(SessionProvider session) {
    if (_session == session) return;
    _session?.removeListener(_onSessionChange);
    _session = session;
    session.addListener(_onSessionChange);
    if (session.isLoggedIn) {
      start();
    } else {
      stop();
    }
  }

  void _onSessionChange() {
    if (_session == null) return;
    if (_session!.isLoggedIn) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    if (!ApiConfig.enabled) return;
    if (_session == null || !_session!.isLoggedIn) return;
    if (_running) {
      _poll();
      return;
    }
    _running = true;
    // 换账号 / 重新登录：游标与基线都要重置，否则会把别人的消息算进来
    _since = '';
    _baselineDone = false;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _poll());
    _poll(); // 立即查一次
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _since = '';
    _baselineDone = false;
    unread.value = 0;
  }

  /// 立即查一次（App 回前台 / 操作后调用）
  ///
  /// [fromBackground] = true 表示是「切回前台」触发的：iOS 挂起后 Dart 定时器
  /// 会停摆，只能靠这个时机把后台期间错过的消息一次性补提醒。
  Future<void> refreshNow({bool fromBackground = false}) => _poll();

  Future<void> _poll() async {
    if (!ApiConfig.enabled) return;
    if (_session == null || !_session!.isLoggedIn) {
      stop();
      return;
    }
    try {
      final res = await MessageService.feed(
        since: _baselineDone ? _since : '',
        limit: 20,
      );
      if (_session == null || !_session!.isLoggedIn) return;

      final summary = res.summary;
      final serverTime = res.serverTime;
      final items = res.items;
      unread.value = summary.total;

      // 首轮：只记游标，不弹
      if (!_baselineDone) {
        _baselineDone = true;
        _since = serverTime;
        return;
      }

      // 推进游标（服务端时间单调递增，用服务端时间避免本机时钟偏差）
      if (serverTime.isNotEmpty) _since = serverTime;

      if (items.isEmpty) return;

      // 只提醒「别人对我做的、且未读」的条目；自己发的私信（to_id 不是自己）后端已过滤
      final fresh = items.where((e) => !e.isRead).toList();
      if (fresh.isEmpty) return;

      // 优先弹系统通知（能在通知中心留痕、锁屏也能看到）；
      // 系统权限没给 / 平台不支持时，退回应用内顶部横幅，保证一定看得见。
      var pushed = false;
      if (NotifyPrefs.enabled) {
        pushed = await _pushNotifications(fresh);
      }
      if (!pushed) {
        onNewItems?.call(fresh, summary);
      }
    } catch (_) {
      // 网络异常：保持现状，下一轮再试
    }
  }

  /// 把一批新条目聚合成尽量少的通知弹出
  ///
  /// 规则：
  ///   · 私信：按人分组，每人一条（最多 3 人）
  ///   · 官方公告：逐条（重要，不合并），最多 2 条
  ///   · 评论/回复：合并一条
  ///   · 点赞：合并一条
  /// 总上限 3 条系统通知，避免一次轮询连弹十几条。
  ///
  /// 返回是否至少弹出成功一条（失败则由上层退回应用内横幅）。
  Future<bool> _pushNotifications(List<FeedItem> items) async {
    final svc = NotificationService.instance;
    var budget = 3;
    var any = false;

    final g = groupFeed(items);
    final chats = g.chats;
    final systems = g.systems;
    final comments = g.comments;
    final likes = g.likes;

    // ① 官方公告：逐条
    for (final n in systems) {
      if (budget <= 0) break;
      budget--;
      if (await svc.show(n)) any = true;
    }

    // ② 私信：每人一条，正文取该人最新一条
    for (final entry in chats.entries) {
      if (budget <= 0) break;
      budget--;
      final list = entry.value;
      final latest = list.last;
      final ok = list.length == 1
          ? await svc.show(latest)
          : await svc.showGrouped(
              title: latest.fromName.isEmpty ? '新私信' : latest.fromName,
              body: '${latest.content}（共 ${list.length} 条新消息）',
              type: 'chat',
              peerId: entry.key,
            );
      if (ok) any = true;
    }

    // ③ 评论 / 回复
    if (comments.isNotEmpty && budget > 0) {
      budget--;
      final latest = comments.last;
      final from = latest.fromName;
      final ok = await svc.showGrouped(
        title: comments.length == 1
            ? (latest.type == 'reply' ? '$from 回复了你' : '$from 评论了你的动态')
            : '${comments.length} 条新评论',
        body: comments.length == 1 ? latest.content : '$from：${latest.content}',
        type: latest.type,
        refId: latest.refId,
      );
      if (ok) any = true;
    }

    // ④ 点赞
    if (likes.isNotEmpty && budget > 0) {
      final names = <String>{};
      for (final l in likes) {
        if (l.fromName.isNotEmpty) names.add(l.fromName);
      }
      final who = names.isEmpty
          ? '有人'
          : (names.length == 1
              ? names.first
              : '${names.first} 等 ${names.length} 人');
      final ok = await svc.showGrouped(
        title: '$who 赞了你的动态',
        body: likes.length == 1 ? '你的动态收到了 1 个赞' : '共收到 ${likes.length} 个赞',
        type: 'like',
        refId: likes.last.refId,
      );
      if (ok) any = true;
    }

    return any;
  }
}
