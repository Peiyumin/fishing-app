import '../services/api_config.dart';
import '../utils/json_num.dart';

/// 商品评价
/// 对应后端 GET /shop/reviews 返回结构（只返回后台已通过/未隐藏的）
class ShopReview {
  final String id;
  final String productId;
  final String userId; // 后台手工添加时为空
  final String nickname;
  final String avatar; // 绝对地址（已修正端口）
  final int rating; // 1~5 星
  final String content;
  final List<String> images;
  final DateTime? createdAt;
  final int vipLevel; // 会员等级（头像会员框）

  const ShopReview({
    required this.id,
    this.productId = '',
    this.userId = '',
    this.nickname = '',
    this.avatar = '',
    this.rating = 5,
    this.content = '',
    this.images = const [],
    this.createdAt,
    this.vipLevel = 0,
  });

  factory ShopReview.fromJson(Map<String, dynamic> json) {
    return ShopReview(
      id: (json['id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatar: ApiConfig.mediaUrl(json['avatar'] as String?) ?? '',
      vipLevel: jsonInt(json['user_vip']) ?? 0,
      rating: jsonInt(json['rating']) ?? 5,
      content: (json['content'] ?? '').toString(),
      images: ApiConfig.mediaList(json['images']),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }

  /// 展示用昵称（后台手工添加且没填昵称时兜底）
  String get displayName => nickname.isEmpty ? '钓友' : nickname;

  /// 头像首字（无头像时用文字头像兜底）
  String get initial => displayName.isEmpty ? '钓' : displayName[0];
}
