import 'member.dart';

/// 会员套餐
class MemberPlan {
  final String id;
  final String name;
  final int days;
  final double price;
  final double originalPrice;
  final int pointsPrice;
  final String badge;

  const MemberPlan({
    required this.id,
    this.name = '',
    this.days = 30,
    this.price = 0,
    this.originalPrice = 0,
    this.pointsPrice = 0,
    this.badge = '',
  });

  bool get supportsPoints => pointsPrice > 0;
  bool get supportsBalance => price > 0;

  /// 月均价格（用于「折合 X 元/月」）
  double get perMonth => days > 0 ? price / (days / 30.0) : price;

  /// 相对原价省的百分比（0~99），无原价返回 0
  int get discountPct {
    if (originalPrice <= price || originalPrice <= 0) return 0;
    final d = ((1 - price / originalPrice) * 100).round();
    return d.clamp(0, 99);
  }

  factory MemberPlan.fromJson(Map<String, dynamic> j) => MemberPlan(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        days: (j['days'] as num?)?.toInt() ?? 30,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        originalPrice: (j['originalPrice'] as num?)?.toDouble() ?? 0,
        pointsPrice: (j['pointsPrice'] as num?)?.toInt() ?? 0,
        badge: (j['badge'] ?? '').toString(),
      );
}

/// 会员权益项
class MemberPerk {
  final String icon;
  final String title;
  final String desc;

  const MemberPerk({this.icon = 'vip', this.title = '', this.desc = ''});

  factory MemberPerk.fromJson(Map<String, dynamic> j) => MemberPerk(
        icon: (j['icon'] ?? 'vip').toString(),
        title: (j['title'] ?? '').toString(),
        desc: (j['desc'] ?? '').toString(),
      );
}

/// 会员中心文案配置
class MemberCenter {
  final String title;
  final String headline;
  final String subheadline;
  final String badgeText;
  final List<MemberPerk> perks;
  final List<String> agreements;

  const MemberCenter({
    this.title = '',
    this.headline = '',
    this.subheadline = '',
    this.badgeText = '',
    this.perks = const [],
    this.agreements = const [],
  });

  factory MemberCenter.fromJson(Map<String, dynamic> j) {
    final perks = (j['perks'] as List?) ?? const [];
    final ag = (j['agreements'] as List?) ?? const [];
    return MemberCenter(
      title: (j['title'] ?? '').toString(),
      headline: (j['headline'] ?? '').toString(),
      subheadline: (j['subheadline'] ?? '').toString(),
      badgeText: (j['badgeText'] ?? '').toString(),
      perks: perks
          .map((p) => MemberPerk.fromJson((p as Map).cast<String, dynamic>()))
          .toList(),
      agreements: ag.map((e) => e.toString()).toList(),
    );
  }
}

/// 当前会员状态
class MemberInfo {
  final bool active;
  final int level;
  final String expire;
  final int daysLeft;
  final int points;
  final double balance;
  final List<MemberPerk> perks;

  const MemberInfo({
    this.active = false,
    this.level = 0,
    this.expire = '',
    this.daysLeft = 0,
    this.points = 0,
    this.balance = 0,
    this.perks = const [],
  });

  factory MemberInfo.fromJson(Map<String, dynamic> j) {
    final perks = (j['perks'] as List?) ?? const [];
    return MemberInfo(
      active: (j['active'] as bool?) ?? false,
      level: (j['level'] as num?)?.toInt() ?? 0,
      expire: (j['expire'] ?? '').toString(),
      daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
      points: (j['points'] as num?)?.toInt() ?? 0,
      balance: (j['balance'] as num?)?.toDouble() ?? 0,
      perks: perks
          .map((p) => MemberPerk.fromJson((p as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  /// 本地会员样式（复用 v26 的等级配色体系）
  MemberStyle get style => MemberStyle.fromLevel(active ? level : 0);
}
