/// 钓点评论（App 展示用）
///
/// 只包含**后台已审核通过**的评论（status=1）。
/// 用户自己刚发的评论会处于待审核状态，前台不展示，接口返回 pending=true。
class SpotComment {
  final String id;
  final String spotId;
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final String content;
  final int userLevel;
  final int vipLevel; // 会员等级（头像会员框）
  final DateTime createdAt;

  const SpotComment({
    required this.id,
    required this.spotId,
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    required this.content,
    this.userLevel = 1,
    this.vipLevel = 0,
    required this.createdAt,
  });

  factory SpotComment.fromJson(Map<String, dynamic> j) {
    return SpotComment(
      id: (j['id'] ?? '').toString(),
      spotId: (j['spot_id'] ?? '').toString(),
      userId: (j['user_id'] ?? '').toString(),
      nickname: (j['user_nickname'] ?? '钓友').toString(),
      avatarUrl: j['user_avatar'] as String?,
      content: (j['content'] ?? '').toString(),
      userLevel: (j['user_level'] as num?)?.toInt() ?? 1,
      vipLevel: (j['user_vip'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  /// 相对时间：刚刚 / 5分钟前 / 3小时前 / 日期
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${createdAt.month}-${createdAt.day}';
  }
}
