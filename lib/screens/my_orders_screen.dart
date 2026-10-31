import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/ui_kit.dart';
import '../models/my_order.dart';
import '../services/shop_service.dart';
import '../widgets/center_toast.dart';
import 'mall_screen.dart';
import '../widgets/app_refresh.dart';

/// 我的订单：商城（积分兑换 / 现金登记）的完整订单中心
///
/// 之前只在「我的」页弹一个底部小栏，只有商品名 + 金额 + 状态文字，
/// 不能筛选、看不到图片、点不进详情、也没法取消或确认收货。
/// 这里做成独立页面：
///   · 顶部五个状态页签（全部 / 待发货 / 已发货 / 已完成 / 已取消）
///   · 订单卡片带商品图、单价×数量、合计、下单时间、状态徽章
///   · 待发货可取消（积分单原路退积分）、已发货可确认收货
///   · 点卡片展开订单详情，下拉刷新
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  // 惰性初始化 + dispose 时首次访问 = 退出页面必崩（见 article_list_screen 注释）
  late final TabController _tab;

  static const _filters = <({String label, int? status})>[
    (label: '全部', status: null),
    (label: '待发货', status: 0),
    (label: '已发货', status: 1),
    (label: '已完成', status: 2),
    (label: '已取消', status: 3),
  ];

  List<MyOrder>? _orders; // null = 首次加载中
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _filters.length, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    final list = await ShopService.fetchMyOrders();
    if (!mounted) return;
    _busy = false;
    setState(() => _orders = list);
  }

  List<MyOrder> get _visible {
    final all = _orders ?? const <MyOrder>[];
    final st = _filters[_tab.index].status;
    if (st == null) return all;
    return all.where((o) => o.status == st).toList();
  }

  int _countOf(int? status) {
    final all = _orders ?? const <MyOrder>[];
    if (status == null) return all.length;
    return all.where((o) => o.status == status).length;
  }

  // ------------------------------------------------------------
  // 操作：取消 / 确认收货
  // ------------------------------------------------------------
  Future<void> _cancel(MyOrder o) async {
    final ok = await _confirm(
      title: '取消这笔订单？',
      body: o.isPoints
          ? '取消后会把这 ${o.amount} 积分原路退回你的账户。'
          : '这是未支付的登记订单，取消后不可恢复。',
      danger: true,
    );
    if (ok != true) return;
    final r = await ShopService.cancelOrder(o.id);
    if (!mounted) return;
    CenterToast.show(
        context, r.ok ? (r.pointsBack > 0 ? '已取消，退回 ${r.pointsBack} 积分' : r.msg) : r.msg);
    if (r.ok) await _load();
  }

  Future<void> _confirmReceive(MyOrder o) async {
    final ok = await _confirm(
      title: '确认已经收到货了？',
      body: '确认后订单结束。没收到货请不要确认，可以先联系客服。',
    );
    if (ok != true) return;
    final r = await ShopService.confirmOrder(o.id);
    if (!mounted) return;
    CenterToast.show(context, r.ok ? '已确认收货' : r.msg);
    if (r.ok) await _load();
  }

  /// 删除订单记录
  ///
  /// 只作用于「已完成 / 已取消」的订单（[MyOrder.canDelete]）：
  /// 待发货的必须先取消（要退积分、恢复库存），不能直接抹掉。
  Future<void> _delete(MyOrder o) async {
    final ok = await _confirm(
      title: '删除这笔订单？',
      body: '删除后这条记录不再出现在「我的订单」里，订单已结束，'
          '不影响已到账的积分和商品。',
      danger: true,
    );
    if (ok != true) return;
    final r = await ShopService.deleteOrder(o.id);
    if (!mounted) return;
    CenterToast.show(context, r.ok ? '订单已删除' : r.msg);
    if (r.ok) await _load();
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        title: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(body,
            style: const TextStyle(
                fontSize: 13.5, color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('确定',
                style: TextStyle(
                    color: danger ? AppTheme.danger : AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // 详情
  // ------------------------------------------------------------
  void _openDetail(MyOrder o) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _OrderDetail(
        order: o,
        onCancel: o.canCancel ? () {
          Navigator.of(ctx).pop();
          _cancel(o);
        } : null,
        onConfirm: o.canConfirm ? () {
          Navigator.of(ctx).pop();
          _confirmReceive(o);
        } : null,
        onDelete: o.canDelete ? () {
          Navigator.of(ctx).pop();
          _delete(o);
        } : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('我的订单'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: AppTheme.surface,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13.5),
              tabs: [
                for (final f in _filters)
                  Tab(
                    height: 44,
                    text: _countOf(f.status) > 0
                        ? '${f.label} ${_countOf(f.status)}'
                        : f.label,
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_orders == null) return const _OrderSkeleton();
    if (_orders!.isEmpty) {
      return AppRefresh(
        onRefresh: _load,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.16),
            _EmptyState(
              title: '还没有订单',
              body: '去商城看看，积分可以兑换实物装备',
              action: '去商城逛逛',
              // ★ 这里原来只写了 Navigator.pop() —— 只把订单页关掉，人还停在
              //   「我的」页面，看起来就是"点了没反应"。改成直接把订单页换成
              //   商城页（pushReplacement）：从商城返回时回到「我的」，
              //   不会再退回到一个空订单页。
              onAction: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const MallScreen()),
              ),
            ),
          ],
        ),
      );
    }
    final list = _visible;
    return AppRefresh(
      onRefresh: _load,
      color: AppTheme.primary,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.16),
                _EmptyState(
                  title: '这个状态下没有订单',
                  body: '换个页签看看',
                  action: '看全部订单',
                  onAction: () {
                    _tab.animateTo(0);
                  },
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final o = list[i];
                return _OrderCard(
                  order: o,
                  onTap: () => _openDetail(o),
                  onCancel: o.canCancel ? () => _cancel(o) : null,
                  onConfirm: o.canConfirm ? () => _confirmReceive(o) : null,
                );
              },
            ),
    );
  }
}

