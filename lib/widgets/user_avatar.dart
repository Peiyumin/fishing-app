import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/member.dart';
import '../services/session_provider.dart';
import 'package:provider/provider.dart';

/// 统一的圆形头像（带会员等级框）
///
/// 三件事保证「头像不会莫名其妙不显示」：
///  1. 自己是当前登录用户时，直接读全局登录态里的头像与会员等级 —— 编辑资料、
///     购买会员后立即同步，不再受信息流 / 评论里那条动态的旧头像与旧会员框影响；
///  2. 图片加载中显示底色，加载失败退回人像占位，不会留下一个空白圆圈；
///  3. 头像只有几十像素，统一按 3 倍像素解码，省内存也更快。
///
/// 会员：传 [vipLevel]（或 [member] 拿到后台配置的配色）时自动套上渐变会员框 +
/// 右下角皇冠角标；level 0 不显示，普通用户观感与原来完全一致。
class UserAvatar extends StatelessWidget {
  final String? url;
  final String? userId;
  final double radius;

  /// 会员等级（0 / null = 普通用户，不显示会员框）
  final int? vipLevel;

  /// 完整会员样式（后台下发的名称与配色，优先级高于 vipLevel）
  final MemberStyle? member;

  const UserAvatar({
    super.key,
    required this.url,
    this.userId,
    this.radius = 16,
    this.vipLevel,
    this.member,
  });

  @override
  Widget build(BuildContext context) {
    // 自己的头像以登录态为准（登录态不存在时降级用传入的 url）
    String? src = url;
    MemberStyle effectiveMember = member ?? MemberStyle.fromLevel(vipLevel ?? 0);
    try {
      final session = context.watch<SessionProvider>();
      if (session.isLoggedIn &&
          userId != null &&
          userId!.isNotEmpty &&
          session.userId == userId) {
        src = session.avatarUrl ?? url;
        // 自己的会员框一律以登录态为准：编辑资料 / 购买会员后立即同步，
        // 不再受信息流 / 评论里那条动态的旧等级快照影响（忽略传入的 vipLevel）
        effectiveMember = session.vip;
      }
    } catch (_) {
      // 没有 Provider 的场景（预览/测试）直接用传入地址
    }

    final style = effectiveMember;
    final isVip = style.isVip;
    final size = radius * 2;

    final core = ClipOval(child: _content(src, size));

    if (!isVip) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border, width: 1.2),
        ),
        child: core,
      );
    }

    // 会员框：外圈渐变 + 内白边 + 头像，右下角一颗小皇冠
    final crown = (radius * 0.62).clamp(12.0, 18.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(2.2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [style.color, style.color2],
              ),
              boxShadow: [
                BoxShadow(
                  color: style.color.withOpacity(0.35),
                  blurRadius: 6,
                  spreadRadius: 0.4,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(1.6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: core,
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: crown,
              height: crown,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [style.color, style.color2],
                ),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Icon(
                Icons.workspace_premium,
                size: crown * 0.66,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(String? src, double size) {
    final hasImage = src != null && src.isNotEmpty;
    if (!hasImage) return _fallback();
    return CachedNetworkImage(
      imageUrl: src,
      fit: BoxFit.cover,
      width: size,
      height: size,
      memCacheWidth: (size * 3).round(),
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => Container(color: AppTheme.primarySoft),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() => Container(
        color: AppTheme.primarySoft,
        child: Icon(
          Icons.person,
          size: radius * 1.1,
          color: AppTheme.textSecondary,
        ),
      );
}
