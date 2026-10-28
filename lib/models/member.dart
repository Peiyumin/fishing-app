import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/json_num.dart';

/// 会员等级样式（对应后端 lib/member.php 的等级配置）
///
/// level 0 = 普通用户（不显示会员框），1~6 = 会员等级。
/// 名称与配色都由后台「会员设置」控制，App 只负责渲染。
class MemberStyle {
  final int level;
  final String name;
  final Color color;
  final Color color2;
  final String expire;

  const MemberStyle({
    this.level = 0,
    this.name = '普通用户',
    this.color = AppTheme.textTertiary,
    this.color2 = AppTheme.primaryBorder,
    this.expire = '',
  });

  static const MemberStyle normal = MemberStyle();
  static const Color normalColor = AppTheme.textTertiary;
  static const Color normalColor2 = AppTheme.primaryBorder;

  bool get isVip => level > 0;

  /// 「Lv3」
  String get levelLabel => 'Lv$level';

  /// 后台下发的 #RRGGBB → Color（非法值回退）
  static Color parseColor(dynamic raw, Color fallback) {
    if (raw is! String) return fallback;
    final s = raw.trim().replaceFirst('#', '');
    if (s.length != 6) return fallback;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 | v);
  }

  factory MemberStyle.fromJson(Map<String, dynamic> json) {
    final lv = jsonInt(json['vipLevel']) ?? 0;
    if (lv <= 0) {
      return MemberStyle(expire: (json['vipExpire'] ?? '').toString());
    }
    return MemberStyle(
      level: lv,
      name: (json['vipName'] as String?)?.isNotEmpty == true
          ? json['vipName'] as String
          : '会员',
      color: parseColor(json['vipColor'], AppTheme.starDark),
      color2: parseColor(json['vipColor2'], AppTheme.star),
      expire: (json['vipExpire'] ?? '').toString(),
    );
  }

  /// 只带等级数字（动态卡片等拿不到配色时用）
  ///
  /// ★ v2.1.36 配色统一：原来 6 档是「铜/银/金/钢蓝/紫/玫红」六种色相，
  ///   一进个人页就是一条小彩虹，跟「近黑 + 冷灰 + 荧光黄绿」的体系完全无关。
  ///   现在按「明度递进 + 只有最高档给荧光黄绿」重排：
  ///   灰 → 深灰 → 暖金（黄金就该是金）→ 石墨 → 近黑 → 荧光黄绿，
  ///   一眼能看出等级高低，又不破坏色板。
  factory MemberStyle.fromLevel(int level) {
    if (level <= 0) return MemberStyle.normal;
    final colors = [
      [AppTheme.textTertiary, AppTheme.primaryBorder], // 青铜：浅灰
      [AppTheme.textSecondary, AppTheme.primaryBorder], // 白银：冷灰
      [AppTheme.starDark, AppTheme.star], // 黄金：暖金
      [AppTheme.violet, AppTheme.primaryBorder], // 铂金：石墨
      [AppTheme.primary, AppTheme.violet], // 钻石：近黑
      [AppTheme.accentDark, AppTheme.accent], // 至尊：荧光黄绿
    ];
    final i = (level - 1).clamp(0, colors.length - 1);
    const names = ['青铜会员', '白银会员', '黄金会员', '铂金会员', '钻石会员', '至尊会员'];
    return MemberStyle(
      level: level.clamp(1, 6),
      name: names[i],
      color: colors[i][0],
      color2: colors[i][1],
    );
  }
}
