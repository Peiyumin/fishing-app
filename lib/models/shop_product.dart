import '../services/api_config.dart';
import '../utils/json_num.dart';

/// 商城商品（测试版：展示 + 两种下单方式，现金支付未接入）
/// 对应后端 GET /shop/products 返回结构
///
/// 两种购买方式：
///   1. 现金购买：price（人民币售价）
///   2. 积分兑换：pointsPrice（>0 才支持，兑换时扣用户积分）
class ShopProduct {
  final String id;
  final String name;
  final String image; // 绝对地址（已修正端口）
  final String price; // 售价（字符串，兼容 9.9 / 99）
  final int pointsPrice; // 积分兑换价（0 = 不支持积分兑换）
  final String originalPrice; // 划线原价（可空）
  final String description; // 富文本：可含 <img src>，App 解析成图文混排
  final List<String> detailImages; // 描述里插入的图片（后端抽取，兜底用）
  final String category;
  final String brand; // 品牌（后台自定义）
  final String origin; // 产地（后台自定义）
  final String material; // 材质（后台自定义）
  final int stock; // 0 = 不限制
  final double rating; // 平均评分（0 表示暂无评价）
  final int reviewCount; // 评价条数

  const ShopProduct({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    this.pointsPrice = 0,
    this.originalPrice = '',
    this.description = '',
    this.detailImages = const [],
    this.category = '',
    this.brand = '',
    this.origin = '',
    this.material = '',
    this.stock = 0,
    this.rating = 0,
    this.reviewCount = 0,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    final img = (json['image'] ?? json['image_url'] ?? '').toString();
    final inline = _inlineImages((json['description'] ?? '').toString());
    return ShopProduct(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      image: ApiConfig.mediaUrl(img) ?? '',
      price: (json['price'] ?? '0').toString(),
      pointsPrice: jsonInt(json['points_price']) ?? 0,
      originalPrice: (json['original_price'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      detailImages: _mergeImages(ApiConfig.mediaList(json['detail_images']), inline),
      category: (json['category'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      origin: (json['origin'] ?? '').toString(),
      material: (json['material'] ?? '').toString(),
      stock: jsonInt(json['stock']) ?? 0,
      rating: jsonDouble(json['rating']) ?? 0,
      reviewCount: jsonInt(json['review_count']) ?? 0,
    );
  }

  /// 是否有划线折扣
  bool get hasDiscount {
    final o = double.tryParse(originalPrice);
    final p = double.tryParse(price);
    return o != null && p != null && o > p;
  }

  /// 是否支持积分兑换
  bool get canRedeem => pointsPrice > 0;

  /// 商品参数（品牌 / 产地 / 材质 / 分类），只返回有值的项
  List<(String, String)> get specs {
    final out = <(String, String)>[];
    if (brand.isNotEmpty) out.add(('品牌', brand));
    if (origin.isNotEmpty) out.add(('产地', origin));
    if (material.isNotEmpty) out.add(('材质', material));
    if (category.isNotEmpty) out.add(('分类', category));
    out.add(('库存', stock == 0 ? '充足' : '$stock 件'));
    return out;
  }

  /// 商品详情的「图文块」：文字段与图片段按原文顺序排列
  ///
  /// 后台描述形如「竿身轻<img src="...">腰力足」，这里拆成
  /// [('text','竿身轻'), ('image', url), ('text','腰力足')]，
  /// App 依次渲染，实现「描述里插入图片」的效果。
  List<(String, String)> get detailBlocks {
    final html = description;
    if (html.isEmpty) {
      return detailImages
          .map((u) => ('image', u))
          .toList(growable: false);
    }
    final re = _imgTag;
    final blocks = <(String, String)>[];
    int cursor = 0;
    for (final m in re.allMatches(html)) {
      final before = html.substring(cursor, m.start);
      final t = _plain(before);
      if (t.isNotEmpty) blocks.add(('text', t));
      final url = ApiConfig.mediaUrl(m.group(1));
      if (url != null && url.isNotEmpty) blocks.add(('image', url));
      cursor = m.end;
    }
    final tail = _plain(html.substring(cursor));
    if (tail.isNotEmpty) blocks.add(('text', tail));
    if (blocks.isEmpty && detailImages.isNotEmpty) {
      for (final u in detailImages) {
        blocks.add(('image', u));
      }
    }
    return blocks;
  }

  /// 描述里的内联图片（后端抽成的 detail_images 缺失时的兜底）
  /// 匹配描述里的 <img src="...">（属性里的单引号/双引号都兼容）
  static final RegExp _imgTag =
      RegExp("<img[^>]*?src=[\"']([^\"']+)[\"'][^>]*>", caseSensitive: false);

  static List<String> _inlineImages(String html) {
    if (html.isEmpty) return const [];
    final re = _imgTag;
    return re
        .allMatches(html)
        .map((m) => ApiConfig.mediaUrl(m.group(1)))
        .whereType<String>()
        .where((u) => u.isNotEmpty)
        .toList();
  }

  static List<String> _mergeImages(List<String> a, List<String> b) {
    if (a.isNotEmpty) return a;
    return b;
  }

  /// 去掉剩余 HTML 标签，只留纯文本
  static String _plain(String s) {
    final t = s.replaceAll(RegExp(r'<[^>]*>'), '');
    return t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('\r', '')
        .trim();
  }
}