// ============================================================
// 订单卡片
// ============================================================
class _OrderCard extends StatelessWidget {
  final MyOrder order;
  final VoidCallback onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  const _OrderCard({
    required this.order,
    required this.onTap,
    this.onCancel,
    this.onConfirm,
  });

  static Color statusColor(int s) {
    switch (s) {
      case 1:
        return AppTheme.accentDark;
      case 2:
        return AppTheme.primary;
      case 3:
        return AppTheme.textSecondary;
      default:
        return AppTheme.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = statusColor(order.status);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          boxShadow: AppTheme.lightShadow,
        ),
        child: Column(
          children: [
            // 顶部：订单号 + 状态
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Text('订单号 ${_shortId(order.id)}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(order.label,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: c,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.divider),
            // 商品行
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(url: order.productImage),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _Tag(text: order.typeLabel,
                                color: order.isPoints
                                    ? AppTheme.star
                                    : AppTheme.accentDark),
                            const SizedBox(width: 6),
                            Text('${order.unitText} × ${order.quantity}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(order.createdAtText,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(order.amountText,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text('共 ${order.quantity} 件',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            // 底部操作
            if (onCancel != null || onConfirm != null) ...[
              const Divider(height: 1, color: AppTheme.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onCancel != null)
                      _GhostBtn(label: '取消订单', onTap: onCancel!),
                    if (onCancel != null && onConfirm != null)
                      const SizedBox(width: 8),
                    if (onConfirm != null)
                      _SolidBtn(label: '确认收货', onTap: onConfirm!),
                  ],
                ),
              ),
            ] else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  static String _shortId(String id) {
    if (id.length <= 10) return id;
    return '…${id.substring(id.length - 10)}';
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  const _Thumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 64,
        height: 64,
        color: AppTheme.primarySoft,
        child: url.isEmpty
            ? const Icon(Icons.inventory_2_outlined,
                color: AppTheme.primary, size: 26)
            : Image.network(
                url,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.inventory_2_outlined,
                    color: AppTheme.primary,
                    size: 26),
              ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12.5, color: AppTheme.textSecondary)),
      ),
    );
  }
}

class _SolidBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SolidBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                color: Colors.white,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ============================================================
// 订单详情
// ============================================================
class _OrderDetail extends StatelessWidget {
  final MyOrder order;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final VoidCallback? onDelete;
  const _OrderDetail({
    required this.order,
    this.onCancel,
    this.onConfirm,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = _OrderCard.statusColor(order.status);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('订单详情',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(order.label,
                      style: TextStyle(
                          fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(url: order.productImage),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.productName,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('${order.unitText} × ${order.quantity}',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Text(order.amountText,
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.divider),
            const SizedBox(height: 12),
            _kv('订单号', order.id),
            _kv('下单时间', order.createdAtText),
            _kv('购买方式', order.typeLabel),
            _kv('数量', '${order.quantity}'),
            if (order.remark.isNotEmpty) _kv('备注', order.remark),
            if (order.canCancel)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('商家还没发货，可以取消；积分兑换会原路退回积分。',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ),
            if (order.canConfirm)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('收到货后请点「确认收货」，我们才能结算给商家。',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ),
            if (order.canDelete)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('订单已结束，可以删掉这条记录，列表会更清爽。',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Text('关闭',
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textSecondary)),
                    ),
                  ),
                ),
                if (onCancel != null || onConfirm != null || onDelete != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onConfirm ?? onCancel ?? onDelete,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: onConfirm != null
                              ? AppTheme.primary
                              : (onCancel != null
                                  ? AppTheme.danger
                                  : AppTheme.danger.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(12),
                          border: onDelete != null
                              ? Border.all(color: AppTheme.danger.withOpacity(0.35))
                              : null,
                        ),
                        child: Text(
                            onConfirm != null
                                ? '确认收货'
                                : (onCancel != null ? '取消订单' : '删除订单'),
                            style: TextStyle(
                                fontSize: 14,
                                color: onDelete != null
                                    ? AppTheme.danger
                                    : Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.textPrimary)),
            ),
          ],
        ),
      );
}

// ============================================================
// 空态 / 骨架
// ============================================================
class _EmptyState extends StatelessWidget {
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  const _EmptyState({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  // v2.1.59：空状态统一走 UiEmptyState（黑底胶囊按钮 + 圆角方形图标底），
  // 原来这里是自己拼的一套「浅灰圆 + 浅灰胶囊按钮」，和发现页/我的页
  // 的空状态不是同一个长相。
  @override
  Widget build(BuildContext context) {
    return Center(
      child: UiEmptyState(
        icon: Icons.receipt_long_outlined,
        title: title,
        desc: body,
        actionLabel: action,
        onAction: onAction,
      ),
    );
  }
}

/// 首屏骨架：三张灰卡片，避免全屏转圈（用户讨厌满屏 spinner）
class _OrderSkeleton extends StatelessWidget {
  const _OrderSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(0.75, 13),
                  const SizedBox(height: 8),
                  _bar(0.45, 11),
                  const SizedBox(height: 8),
                  _bar(0.3, 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double w, double h) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: w,
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}
