import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 官方账号标识（v39）
///
/// 用户在后台把账号设为「官方」后，App 端要能一眼认出来 —— 官方发的公告
/// 代表平台，不能和普通钓友的帖子长得一样。三件东西共用同一套配色：
///
///   · [OfficialBadge]    昵称后面的金色「官方」小胶囊（信息流 / 详情 / 评论）
///   · [OfficialAvatarGlyph] 官方账号没上传头像时的内置头像（金色圆 + 对勾）
///   · [OfficialAvatarMark]  官方账号有自己的头像时，右下角的金色小角标
///
/// 配色全部走 AppTheme 的琥珀系（star / starLight / starDark）：
/// 金色是「认证」的通用语义，而且和主题的 accent 黄绿、water 蓝都不撞，
/// 不会和会员框、LV 角标混成一片。
class OfficialBadge extends StatelessWidget {
  /// 胶囊高度（字高、圆角、图标都按它等比算，18px 小卡片到 22px 详情页共用一份）
  final double height;

  /// 只画金色对勾、不写「官方」二字 —— 双列瀑布流那种窄卡片用，
  /// 昵称 + LV 已经占满一行，再塞一个带字的胶囊会把名字挤没。
  final bool iconOnly;

  const OfficialBadge({super.key, this.height = 15, this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    final h = height;
    if (iconOnly) {
      return Semantics(
        label: '官方账号',
        child: Icon(Icons.verified, size: h, color: AppTheme.star),
      );
    }
    return Semantics(
      label: '官方账号',
      child: Container(
        height: h,
        padding: EdgeInsets.symmetric(horizontal: h * 0.34),
        decoration: BoxDecoration(
          color: AppTheme.star,
          borderRadius: BorderRadius.circular(h * 0.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: h * 0.64, color: AppTheme.primary),
            SizedBox(width: h * 0.14),
            Text(
              '官方',
              style: TextStyle(
                fontSize: h * 0.62,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 官方账号的默认头像（没上传头像时用，金色圆底 + 白色认证对勾）
class OfficialAvatarGlyph extends StatelessWidget {
  final double size;

  const OfficialAvatarGlyph({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.star, AppTheme.starDark],
        ),
      ),
      child: Icon(Icons.verified, size: size * 0.58, color: Colors.white),
    );
  }
}

/// 官方账号已有自定义头像时，右下角的小角标（和会员皇冠同位置，官方优先）
class OfficialAvatarMark extends StatelessWidget {
  final double size;

  const OfficialAvatarMark({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.star,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Icon(Icons.check, size: size * 0.66, color: AppTheme.primary),
    );
  }
}
