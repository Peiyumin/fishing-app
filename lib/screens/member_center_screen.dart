import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/member.dart';
import '../models/member_plan.dart';
import '../services/member_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/app_refresh.dart';
import '../utils/json_num.dart';

/// 会员中心（v27，参考图三 / 图四）
/// 配色沿用 App 青绿主题：深湖绿渐变头部 + 暖金强调，权益网格 + 套餐选择
class MemberCenterScreen extends StatefulWidget {
  const MemberCenterScreen({super.key});

  @override
  State<MemberCenterScreen> createState() => _MemberCenterScreenState();
}

class _MemberCenterScreenState extends State<MemberCenterScreen> {
  MemberCenter _center = const MemberCenter();
  List<MemberPlan> _plans = const [];
  MemberInfo _info = const MemberInfo();
  bool _loading = true;
  String _planId = '';
  String _payType = 'points'; // points 积分 / balance 余额 / cash 现金
  // `_center` 是不可空类型（默认空对象），不能拿它判「有没有拉到过」——
  // 之前写成 `_center == null` 恒为 false，等于首屏永远不转圈。单独记一个标志。
  bool _loadedOnce = false;
  bool _buying = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 已经拿到过数据时刷新不清空（只更新内容），避免整块消失闪白
    setState(() => _loading = !_loadedOnce);
    try {
      final r = await MemberService.plans();
      final info = await MemberService.info();
      if (!mounted) return;
      setState(() {
        _center = r.center;
        _plans = r.plans;
        _info = info;
        _planId = _plans.isNotEmpty ? _plans.first.id : '';
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _buy() async {
    if (_planId.isEmpty) {
      CenterToast.show(context, '请选择套餐');
      return;
    }
    if (!_agreed) {
      CenterToast.show(context, '请先勾选同意会员协议');
      return;
    }
    final plan = _plans.firstWhere((p) => p.id == _planId);
    final payName =
        _payType == 'points' ? '积分兑换' : (_payType == 'balance' ? '余额支付' : '现金支付');
    final confirmText = _payType == 'points'
        ? '将扣除 ${plan.pointsPrice} 积分，兑换 ${plan.name}（${plan.days} 天）'
        : _payType == 'balance'
            ? '将扣除余额 ¥${plan.price.toStringAsFixed(2)}，购买 ${plan.name}（${plan.days} 天）'
            : '将创建现金订单（¥${plan.price.toStringAsFixed(2)}），需后台确认后生效';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        title: const Text('确认开通', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('支付方式：$payName', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text(confirmText,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _buying = true);
    try {
      final r = await MemberService.buy(_planId, _payType);
      if (!mounted) return;
      if (r.info != null) setState(() => _info = r.info!);
      CenterToast.show(context, r.msg);
      if (r.ok && r.info != null && r.info!.active) {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final style = _info.active ? MemberStyle.fromLevel(_info.level) : MemberStyle.normal;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('会员中心', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Navigator.of(context).pushNamed('/member-orders');
              if (data == true) _load();
            },
            child: const Text('我的订单',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : AppRefresh(
              color: AppTheme.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _hero(style, session.nickname ?? '钓友'),
                  _perksGrid(),
                  _planSelector(),
                  _agreementRow(),
                  _buyButton(),
                  if (_info.active) _activeHint(),
                ],
              ),
            ),
    );
  }

  // ─────────────── 头部 ───────────────
  Widget _hero(MemberStyle style, String nickname) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _center.title.isEmpty ? 'FISHMAN PRO · 钓鱼佬会员' : _center.title,
                      style: TextStyle(
                          color: AppTheme.star,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _center.headline.isEmpty ? '找准钓点，看透鱼情' : _center.headline,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _center.subheadline.isEmpty ? '少空军一次就值回' : _center.subheadline,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.phishing, size: 46, color: Colors.white24),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined,
                        size: 13, color: AppTheme.star),
                    const SizedBox(width: 5),
                    Text(
                      _center.badgeText.isEmpty ? '高手都在用' : _center.badgeText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _info.active ? '${style.name} · 剩余 ${_info.daysLeft} 天' : '未开通',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────── 权益网格（图四） ───────────────
  Widget _perksGrid() {
    final perks = _center.perks.isEmpty
        ? [
            const MemberPerk(icon: 'nearby', title: '附近钓友', desc: '发现身边的钓友'),
            const MemberPerk(icon: 'fish', title: 'AI 鱼种识别', desc: '照片自动识别'),
            const MemberPerk(icon: 'wallet', title: '余额充值', desc: '充值更划算'),
            const MemberPerk(icon: 'vip', title: '尊贵标识', desc: '专属 VIP 标识'),
          ]
        : _center.perks;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('全部会员权益',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('${perks.length} PERKS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 76,
            ),
            itemCount: perks.length,
            itemBuilder: (_, i) {
              final p = perks[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(MemberService.perkIconOf(p.icon),
                          size: 18, color: AppTheme.primaryDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          if (p.desc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(p.desc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─────────────── 套餐选择 ───────────────
  Widget _planSelector() {
    if (_plans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Text('后台暂未配置会员套餐，请先在「运营配置 → 会员套餐」添加',
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary, height: 1.5)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        children: [
          for (final plan in _plans) _planCard(plan),
        ],
      ),
    );
  }

  Widget _planCard(MemberPlan plan) {
    final active = plan.id == _planId;
    final dPct = plan.discountPct;
    return GestureDetector(
      onTap: () => setState(() => _planId = plan.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryLight : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
              color: active ? AppTheme.primary : AppTheme.border, width: active ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                    color: active ? AppTheme.primary : AppTheme.border, width: 1.4),
              ),
              child: active
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(plan.name.isEmpty ? '会员套餐' : plan.name,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800)),
                      if (plan.badge.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.starLight,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(plan.badge,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  color: AppTheme.warning,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${plan.days} 天 · 折合 ${plan.perMonth.toStringAsFixed(plan.perMonth < 10 ? 1 : 0)} 元/月',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (plan.price > 0)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('¥',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                      const SizedBox(width: 1),
                      Text(_trim(plan.price),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                              height: 1.05)),
                    ],
                  )
                else
                  Text('${plan.pointsPrice} 积分',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                if (plan.originalPrice > plan.price)
                  Text('¥${_trim(plan.originalPrice)}',
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textSecondary,
                          decoration: TextDecoration.lineThrough)),
                if (dPct > 0)
                  Text('省 $dPct%',
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── 支付方式 ───────────────
  Widget _agreementRow() {
    final ags = _center.agreements.isNotEmpty
        ? _center.agreements
        : const ['用户协议', '隐私政策', '会员服务协议'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              activeColor: AppTheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final a in ags) ...[
                  if (a != ags.first) const Text('、'),
                  Text('《$a》',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buyButton() {
    final plan = _plans.isEmpty ? null : _plans.firstWhere((p) => p.id == _planId, orElse: () => _plans.first);
    final canPoints = plan != null && plan.supportsPoints;
    final canBalance = plan != null && plan.supportsBalance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          // 支付方式切换
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              children: [
                _payChip('points', '积分兑换', canPoints, _info.points),
                _payChip('balance', '余额支付', canBalance, _info.balance),
                _payChip('cash', '现金支付', true, null),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: _buying ? null : _buy,
              child: _buying
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      plan == null
                          ? '暂无可用套餐'
                          : (_payType == 'points'
                              ? '${plan.pointsPrice} 积分兑换 · ${plan.name}'
                              : _payType == 'balance'
                                  ? '余额支付 · ¥${plan.price.toStringAsFixed(2)}'
                                  : '现金支付 · ¥${plan.price.toStringAsFixed(2)}'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _payChip(String key, String label, bool enabled, num? value) {
    final active = _payType == key;
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? () => setState(() => _payType = key) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: active ? Border.all(color: AppTheme.primary) : null,
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: enabled
                          ? (active ? AppTheme.primary : AppTheme.textSecondary)
                          : AppTheme.textSecondary.withOpacity(0.45))),
              if (value != null) ...[
                const SizedBox(height: 2),
                Text(
                  key == 'points' ? '余额 $value' : '余额 ¥${_trim(value.toDouble())}',
                  style: TextStyle(
                      fontSize: 9.5,
                      color: (active ? AppTheme.primary : AppTheme.textSecondary)
                          .withOpacity(0.75)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium,
                size: 18, color: AppTheme.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _info.expire.isEmpty
                    ? '会员已生效'
                    : '会员有效期至 ${_info.expire.substring(0, 10)}，到期后自动恢复普通用户',
                style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.primaryDark,
                    height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}

/// 会员订单列表
class MemberOrdersScreen extends StatefulWidget {
  const MemberOrdersScreen({super.key});

  @override
  State<MemberOrdersScreen> createState() => _MemberOrdersScreenState();
}

class _MemberOrdersScreenState extends State<MemberOrdersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 已有订单时刷新不清空列表，避免整块消失闪白
    setState(() => _loading = _orders.isEmpty);
    try {
      final list = await MemberService.orders();
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('会员订单')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _orders.isEmpty
              ? const Center(
                  child: Text('暂无订单',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)))
              : AppRefresh(
                  color: AppTheme.primary,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _orders.length,
                    itemBuilder: (_, i) {
                      final o = _orders[i];
                      final st = jsonInt(o['status']) ?? 0;
                      final label =
                          st == 1 ? '已生效' : (st == 2 ? '已取消' : '待确认');
                      final color = st == 1
                          ? AppTheme.primary
                          : (st == 2 ? AppTheme.danger : AppTheme.warning);
                      final amount = jsonDouble(o['amount']) ?? 0;
                      final pointsCost = jsonInt(o['pointsCost']) ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${o['planName'] ?? '会员套餐'}',
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${o['days'] ?? 0} 天 · '
                                    '${amount > 0 ? '¥${amount.toStringAsFixed(2)}' : (pointsCost > 0 ? '$pointsCost 积分' : '—')}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(label,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
