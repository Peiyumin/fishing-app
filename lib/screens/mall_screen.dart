import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/shop_product.dart';
import '../models/user_profile.dart';
import '../services/shop_service.dart';
import 'product_detail_screen.dart';
import '../widgets/app_refresh.dart';

/// 商城（测试版）
/// 商品由后台「运营配置 → 商城管理」配置，前端只读展示。
/// 目前不含下单支付：点「立即购买」给出提示，先把「后台配置 → 前端展示」跑通。
class MallScreen extends StatefulWidget {
  const MallScreen({super.key});

  @override
  State<MallScreen> createState() => _MallScreenState();
}

class _MallScreenState extends State<MallScreen> {
  List<ShopProduct> _items = [];
  bool _loading = true;
  String _cat = '全部';

  /// 我的积分余额（用于商城页顶部「我的积分」展示；未登录/失败时为 null）
  UserProfile? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 已有商品时刷新不清空列表，避免整块消失闪白
    setState(() => _loading = _items.isEmpty);
    final results = await Future.wait([
      ShopService.fetchProducts(),
      ShopService.fetchMyPoints(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<ShopProduct>;
      _me = results[1] as UserProfile?;
      _loading = false;
    });
  }

  List<String> get _cats {
    final s = <String>{'全部'};
    for (final p in _items) {
      if (p.category.isNotEmpty) s.add(p.category);
    }
    return s.toList();
  }

  List<ShopProduct> get _filtered =>
      _cat == '全部' ? _items : _items.where((p) => p.category == _cat).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商城'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: AppRefresh(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : ListView(
                children: [
                  _banner(),
                  if (_cats.length > 1) _catBar(),
                  if (_filtered.isEmpty) _empty() else _grid(),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('渔报 · 渔具商城',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: const Text('测试版',
                          style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_me == null
                    ? '精选钓具好物 · 支持现金与积分兑换'
                    : '我的${_me!.pointsName} ${_me!.points} · 可兑换积分商品',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _catBar() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _cats[i];
          final on = c == _cat;
          return GestureDetector(
            onTap: () => setState(() => _cat = c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: on ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                border: Border.all(
                    color: on ? AppTheme.primary : AppTheme.border),
              ),
              child: Center(
                child: Text(
                  c,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: on ? Colors.white : AppTheme.textSecondary,
                    fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _filtered.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (_, i) => _card(_filtered[i]),
      ),
    );
  }

  Widget _card(ShopProduct p) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
            )
            // 详情页可能兑换了积分：回来刷新商品（库存/评分）与我的积分
            .then((_) => _load()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _image(p.image)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('¥${p.price}',
                          style: const TextStyle(
                              color: AppTheme.danger,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      if (p.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '¥${p.originalPrice}',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (p.canRedeem) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.starLight,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.stars_rounded,
                              size: 12, color: AppTheme.star),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text('${p.pointsPrice} 积分',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.starDark,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(String url) {
    if (url.isEmpty) {
      return Container(
        color: AppTheme.primarySoft,
        child: const Icon(Icons.photo_outlined,
            size: 34, color: AppTheme.primaryBorder),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (c, child, prog) => prog == null
          ? child
          : Container(
              color: AppTheme.primarySoft,
              child: const Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
      errorBuilder: (c, e, s) => Container(
        color: AppTheme.primarySoft,
        child: const Icon(Icons.broken_image_outlined,
            size: 34, color: AppTheme.primaryBorder),
      ),
    );
  }

  Widget _empty() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.shopping_bag_outlined,
              size: 56, color: AppTheme.primaryBorder),
          SizedBox(height: 12),
          Text('商城正在上新，稍后再来看看',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
