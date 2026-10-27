import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/shop_product.dart';

void main() {
  test('商品详情：描述里的 <img> 被解析成「文字 → 图片 → 文字」顺序块', () {
    final p = ShopProduct.fromJson({
      'id': 'p1',
      'name': '碳素路亚竿',
      'image': '/uploads/a.jpg',
      'price': '129',
      'points_price': 1290,
      'category': '鱼竿',
      'brand': '光威',
      'origin': '山东威海',
      'material': '高碳纤维',
      'stock': 12,
      'rating': 4.8,
      'review_count': 36,
      'description':
          '竿身轻<img src="/uploads/d1.jpg">腰力足<img src=\'/uploads/d2.jpg\'>收竿快',
      'detail_images': ['/uploads/d1.jpg', '/uploads/d2.jpg'],
    });

    final blocks = p.detailBlocks;
    expect(blocks.length, 5);
    expect(blocks[0].$1, 'text');
    expect(blocks[0].$2, '竿身轻');
    expect(blocks[1].$1, 'image');
    expect(blocks[1].$2.endsWith('/uploads/d1.jpg'), isTrue);
    expect(blocks[2].$2, '腰力足');
    expect(blocks[3].$1, 'image');
    expect(blocks[3].$2.endsWith('/uploads/d2.jpg'), isTrue);
    expect(blocks[4].$2, '收竿快');

    // 图片地址要补成带端口的绝对地址，否则 App 加载 404
    expect(blocks[1].$2.startsWith('http'), isTrue);
  });

  test('双支付方式：积分价为 0 表示不支持积分兑换', () {
    final a = ShopProduct.fromJson({'id': 'a', 'points_price': 0});
    final b = ShopProduct.fromJson({'id': 'b', 'points_price': 500});
    expect(a.canRedeem, isFalse);
    expect(b.canRedeem, isTrue);
    expect(b.pointsPrice, 500);
  });

  test('商品参数：品牌 / 产地 / 材质 / 分类 / 库存', () {
    final p = ShopProduct.fromJson({
      'id': 'p2',
      'brand': '光威',
      'origin': '山东威海',
      'material': '高碳纤维',
      'category': '鱼竿',
      'stock': 0,
    });
    expect(p.specs.map((e) => e.$1).toList(),
        ['品牌', '产地', '材质', '分类', '库存']);
    expect(p.specs.first.$2, '光威');
    expect(p.specs.last.$2, '充足');
  });

  test('无图描述：只剩文字块，不会解析出图片', () {
    final p = ShopProduct.fromJson({
      'id': 'p3',
      'description': '这是一段纯文字描述，没有插图。',
    });
    expect(p.detailBlocks.length, 1);
    expect(p.detailBlocks.single.$1, 'text');
  });
}
