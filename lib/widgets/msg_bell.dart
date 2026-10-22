import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/message_service.dart';

/// 首页右上角消息铃铛：显示未读数，点击进消息中心
/// 未登录或后端不可用时静默不显示红点（不影响首页使用）
class MsgBellButton extends StatefulWidget {
  const MsgBellButton({super.key});

  @override
  State<MsgBellButton> createState() => _MsgBellButtonState();
}

class _MsgBellButtonState extends State<MsgBellButton> {
  int _unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // 每 60 秒刷新一次未读数（进后台时 timer 仍跑，开销可忽略）
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await MessageService.summary();
      if (!mounted) return;
      if (s.total != _unread) setState(() => _unread = s.total);
    } catch (_) {
      // 未登录 / 网络异常：保持当前状态
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Navigator.of(context).pushNamed('/message-center');
        _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none, size: 21, color: Colors.white),
            if (_unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text(
                    _unread > 99 ? '99+' : '$_unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        height: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
