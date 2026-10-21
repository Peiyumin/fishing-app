import '../services/api_config.dart';

/// 商城商品（测试版：仅展示，不含下单支付）
/// 对应后端 GET /shop/products 返回结构
class ShopProduct {
  final String id;
  final String name;
  final String image; // 绝对地址（已修正端口）
  final String price; // 售价（字符串，兼容 9.9 / 99）
  final String originalPrice; // 划线原价（可空）
  final String description;
  final String category;
  final int stock; // 0 = 不限制

  const ShopProduct({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    this.originalPrice = '',
    this.description = '',
    this.category = '',
    this.stock = 0,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    final img = (json['image'] ?? json['image_url'] ?? '').toString();
    return ShopProduct(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      image: ApiConfig.mediaUrl(img) ?? '',
      price: (json['price'] ?? '0').toString(),
      originalPrice: (json['original_price'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      stock: (json['stock'] as num?)?.toInt() ?? 0,
    );
  }

  /// 是否有划线折扣
  bool get hasDiscount {
    final o = double.tryParse(originalPrice);
    final p = double.tryParse(price);
    return o != null && p != null && o > p;
  }
}
