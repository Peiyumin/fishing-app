/// 首页装修数据（v46）
///
/// 三者都由后台配置、App 只负责渲染：
///   · 首页宫格导航（名字 / 图标 / 跳转 / 顺序 / 显示与否）
///   · 宫格一行显示几个（4 或 5）
///   · 首页广告位（横幅图 + 详情正文 + 可选外链）
///
/// ★ [HomeLayout.fallback] 是**内置兜底**：后端没配、断网、接口 404 时都用它，
///   保证首页永远是原来那 10 个入口，而不是一个空宫格。
library;

class HomeCategory {
  final String id;
  final String name;

  /// 内置图标 key（见 `lib/utils/home_icons.dart`）
  final String icon;

  /// 后台传的自定义图标地址（有就优先用它）
  final String? iconUrl;

  /// builtin = 跳 App 内页面；none = 不跳转
  final String action;

  /// [action] 为 builtin 时是页面 tag（spot / catch / shop…）
  final String value;

  const HomeCategory({
    required this.id,
    required this.name,
    this.icon = '',
    this.iconUrl,
    this.action = 'builtin',
    this.value = '',
  });

  factory HomeCategory.fromJson(Map<String, dynamic> j) {
    final url = (j['icon_url'] ?? '').toString().trim();
    return HomeCategory(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      icon: (j['icon'] ?? '').toString(),
      iconUrl: url.isEmpty ? null : url,
      action: (j['action'] ?? 'builtin').toString(),
      value: (j['value'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'icon_url': iconUrl,
        'action': action,
        'value': value,
      };
}

class HomeAd {
  final String id;
  final String title;
  final String image;

  /// 详情页正文（后台手填，换行原样保留）
  final String content;

  /// 可选外链：详情页底部出现「打开链接」
  final String? link;

  const HomeAd({
    required this.id,
    required this.title,
    required this.image,
    this.content = '',
    this.link,
  });

  factory HomeAd.fromJson(Map<String, dynamic> j) {
    final link = (j['link'] ?? '').toString().trim();
    return HomeAd(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      image: (j['image'] ?? '').toString(),
      content: (j['content'] ?? '').toString(),
      link: link.isEmpty ? null : link,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'image': image,
        'content': content,
        'link': link,
      };
}

class HomeLayout {
  /// 一行显示几个（只可能是 4 或 5）
  final int gridCols;
  final List<HomeCategory> categories;
  final List<HomeAd> ads;

  const HomeLayout({
    required this.gridCols,
    required this.categories,
    required this.ads,
  });

  /// 后台没配 / 拉不到接口时的兜底：和改版前首页那 10 个入口完全一致
  static const HomeLayout fallback = HomeLayout(
    gridCols: 5,
    categories: [
      HomeCategory(id: 'f-weather', name: '天气', icon: 'weather', value: 'weather'),
      HomeCategory(id: 'f-spot', name: '钓点', icon: 'spot', value: 'spot'),
      HomeCategory(id: 'f-catch', name: '渔获', icon: 'catch', value: 'catch'),
      HomeCategory(id: 'f-lure', name: '路亚', icon: 'lure', value: 'lure'),
      HomeCategory(id: 'f-blackpit', name: '黑坑', icon: 'blackpit', value: 'blackpit'),
      HomeCategory(id: 'f-gear', name: '装备', icon: 'gear', value: 'gear'),
      HomeCategory(id: 'f-skill', name: '技巧', icon: 'skill', value: 'skill'),
      HomeCategory(id: 'f-event', name: '活动', icon: 'event', value: 'event'),
      HomeCategory(id: 'f-shop', name: '商城', icon: 'shop', value: 'shop'),
      HomeCategory(id: 'f-live', name: '直播', icon: 'live', value: 'live'),
    ],
    ads: [],
  );

  factory HomeLayout.fromJson(Map<String, dynamic> j) {
    final cols = (j['grid_cols'] is num)
        ? (j['grid_cols'] as num).toInt()
        : int.tryParse((j['grid_cols'] ?? '').toString()) ?? 5;
    final cats = <HomeCategory>[];
    final rawCats = j['categories'];
    if (rawCats is List) {
      for (final c in rawCats) {
        if (c is Map) {
          final cat = HomeCategory.fromJson(Map<String, dynamic>.from(c));
          if (cat.name.trim().isNotEmpty) cats.add(cat);
        }
      }
    }
    final ads = <HomeAd>[];
    final rawAds = j['ads'];
    if (rawAds is List) {
      for (final a in rawAds) {
        if (a is Map) {
          final ad = HomeAd.fromJson(Map<String, dynamic>.from(a));
          if (ad.image.trim().isNotEmpty) ads.add(ad);
        }
      }
    }
    return HomeLayout(
      gridCols: (cols == 4 || cols == 5) ? cols : 5,
      categories: cats.isEmpty ? fallback.categories : cats,
      ads: ads,
    );
  }

  Map<String, dynamic> toJson() => {
        'grid_cols': gridCols,
        'categories': categories.map((c) => c.toJson()).toList(),
        'ads': ads.map((a) => a.toJson()).toList(),
      };

  /// 首页只展示第一条在投广告（后台按 sort 排好了）
  HomeAd? get topAd => ads.isEmpty ? null : ads.first;
}
