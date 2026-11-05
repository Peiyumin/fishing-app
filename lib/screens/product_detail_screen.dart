import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import '../models/shop_product.dart';
import '../models/shop_review.dart';
import '../models/user_address.dart';
import '../services/refresh_bus.dart';
import '../services/settings_service.dart';
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
    if (!mounted) return;
    if (usePoints && !_p.canRedeem) {
      CenterToast.show(context, '该商品不支持积分兑换');
      return;
    }

    // 积分兑换的三段式流程（v2.1.77 修正顺序）：
    //
    //   ① 先问「要不要换」——扣积分不可逆，必须在问地址之前问清楚
    //   ② 确认了才查收货地址：有地址 → 选一个；没地址 → 现场添加
    //   ③ 地址定下来再最后确认一次（带地址摘要），确认前一分积分都不扣
    //
    // 老流程（v2.1.76）是点「兑换」直接弹地址表单，等于「还没决定换不换就让你填地址」，
    // 而且弹层里的按钮一点就扣分，没有任何二次确认的机会。
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
                  child: const Text('继续选择地址'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }

    UserAddress? addr;
    if (usePoints) {
      while (true) {
        // ② 有地址就是单选题，没地址直接进表单
        final picked = await showModalBottomSheet<UserAddress>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppTheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: const _CheckoutSheet(),
          ),
        );
        if (picked == null) return; // 关掉弹层 = 放弃兑换
        if (!mounted) return;

        // ③ 地址选好，最后确认一次（地址 + 扣多少积分都摆出来）
        final done = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('确认兑换'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _confirmRow('收货人', '${picked.name}  ${picked.maskedPhone}'),
                    const SizedBox(height: 8),
                    _confirmRow('寄送到', picked.fullAddress),
                    const SizedBox(height: 12),
                    Text(
                      '将消耗 ${_p.pointsPrice} 积分兑换「${_p.name}」，'
                      '兑换后积分不可退回。',
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('修改地址'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('确认兑换'),
                  ),
                ],
              ),
            ) ??
            false;
        if (done) {
          addr = picked;
          break;
        }
        // 点了「修改地址」→ 回到地址弹层重新选
        if (!mounted) return;
      }
    }

    setState(() => _ordering = true);
    try {
      final res = await ShopService.createOrder(
        productId: _p.id,
        usePoints: usePoints,
        recvName: addr?.name ?? '',
        recvPhone: addr?.phone ?? '',
        recvRegion: addr?.region ?? '',
        recvDetail: addr?.detail ?? '',
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

  /// 最终确认弹窗里的「标签 + 内容」一行
  Widget _confirmRow(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AppTheme.textTertiary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      );

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
  ///
  /// v2.1.76：连续的详情图之间**不留白缝、不切圆角**。
  /// 后台一次上传的几张图常常是一张长图被切开（或同一组实拍），
  /// 中间留 10px 白缝 + 四角圆角，看起来像断成几块碎片。
  /// 现在的规则：上一张也是图 → 上边不留圆角；下一张也是图 → 下边不留白、不留圆角。
  /// 于是连续 N 张图会拼成一块完整的长图，只有整组的最上和最下才有圆角。
  Widget _detailBlocks() {
    final blocks = _p.detailBlocks;
    if (blocks.isEmpty) return const SizedBox();

    bool isImgAt(int i) => i >= 0 && i < blocks.length && blocks[i].$1 == 'image';
    const r = AppTheme.radiusSm;

    final items = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.$1 == 'image') {
        final prevImg = isImgAt(i - 1);
        final nextImg = isImgAt(i + 1);
        items.add(Padding(
          padding: EdgeInsets.only(bottom: nextImg ? 0 : 10),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(prevImg ? 0 : r),
              topRight: Radius.circular(prevImg ? 0 : r),
              bottomLeft: Radius.circular(nextImg ? 0 : r),
              bottomRight: Radius.circular(nextImg ? 0 : r),
            ),
            child: CachedNetworkImage(
              imageUrl: b.$2,
              width: double.infinity,
              // fitWidth 而不是 cover：cover 在高度未定时会按比例撑开，
              // 但一旦图片尺寸异常就会裁掉边缘，接缝处出现半像素白线
              fit: BoxFit.fitWidth,
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
        ));
      } else {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(b.$2,
              style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.65,
                  color: AppTheme.textSecondary)),
        ));
      }
    }

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
          ...items,
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

