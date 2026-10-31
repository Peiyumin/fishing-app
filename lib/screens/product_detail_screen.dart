import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import '../models/shop_product.dart';
import '../models/shop_review.dart';
import '../services/refresh_bus.dart';
import '../services/shop_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/login_gate.dart';
import '../widgets/user_avatar.dart';

/// 商品详情页（v25）
/// 展示：主图 / 价格 / 积分兑换价 / 品牌·产地·材质·分类·库存 / 图文详情 / 商品评价
/// 下单：两种支付方式 —— 积分兑换（实时扣积分）与现金购买（测试版只登记订单）
class ProductDetailScreen extends StatefulWidget {
  final ShopProduct product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late ShopProduct _p;
  List<ShopReview> _reviews = [];
  bool _loadingReviews = true;
  bool _ordering = false;

  @override
  void initState() {
    super.initState();
    _p = widget.product;
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final list = await ShopService.fetchReviews(_p.id);
    if (!mounted) return;
    setState(() {
      _reviews = list;
      _loadingReviews = false;
    });
  }

  Future<void> _reloadProduct() async {
    final fresh = await ShopService.fetchProduct(_p.id);
    if (!mounted || fresh == null) return;
    setState(() => _p = fresh);
  }

  // ---------------- 下单 ----------------

  Future<void> _order({required bool usePoints}) async {
    final session = context.read<SessionProvider>();
    if (!session.isLoggedIn) {
      if (!await ensureLogin(context, hint: '登录后即可下单购买')) return;
    }
    if (usePoints && !_p.canRedeem) {
      CenterToast.show(context, '该商品不支持积分兑换');
      return;
    }

    // 积分兑换前先确认（会真实扣除积分）
    if (usePoints) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('确认积分兑换'),
              content: Text(
                '将消耗 ${_p.pointsPrice} 积分兑换「${_p.name}」，'
                '兑换后积分不可退回，确认继续？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('再想想'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('确认兑换'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }

    setState(() => _ordering = true);
    try {
      final res = await ShopService.createOrder(
        productId: _p.id,
        usePoints: usePoints,
      );
      if (!mounted) return;
      if (usePoints) {
        final spent = res['points_spent'] ?? res['pointsPrice'];
        final left = res['points_left'];
        CenterToast.show(
          context,
          left == null
              ? '兑换成功，已消耗 $spent 积分'
              : '兑换成功，已消耗 $spent 积分，剩余 $left 积分',
        );
        // 积分变了：让「我的」页与商城页的积分余额同步刷新
        RefreshBus.bumpProfile();
        await _reloadProduct();
      } else {
        CenterToast.show(
            context, (res['message'] ?? '测试版：暂未开放在线支付').toString());
      }
    } catch (e) {
      if (mounted) CenterToast.show(context, '下单失败：$e');
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  // ---------------- 评价 ----------------

  Future<void> _showReviewSheet() async {
    final session = context.read<SessionProvider>();
    if (!session.isLoggedIn) {
      if (!await ensureLogin(context, hint: '登录后即可评价')) return;
      if (!mounted) return;
    }
    int stars = 5;
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('写评价',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(5, (i) {
                        return IconButton(
                          onPressed: () => setLocal(() => stars = i + 1),
                          icon: Icon(
                            i < stars ? Icons.star : Icons.star_border,
                            color: AppTheme.star,
                            size: 28,
                          ),
                        );
                      }),
                    ),
                    TextField(
                      controller: ctrl,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: '说说这件商品的使用感受…',
                        filled: true,
                        fillColor: AppTheme.background,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.emoji_emotions_outlined,
                              size: 20, color: AppTheme.textSecondary),
                          tooltip: '表情',
                          onPressed: () => showEmojiSheet(context, ctrl),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final text = ctrl.text.trim();
                          if (text.isEmpty) {
                            CenterToast.show(ctx, '请填写评价内容');
                            return;
                          }
                          Navigator.of(ctx).pop();
                          try {
                            await ShopService.addReview(
                              productId: _p.id,
                              rating: stars,
                              content: text,
                            );
                            if (mounted) {
                              CenterToast.show(context, '评价已发布');
                              await _loadReviews();
                              await _reloadProduct();
                            }
                          } catch (e) {
                            if (mounted) {
                              CenterToast.show(context, '发布失败：$e');
                            }
                          }
                        },
                        child: const Text('发布评价'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ---------------- 页面 ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商品详情'),
      ),
      bottomNavigationBar: _bottomBar(),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _hero(),
          _priceBlock(),
          _specTable(),
          _detailBlocks(),
          _reviewSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _hero() {
    if (_p.image.isEmpty) {
      return Container(
        height: 260,
        color: AppTheme.primarySoft,
        child: const Icon(Icons.photo_outlined,
            size: 60, color: AppTheme.primaryBorder),
      );
    }
    return CachedNetworkImage(
      imageUrl: _p.image,
      height: 260,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) =>
          Container(height: 260, color: AppTheme.primarySoft),
      errorWidget: (_, __, ___) => Container(
        height: 260,
        color: AppTheme.primarySoft,
        child: const Icon(Icons.broken_image_outlined,
            size: 60, color: AppTheme.primaryBorder),
      ),
    );
  }

  Widget _priceBlock() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_p.name,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  height: 1.35)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('¥${_p.price}',
                  style: const TextStyle(
                      color: AppTheme.danger,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              if (_p.hasDiscount) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('¥${_p.originalPrice}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough)),
                ),
              ],
              const Spacer(),
              if (_p.reviewCount > 0)
                Row(
                  children: [
                    const Icon(Icons.star, size: 15, color: AppTheme.star),
                    const SizedBox(width: 3),
                    Text(
                      '${_p.rating.toStringAsFixed(1)} · ${_p.reviewCount} 条评价',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
          if (_p.canRedeem) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.starLight,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars_rounded,
                      size: 15, color: AppTheme.star),
                  const SizedBox(width: 5),
                  Text('可用 ${_p.pointsPrice} 积分兑换',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.starDark,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _specTable() {
    final specs = _p.specs;
    if (specs.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('商品参数',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          ...specs.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(s.$1,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.$2,
                          style: const TextStyle(
                              fontSize: 13.5,
                              color: AppTheme.textPrimary,
                              height: 1.4)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// 图文混排详情：按后台插入顺序渲染「文字 → 图片 → 文字」
  Widget _detailBlocks() {
    final blocks = _p.detailBlocks;
    if (blocks.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('商品详情',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          ...blocks.map((b) {
            if (b.$1 == 'image') {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: CachedNetworkImage(
                    imageUrl: b.$2,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 160,
                      color: AppTheme.primarySoft,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 120,
                      color: AppTheme.primarySoft,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppTheme.primaryBorder),
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(b.$2,
                  style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.65,
                      color: AppTheme.textSecondary)),
            );
          }),
        ],
      ),
    );
  }

  Widget _reviewSection() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('商品评价',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              if (_p.reviewCount > 0) ...[
                const SizedBox(width: 6),
                Text('(${_p.reviewCount})',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary)),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: _showReviewSheet,
                icon: const Icon(Icons.rate_review_outlined, size: 16),
                label: const Text('写评价'),
              ),
            ],
          ),
          if (_p.reviewCount > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_p.rating.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.star)),
                const SizedBox(width: 8),
                ...List.generate(5, (i) {
                  final filled = i + 0.5 < _p.rating;
                  return Icon(
                    filled ? Icons.star : Icons.star_border,
                    size: 16,
                    color: AppTheme.star,
                  );
                }),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (_loadingReviews)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('还没有评价，来写下第一条吧',
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            )
          else
            ..._reviews.map(_reviewRow),
        ],
      ),
    );
  }

  Widget _reviewRow(ShopReview r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            url: r.avatar.isNotEmpty ? r.avatar : null,
            userId: r.userId.isNotEmpty ? r.userId : null,
            radius: 17,
            vipLevel: r.vipLevel,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.displayName,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    const Spacer(),
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < r.rating ? Icons.star : Icons.star_border,
                        size: 13,
                        color: AppTheme.star,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.content,
                    style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部双按钮：积分兑换 / 现金购买
  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(top: BorderSide(color: AppTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_p.canRedeem) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _ordering ? null : () => _order(usePoints: true),
                  icon: const Icon(Icons.stars_rounded, size: 18),
                  label: Text('${_p.pointsPrice} 积分兑换'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.starDark,
                    side: const BorderSide(color: AppTheme.star),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMd)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: _p.canRedeem ? 1 : 2,
              child: ElevatedButton.icon(
                onPressed: _ordering ? null : () => _order(usePoints: false),
                icon: _ordering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.shopping_cart_checkout, size: 18),
                label: Text('¥${_p.price} 立即购买'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
