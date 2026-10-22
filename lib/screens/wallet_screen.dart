import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/wallet.dart';
import '../services/session_provider.dart';
import '../services/wallet_service.dart';
import '../widgets/center_toast.dart';

/// 钱包（v27）：余额 + 积分 + 流水 + 充值
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletInfo _info = const WalletInfo();
  List<WalletLog> _logs = const [];
  List<ChargePlan> _plans = const [];
  bool _loading = true;
  int _logPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await WalletService.info();
      final plans = await WalletService.chargePlans();
      final logs = await WalletService.logs(page: 1);
      if (!mounted) return;
      setState(() {
        _info = info;
        _plans = plans;
        _logs = logs;
        _logPage = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _loadMoreLogs() async {
    try {
      final more = await WalletService.logs(page: _logPage + 1);
      if (!mounted || more.isEmpty) return;
      setState(() {
        _logPage++;
        _logs = [..._logs, ...more];
      });
    } catch (_) {/* 静默 */}
  }

  Future<void> _charge() async {
    if (_plans.isEmpty) {
      CenterToast.show(context, '后台暂未配置充值档位');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChargeSheet(
        plans: _plans,
        onConfirm: (plan) async {
          Navigator.of(context).pop();
          try {
            final order = await WalletService.charge(plan.id);
            if (!mounted) return;
            _showOrderDialog(order);
          } catch (e) {
            if (mounted) {
              CenterToast.show(
                  context, e.toString().replaceAll('Exception: ', ''));
            }
          }
        },
      ),
    );
  }

  void _showOrderDialog(ChargeOrder order) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        title: const Text('充值单已创建', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('金额：¥${order.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 6),
            const Text(
                '请按后台提供的收款方式完成转账，管理员确认到账后余额自动到账，并附赠赠送余额与积分。',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _load();
            },
            child: const Text('知道了', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('我的钱包', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            _balanceCard(),
            const SizedBox(height: 12),
            _actionsRow(),
            const SizedBox(height: 12),
            _summaryRow(),
            const SizedBox(height: 16),
            const Text('收支明细',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_loading && _logs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primary)),
              )
            else if (_logs.isEmpty)
              _emptyLogs()
            else
              ..._logs.map(_logTile),
            if (_logs.length >= 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: _loadMoreLogs,
                  child: const Text('加载更多',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard() {
    return Container(
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
          Text('账户余额（元）',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8), fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('¥',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              Text(_info.balance.toStringAsFixed(2),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.05)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: AppTheme.star),
                const SizedBox(width: 8),
                Text('${_info.pointsName} ',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12)),
                Text('${_info.points}',
                    style: const TextStyle(
                        color: AppTheme.star,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('可用于积分兑换',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsRow() {
    return Row(
      children: [
        Expanded(
          child: _actionButton('充值', Icons.add_card_outlined, _charge),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton('会员中心', Icons.workspace_premium_outlined, () {
            Navigator.of(context).pushNamed('/member-center');
          }),
        ),
      ],
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: AppTheme.primary),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow() {
    return Row(
      children: [
        _summaryCell('累计收入', '¥${_info.totalIn.toStringAsFixed(2)}', AppTheme.primary),
        _summaryCell('累计支出', '¥${_info.totalOut.toStringAsFixed(2)}', AppTheme.danger),
        _summaryCell('累计获得', '${_info.totalPoints}', AppTheme.star),
      ],
    );
  }

  Widget _summaryCell(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _logTile(WalletLog log) {
    final income = log.isIncome;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
              color: income ? AppTheme.primaryLight : AppTheme.dangerLight,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(
              income ? Icons.south_west : Icons.north_east,
              size: 17,
              color: income ? AppTheme.primary : AppTheme.danger,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.title.isEmpty ? '收支' : log.title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (log.remark.isNotEmpty) log.remark,
                    _fmt(log.createdAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${income ? '+' : '-'}¥${log.amount.abs().toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: income ? AppTheme.primary : AppTheme.danger),
              ),
              if (log.pointsDelta != 0) ...[
                const SizedBox(height: 2),
                Text('${log.pointsDelta > 0 ? '+' : ''}${log.pointsDelta} ${_info.pointsName}',
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyLogs() => Container(
        padding: const EdgeInsets.symmetric(vertical: 34),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 38, color: AppTheme.textSecondary),
            SizedBox(height: 8),
            Text('暂无收支记录',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
          ],
        ),
      );

  static String _fmt(String iso) {
    if (iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// 充值档位选择弹层
class _ChargeSheet extends StatefulWidget {
  final List<ChargePlan> plans;
  final void Function(ChargePlan plan) onConfirm;
  const _ChargeSheet({required this.plans, required this.onConfirm});

  @override
  State<_ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends State<_ChargeSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final selected = _selected ?? (widget.plans.isNotEmpty ? widget.plans.first.id : null);
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppTheme.radiusLg),
          topRight: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('余额充值',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('选择档位后生成充值单，管理员确认到账后余额与赠送一并到账',
              style: TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: widget.plans.map((p) {
              final active = selected == p.id;
              return GestureDetector(
                onTap: () => setState(() => _selected = p.id),
                child: Container(
                  width: (MediaQuery.of(context).size.width - 42) / 3,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.primaryLight : AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                        color: active ? AppTheme.primary : AppTheme.primaryBorder),
                  ),
                  child: Column(
                    children: [
                      Text('¥${_trim(p.amount)}',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: active
                                  ? AppTheme.primaryDark
                                  : AppTheme.textPrimary)),
                      if (p.bonus > 0) ...[
                        const SizedBox(height: 3),
                        Text('赠 ¥${_trim(p.bonus)}',
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.primary)),
                      ],
                      if (p.pointsBonus > 0) ...[
                        const SizedBox(height: 2),
                        Text('赠 ${p.pointsBonus} 积分',
                            style: const TextStyle(
                                fontSize: 10, color: AppTheme.textSecondary)),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: selected == null
                  ? null
                  : () {
                      final plan =
                          widget.plans.firstWhere((p) => p.id == selected);
                      widget.onConfirm(plan);
                    },
              child: const Text('生成充值单',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}

/// 钱包入口（我的页跳转用，带登录态）
class WalletEntry {
  static Future<void> open(BuildContext context) async {
    final session = context.read<SessionProvider>();
    if (!session.isLoggedIn) {
      CenterToast.show(context, '请先登录');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WalletScreen()),
    );
  }
}
