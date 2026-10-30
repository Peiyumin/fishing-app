import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/weather_forecast.dart';
import '../services/ai_report.dart';
import '../services/ai_spot_service.dart';
import '../services/geo_place.dart';
import '../services/map_launcher.dart';
import '../utils/county_label.dart';
import '../widgets/center_toast.dart';

/// AI 钓点分析详情（v2.1.56）
///
/// 用户给的版式（图四/图五）：雷达扫出来的点不再是「飞过去就完事」，
/// 点进去要能看到**为什么推荐这里** —— 分数、最佳窗口、定位地址、
/// 当日天气、黄金小时、逐条依据、怎么钓。底部两个动作：反馈 / 导航前往。
///
/// 配色沿用雷达页的「暗舱 HUD」：inkBg 底 + accent 荧光绿做主色，
/// 不跟白天用的白底页面混，用户能感觉到「这是 AI 在说话」。
///
/// 数据全部本地算（天气来自 Open-Meteo，地址来自后端逆地理），
/// 不依赖服务端出报告，离线时也能显示「只按水域和距离」的降级版。
class AiSpotDetailScreen extends StatefulWidget {
  const AiSpotDetailScreen({
    super.key,
    required this.spot,
    required this.myLat,
    required this.myLng,
    this.rank,
    this.total,
    this.autoLoad = true,
    this.debugBundle,
    this.debugPlace,
  });

  final AiSpot spot;

  /// 我的位置：用来算方位（迎风岸/背风岸）和车程
  final double myLat;
  final double myLng;

  /// 「第 N 推荐 / 共 M 处」
  final int? rank;
  final int? total;

  /// 是否自动拉天气/逆地理（测试与截图里关掉，避免真的发网络）
  final bool autoLoad;

  /// 仅测试/截图用：直接喂一份天气，跳过网络请求
  final WeatherBundle? debugBundle;

  /// 仅测试/截图用：直接喂一个地址，跳过逆地理
  final GeoPlace? debugPlace;

  @override
  State<AiSpotDetailScreen> createState() => _AiSpotDetailScreenState();
}

class _AiSpotDetailScreenState extends State<AiSpotDetailScreen> {
  static const Color _bg = AppTheme.inkBg;
  static const Color _card = AppTheme.inkSurface;
  static const Color _green = AppTheme.accent;
  static const Color _blue = AppTheme.water;
  static const Color _dim = AppTheme.inkMuted;

  late AiReport _report = AiReport.build(
    spot: widget.spot,
    bundle: widget.debugBundle,
    myLat: widget.myLat,
    myLng: widget.myLng,
  );

