/// 附近钓友
class NearbyAngler {
  final String userId;
  final String nickname;
  final String avatar;
  final int vipLevel;
  final int level;
  final int distance; // 米
  final double distanceKm;
  final String geoAt;

  const NearbyAngler({
    required this.userId,
    this.nickname = '',
    this.avatar = '',
    this.vipLevel = 0,
    this.level = 1,
    this.distance = 0,
    this.distanceKm = 0,
    this.geoAt = '',
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
        vipLevel: (j['vipLevel'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 1,
        distance: (j['distance'] as num?)?.toInt() ?? 0,
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
        geoAt: (j['geoAt'] ?? '').toString(),
      );
}
