import '../models/my_order.dart';
import '../models/shop_product.dart';
import '../models/shop_review.dart';
import '../models/user_profile.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'follow_service.dart';

/// 商城：商品 / 评价 / 下单（后台「商城管理」配置商品，前端展示 + 下单）
///
/// 两种购买方式（v25）：
///   points 积分兑换 —— 后台给商品配「积分兑换价」，用户确认后实时扣积分
///   cash   现金购买 —— 测试版只登记订单，未接入支付
class ShopService {
  static bool get _demo => !ApiConfig.enabled;

  /// 演示商品（后端不可用时兜底，保证商城页始终有内容可看）
  static const List<ShopProduct> _demoItems = [
    ShopProduct(
      id: 's1',
      name: '碳素路亚竿 2.1m 中调 ML',
      image: 'https://picsum.photos/seed/shop1/600/600',
      price: '129',
      pointsPrice: 1290,
      originalPrice: '199',
      description:
          '高碳布轻量化，手感灵敏，适合淡水路亚翘嘴 / 鲈鱼。<img src="https://picsum.photos/seed/shop1d/800/500">',
      category: '鱼竿',
      brand: '光威',
      origin: '山东威海',
      material: '高碳纤维',
      stock: 12,
      rating: 4.8,
      reviewCount: 36,
    ),
    ShopProduct(
      id: 's2',
      name: '仿生软饵套装 20 枚',
      image: 'https://picsum.photos/seed/shop2/600/600',
      price: '19.9',
      pointsPrice: 199,
      originalPrice: '29.9',
      description: '多种泳姿软虫，搭配铅头钩，鲫鱼、鲈鱼通杀。',
      category: '鱼饵',
      brand: '钓迷',
      origin: '广东东莞',
      material: '环保硅胶',
      stock: 0,
      rating: 4.6,
      reviewCount: 18,
    ),
    ShopProduct(
      id: 's3',
      name: '加重铅坠 环保涂层 100g',
      image: 'https://picsum.photos/seed/shop3/600/600',
      price: '9.9',
      pointsPrice: 99,
      description: '走水必备，入口快、抗流强，一包 10 枚。',
      category: '配件',
      brand: '渔匠',
      origin: '浙江宁波',
      material: '环保合金',
      stock: 30,
      rating: 4.4,
      reviewCount: 9,
    ),
    ShopProduct(
      id: 's4',
      name: '钓鱼防晒速干帽',
      image: 'https://picsum.photos/seed/shop4/600/600',
      price: '39',
      originalPrice: '59',
      description: 'UPF50+ 防晒，透气速干，宽檐遮阳不闷头。',
      category: '装备',
      brand: '野行者',
      origin: '福建厦门',
      material: '速干涤纶',
      stock: 8,
      rating: 4.5,
      reviewCount: 12,
    ),
    ShopProduct(
      id: 's5',
      name: '折叠钓鱼椅 便携款',
      image: 'https://picsum.photos/seed/shop5/600/600',
      price: '89',
      pointsPrice: 890,
      originalPrice: '129',
      description: '铝合金骨架，承重 120kg，收起仅 1.2kg。',
      category: '装备',
      brand: '钓王',
      origin: '江苏常州',
      material: '铝合金 + 牛津布',
      stock: 5,
      rating: 4.7,
      reviewCount: 21,
    ),
    ShopProduct(
      id: 's6',
      name: '夜钓蓝光钓鱼灯',
      image: 'https://picsum.photos/seed/shop6/600/600',
      price: '49',
      pointsPrice: 490,
      description: '三档调光，USB 充电，防水防摔，夜钓不惊鱼。',
      category: '配件',
      brand: '夜钓者',
      origin: '广东深圳',
      material: 'ABS + LED',
      stock: 20,
      rating: 4.3,
      reviewCount: 7,
    ),
  ];

  /// 演示评价
  static const List<ShopReview> _demoReviews = [
    ShopReview(
      id: 'r1',
      productId: 's1',
      nickname: '路亚小王',
      rating: 5,
      content: '竿子很轻，腰力足，翘嘴上岸一点不费劲，性价比高。',
    ),
    ShopReview(
      id: 'r2',
      productId: 's1',
      nickname: '老钓翁',
      rating: 4,
      content: '手感不错，导环顺滑，就是竿袋能再厚实点就完美了。',
    ),
    ShopReview(
      id: 'r3',
      productId: 's2',
      nickname: '野钓阿强',
      rating: 5,
      content: '软虫泳姿很自然，鲈鱼咬口明显变多，回购第三套了。',
    ),
  ];