  GeoPlace? _place;
  bool _weatherArrived = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (widget.debugBundle != null) _weatherArrived = true;
    if (widget.debugPlace != null) _place = widget.debugPlace;
    if (widget.autoLoad && widget.debugBundle == null) _load();
  }

  Future<void> _load() async {
    // 天气与地址并发：任何一个慢都不拖住另一个
    GeoPlace.reverse(widget.spot.lat, widget.spot.lng).then((p) {
      if (mounted && p != null && !p.isEmpty) setState(() => _place = p);
    });
    try {
      final b = await AiSpotService.weatherAt(
        widget.spot.lat,
        widget.spot.lng,
      );
      if (!mounted || b == null) return;
      setState(() {
        _report = AiReport.build(
          spot: widget.spot,
          bundle: b,
          myLat: widget.myLat,
          myLng: widget.myLng,
        );
        _weatherArrived = true;
      });
    } catch (_) {
      // 拿不到天气就保持降级版报告
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
          children: [
            _topBar(),
            const SizedBox(height: 10),
            _scoreCard(),
            const SizedBox(height: 10),
            _addressCard(),
            const SizedBox(height: 12),
            _actionRow(),
            const SizedBox(height: 16),
            _tabBar(),
            const SizedBox(height: 12),
            if (_tab == 0) ..._basisTab(),
            if (_tab == 1) ..._howToTab(),
            if (_tab == 2) ..._scoreTab(),
          ],
        ),
      ),
    );
  }

  // ── 顶栏 ───────────────────────────────────────────────────
  Widget _topBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          tooltip: '关闭',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
        const SizedBox(width: 2),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 钓点分析',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'AI SPOT ANALYSIS',
              style: TextStyle(
                color: _blue,
                fontSize: 9,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _green.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _green.withOpacity(0.4)),
          ),
          child: Text(
            widget.rank != null
                ? (widget.total != null
                    ? '第 ${widget.rank} 推荐 / 共 ${widget.total} 处'
                    : '第 ${widget.rank} 推荐')
                : 'AI 推荐',
            style: const TextStyle(
              color: _green,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ── 分数卡 ─────────────────────────────────────────────────
  Widget _scoreCard() {
    final r = _report;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScoreRing(score: r.score),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名字 + 档位
                    Text(
                      widget.spot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(r.grade, _green),
                        _chip(
                          r.picks.length > 1
                              ? '适合 ${r.picks.map((e) => e.name).join(' · ')}'
                              : '适合 ${r.species}',
                          _blue,
                        ),
                        _chip(widget.spot.kind, _dim),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 12, color: _dim),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '最佳窗口 ${r.dateTag} · ${r.windowText}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.near_me_outlined, size: 12, color: _dim),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '距离你约 ${r.distanceText}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            r.headline,
            style: const TextStyle(
                color: Colors.white, fontSize: 13.5, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.38)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ── 定位地址 ───────────────────────────────────────────────
  Widget _addressCard() {
    final full = _place?.display ?? '';
    final county = _place == null
        ? ''
        : countyLabel(
            city: _place!.city,
            district: _place!.district,
            province: _place!.province,
            // ★ v2.1.57：地址卡标题要带省（河南省·禹州市），用户明确要求
            withProvince: true,
          );
    return Material(
      color: Colors.white.withOpacity(0.045),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: full.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: full));
                if (mounted) CenterToast.show(context, '地址已复制');
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, size: 16, color: _blue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      county.isEmpty ? '定位地址' : county,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      full.isEmpty ? '正在解析地址…（也可以直接点「导航前往」）' : full,
                      style: const TextStyle(
                          color: _dim, fontSize: 11.5, height: 1.45),
                    ),
                  ],
                ),
              ),
              if (full.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.copy_rounded, size: 14, color: _dim),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 反馈 / 导航 ────────────────────────────────────────────
  Widget _actionRow() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: _feedback,
            icon: const Icon(Icons.flag_outlined, size: 17),
            label: const Text('反馈', style: TextStyle(fontSize: 13.5)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.22)),
              backgroundColor: Colors.white.withOpacity(0.05),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: () => MapLauncher.navigate(
              context,
              lat: widget.spot.lat,
              lng: widget.spot.lng,
              name: widget.spot.name,
              address: _place?.bestAddress ?? '',
            ),
            icon: const Icon(Icons.navigation_rounded, size: 17),
            label: const Text('导航前往', style: TextStyle(fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: AppTheme.inkBg,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _feedback() async {
    String reason = '坐标不准';
    final noteCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('这个钓点哪里不对？',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['坐标不准', '已经不能钓', '进不去/有围栏', '水质很差', '其他']
                    .map((r) => ChoiceChip(
                          label: Text(r),
                          selected: reason == r,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: reason == r ? Colors.white : _dim,
                          ),
                          selectedColor: _green.withOpacity(0.22),
                          backgroundColor: Colors.white.withOpacity(0.05),
                          side: BorderSide(
                            color: reason == r
                                ? _green.withOpacity(0.6)
                                : Colors.white.withOpacity(0.12),
                          ),
                          onSelected: (_) => setSt(() => reason = r),
                        ))
                    .toList()),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '补充说明（选填）',
                  hintStyle: const TextStyle(color: _dim, fontSize: 12.5),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: AppTheme.inkBg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('提交反馈',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await AiSpotService.report(
        spot: widget.spot,
        reason: reason,
        note: noteCtrl.text.trim(),
      );
      if (mounted) CenterToast.show(context, '已提交，感谢反馈！');
    } catch (e) {
      if (mounted) {
        CenterToast.show(
          context,
          e
              .toString()
              .replaceFirst(RegExp(r'^(ApiException|Exception):\s*'), ''),
        );
      }
    }
  }

  // ── 三个 tab ───────────────────────────────────────────────
  static const List<String> _tabs = ['依据', '怎么钓', '评分'];

  Widget _tabBar() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _tabs[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _tab == i ? AppTheme.inkBg : _dim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(IconData icon, String title, {String? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _blue),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(trailing,
                style: const TextStyle(
                    color: _green, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }

  // ── 依据 ───────────────────────────────────────────────────
  List<Widget> _basisTab() {
    final r = _report;
    return [
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.wb_cloudy_outlined, '当日天气',
                trailing: _weatherArrived ? '${r.dateTag} · ${r.score} 分' : '读取中'),
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: r.metrics.map(_metricPill).toList(),
            ),
            if (r.golden.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 13, color: _dim),
                  const SizedBox(width: 5),
                  const Text('黄金小时',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('今天最好的三个时段',
                      style: TextStyle(color: _dim, fontSize: 10.5)),
                ],
              ),
              const SizedBox(height: 8),
              ...r.golden.map(_goldRow),
            ],
          ],
        ),
      ),
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.explore_outlined, '为什么选这里'),
            const SizedBox(height: 4),
            ...r.reasons.map(_reasonTile),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
        child: Text(
          '提示：本推荐由 AI 综合天气、水域结构、卫星图与社区数据生成，仅供参考。'
          '请遵守当地禁渔规定并注意人身安全。',
          style: TextStyle(color: _dim.withOpacity(0.85), fontSize: 10.5, height: 1.6),
        ),
      ),
    ];
  }

  Widget _metricPill(AiMetric m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconOf(m.icon), size: 12, color: _blue),
          const SizedBox(width: 5),
          Text('${m.label} ',
              style: TextStyle(color: _dim, fontSize: 10.5, height: 1.2)),
          Text(m.value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2)),
        ],
      ),
    );
  }

  Widget _goldRow(AiGold g) {
    final k = (g.score / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(g.hhmm,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: k,
                minHeight: 6,
                backgroundColor: Colors.white.withOpacity(0.07),
                valueColor: AlwaysStoppedAnimation(
                  g.score >= 80 ? _green : (g.score >= 60 ? _blue : _dim),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text('${g.score}分',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: g.score >= 80 ? _green : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _reasonTile(AiReason r) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_iconOf(r.icon), size: 15, color: _green),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(r.tag,
                          style: TextStyle(color: _dim, fontSize: 9.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.body,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11.5, height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 怎么钓 ─────────────────────────────────────────────────
  List<Widget> _howToTab() {
    final r = _report;
    final picks = r.picks;
    return [
      // ★ v2.1.57：鱼种不再只写死「鲫鱼」一条，按习性给出主攻 + 备选
      if (picks.isNotEmpty)
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(Icons.set_meal_outlined, '适合的鱼种',
                  trailing: '按习性推荐'),
              const SizedBox(height: 4),
              for (var i = 0; i < picks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (i == 0 ? _green : _blue).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                              color: i == 0 ? _green : _blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(picks[i].name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(width: 6),
                                Text('匹配 ${picks[i].match}',
                                    style: TextStyle(
                                        color: i == 0 ? _green : _dim,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700)),
                                if (i == 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _green.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('主攻',
                                        style: TextStyle(
                                            color: _green,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(picks[i].habit,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                    height: 1.5)),
                            if (picks[i].why.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(picks[i].why,
                                  style: TextStyle(
                                      color: _dim.withOpacity(0.9),
                                      fontSize: 10.5,
                                      height: 1.5)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                '排序依据：当前水温是否落在该鱼舒适区（70%）、现在是否在它的开口时段（20%）、'
                '今天的风浪是否合它性子（10%）。',
                style: TextStyle(
                    color: _dim.withOpacity(0.85), fontSize: 10.5, height: 1.5),
              ),
            ],
          ),
        ),
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.set_meal_outlined, '${r.species} · ${r.mode}',
                trailing: r.windowText),
            const SizedBox(height: 8),
            ...r.tactics.map((t) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconOf(t.icon), size: 14, color: _blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(t.body,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                    height: 1.55)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
        child: Text(
          '钓法建议由鱼种习性 + 当前水温/溶氧推导，具体用饵还要看当地水情。',
          style: TextStyle(color: _dim.withOpacity(0.85), fontSize: 10.5, height: 1.5),
        ),
      ),
    ];
  }

  // ── 评分 ───────────────────────────────────────────────────
  List<Widget> _scoreTab() {
    final r = _report;
    return [
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.grade_outlined, '分数构成', trailing: '${r.score} 分'),
            const SizedBox(height: 6),
            ...r.parts.map((p) => Padding(
                  padding: const EdgeInsets.only(top: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.label,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(p.note,
                                style: TextStyle(
                                    color: _dim, fontSize: 11, height: 1.45)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        AiScoreParts.signed(p.value),
                        style: TextStyle(
                          color: p.value > 0
                              ? _green
                              : (p.value < 0 ? AppTheme.danger : Colors.white54),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white.withOpacity(0.07)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('综合得分',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${r.score}',
                    style: const TextStyle(
                        color: _green,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1)),
                const SizedBox(width: 3),
                const Text('分', style: TextStyle(color: _dim, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.info_outline, '怎么读这个分数'),
            const SizedBox(height: 8),
            Text(
              '80 分以上＝条件到位，值得专程跑一趟；60~79 分＝可以去，重点守早晚；'
              '60 分以下＝路过试试就好。\n'
              '分数 = 天气基础分（气压/水温/溶氧/风/时段）+ 水体类型 + 风向岸线 − 距离成本，'
              '和天气页的垂钓指数用的是同一套引擎，同一小时不会出现两个数。',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.65),
            ),
          ],
        ),
      ),
    ];
  }

  static IconData _iconOf(AiIcon i) => switch (i) {
        AiIcon.weather => Icons.wb_cloudy_outlined,
        AiIcon.temp => Icons.thermostat,
        AiIcon.water => Icons.water_drop_outlined,
        AiIcon.wind => Icons.air,
        AiIcon.pressure => Icons.speed,
        AiIcon.oxygen => Icons.bubble_chart_outlined,
        AiIcon.humidity => Icons.opacity,
        AiIcon.climate => Icons.wb_twilight,
        AiIcon.coast => Icons.waves,
        AiIcon.road => Icons.directions_car_outlined,
        AiIcon.fish => Icons.set_meal_outlined,
        AiIcon.evidence => Icons.verified_outlined,
        AiIcon.time => Icons.schedule,
        AiIcon.gear => Icons.straighten,
        AiIcon.bait => Icons.grass_outlined,
        AiIcon.spot => Icons.my_location,
        AiIcon.warn => Icons.warning_amber_rounded,
      };
}

/// 分数环：一段圆弧 + 中间数字（不引第三方图表库）
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppTheme.accent
        : (score >= 60 ? AppTheme.water : AppTheme.inkMuted);
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(76),
            painter: _RingPainter(
              value: (score / 100).clamp(0.0, 1.0),
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  color: color,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 1),
              const Text('分',
                  style: TextStyle(color: AppTheme.inkMuted, fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withOpacity(0.08),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}
