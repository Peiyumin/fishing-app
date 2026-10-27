/// 钓点 数据模型
///
/// kind 类型：
///   venue=本地钓场（后台审核后展示，带封面/星级/收费等信息）
///   wild =野钓点（用户在卫星地图上标记，保存后实时展示）
///   shop =渔具店（后台审核后展示）
/// status 审核状态：0=待审核 1=通过 2=已拒绝（API 只返回 status=1）
class FishingSpot {
  final String id;
  final String name;
  final String type; // 野钓 / 路亚 / 黑坑 / 海钓…
  final String kind; // venue / wild / shop
  final int status; // 0 待审核 / 1 通过 / 2 拒绝
  final double lat;
  final double lng;
  final double rating; // 评分 0-5
  final String description;
  final String? coverUrl; // 封面图（钓场/渔具店）
  final List<String> imageUrls; // 环境展示图（钓点详情页顶部图集，最多 9 张）
  final String address; // 详细地址
  final String fee; // 收费说明（如：正钓 200/4h）
  final String fish; // 主要鱼种
  final String tags; // 标签（推荐/黑坑/电话认证…）
  final String phone; // 联系电话

  /// 渔具店是否支持外送（其他类型恒 false）
  final bool delivery;
  final int reportCount; // 被报错次数
  final bool verified; // 是否官方核实
  final int commentCount; // 评论数（钓场）

  const FishingSpot({
    required this.id,
    required this.name,
    required this.type,
    this.kind = 'wild',
    this.status = 1,
    required this.lat,
    required this.lng,
    required this.rating,
    required this.description,
    this.coverUrl,
    this.imageUrls = const [],
    this.address = '',
    this.fee = '',
    this.fish = '',
    this.tags = '',
    this.phone = '',
    this.delivery = false,
    this.reportCount = 0,
    this.verified = false,
    this.commentCount = 0,
  });

  /// 类型中文名
  String get kindLabel =>
      kind == 'venue' ? '本地钓场' : (kind == 'shop' ? '渔具店' : '野钓点');

  /// 是否钓场类（列表卡片样式展示）
  bool get isVenue => kind == 'venue';

  /// 不可变更新副本（用于点赞/报错数本地即时刷新）
  FishingSpot copyWith({
    String? id,
    String? name,
    String? type,
    String? kind,
    int? status,
    double? lat,
    double? lng,
    double? rating,
    String? description,
    String? coverUrl,
    List<String>? imageUrls,
    String? address,
    String? fee,
    String? fish,
    String? tags,
    String? phone,
    bool? delivery,
    int? reportCount,
    bool? verified,
    int? commentCount,
  }) {
    return FishingSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      rating: rating ?? this.rating,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      address: address ?? this.address,
      fee: fee ?? this.fee,
      fish: fish ?? this.fish,
      tags: tags ?? this.tags,
      phone: phone ?? this.phone,
      delivery: delivery ?? this.delivery,
      reportCount: reportCount ?? this.reportCount,
      verified: verified ?? this.verified,
      commentCount: commentCount ?? this.commentCount,
    );
  }
}

