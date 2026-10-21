/// 「我的」页配置（对应后端 GET /profile/config，后台「我的页配置」可改）
///
/// 后端拿不到时用 [ProfilePageConfig.defaults]，保证任何情况下页面都有内容。
class ProfileItem {
  final String title;
  final String icon;
  final String action;

  const ProfileItem({
    required this.title,
    this.icon = 'star',
    this.action = 'none',
  });

  factory ProfileItem.fromJson(Map<String, dynamic> json) {
    return ProfileItem(
      title: (json['title'] ?? '').toString(),
      icon: (json['icon'] ?? 'star').toString(),
      action: (json['action'] ?? 'none').toString(),
    );
  }
}

class ProfileCardItem {
  final String title;
  final String desc;
  final String button;
  final String action;

  const ProfileCardItem({
    required this.title,
    this.desc = '',
    this.button = '去看看',
    this.action = 'none',
  });

  factory ProfileCardItem.fromJson(Map<String, dynamic> json) {
    return ProfileCardItem(
      title: (json['title'] ?? '').toString(),
      desc: (json['desc'] ?? '').toString(),
      button: (json['button'] ?? '去看看').toString(),
      action: (json['action'] ?? 'none').toString(),
    );
  }
}

class SmartBarConfig {
  final String title;
  final String desc;
  final String action;

  const SmartBarConfig({
    this.title = '智能服务',
    this.desc = 'AI 识鱼 · 逐时鱼口 · 出钓建议',
    this.action = 'ai',
  });

  factory SmartBarConfig.fromJson(Map<String, dynamic> json) {
    return SmartBarConfig(
      title: (json['title'] ?? '智能服务').toString(),
      desc: (json['desc'] ?? '').toString(),
      action: (json['action'] ?? 'ai').toString(),
    );
  }
}

class ProfilePageConfig {
  final List<ProfileItem> menus;
  final String servicesTitle;
  final List<ProfileItem> services;
  final SmartBarConfig smartBar;
  final List<ProfileCardItem> cards;
  final String memberBarText;

  const ProfilePageConfig({
    required this.menus,
    required this.servicesTitle,
    required this.services,
    required this.smartBar,
    required this.cards,
    required this.memberBarText,
  });

  static const ProfilePageConfig defaults = ProfilePageConfig(
    menus: [
      ProfileItem(title: '我的订单', icon: 'order', action: 'orders'),
      ProfileItem(title: '我的卡券', icon: 'coupon', action: 'coupons'),
    ],
    servicesTitle: '我的服务',
    services: [
      ProfileItem(title: '我的渔获', icon: 'fish', action: 'myPosts'),
      ProfileItem(title: '我的徽章', icon: 'medal', action: 'badges'),
      ProfileItem(title: '我的关注', icon: 'follow', action: 'following'),
      ProfileItem(title: '我的收藏', icon: 'heart', action: 'favorites'),
      ProfileItem(title: '帮助反馈', icon: 'help', action: 'help'),
    ],
    smartBar: SmartBarConfig(),
    cards: [
      ProfileCardItem(title: '附近钓点', desc: '按定位找最近的钓点', button: '去看看', action: 'spots'),
      ProfileCardItem(title: '我的活动', desc: '平台赛事与线下约钓', button: '更多活动', action: 'events'),
    ],
    memberBarText: '会员中心',
  );

  factory ProfilePageConfig.fromJson(Map<String, dynamic> json) {
    List<ProfileItem> items(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => ProfileItem.fromJson(Map<String, dynamic>.from(m)))
          .where((e) => e.title.isNotEmpty)
          .toList();
    }

    return ProfilePageConfig(
      menus: items(json['menus']).isEmpty
          ? defaults.menus
          : items(json['menus']),
      servicesTitle: (json['servicesTitle'] ?? defaults.servicesTitle).toString(),
      services: items(json['services']).isEmpty
          ? defaults.services
          : items(json['services']),
      smartBar: json['smartBar'] is Map
          ? SmartBarConfig.fromJson(
              Map<String, dynamic>.from(json['smartBar'] as Map))
          : defaults.smartBar,
      cards: (json['cards'] is List)
          ? (json['cards'] as List)
              .whereType<Map>()
              .map((m) =>
                  ProfileCardItem.fromJson(Map<String, dynamic>.from(m)))
              .where((e) => e.title.isNotEmpty)
              .toList()
          : defaults.cards,
      memberBarText:
          (json['memberBarText'] ?? defaults.memberBarText).toString(),
    );
  }
}