  /// 拉取上架商品
  static Future<List<ShopProduct>> fetchProducts() async {
    if (_demo) {
      await Future.delayed(const Duration(milliseconds: 250));
      return List<ShopProduct>.from(_demoItems);
    }
    try {
      final data = await ApiClient.get('/shop/products') as List;
      return data
          .map((e) => ShopProduct.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      // 后端不可达 / 接口未部署：回落到演示商品，保证页面可用
      return List<ShopProduct>.from(_demoItems);
    }
  }

  /// 单个商品详情（列表已带全部字段，这里主要用于刷新评分/库存）
  static Future<ShopProduct?> fetchProduct(String id) async {
    if (_demo) {
      for (final p in _demoItems) {
        if (p.id == id) return p;
      }
      return null;
    }
    try {
      final data = await ApiClient.get('/shop/products/$id') as Map;
      return ShopProduct.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// 某商品的评价列表（只返回后台未隐藏的）
  static Future<List<ShopReview>> fetchReviews(String productId) async {
    if (_demo) {
      await Future.delayed(const Duration(milliseconds: 150));
      return _demoReviews.where((r) => r.productId == productId).toList();
    }
    try {
      final data = await ApiClient.get(
        '/shop/reviews',
        {'product_id': productId},
      ) as List;
      return data
          .map((e) => ShopReview.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 发表评价（需登录）
  static Future<void> addReview({
    required String productId,
    required int rating,
    required String content,
  }) async {
    if (_demo) throw Exception('演示模式暂不支持发表评价');
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/shop/reviews', {
      'product_id': productId,
      'rating': rating,
      'content': content,
    });
  }

  /// 我的积分余额与积分名称（用于商城页展示「我的积分」）
  /// 失败时返回 null，页面自行隐藏该入口
  static Future<UserProfile?> fetchMyPoints() async {
    if (_demo || ApiClient.token == null) return null;
    try {
      return await FollowService.fetchMe();
    } catch (_) {
      return null;
    }
  }

  /// 下单
  /// [usePoints] = true → 积分兑换（扣积分）；false → 现金购买（测试版只登记）
  /// 返回后端结果 Map：积分兑换含 pointsSpent / pointsLeft / pointsName
  static Future<Map<String, dynamic>> createOrder({
    required String productId,
    required bool usePoints,
    int quantity = 1,
  }) async {
    if (_demo) {
      // 演示模式：不真的扣积分，只返回提示
      return {
        'ok': true,
        'type': usePoints ? 'points' : 'cash',
        'message':
            usePoints ? '演示模式：积分兑换未真实扣减' : '演示模式：现金购买未接入支付',
      };
    }
    if (ApiClient.token == null) throw Exception('请先登录');
    final data = await ApiClient.post('/shop/order', {
      'product_id': productId,
      'type': usePoints ? 'points' : 'cash',
      'quantity': quantity,
    }) as Map;
    return Map<String, dynamic>.from(data);
  }

  /// 我的订单（积分兑换 / 现金登记）
  /// 老后端没有该接口时返回空列表，页面显示「暂无订单」而不是报错
  static Future<List<MyOrder>> fetchMyOrders() async {
    if (_demo || ApiClient.token == null) return const [];
    try {
      final data = await ApiClient.get('/shop/orders');
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => MyOrder.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 取消订单（仅「待处理」可取消；积分单会原路退回积分）
  static Future<({bool ok, String msg, int pointsBack})> cancelOrder(
      String orderId) async {
    try {
      final data = await ApiClient.post('/shop/orders/$orderId/cancel', const {});
      final m = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return (
        ok: true,
        msg: (m['message'] ?? '订单已取消').toString(),
        pointsBack: (m['points_back'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      return (ok: false, msg: _msgOf(e), pointsBack: 0);
    }
  }

  /// 确认收货（仅「已发货」可确认）
  static Future<({bool ok, String msg})> confirmOrder(String orderId) async {
    try {
      final data = await ApiClient.post('/shop/orders/$orderId/confirm', const {});
      final m = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return (ok: true, msg: (m['message'] ?? '已确认收货').toString());
    } catch (e) {
      return (ok: false, msg: _msgOf(e));
    }
  }

  /// 从 Exception / 其它异常里取出后端返回的中文提示
  /// （api_client 抛的是 Exception('已发货的订单不能取消')，toString 会带前缀）
  static String _msgOf(Object e) {
    final s = e.toString();
    for (final p in ['ApiException: ', 'Exception: ']) {
      if (s.startsWith(p)) return s.substring(p.length).trim();
    }
    return '操作失败，请稍后重试';
  }
}