/// 内置示例钓点（覆盖多城市坐标，仅演示）
/// venue=钓场（带星级/收费/电话等完整信息），wild=野钓点
List<FishingSpot> demoSpots = [
  // —— 本地钓场（演示数据带完整信息）——
  const FishingSpot(
    id: 's2',
    name: '西溪路亚基地',
    type: '路亚',
    kind: 'venue',
    lat: 30.276,
    lng: 120.083,
    rating: 4.3,
    description: '城市近郊路亚塘，鲈鱼、鳜鱼活跃，环境好。',
    coverUrl: 'https://picsum.photos/seed/venue1/600/400',
    address: '杭州市西湖区西溪湿地洪园景区南门',
    fee: '门票 120 元/天，含 4 小时',
    fish: '鲈鱼、鳜鱼、翘嘴',
    tags: '推荐,路亚,电话认证',
    phone: '0571-88886666',
    commentCount: 36,
    verified: true,
  ),
  const FishingSpot(
    id: 's3',
    name: '青山湖黑坑',
    type: '黑坑',
    kind: 'venue',
    lat: 30.237,
    lng: 119.723,
    rating: 4.0,
    description: '放钓黑坑，密度高，竞技手感好，回鱼规则透明。',
    coverUrl: 'https://picsum.photos/seed/venue2/600/400',
    address: '杭州市临安区青山湖畔绿道 3 号入口',
    fee: '正钓 200 元/4h，偷驴 100 元',
    fish: '鲫鱼、鲤鱼、草鱼',
    tags: '黑坑,密度高',
    phone: '13800002222',
    commentCount: 21,
  ),
  const FishingSpot(
    id: 's6',
    name: '金海湖路亚场',
    type: '路亚',
    kind: 'venue',
    lat: 40.330,
    lng: 117.120,
    rating: 4.5,
    description: '北京近郊水库，翘嘴、鳡鱼活跃，风景好。',
    coverUrl: 'https://picsum.photos/seed/venue3/600/400',
    address: '北京市平谷区金海湖镇环湖路',
    fee: '120 元/天，船钓另计',
    fish: '翘嘴、鳡鱼、鲈鱼',
    tags: '推荐,路亚,大水面',
    phone: '010-6688888',
    commentCount: 52,
    verified: true,
  ),
  const FishingSpot(
    id: 's10',
    name: '太湖湾黑坑塘',
    type: '黑坑',
    kind: 'venue',
    lat: 31.430,
    lng: 120.180,
    rating: 3.9,
    description: '无锡竞技黑坑，正钓偷驴都有，塘规透明。',
    coverUrl: 'https://picsum.photos/seed/venue4/600/400',
    address: '无锡市滨湖区太湖湾环湖公路',
    fee: '正钓 300 元/5h',
    fish: '鲫鱼、鲤鱼、青鱼',
    tags: '黑坑,竞技',
    phone: '0510-8899999',
    commentCount: 14,
  ),
  // —— 野钓点（演示数据）——
  const FishingSpot(
    id: 's1',
    name: '千岛湖中心渔场',
    type: '野钓',
    kind: 'wild',
    lat: 29.605,
    lng: 119.048,
    rating: 4.6,
    description: '水面开阔，鲫鲤草鱼多，适合长竿守钓。',
    verified: true,
  ),
  const FishingSpot(
    id: 's4',
    name: '富春江野钓点',
    type: '野钓',
    kind: 'wild',
    lat: 29.954,
    lng: 119.959,
    rating: 4.4,
    description: '江河走水，鳊鱼、黄尾多，注意安全。',
  ),
  const FishingSpot(
    id: 's5',
    name: '东湖绿道野钓区',
    type: '野钓',
    kind: 'wild',
    lat: 30.560,
    lng: 114.305,
    rating: 4.2,
    description: '武汉城中湖，周末休闲钓，鲫鱼白条不断。',
  ),
  const FishingSpot(
    id: 's7',
    name: '三岔湖钓点',
    type: '野钓',
    kind: 'wild',
    lat: 30.380,
    lng: 104.250,
    rating: 4.1,
    description: '成都最大人工湖，鲢鳙鲤鱼多，钓位充足。',
  ),
  const FishingSpot(
    id: 's8',
    name: '流溪河野钓段',
    type: '野钓',
    kind: 'wild',
    lat: 23.570,
    lng: 113.630,
    rating: 4.0,
    description: '广州近郊溪流，罗非、鲮鱼好钓，夏季尤佳。',
  ),
  const FishingSpot(
    id: 's9',
    name: '淀山湖翘嘴基地',
    type: '野钓',
    kind: 'wild',
    lat: 31.120,
    lng: 121.020,
    rating: 4.4,
    description: '上海周边大水面，翘嘴、青稍爆发期手感炸裂。',
  ),
];
