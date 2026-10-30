import '../models/badge.dart';
import '../models/member.dart';
import '../services/api_config.dart';
import '../utils/json_num.dart';

/// 用户公开资料（关注/粉丝 / 我的页 / 会员 / 徽章）
/// 对应后端 /users/me 与 /users/:id 返回结构
class UserProfile {
  final String id;
  final int userNo; // 数字用户 ID（后台按号查人，替代 UUID 英文串）
  final String nickname;
  final String? avatar;

  /// 个人主页背景图（v2.1.56，所有人可见；空 = 用默认渐变）
  final String? cover;
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

  /// 注册地（v2.1.57）：后端存的「河南省·禹州市」，空串 = 未记录
  final String regPlace;
  final int catchCount; // 发布渔获次数
  final MemberStyle vip; // 会员等级（等级 0 = 普通用户）
  final List<BadgeItem> badges; // 已获得的徽章

  const UserProfile({
    required this.id,
    this.userNo = 0,
    required this.nickname,
    this.avatar,
    this.cover,
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
    this.regPlace = '',
    this.catchCount = 0,
    this.vip = MemberStyle.normal,
    this.badges = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] ?? '').toString(),
      userNo: jsonInt(json['userNo']) ?? 0,
      nickname: (json['nickname'] as String?) ?? '钓友',
      avatar: ApiConfig.mediaUrl(json['avatar'] as String?),
      cover: ApiConfig.mediaUrl((json['cover'] ?? '').toString()),
      bio: (json['bio'] ?? '').toString(),
      followerCount: jsonInt(json['followerCount']) ?? 0,
      followingCount: jsonInt(json['followingCount']) ?? 0,
      postCount: jsonInt(json['postCount']) ?? 0,
      isFollowing: jsonBool(json['isFollowing'], fallback: false),
      isMe: jsonBool(json['isMe'], fallback: false),
      points: jsonInt(json['points']) ?? 0,
      pointsName: (json['pointsName'] as String?)?.isNotEmpty == true
          ? json['pointsName'] as String
          : '积分',
      likeCount: jsonInt(json['likeCount']) ?? 0,
      level: jsonInt(json['level']) ?? 1,
      regPlace: (json['regPlace'] ?? '').toString(),
      catchCount: jsonInt(json['catchCount']) ?? 0,
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
    String? id,
    int? userNo,
    String? nickname,
    String? avatar,
    String? cover,
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
    String? regPlace,
    int? catchCount,
    MemberStyle? vip,
    List<BadgeItem>? badges,
  }) {
    return UserProfile(
      id: id ?? this.id,
      userNo: userNo ?? this.userNo,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      cover: cover ?? this.cover,
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
      regPlace: regPlace ?? this.regPlace,
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
