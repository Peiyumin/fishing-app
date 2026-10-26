import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/signin.dart';
import '../services/session_provider.dart';
import '../services/signin_service.dart';
import '../widgets/center_toast.dart';
import 'discover_screen.dart';
import 'nearby_anglers_screen.dart';
import 'publish_catch_screen.dart';
import 'publish_hub_screen.dart';
import '../widgets/app_refresh.dart';

/// 每日签到 / 每日任务（v27，参考图一，配色沿用 App 青绿 + 暖金）
class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  /// 预览/测试钩子：给定时直接当作首屏状态，不请求接口
  ///
  /// 生产环境恒为 null（登录后由接口给真实数据）。
  /// 只有本地 web 预览入口会用它，用来把「今天这格」「已完成待领」
  /// 这些平时很难凑出来的状态渲染出来看。
  static SigninStatus? debugStatus;

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  SigninStatus _status = SigninService.fallback;
  bool _loading = true;
  bool _submitting = false;

  /// 正在领奖的任务 key（防止连点重复提交）
  String? _claiming;

  @override
  void initState() {
    super.initState();
    final dbg = SigninScreen.debugStatus;
    if (dbg != null) {
      _status = dbg;
      _loading = false;
      return;
    }
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
                // 原来是 '🎁' emoji：缺彩色 emoji 字体时是方块
                child: const Icon(Icons.card_giftcard,
                    size: 34, color: AppTheme.starDark),
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
      body: AppRefresh(
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
    // ★ 修掉「第一个格子一片空白」的 bug：
    //   原来 isToday 时底色刷成纯白（Colors.white），而里面
    //   「+5」「1」「1天」的文字颜色都是 Colors.white —— 白字白底，
    //   整格看起来就是空的。今天这格改成「白底 + 深色字」。
    final textColor =
        isToday ? AppTheme.primaryDark : Colors.white;
    final subColor = isToday
        ? AppTheme.primaryDark.withOpacity(0.72)
        : Colors.white.withOpacity(0.8);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: done
            ? Colors.white.withOpacity(0.22)
            : (isToday ? Colors.white : Colors.white.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: isToday
            ? Border.all(color: AppTheme.star, width: 1.4)
            : null,
      ),
      child: Column(
        children: [
          Text('+${reward.points}',
              style: TextStyle(
                  color: textColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: done
                  ? AppTheme.star
                  : (isToday
                      ? AppTheme.star
                      : Colors.white.withOpacity(0.25)),
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
          Text('${day}天', style: TextStyle(color: subColor, fontSize: 9.5)),
        ],
      ),
    );
  }

  /// 每日任务
  ///
  /// 任务清单来自后端（`GET /signin` 的 tasks 字段），完成度按当天
  /// 真实行为统计。三态：
  ///   · 未完成 → 「去完成」，点了跳到对应页面，回来自动刷新进度
  ///   · 已完成未领 → 「领取 +N」，点了调 `POST /signin/tasks`
  ///   · 已领取 → 「已领取」，置灰不可点
  Widget _tasksCard() {
    final tasks = _status.tasks;
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
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('完成任务可获得积分奖励，发布渔获还有额外积分',
              style: TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('任务加载中…',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ),
          for (final t in tasks) _taskRow(t),
        ],
      ),
    );
  }

  Widget _taskRow(DailyTask t) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: t.claimed ? null : () => _onTaskTap(t),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Icon(_taskIcon(t.icon), size: 18, color: AppTheme.primary),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          // ★ 完成任务后要能一眼看出「这行已经做完了、只差领奖」。
          //   以前只有按钮从「去完成」变成「领取 +N」这一处差异，
          //   列表扫下来几乎看不出来，用户反馈「缺少任务标识」。
          if (t.done && !t.claimed) ...[
            const SizedBox(width: 6),
            _doneTag(),
          ],
        ],
      ),
      subtitle: Row(children: [
        Expanded(
          child: Text(
            t.target > 1 ? '${t.desc}（${t.progress}/${t.target}）' : t.desc,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
        Text('+${t.points}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.star)),
      ]),
      trailing: _taskAction(t),
    );
  }

  /// 「已完成（待领取）」小标签：带勾的浅绿胶囊
  Widget _doneTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, size: 10, color: AppTheme.primary),
        SizedBox(width: 2),
        Text('已完成',
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary)),
      ]),
    );
  }

  Widget _taskAction(DailyTask t) {
    if (t.claimed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.divider,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text('已领取',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      );
    }
    if (t.done) {
      // 已完成 → 直接领
      final busy = _claiming == t.key;
      return GestureDetector(
        onTap: busy ? null : () => _claim(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.star,
            borderRadius: BorderRadius.circular(18),
          ),
          child: busy
              ? const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.6, color: Colors.white))
              : Text('领取',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _onTaskTap(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    );
  }

  IconData _taskIcon(String key) {
    switch (key) {
      case 'fish':
        return Icons.phishing_outlined;
      case 'edit':
        return Icons.edit_outlined;
      case 'comment':
        return Icons.chat_bubble_outline;
      case 'follow':
        return Icons.person_add_alt_outlined;
      case 'check':
        return Icons.event_available_outlined;
      default:
        return Icons.task_alt_outlined;
    }
  }

  /// 点任务：跳对应页面（签到那条直接签到）
  Future<void> _onTaskTap(DailyTask t) async {
    switch (t.key) {
      case 'checkin':
        if (!_status.signedToday) {
          await _checkin();
        } else {
          CenterToast.show(context, '今天已经签到过了');
        }
        return;
      case 'publish_catch':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const PublishCatchScreen()));
        break;
      case 'publish_post':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const PublishHubScreen()));
        break;
      case 'comment_2':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const DiscoverScreen()));
        break;
      case 'follow_2':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const NearbyAnglersScreen()));
        break;
      default:
        return;
    }
    // 从目标页回来，立刻刷新完成度（比如刚发完渔获，这里就能领了）
    if (mounted) await _load();
  }

  /// 领奖
  Future<void> _claim(DailyTask t) async {
    if (_claiming != null) return;
    setState(() => _claiming = t.key);
    try {
      final r = await SigninService.claimTask(t.key);
      if (!mounted) return;
      setState(() {
        _claiming = null;
        _status = _status.copyWith(tasks: r.tasks, points: r.total);
      });
      if (r.already) {
        CenterToast.show(context, '今天已经领过了');
      } else {
        CenterToast.show(context, '领取成功  +${r.points} ${_status.pointsName}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _claiming = null);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
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
                      child: Text('签到成功，获得 ${_got!.describe(_status.pointsName)}',
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
