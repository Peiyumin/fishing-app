import '../models/badge.dart';
import '../models/member.dart';
import '../services/api_config.dart';

/// 用户公开资料（关注/粉丝 / 我的页 / 会员 / 徽章）
/// 对应后端 /users/me 与 /users/:id 返回结构
class UserProfile {
  final String id;
  final String nickname;
  final String? avatar;
  final String bio; // 个人签名
  final int followerCount;
  final int followingCount;
  final int postCount;
  final bool isFollowing; // 当前登录用户是否已关注 TA
  final bool isMe; // 是否是当前登录用户本人
  final int points; // 积分余额（发布渔获等行为获得，后台可配置名称）
  final String pointsName; // 积分在 App 内的名称（如：积分 / 鱼币）
  final int likeCount; // 累计获赞（我的页「喜欢」）
  final int level; // 等级（exp 换算的 LV1~LV30）
  final int catchCount; // 发布渔获次数
  final MemberStyle vip; // 会员等级（等级 0 = 普通用户）
  final List<BadgeItem> badges; // 已获得的徽章

  const UserProfile({
    required this.id,
    required this.nickname,
    this.avatar,
    this.bio = '',
    this.followerCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
    this.isFollowing = false,
    this.isMe = false,
    this.points = 0,
    this.pointsName = '积分',
    this.likeCount = 0,
    this.level = 1,
    this.catchCount = 0,
    this.vip = MemberStyle.normal,
    this.badges = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nickname: (json['nickname'] as String?) ?? '钓友',
      avatar: ApiConfig.mediaUrl(json['avatar'] as String?),
      bio: (json['bio'] ?? '').toString(),
      followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
      followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
      postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      isFollowing: (json['isFollowing'] as bool?) ?? false,
      isMe: (json['isMe'] as bool?) ?? false,
      points: (json['points'] as num?)?.toInt() ?? 0,
      pointsName: (json['pointsName'] as String?)?.isNotEmpty == true
          ? json['pointsName'] as String
          : '积分',
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      catchCount: (json['catchCount'] as num?)?.toInt() ?? 0,
      vip: MemberStyle.fromJson(json),
      badges: (json['badges'] is List)
          ? (json['badges'] as List)
              .whereType<Map>()
              .map((m) => BadgeItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  UserProfile copyWith({
    String? nickname,
    String? avatar,
    String? bio,
    int? followerCount,
    int? followingCount,
    int? postCount,
    bool? isFollowing,
    bool? isMe,
    int? points,
    String? pointsName,
    int? likeCount,
    int? level,
    int? catchCount,
    MemberStyle? vip,
    List<BadgeItem>? badges,
  }) {
    return UserProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      postCount: postCount ?? this.postCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isMe: isMe ?? this.isMe,
      points: points ?? this.points,
      pointsName: pointsName ?? this.pointsName,
      likeCount: likeCount ?? this.likeCount,
      level: level ?? this.level,
      catchCount: catchCount ?? this.catchCount,
      vip: vip ?? this.vip,
      badges: badges ?? this.badges,
    );
  }
}

/// 关注功能尚未在后端启用时抛出（前端捕获后给出友好提示）
class FollowNotAvailableException implements Exception {
  final String message;
  const FollowNotAvailableException(
      [this.message = '关注/粉丝功能需升级后端后启用']);
  @override
  String toString() => message;
}
