import 'package:intl/intl.dart';

/// 动态/渔获发布 数据模型
/// 对应 posts 表，并通过外联 users 取到作者昵称与头像
///
/// category 发布类别：
///   post=渔获动态  ask=钓鱼问答  say=随便说说  sell=出售二手  buy=求购二手
/// price 仅二手类别使用：出售=售价，求购=预算
class Post {
  final String id;
  final String userId;
  final String? username;
  final String? avatarUrl;
  final String title;
  final String? body;
  final List<String> imageUrls;
  final String? videoUrl; // 视频动态：视频地址（与 imageUrls 二选一）
  final String category; // post / ask / say / sell / buy
  final String price; // 二手价格（其他类别为空串）
  final String? locationName;
  final double? lat;
  final double? lng;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final int viewCount; // 浏览人数（热门/推荐算法依据）
  final String city; // 发布时定位的地级市（同城过滤）
  final bool likedByMe; // 当前用户是否已点赞（前端高亮用）
  final int userLevel; // 作者等级（LV1–LV30，后端按经验值换算）
  final bool isFollowing; // 我是否已关注作者
  final bool isMe; // 作者是不是我自己

  static const Map<String, String> categoryLabels = {
    'post': '渔获',
    'ask': '问答',
    'say': '说说',
    'sell': '出售',
    'buy': '求购',
  };

  const Post({
    required this.id,
    required this.userId,
    this.username,
    this.avatarUrl,
    required this.title,
    this.body,
    this.imageUrls = const [],
    this.videoUrl,
    this.category = 'post',
    this.price = '',
    this.locationName,
    this.lat,
    this.lng,
    required this.createdAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.city = '',
    this.likedByMe = false,
    this.userLevel = 1,
    this.isFollowing = false,
    this.isMe = false,
  });

  /// 把 Supabase 返回的 JSON 转成 Post
  /// 注意：profiles 是嵌套对象，需要单独取字段
  factory Post.fromJson(Map<String, dynamic> json, {bool likedByMe = false}) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final images = json['image_urls'];
    return Post(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: profile?['username'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
      title: json['title'] as String? ?? '无标题',
      body: json['body'] as String?,
      imageUrls: images == null
          ? const []
          : List<String>.from(images as List),
      videoUrl: (json['video'] ?? json['video_url']) as String?,
      category: (json['category'] as String?)?.isNotEmpty == true
          ? json['category'] as String
          : 'post',
      price: (json['price'] as String?) ?? '',
      locationName: json['location_name'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      city: (json['city'] ?? '').toString(),
      likedByMe: likedByMe,
      userLevel: (json['user_level'] as num?)?.toInt() ?? 1,
      isFollowing: json['is_following'] == true,
      isMe: json['is_me'] == true,
    );
  }

  /// 是否视频动态
  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// 是否二手类（出售/求购）
  bool get isTrade => category == 'sell' || category == 'buy';

  /// 类别中文名
  String get categoryLabel => categoryLabels[category] ?? '动态';

  /// 相对时间：刚刚 / 5分钟前 / 3小时前 / 日期
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return DateFormat('MM-dd HH:mm').format(createdAt);
  }

  /// 不可变更新副本（用于点赞状态/计数本地即时刷新）
  Post copyWith({
    String? id,
    String? userId,
    String? username,
    String? avatarUrl,
    String? title,
    String? body,
    List<String>? imageUrls,
    String? videoUrl,
    String? category,
    String? price,
    String? locationName,
    double? lat,
    double? lng,
    DateTime? createdAt,
    int? likeCount,
    int? commentCount,
    int? viewCount,
    String? city,
    bool? likedByMe,
    int? userLevel,
    bool? isFollowing,
    bool? isMe,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      title: title ?? this.title,
      body: body ?? this.body,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrl: videoUrl ?? this.videoUrl,
      category: category ?? this.category,
      price: price ?? this.price,
      locationName: locationName ?? this.locationName,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      city: city ?? this.city,
      likedByMe: likedByMe ?? this.likedByMe,
      userLevel: userLevel ?? this.userLevel,
      isFollowing: isFollowing ?? this.isFollowing,
      isMe: isMe ?? this.isMe,
    );
  }
}
