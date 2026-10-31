import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/member.dart';
import '../services/member_service.dart';
import '../services/session_provider.dart';

/// 会员门槛：当前用户不是会员时弹窗引导去开通会员，并返回 false（不继续）。
/// 已经是会员则直接返回 true（调用方可继续打开私信等会员专属功能）。
Future<bool> ensureMember(BuildContext context) async {
  return ensureMemberFeature(
    context,
    title: '开通会员',
    desc: '私信功能仅对会员开放，开通会员后即可与钓友畅聊。',
  );
}

/// 会员专属功能的统一闸门（v2.1.61）
///
/// 用法：进入会员功能前 `if (!await ensureMemberFeature(...)) return;`
///
/// ★ 为什么不用「各自弹各自的框」：
///   到 2.1.60 为止，私信、AI 分析、钱包各写了一份 AlertDialog，
///   文案、按钮、圆角都不一样。这里收成一处，样式跟着全站走。
///
/// ★ 买完要**同步会员状态**（这是关键）：
///   会员中心下单成功后只刷新它自己的 `_info`，并不回写 [SessionProvider]。
///   不补这一步的话，用户付完钱返回来看还是「未开通」，得杀掉 App 重开 ——
///   天气 7 天、附近钓友这种「实时按会员身份放行」的页面必然会撞上。
Future<bool> ensureMemberFeature(
  BuildContext context, {
  required String title,
  required String desc,
  String confirmLabel = '去开通会员',
}) async {
  final session = Provider.of<SessionProvider>(context, listen: false);
  if (session.isMember) return true;

  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      title: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppTheme.accentLight,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.workspace_premium_outlined,
                size: 16, color: AppTheme.accentDark),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ),
        ],
      ),
      content: Text(desc,
          style: const TextStyle(
              fontSize: 13, height: 1.55, color: AppTheme.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('以后再说',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  if (go != true || !context.mounted) return false;
  await Navigator.of(context).pushNamed('/member-center');
  if (!context.mounted) return false;

  // 买完回来：把会员等级/到期写回全局会话，页面据此立刻放行
  return syncMembership(session);
}

/// 从后端拉一次会员信息并写回会话；返回「现在是不是会员」
Future<bool> syncMembership(SessionProvider session) async {
  if (!session.isLoggedIn) return false;
  try {
    final info = await MemberService.info();
    if (!info.active) return false;
    final style = MemberStyle.fromLevel(info.level);
    await session.markMember(
      level: info.level,
      name: style.name,
      expire: info.expire,
    );
    return true;
  } catch (_) {
    // 后端没这个接口 / 断网：保持原有状态，不要把已开通的用户降级
    return session.isMember;
  }
}
