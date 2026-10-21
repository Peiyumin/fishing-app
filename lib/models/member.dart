import 'package:flutter/material.dart';

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
    this.color = const Color(0xFF90A4AE),
    this.color2 = const Color(0xFFCFD8DC),
    this.expire = '',
  });

  static const MemberStyle normal = MemberStyle();
  static const Color normalColor = Color(0xFF90A4AE);
  static const Color normalColor2 = Color(0xFFCFD8DC);

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
    final lv = (json['vipLevel'] as num?)?.toInt() ?? 0;
    if (lv <= 0) {
      return MemberStyle(expire: (json['vipExpire'] ?? '').toString());
    }
    return MemberStyle(
      level: lv,
      name: (json['vipName'] as String?)?.isNotEmpty == true
          ? json['vipName'] as String
          : '会员',
      color: parseColor(json['vipColor'], const Color(0xFFD9A22B)),
      color2: parseColor(json['vipColor2'], const Color(0xFFF7DE8B)),
      expire: (json['vipExpire'] ?? '').toString(),
    );
  }

  /// 只带等级数字（动态卡片等拿不到配色时用）
  factory MemberStyle.fromLevel(int level) {
    if (level <= 0) return MemberStyle.normal;
    const colors = [
      [Color(0xFFC08A5B), Color(0xFFE6C6A8)],
      [Color(0xFF8C9AA6), Color(0xFFD3DCE4)],
      [Color(0xFFD9A22B), Color(0xFFF7DE8B)],
      [Color(0xFF5B8FA8), Color(0xFFB6DBEA)],
      [Color(0xFF7B5BD6), Color(0xFFC5B4F5)],
      [Color(0xFFB23A48), Color(0xFFF0A8AE)],
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