// ============================================================
// 积分兑换 · 填写收货地址（v43）
// ============================================================
/// 兑换流程第二步弹出来的地址弹层
///
/// 只负责「挑一个地址」或「现场加一个地址」，**不负责扣积分** ——
/// 扣积分放在它之后的最终确认弹窗里，所以用户在这里点错了也不会误扣。
///
/// 两种状态：
///   · 已有地址 → 单选列表（默认选中「默认地址」），底部「使用这个地址」
///   · 没有地址 → 直接出表单（收货人 / 手机号 / 所在地区 / 详细地址）
///
/// 表单保存走 [SettingsService.saveAddress]，写的是 user_addresses 表，
/// 所以「我的 → 设置 → 收货地址」里会立刻出现这一条，两处共用一份数据。
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet();

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  List<UserAddress> _list = const [];
  UserAddress? _picked;
  bool _loading = true;
  bool _formMode = false; // true = 正在填新地址
  bool _saving = false;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _region = TextEditingController();
  final _detail = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _region.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<UserAddress> list = const [];
    try {
      list = await SettingsService.addresses();
    } catch (_) {
      // 拉不到地址不算失败：直接让用户手填（离线/老后端都能兑换）
    }
    if (!mounted) return;
    setState(() {
      _list = list;
      _picked = list.isEmpty
          ? null
          : list.firstWhere((a) => a.isDefault, orElse: () => list.first);
      _formMode = list.isEmpty; // 没有地址就不用让用户再点一次「新增」
      _loading = false;
    });
  }

  Future<void> _saveNew() async {
    if (_saving) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final region = _region.text.trim();
    final detail = _detail.text.trim();
    if (name.isEmpty) {
      CenterToast.show(context, '请填写收货人姓名');
      return;
    }
    if (phone.length < 6) {
      CenterToast.show(context, '请填写正确的手机号');
      return;
    }
    if (detail.isEmpty) {
      CenterToast.show(context, '请填写详细地址');
      return;
    }
    setState(() => _saving = true);
    try {
      final list = await SettingsService.saveAddress(
        name: name,
        phone: phone,
        region: region,
        detail: detail,
        isDefault: _list.isEmpty, // 第一条自动设为默认地址
      );
      if (!mounted) return;
      UserAddress? saved;
      for (final a in list) {
        if (a.name == name && a.phone == phone && a.detail == detail) {
          saved = a;
        }
      }
      if (saved == null && list.isNotEmpty) saved = list.last;
      if (saved != null) {
        Navigator.of(context).pop(saved); // 存好就直接去下单
      } else {
        setState(() {
          _saving = false;
          _list = list;
          _picked = list.isEmpty ? null : list.first;
          _formMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        CenterToast.show(context, '保存地址失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: _formMode ? _formBody() : _listBody(),
                ),
              ),
            if (!_loading) _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formMode && !_loading ? '添加收货地址' : '选择收货地址',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    _formMode && !_loading
                        ? '填好后会自动同步到「设置 → 收货地址」'
                        : '选好后还要最后确认一次，确认前不会扣积分',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 20),
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      );

  // ---------------- 已有地址列表 ----------------

  Widget _listBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in _list) ...[
            _addrTile(a),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
          OutlinedButton.icon(
            onPressed: () => setState(() => _formMode = true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('使用新地址'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              side: const BorderSide(color: AppTheme.border),
              foregroundColor: AppTheme.primary,
            ),
          ),
        ],
      );

  Widget _addrTile(UserAddress a) {
    final on = _picked?.id == a.id;
    return GestureDetector(
      onTap: () => setState(() => _picked = a),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: on ? AppTheme.primarySoft : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: on ? AppTheme.primary : AppTheme.border,
            width: on ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: on ? AppTheme.primary : AppTheme.textTertiary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(a.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(a.maskedPhone,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                      if (a.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentLight,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text('默认',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentDark)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(a.fullAddress,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 新地址表单 ----------------

  Widget _formBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_list.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _formMode = false),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('选择已有地址'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  foregroundColor: AppTheme.textSecondary,
                ),
              ),
            ),
          _field(_name, '收货人', hint: '请填写收货人姓名', key: 'checkout_name'),
          const SizedBox(height: 10),
          _field(_phone, '手机号',
              hint: '请填写手机号', keyboard: TextInputType.phone, key: 'checkout_phone'),
          const SizedBox(height: 10),
          _field(_region, '所在地区', hint: '省 / 市 / 区（选填）', key: 'checkout_region'),
          const SizedBox(height: 10),
          _field(_detail, '详细地址',
              hint: '街道、门牌号、楼栋单元', maxLines: 2, key: 'checkout_detail'),
        ],
      );

  Widget _field(TextEditingController c, String label,
      {String? hint,
      TextInputType? keyboard,
      int maxLines = 1,
      String? key}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12.5, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          key: key == null ? null : ValueKey(key),
          controller: c,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: AppTheme.primarySoft,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- 底部按钮 ----------------

  Widget _footer() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 46,
              child: ElevatedButton(
                key: ValueKey(_formMode ? 'checkout_save' : 'checkout_confirm'),
                onPressed: _saving
                    ? null
                    : (_formMode
                        ? _saveNew
                        : (_picked == null
                            ? null
                            : () => Navigator.of(context).pop(_picked))),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_formMode
                        ? '保存并使用这个地址'
                        : '使用这个地址'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formMode
                  ? '保存后地址会同步到「设置 → 收货地址」，兑换前还会再确认一次'
                  : '这一步只是选地址，点下一步才确认兑换、才扣积分',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textTertiary),
            ),
          ],
        ),
      );
}
