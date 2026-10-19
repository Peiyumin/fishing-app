import '../services/api_config.dart';

/// 用户公开资料（关注/粉丝功能）
/// 对应后端 /api/users/:id 返回结构
class UserProfile {
  final String id;
  final String nickname;
  final String? avatar;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final bool isFollowing; // 当前登录用户是否已关注 TA
  final bool isMe; // 是否是当前登录用户本人

  const UserProfile({
    required this.id,
    required this.nickname,
    this.avatar,
    this.followerCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
    this.isFollowing = false,
    this.isMe = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nickname: (json['nickname'] as String?) ?? '钓友',
      avatar: ApiConfig.mediaUrl(json['avatar'] as String?),
      followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
      followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
      postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      isFollowing: (json['isFollowing'] as bool?) ?? false,
      isMe: (json['isMe'] as bool?) ?? false,
    );
  }

  UserProfile copyWith({
    String? nickname,
    String? avatar,
    int? followerCount,
    int? followingCount,
    int? postCount,
    bool? isFollowing,
    bool? isMe,
  }) {
    return UserProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      postCount: postCount ?? this.postCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isMe: isMe ?? this.isMe,
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
