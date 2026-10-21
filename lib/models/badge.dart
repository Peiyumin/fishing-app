/// 徽章（对应后端 badges 表）
///
/// 名称、图标、颜色、达成条件全部由后台「运营配置 → 徽章管理」配置：
///   icon 可以是上传的图片地址（/uploads/badges/x.png），也可以是 emoji（🎣）
///   condition: posts 发布总数 / catches 渔获次数 / points 积分余额 / likes 累计获赞
class BadgeItem {
  final String id;
  final String name;
  final String icon;
  final String color;
  final String condition;
  final int threshold;

  const BadgeItem({
    required this.id,
    required this.name,
    this.icon = '',
    this.color = '',
    this.condition = 'posts',
    this.threshold = 0,
  });

  factory BadgeItem.fromJson(Map<String, dynamic> json) {
    return BadgeItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      condition: (json['condition'] ?? 'posts').toString(),
      threshold: (json['threshold'] as num?)?.toInt() ?? 0,
    );
  }

  /// 图标是不是图片地址（http/https 或站内 /uploads）
  bool get isImage =>
      icon.startsWith('http://') || icon.startsWith('https://') || icon.startsWith('/');

  /// 达成条件说明，如「渔获次数 ≥ 10」
  String get conditionText {
    const labels = {
      'posts': '发布总数',
      'catches': '渔获次数',
      'points': '积分余额',
      'likes': '累计获赞',
    };
    return '${labels[condition] ?? '达成条件'} ≥ $threshold';
  }

  String get shortLabel => name.isEmpty ? '徽章' : name;
}
