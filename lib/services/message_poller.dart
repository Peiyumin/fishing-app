import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_config.dart';
import 'message_service.dart';
import 'session_provider.dart';

/// 全局消息轮询器：弥补「纯拉模式」不及时的问题。
///
/// - 只要登录就在 App 生命周期内持续轮询（默认 15s），比首页铃铛原先的本地 60s 更可靠、
///   且跨所有页面生效；
/// - App 从后台回到前台立即查一次（见 [refreshNow]，由 main 的 lifecycle 触发）；
/// - 未读数通过 [unread] 暴露给铃铛与消息中心；
/// - 监测到「未读数增加」时回调 [onNewMessage]，用于弹出顶部提示，营造「实时收到」的体验。
class MessagePoller {
  MessagePoller._();
  static final MessagePoller instance = MessagePoller._();

  static const _interval = Duration(seconds: 15);

  /// 全局未读总数（铃铛 / 消息中心据此显示红点）
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// 新消息到达（未读增加）回调，参数为 (新增条数, 当前总数)
  void Function(int delta, int total)? onNewMessage;

  SessionProvider? _session;
  Timer? _timer;
  bool _running = false;
  int _baseline = 0; // 首轮作为基线，避免打开 App 时把历史未读误报成「新消息」

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
    if (_running || !ApiConfig.enabled) return;
    if (_session == null || !_session!.isLoggedIn) return;
    _running = true;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _poll());
    _poll(); // 立即查一次
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _baseline = 0;
    unread.value = 0;
  }

  /// 立即查一次（App 回前台 / 操作后调用）
  Future<void> refreshNow() => _poll();

  Future<void> _poll() async {
    if (!ApiConfig.enabled) return;
    if (_session == null || !_session!.isLoggedIn) {
      stop();
      return;
    }
    try {
      final s = await MessageService.summary();
      if (_session == null || !_session!.isLoggedIn) return;
      final total = s.total;
      unread.value = total;
      if (_baseline == 0) {
        _baseline = total; // 首轮只建基线，不报新消息
      } else if (total > _baseline) {
        onNewMessage?.call(total - _baseline, total);
        _baseline = total;
      } else {
        _baseline = total;
      }
    } catch (_) {
      // 网络异常：保持现状，下一轮再试
    }
  }
}
