import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/message_poller.dart';

/// 首页右上角消息铃铛：显示未读数，点击进消息中心。
/// 未读数来自全局 [MessagePoller]（登录后每 15s 轮询 + 回前台即查），
/// 不再本地单独轮询，保证跨页面一致、更及时。
/// 未登录或后端不可用时静默不显示红点（不影响首页使用）。
class MsgBellButton extends StatelessWidget {
  const MsgBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MessagePoller.instance.unread,
      builder: (context, unread, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            await Navigator.of(context).pushNamed('/message-center');
            MessagePoller.instance.refreshNow();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none, size: 21, color: Colors.white),
                if (unread > 0)
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
                        unread > 99 ? '99+' : '$unread',
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
      },
    );
  }
}
