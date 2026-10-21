import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/shop_product.dart';
import '../services/shop_service.dart';
import '../widgets/center_toast.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ShopService.fetchProducts();
    if (!mounted) return;
    setState(() {
      _items = list;
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
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
                    const Text('垂钓圈 · 渔具商城',
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
                const Text('精选钓具好物 · 每日上新',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
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
          childAspectRatio: 0.66,
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
        onTap: () => _showDetail(p),
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

  void _showDetail(ShopProduct p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.94,
          expand: false,
          builder: (_, scroll) {
            return Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusLg)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.zero,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  AspectRatio(aspectRatio: 1.25, child: _image(p.image)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('¥${p.price}',
                                style: const TextStyle(
                                    color: AppTheme.danger,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                            if (p.hasDiscount) ...[
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text('¥${p.originalPrice}',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                        decoration:
                                            TextDecoration.lineThrough)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (p.category.isNotEmpty)
                              _chip(Icons.local_offer_outlined, p.category),
                            _chip(Icons.inventory_2_outlined,
                                p.stock == 0 ? '库存充足' : '库存 ${p.stock}'),
                          ],
                        ),
                        if (p.description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text('商品详情',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                          const SizedBox(height: 6),
                          Text(p.description,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: AppTheme.textSecondary)),
                        ],
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoft,
                            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text('测试版：商品仅作展示，暂未开放在线支付',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              CenterToast.show(
                                  context, '测试版：暂未开放在线支付，敬请期待');
                            },
                            icon: const Icon(Icons.shopping_cart_checkout,
                                size: 18),
                            label: const Text('立即购买（测试版）'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
        ],
      ),
    );
  }
}
