import 'dart:convert';

import 'package:intl/intl.dart';

import 'badge.dart';

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
  final int authorVip; // 作者会员等级（0=普通，头像会员框用）

  /// 渔获页「钓到了什么」：[{'name':'鲫鱼','count':2}]（其他类别为空）
  final List<Map<String, dynamic>> fish;

  /// 作者已获得的徽章（信息流里显示在头像后面，最多 3 枚）
  /// 不走动态列表接口，而是由 BadgeHub 按作者 id 批量拉取后回填，
  /// 这样一屏只多一次请求，不会每张卡片各发一次。
  final List<BadgeItem> badges;

  /// 钓点位置是否公开（false 时其他人看不到具体钓点）
  final bool locPublic;

  /// 渔获尺寸：体长（厘米）/ 重量（克）。AI 视觉估算或用户手填，null=未记录。
  /// 驱动「池塘按真实尺寸 ×10 缩放」与「点击鱼显示尺寸/时间/钓点」。
  final double? lengthCm;
  final double? weightG;

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
    this.authorVip = 0,
    this.fish = const [],
    this.locPublic = true,
    this.lengthCm,
    this.weightG,
    this.badges = const [],
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
      authorVip: (json['user_vip'] as num?)?.toInt() ?? 0,
      fish: parseFish(json['fish']),
      locPublic: json['loc_public'] == null
          ? true
          : (json['loc_public'] is bool
              ? json['loc_public'] as bool
              : (json['loc_public'] as num?)?.toInt() != 0),
      lengthCm: (json['length_cm'] as num?)?.toDouble(),
      weightG: (json['weight_g'] as num?)?.toDouble(),
      badges: parseBadges(json['badges']),
    );
  }

  /// 徽章字段（后端可能直接返回数组，也可能给 JSON 字符串）
  static List<BadgeItem> parseBadges(dynamic raw) {
    if (raw == null) return const [];
    var list = raw;
    if (list is String && list.trim().isNotEmpty) {
      try {
        list = jsonDecode(list);
      } catch (_) {
        return const [];
      }
    }
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => BadgeItem.fromJson(Map<String, dynamic>.from(m)))
        .where((b) => b.name.isNotEmpty || b.icon.isNotEmpty)
        .toList();
  }

  /// 鱼种字段：后端存 JSON 字符串（也兼容已解析的数组）
  static List<Map<String, dynamic>> parseFish(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is List) {
          return v
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  /// 是否视频动态
  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// 是否渔获动态（标题固定为「今日鱼获分享」，鱼种与条数单独一行）
  bool get isCatch => category == 'post';

  /// 展示用标题：渔获统一用固定文案（后台「积分设置」里可改），其余用原标题
  /// 老数据里渔获标题是「鲫鱼×1 · 鲤鱼×1」，这里一并兜住，保证首页/详情页一致
  String get displayTitle => isCatch ? _catchTitle : title;

  /// 渔获标题文案（与后端 catch_title_text() 保持一致）
  static const String _catchTitle = '今日鱼获分享';

  /// 渔获摘要：「鲫鱼 2 条 · 鲤鱼 1 条」（首页卡片、详情页都用它）
  String get catchSummary {
    if (fish.isEmpty) return '';
    final parts = <String>[];
    for (final f in fish) {
      final name = (f['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final n = (f['count'] as num?)?.toInt() ?? 1;
      parts.add('$name ${n <= 0 ? 1 : n} 条');
    }
    return parts.join(' · ');
  }

  /// 渔获总条数
  int get catchTotal {
    var total = 0;
    for (final f in fish) {
      final n = (f['count'] as num?)?.toInt() ?? 0;
      total += n <= 0 ? 1 : n;
    }
    return total;
  }

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
    int? authorVip,
    List<Map<String, dynamic>>? fish,
    bool? locPublic,
    double? lengthCm,
    double? weightG,
    List<BadgeItem>? badges,
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
      authorVip: authorVip ?? this.authorVip,
      fish: fish ?? this.fish,
      locPublic: locPublic ?? this.locPublic,
      lengthCm: lengthCm ?? this.lengthCm,
      weightG: weightG ?? this.weightG,
      badges: badges ?? this.badges,
    );
  }
}
