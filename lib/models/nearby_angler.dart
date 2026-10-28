/// 附近钓友
import '../utils/json_num.dart';

class NearbyAngler {
  final String userId;
  final String nickname;
  final String avatar;
  final String bio; // 个人签名
  final int vipLevel;
  final int level;
  final int distance; // 米
  final double distanceKm;
  final String geoAt;
  final bool followed; // 我是否已关注对方（后端返回）
  final bool member; // 对方是否为会员

  const NearbyAngler({
    required this.userId,
    this.nickname = '',
    this.avatar = '',
    this.bio = '',
    this.vipLevel = 0,
    this.level = 1,
    this.distance = 0,
    this.distanceKm = 0,
    this.geoAt = '',
    this.followed = false,
    this.member = false,
  });

  String get distanceText {
    if (distance < 1000) return '${distance}m';
    final km = distanceKm;
    if (km <= 0) return '${distance}m';
    final s = km.toStringAsFixed(1);
    final text = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    return '${text}km';
  }

  factory NearbyAngler.fromJson(Map<String, dynamic> j) => NearbyAngler(
        userId: (j['userId'] ?? '').toString(),
        nickname: (j['nickname'] ?? '').toString(),
        avatar: (j['avatar'] ?? '').toString(),
        bio: (j['bio'] ?? '').toString(),
        vipLevel: jsonInt(j['vipLevel']) ?? 0,
        level: jsonInt(j['level']) ?? 1,
        distance: jsonInt(j['distance']) ?? 0,
        distanceKm: jsonDouble(j['distanceKm']) ?? 0,
        geoAt: (j['geoAt'] ?? '').toString(),
        followed: jsonBool(j['followed'], fallback: false),
        member: jsonBool(j['member'], fallback: false),
      );
}
