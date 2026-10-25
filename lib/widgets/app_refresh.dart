import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';

/// 全局统一的下拉刷新（图二样式）
///
/// 和默认 `RefreshIndicator` 的区别：下拉触发之后，列表顶部会滑出一条
/// 灰色提示条——左边小转圈，右边两行字：
///
/// ```
/// ⟳  垂钓圈 为您玩命加载…
///    最后更新：今天 20:49
/// ```
///
/// 「最后更新」是本机持久化的**上次刷新完成时间**，所以第一次进页面下拉、
/// 数据还没回来时也能看到上次是什么时候刷的（这正是图二的语义：
/// 它显示的不是当前这次要多久，而是上次的数据有多新）。
///
/// 用法与 `RefreshIndicator` 完全一致，直接替换即可：
/// ```dart
/// AppRefresh(onRefresh: _load, child: ListView(...))
/// ```
class AppRefresh extends StatefulWidget {
  /// 刷新回调（与 RefreshIndicator.onRefresh 同签名）
  final Future<void> Function() onRefresh;

  /// 被包裹的滚动视图
  final Widget child;

  /// 转圈颜色（默认品牌绿）
  final Color? color;

  /// 转圈背景色
  final Color? backgroundColor;

  /// 触发下拉的位移阈值
  final double? displacement;

  /// 距顶部的额外偏移（页面有吸顶头部时用）
  final double? edgeOffset;

  /// 「最后更新」的存档键：不同页面各存一份，不传则全局共用一份
  final String? memoKey;

  const AppRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.backgroundColor,
    this.displacement,
    this.edgeOffset,
    this.memoKey,
  });

  @override
  State<AppRefresh> createState() => _AppRefreshState();
}

class _AppRefreshState extends State<AppRefresh>
    with SingleTickerProviderStateMixin {
  static const String _prefsPrefix = 'refresh_last_at_';

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

  bool _busy = false;

  /// 上次刷新完成时间（null = 本机还没记录过）
  DateTime? _last;

  String get _memoKey => widget.memoKey ?? 'global';

  @override
  void initState() {
    super.initState();
    _restoreLast();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _restoreLast() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_prefsPrefix$_memoKey');
      if (raw == null || raw.isEmpty) return;
      final t = DateTime.tryParse(raw);
      if (t == null) return;
      if (!mounted) return;
      setState(() => _last = t);
    } catch (_) {
      // 读不到就当作没记录过，不影响刷新
    }
  }

  Future<void> _persistLast(DateTime t) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_prefsPrefix$_memoKey', t.toIso8601String());
    } catch (_) {
      // 存不进去只是下次显示不出来，不该影响刷新结果
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    _anim.forward();

    var ok = true;
    try {
      await widget.onRefresh();
    } catch (_) {
      // 页面自己的 onRefresh 里通常已经有 toast，这里只保证 UI 收尾
      ok = false;
    }

    // 失败不更新「最后更新」——否则下次进页面会显示一个假的新时间
    DateTime? now;
    if (ok) {
      now = DateTime.now();
      // 先落盘再收起，避免收起动画期间闪一下旧的「最后更新」
      await _persistLast(now);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (now != null) _last = now;
    });
    // 让「最后更新」停留一小会儿再滑走，否则加载飞快时用户根本看不到
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _anim.reverse();
  }

  /// 今天 20:49 / 昨天 09:12 / 10-23 15:04
  String _fmt(DateTime? t) {
    if (t == null) return '还没有记录';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    return '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} $hm';
  }

  Widget _hintBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF2F4F3),
        border: Border(
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // 整条居中：两行字都居中排，不再左边留一个转圈图标
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '垂钓圈 为您玩命加载…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '最后更新：${_fmt(_last)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.25,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 下拉手势仍交给 RefreshIndicator，但它的转圈图标**不显示**：
        // 用户要求「把原来的加载图标删掉」，视觉反馈只留上面那条居中提示。
        // color/backgroundColor 给透明即可，动画逻辑照常（松手触发 onRefresh）。
        RefreshIndicator(
          onRefresh: _run,
          color: Colors.transparent,
          backgroundColor: Colors.transparent,
          displacement: widget.displacement ?? 40,
          edgeOffset: widget.edgeOffset ?? 0,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                // 收起后整块从树上移除：既省一层合成，也避免任何动画
                // 在屏幕外白转（无限动画会让 pumpAndSettle 永远等不到静止）
                if (_anim.value == 0 && !_busy) return const SizedBox.shrink();
                return SlideTransition(position: _slide, child: _hintBar());
              },
            ),
          ),
        ),
      ],
    );
  }
}
