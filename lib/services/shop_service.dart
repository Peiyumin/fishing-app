import '../models/shop_product.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 商城：商品列表（后台「商城管理」配置，前端只读展示）
class ShopService {
  static bool get _demo => !ApiConfig.enabled;

  /// 演示商品（后端不可用时兜底，保证商城页始终有内容可看）
  static const List<ShopProduct> _demoItems = [
    ShopProduct(
      id: 's1',
      name: '碳素路亚竿 2.1m 中调 ML',
      image: 'https://picsum.photos/seed/shop1/600/600',
      price: '129',
      originalPrice: '199',
      description: '高碳布轻量化，手感灵敏，适合淡水路亚翘嘴 / 鲈鱼。',
      category: '鱼竿',
      stock: 12,
    ),
    ShopProduct(
      id: 's2',
      name: '仿生软饵套装 20 枚',
      image: 'https://picsum.photos/seed/shop2/600/600',
      price: '19.9',
      originalPrice: '29.9',
      description: '多种泳姿软虫，搭配铅头钩，鲫鱼、鲈鱼通杀。',
      category: '鱼饵',
      stock: 0,
    ),
    ShopProduct(
      id: 's3',
      name: '加重铅坠 环保涂层 100g',
      image: 'https://picsum.photos/seed/shop3/600/600',
      price: '9.9',
      description: '走水必备，入口快、抗流强，一包 10 枚。',
      category: '配件',
      stock: 30,
    ),
    ShopProduct(
      id: 's4',
      name: '钓鱼防晒速干帽',
      image: 'https://picsum.photos/seed/shop4/600/600',
      price: '39',
      originalPrice: '59',
      description: 'UPF50+ 防晒，透气速干，宽檐遮阳不闷头。',
      category: '装备',
      stock: 8,
    ),
    ShopProduct(
      id: 's5',
      name: '折叠钓鱼椅 便携款',
      image: 'https://picsum.photos/seed/shop5/600/600',
      price: '89',
      originalPrice: '129',
      description: '铝合金骨架，承重 120kg，收起仅 1.2kg。',
      category: '装备',
      stock: 5,
    ),
    ShopProduct(
      id: 's6',
      name: '夜钓蓝光钓鱼灯',
      image: 'https://picsum.photos/seed/shop6/600/600',
      price: '49',
      description: '三档调光，USB 充电，防水防摔，夜钓不惊鱼。',
      category: '配件',
      stock: 20,
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
}
