import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../screens/auth_screen.dart';
import '../services/ai_quota_service.dart';
import '../services/session_provider.dart';
import 'center_toast.dart';

/// AI 分析次数闸门（v2.1.56）
///
/// 会员 → 直接放行（不限次数）；非会员 → 免费 [AiQuota.limit] 次，
/// 用完弹窗引导开通会员。未登录先要求登录（否则次数没法记账）。
Future<bool> ensureAiQuota(BuildContext context) async {
  final session = Provider.of<SessionProvider>(context, listen: false);
  if (!session.isLoggedIn) {
    CenterToast.show(context, 'AI 分析需要登录后使用', icon: Icons.lock_outline);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    return false;
  }
  if (session.isMember) return true;

  final q = await AiQuotaService.fetch(refresh: true, userId: session.userId);
  if (q.canUse) return true;
  if (!context.mounted) return false;

  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('免费次数已用完'),
      content: Text(
        'AI 水域分析是会员功能，每个账号可免费体验 ${q.limit} 次，'
        '你已用完。开通会员后不限次数，还能解锁全部鱼种图鉴、不限条数私信。',
        style: const TextStyle(height: 1.55, fontSize: 13.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('以后再说'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('去开通会员', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    Navigator.of(context).pushNamed('/member-center');
  }
  return false;
}
