import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_provider.dart';

/// 会员门槛：当前用户不是会员时弹窗引导去开通会员，并返回 false（不继续）。
/// 已经是会员则直接返回 true（调用方可继续打开私信等会员专属功能）。
Future<bool> ensureMember(BuildContext context) async {
  final session = Provider.of<SessionProvider>(context, listen: false);
  if (session.isMember) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('开通会员'),
      content: const Text('私信功能仅对会员开放，开通会员后即可与钓友畅聊。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style:
              ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('去开通会员',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  if (go == true) {
    Navigator.of(context).pushNamed('/member-center');
  }
  return false;
}
