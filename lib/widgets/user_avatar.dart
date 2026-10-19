import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/session_provider.dart';
import 'package:provider/provider.dart';

/// 统一的圆形头像
///
/// 三件事保证「头像不会莫名其妙不显示」：
///  1. 自己是当前登录用户时，直接读全局登录态里的头像 —— 编辑资料后立刻刷新，
///     不再受信息流里那条动态的旧头像快照影响；
///  2. 图片加载中显示底色，加载失败退回人像占位，不会留下一个空白圆圈；
///  3. 头像只有几十像素，统一按 3 倍像素解码，省内存也更快。
class UserAvatar extends StatelessWidget {
  final String? url;
  final String? userId;
  final double radius;

  const UserAvatar({
    super.key,
    required this.url,
    this.userId,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    // 自己的头像以登录态为准（登录态不存在时降级用传入的 url）
    String? src = url;
    try {
      final session = context.watch<SessionProvider>();
      if (session.isLoggedIn &&
          userId != null &&
          userId!.isNotEmpty &&
          session.userId == userId) {
        src = session.avatarUrl ?? url;
      }
    } catch (_) {
      // 没有 Provider 的场景（预览/测试）直接用传入地址
    }

    final size = radius * 2;
    final hasImage = src != null && src.isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.border, width: 1.2),
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: src!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                memCacheWidth: (size * 3).round(),
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (_, __) =>
                    Container(color: AppTheme.primarySoft),
                errorWidget: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
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
