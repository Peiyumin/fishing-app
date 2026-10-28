import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth_screen.dart';
import '../services/session_provider.dart';

/// 未登录时的统一拦截（v2.1.48）
///
/// 需求：「没有登录的用户不管点什么内容都弹出登录页」。
/// 以前各页面是自己 `CenterToast.show('请先登录')`，一行小字一闪而过，
/// 用户不知道该去哪登录；而且每个页面的文案、行为都不一样。
///
/// 现在统一走这里：**弹出与启动时完全同一套登录页**（深色设计稿那版），
/// 登录成功后返回 true，调用方接着做原本要做的事 —— 用户不用再点一次。
///
/// 用法：
/// ```dart
/// if (!await ensureLogin(context, hint: '登录后可以收藏钓点')) return;
/// Navigator.push(...);
/// ```
///
/// ★ 一定用 `rootNavigator: true`：部分页面在 TabBarView / 嵌套 Navigator 里，
///   用局部 Navigator 弹出来的登录页会被底部导航盖住一半。
Future<bool> ensureLogin(BuildContext context, {String? hint}) async {
  final sp = context.read<SessionProvider>();
  if (sp.isLoggedIn) return true;
  final nav = Navigator.of(context, rootNavigator: true);
  final ok = await nav.push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AuthScreen(hint: hint, barrier: true),
  ));
  // 页面已经不在树上时只按登录态判断
  if (!context.mounted) return sp.isLoggedIn;
  return ok == true || sp.isLoggedIn;
}

/// 不关心结果时用这个（例如只是弹一下让人去登录）
Future<void> promptLogin(BuildContext context, {String? hint}) async {
  await ensureLogin(context, hint: hint);
}
