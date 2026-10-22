import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/signin.dart';
import '../services/session_provider.dart';
import '../services/signin_service.dart';
import '../widgets/center_toast.dart';

/// 每日签到 / 每日任务（v27，参考图一，配色沿用 App 青绿 + 暖金）
class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  SigninStatus _status = SigninService.fallback;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await SigninService.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _checkin() async {
    if (_submitting || _status.signedToday) return;
    setState(() => _submitting = true);
    try {
      final r = await SigninService.checkin();
      if (!mounted) return;
      setState(() {
        _status = r.status;
        _submitting = false;
      });
      _showReward(r.reward, r.streak);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showReward(SigninReward reward, int streak) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppTheme.starLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🎁', style: TextStyle(fontSize: 32)),
              ),
              const SizedBox(height: 14),
              const Text('签到成功',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('已连续签到 $streak 天',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  reward.describe(_status.pointsName),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryDark),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('开心收下',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('每日任务', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            if (_loading) _loadingBar(),
            _signinCard(),
            const SizedBox(height: 14),
            _tasksCard(),
            const SizedBox(height: 14),
            _rulesCard(),
          ],
        ),
      ),
    );
  }

  Widget _loadingBar() => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: LinearProgressIndicator(
            minHeight: 2, color: AppTheme.primary, backgroundColor: AppTheme.divider),
      );

  /// 签到奖励卡（7 天循环）
  Widget _signinCard() {
    final rewards = _status.rewards;
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Text('签到领奖励',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('本周已签到 ${_status.streak % 7 == 0 && _status.streak > 0 ? 7 : _status.streak % 7} 天',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 11.5)),
              const Spacer(),
              if (_status.signedToday)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('明天再来哦',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 7 天格子
          Row(
            children: List.generate(7, (i) {
              final done = i < (_status.streak % 7 == 0 && _status.streak > 0 ? 7 : _status.streak % 7);
              final isToday = i + 1 == _status.dayIndex && !_status.signedToday;
              final r = i < rewards.length ? rewards[i] : const SigninReward();
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
                  child: _dayCell(
                    day: i + 1,
                    reward: r,
                    done: done,
                    isToday: isToday,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _status.signedToday
                    ? Colors.white.withOpacity(0.28)
                    : AppTheme.star,
                foregroundColor: _status.signedToday ? Colors.white : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: _status.signedToday ? null : _checkin,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      _status.signedToday ? '今日已签到' : '立即签到',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell({
    required int day,
    required SigninReward reward,
    required bool done,
    required bool isToday,
  }) {
    final highlight = isToday;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: done
            ? Colors.white.withOpacity(0.22)
            : (highlight ? Colors.white : Colors.white.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: highlight
            ? Border.all(color: AppTheme.star, width: 1.4)
            : null,
      ),
      child: Column(
        children: [
          Text('+${reward.points}',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: done ? AppTheme.star : Colors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text('$day',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 3),
          Text('${day}天',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8), fontSize: 9.5)),
        ],
      ),
    );
  }

  /// 每日任务（引导型）
  Widget _tasksCard() {
    final tasks = <({String title, String desc, String reward, IconData icon})>[
      (title: '发布 1 条渔获', desc: '每日发布 1 条渔获贴', reward: '+积分', icon: Icons.phishing_outlined),
      (title: '分享抽奖活动', desc: '每日首次分享抽奖活动', reward: '+1', icon: Icons.ios_share_outlined),
      (title: '发布任意类型帖', desc: '每日首次发布帖子', reward: '+1', icon: Icons.edit_outlined),
      (title: '发布 2 条评论', desc: '每日发布任意 2 条评论', reward: '+1', icon: Icons.chat_bubble_outline),
      (title: '关注 2 名用户', desc: '每日新关注 2 名钓友', reward: '+1', icon: Icons.person_add_alt_outlined),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日任务',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('完成任务可获得积分奖励，发布渔获还有额外积分',
              style: TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          for (final t in tasks)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(t.icon, size: 18, color: AppTheme.primary),
              ),
              title: Text(t.title,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              subtitle: Text(t.desc,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text('去完成',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rulesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              const Text('签到规则',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _status.rules.isEmpty
                ? '每日可签到 1 次；连续签到 7 天为一个周期，中断后从第 1 天重新开始。'
                : _status.rules,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text('当前余额 ¥${_status.balance.toStringAsFixed(2)} · ${_status.pointsName} ${_status.points}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 登录后自动弹出的每日签到窗口（后台「签到设置」可开关）
/// 返回 true 表示已弹出过（用于首页做「每天只弹一次」的本地闸门）。
Future<bool> showSigninDialog(BuildContext context) async {
  if (!context.mounted) return false;
  SigninStatus status;
  try {
    status = await SigninService.status();
  } catch (_) {
    return false; // 拉不到就安静不弹，避免打扰
  }
  if (!context.mounted) return false;
  if (!status.enabled || !status.autoPopup || status.signedToday) return false;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _SigninDialog(status: status),
  );
  return true;
}

class _SigninDialog extends StatefulWidget {
  final SigninStatus status;
  const _SigninDialog({required this.status});

  @override
  State<_SigninDialog> createState() => _SigninDialogState();
}

class _SigninDialogState extends State<_SigninDialog> {
  late SigninStatus _status = widget.status;
  bool _busy = false;
  SigninReward? _got;

  Future<void> _checkin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await SigninService.checkin();
      if (!mounted) return;
      setState(() {
        _status = r.status;
        _got = r.reward;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final name = session.nickname ?? '钓友';
    final rewards = _status.rewards;
    final doneCount = _status.streak % 7 == 0 && _status.streak > 0 ? 7 : _status.streak % 7;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryDark, AppTheme.primary],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusLg),
                  topRight: Radius.circular(AppTheme.radiusLg),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                      const Text('每日签到',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.close,
                            size: 19, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('$name，今天也要元气满满',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('已连续签到 ',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary)),
                      Text('${_status.streak}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary)),
                      const Text(' 天，共 ',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary)),
                      Text('${_status.total}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary)),
                      const Text(' 天',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(7, (i) {
                      final done = i < doneCount;
                      final isToday = i + 1 == _status.dayIndex;
                      final r = i < rewards.length ? rewards[i] : const SigninReward();
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 6 ? 0 : 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: done
                                  ? AppTheme.primaryLight
                                  : (isToday ? AppTheme.starLight : AppTheme.primarySoft),
                              borderRadius: BorderRadius.circular(9),
                              border: isToday && !_status.signedToday
                                  ? Border.all(
                                      color: AppTheme.star, width: 1.3)
                                  : null,
                            ),
                            child: Column(
                              children: [
                                Text('+${r.points}',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: done
                                            ? AppTheme.primary
                                            : AppTheme.textSecondary)),
                                const SizedBox(height: 4),
                                Text('${i + 1}天',
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  if (_got != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.starLight,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Text('🎉 获得 ${_got!.describe(_status.pointsName)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.warning)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _status.signedToday
                            ? AppTheme.border
                            : AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22)),
                      ),
                      onPressed: _status.signedToday
                          ? () => Navigator.of(context).pop()
                          : _checkin,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              _status.signedToday ? '今日已签到' : '立即签到',
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SigninScreen(),
                      ));
                    },
                    child: const Text('查看每日任务',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
