import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/water_body.dart';
import '../services/ai_spot_service.dart';
import 'ai_spot_detail_screen.dart';

/// AI 找钓点 · 雷达扫描页（v2.1.49）
///
/// 交互：地图上点「AI 找钓点」→ 全屏雷达开始扫描（扫描线转圈）→
/// 扫到的水域逐个点亮 → 扫描完把结果列表推上来。
///
/// 为什么这样做：原来点一下只是转个圈然后直接弹一个白色底部面板，
/// 用户感觉不到「AI 在算」，只觉得卡了一下。现在把计算过程可视化，
/// 扫描线扫过哪里、点亮了几个点，都是实时反馈。
///
/// 性能：整块雷达由 [CustomPainter] + 单个 [AnimationController] 驱动
/// （`super(repaint: ctrl)`），**每帧不重建 widget 树、不 setState**。
/// 光点是否点亮写在 painter 持有的可变列表里，跨帧保留。
class AiRadarScreen extends StatefulWidget {
  const AiRadarScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.spots,
    required this.waters,
    this.debugSpots,
  });

  final double lat;
  final double lng;
  final List<FishingSpot> spots;
  final List<WaterBody> waters;

  /// 仅测试用：直接给结果，跳过网络请求（截图验证扫描动画时用）
  final List<AiSpot>? debugSpots;

  @override
  State<AiRadarScreen> createState() => _AiRadarScreenState();
}

/// 返回给地图页：完整结果 + 用户点选的那一条（没点就是 null）
class AiRadarResult {
  const AiRadarResult({required this.list, this.picked});
  final List<AiSpot> list;
  final AiSpot? picked;
}

enum _Phase { scanning, done }

class _AiRadarScreenState extends State<AiRadarScreen>
    with SingleTickerProviderStateMixin {
  // ── 配色：全部取自 AppTheme ────────────────────────────────
  // ★ 这里原来是四只手调的近黑色/青绿色（#04070A、#35E0C8…），被
  //   `theme_palette_test` 拦下了。现在是深色族 ink* + accent + water 的组合：
  //   荧光绿是扫描线和高分点，water 蓝是「已扫完」和次优点的冷色，
  //   inkMuted 是弱文案。视觉上仍然是暗舱 HUD，但和 App 其它暗色界面
  //   （启动页/地图暗色层）用同一套底色，不会一进雷达就换了个 App。
  static const Color _bg = AppTheme.inkBg;
  static const Color _green = AppTheme.accent;
  static const Color _blue = AppTheme.water;
  static const Color _dim = AppTheme.inkMuted;

  late final AnimationController _spin;
  final List<_Blip> _blips = [];

  _Phase _phase = _Phase.scanning;
  List<AiSpot> _list = const [];
  String? _error;
  bool _revealRequested = false;

  /// 可见的点数（用于顶部「已发现 N 处」实时文案）
  int _litCount = 0;

  @override
  void initState() {
    super.initState();
    // 一圈 2.6 秒；常驻循环，点亮靠 painter 内部判角度
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _spin.addListener(_onTick);
    _run();
  }

  @override
  void dispose() {
    _spin.removeListener(_onTick);
    _spin.dispose();
    super.dispose();
  }

  static const Duration _minScan = Duration(milliseconds: 1500);

  Future<void> _run() async {
    final started = DateTime.now();
    List<AiSpot> list = const [];
    String? err;
    final injected = widget.debugSpots;
    if (injected != null) {
      list = injected;
    } else {
      try {
        list = await AiSpotService.recommend(
          lat: widget.lat,
          lng: widget.lng,
          spots: widget.spots,
          waters: widget.waters,
        ).timeout(const Duration(seconds: 18));
      } catch (_) {
        err = '扫描失败，请检查网络后重试';
      }
    }

    // 数据回得太快会让动画一闪而过，补足最短扫描时长
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minScan) {
      await Future.delayed(_minScan - elapsed);
    }
    if (!mounted) return;

    if (err != null) {
      setState(() {
        _error = err;
        _phase = _Phase.done;
      });
      return;
    }
    if (list.isEmpty) {
      setState(() {
        _error = '附近 60 公里内没扫到合适的水域';
        _phase = _Phase.done;
      });
      return;
    }

    // 点按「分数高的靠里、按黄金角错开」，避免全挤在一条线上
    _blips.clear();
    for (var i = 0; i < list.length; i++) {
      final score = list[i].score.clamp(0, 100) / 100.0;
      _blips.add(_Blip(
        // 分数越高越靠近圆心（0.30~0.92）
        radius: (0.92 - score * 0.55).clamp(0.28, 0.94),
        // 137.5° 黄金角，视觉上分布最均匀
        angle: (i * 2.399963) % (math.pi * 2),
        score: list[i].score,
        label: list[i].name,
      ));
    }
    setState(() {
      _list = list;
    });
    // ★ 数据到了之后把扫描线拨回 12 点，重新扫一圈 —— 保证「一圈扫完 = 全部
    //   点亮」，而不是让用户等第二圈转到剩余角度（第一圈前半段是空的）。
    //   注意：`value = 0` 这个 setter 内部会 **stop()**，必须紧跟着 repeat()，
    //   否则扫描线会死死停在 12 点，一个点都不会亮。
    _spin.value = 0;
    _spin.repeat();
  }

  /// 全部点亮后延迟多久切到结果态（用动画自身的累计时间算，
  /// 不挂 `Future.delayed` —— widget 测试里裸 timer 会导致
  /// 「Timer is still pending」）
  static const Duration _revealDelay = Duration(milliseconds: 520);
  Duration? _revealSince;

  void _onTick() {
    if (_phase != _Phase.scanning) return;
    if (_blips.isNotEmpty) {
      // 扫描线转满一圈后把所有点都点亮了 → 切到结果态。
      // 只在满足条件时 setState 一次，不做逐帧刷新。
      final lit = _blips.where((b) => b.lit).length;
      if (lit != _litCount) {
        _litCount = lit;
        if (mounted) setState(() {});
      }
      if (!_revealRequested && lit == _blips.length && _litCount > 0) {
        _revealRequested = true;
        _revealSince = _spin.lastElapsedDuration;
      }
    }
    final since = _revealSince;
    final now = _spin.lastElapsedDuration;
    if (!_revealRequested || since == null || now == null) return;
    if (now - since >= _revealDelay) {
      if (mounted) setState(() => _phase = _Phase.done);
    }
  }

  void _close([AiSpot? picked]) {
    Navigator.of(context).pop(AiRadarResult(list: _list, picked: picked));
  }

  /// 打开某个点的 AI 分析详情（图四/图五版式）
  Future<void> _openReport(AiSpot s, int i) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiSpotDetailScreen(
          spot: s,
          myLat: widget.lat,
          myLng: widget.lng,
          rank: i + 1,
          total: _list.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final radarSize = math.min(size.width - 40, size.height * 0.46);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // 背景：极淡的径向光晕，让雷达像悬在暗舱里
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.1,
                  colors: [
                    AppTheme.inkSurface,
                    _bg.withOpacity(0.98),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                _radar(radarSize),
                const Spacer(),
                _bottomPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _close(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: '关闭',
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI 水域扫描',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'AI WATER SCAN',
                style: TextStyle(
                  color: _blue,
                  fontSize: 9.5,
                  letterSpacing: 2.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          _statusChip(),
        ],
      ),
    );
  }

  Widget _statusChip() {
    final scanning = _phase == _Phase.scanning;
    final text = scanning
        ? (_blips.isEmpty ? '扫描中' : '发现 $_litCount/${_blips.length}')
        : (_error != null ? '无结果' : '${_list.length} 处');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scanning ? _green.withOpacity(0.14) : _blue.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (scanning ? _green : _blue).withOpacity(0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scanning ? _green : _blue,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: scanning ? _green : _blue,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _radar(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外发光（径向渐变代替 MaskFilter.blur：blur 在低端机上很吃 GPU）
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _green.withOpacity(0.10),
                  _green.withOpacity(0.0),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          CustomPaint(
            size: Size.square(size),
            painter: _RadarPainter(
              ctrl: _spin,
              blips: _blips,
              phase: _phase,
              green: _green,
              blue: _blue,
              dim: _dim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    final scanning = _phase == _Phase.scanning;
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AppTheme.inkSurface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: scanning ? _scanningHint() : _resultBody(),
      ),
    );
  }

  Widget _scanningHint() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '正在扫描周边水域',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '结合实时天气、气压、风向与水深，判断哪些水域现在最值得去',
          style: TextStyle(color: _dim, fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 14),
        _scanBar(),
      ],
    );
  }

  /// 扫描进度条：一条来回跑的荧光条（不用进度值，因为真实进度不可知）
  Widget _scanBar() {
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (ctx, box) {
          return AnimatedBuilder(
            animation: _spin,
            builder: (_, __) {
              final w = box.maxWidth;
              final segW = w * 0.28;
              final x = (w - segW) * _easeInOut(_spin.value);
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x,
                    width: segW,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(colors: [
                          _green.withOpacity(0.0),
                          _green,
                          _green.withOpacity(0.0),
                        ]),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  double _easeInOut(double t) =>
      t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;

  Widget _resultBody() {
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ghostButton('重新扫描', () {
                setState(() {
                  _error = null;
                  _phase = _Phase.scanning;
                  _blips.clear();
                  _litCount = 0;
                  _revealRequested = false;
                  _revealSince = null;
                });
                _run();
              }),
              const SizedBox(width: 10),
              _ghostButton('关闭', () => _close()),
            ],
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '扫描完成',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '发现 ${_list.length} 处 · 按推荐度排序',
              style: const TextStyle(color: _dim, fontSize: 11.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(MediaQuery.of(context).size.height * 0.40, 360),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _spotTile(_list[i], i),
          ),
        ),
      ],
    );
  }

  Widget _spotTile(AiSpot s, int i) {
    final g = s.grade;
    final hot = s.score >= 80;
    final color = hot ? _green : (s.score >= 60 ? _blue : _dim);
    return Material(
      color: Colors.white.withOpacity(0.045),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // v2.1.56：点一条不再只是「飞过去」——进 AI 分析详情页，
        // 里面有分数构成、定位地址、导航和反馈（用户给的图四/图五版式）
        onTap: () => _openReport(s, i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 序号 / 分数
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.32)),
                ),
                child: Column(
                  children: [
                    Text(
                      '${s.score.round()}',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      g,
                      style: TextStyle(
                        color: color.withOpacity(0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.km < 1
                              ? '${(s.km * 1000).round()} m'
                              : '${s.km.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _dim,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppTheme.inkMuted.withOpacity(0.55)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ghostButton(String text, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _green,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        side: BorderSide(color: _green.withOpacity(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

/// 雷达上的一个光点
class _Blip {
  _Blip({
    required this.radius,
    required this.angle,
    required this.score,
    required this.label,
  });

  final double radius; // 0..1（相对半径）
  final double angle; // 弧度
  final int score;
  final String label;
  bool lit = false;
  double flashAt = -1; // 点亮时刻（扫描圈的相位），用来做扩散波纹
}

/// 雷达绘制器
///
/// ★ 关键：`super(repaint: ctrl)` —— 由 AnimationController 直接驱动重绘，
///   上层 widget 一帧都不重建。光点的 lit 状态存在 [_Blip] 里（跨帧保留），
///   所以也不需要 setState。
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.ctrl,
    required this.blips,
    required this.phase,
    required this.green,
    required this.blue,
    required this.dim,
  }) : super(repaint: ctrl);

  final AnimationController ctrl;
  final List<_Blip> blips;
  final _Phase phase;
  final Color green;
  final Color blue;
  final Color dim;

  static const double _startAngle = -math.pi / 2; // 12 点方向起扫

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 12;
    final t = ctrl.value;
    final sweep = _startAngle + t * math.pi * 2;

    _paintBackdrop(canvas, c, r);
    _paintGraticule(canvas, c, r, t);
    // 扫描完成就不再画扫描扇形/亮线 —— 留着会让人以为还在扫
    if (phase == _Phase.scanning) _paintSweep(canvas, c, r, sweep);
    _paintBlips(canvas, c, r, sweep, t);
    _paintCore(canvas, c, r, t);
  }

  // ── 1. 底盘：深色圆 + 边界 ────────────────────────────────
  void _paintBackdrop(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, [
          AppTheme.inkSurfaceAlt,
          AppTheme.inkBg,
        ], [0.0, 1.0]),
    );
    // 边界环
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = blue.withOpacity(0.32),
    );
    // 外侧第二道淡环（科技感）
    canvas.drawCircle(
      c,
      r + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = blue.withOpacity(0.12),
    );
  }

  // ── 2. 刻度：同心圆 + 十字线 + 角度刻度 + 外圈短线 ──────────
  void _paintGraticule(Canvas canvas, Offset c, double r, double t) {
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withOpacity(0.055);

    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(c, r * i / 4, grid);
    }
    // 十字准线
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), grid);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), grid);

    // 角度刻度：每 10° 一根，30° 长一点
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..color = blue.withOpacity(0.22);
    for (var deg = 0; deg < 360; deg += 10) {
      final a = _startAngle + deg * math.pi / 180;
      final long = deg % 30 == 0;
      final len = long ? r * 0.055 : r * 0.028;
      tick.strokeWidth = long ? 1.1 : 0.7;
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * (r - len), c.dy + math.sin(a) * (r - len)),
        Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r),
        tick,
      );
    }

    // 最外圈：反向缓转的短虚线环
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = green.withOpacity(0.18);
    for (var deg = 0; deg < 360; deg += 24) {
      final a = _startAngle - t * math.pi * 0.5 + deg * math.pi / 180;
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * (r + 3), c.dy + math.sin(a) * (r + 3)),
        Offset(c.dx + math.cos(a) * (r + 10), c.dy + math.sin(a) * (r + 10)),
        outer,
      );
    }
  }

  // ── 3. 扫描扇形（拖尾） + 前沿亮线 ─────────────────────────
  void _paintSweep(Canvas canvas, Offset c, double r, double sweep) {
    const tail = math.pi * 0.62; // 拖尾约 112°
    final rect = Rect.fromCircle(center: c, radius: r);

    // ★ 不用 `ui.Gradient.sweep` 画扇形：它的 startAngle/endAngle 必须落在
    //   [0, 2π)，而扫描角是从 -π/2 起算并会越过 2π，一旦出界就会把整个圆
    //   铺满（看起来像一块半透明的大饼）。改成叠加若干细扇形，从尾部到
    //   前沿透明度递增 —— 角度随便给，视觉上也更像真实雷达余晖。
    //
    //   扇形是**环形**的（内半径 8%）：所有段都汇聚到圆心会把中点叠成一团
    //   亮斑，把中心光核糊掉；挖掉中间后中心核才干净。
    const segs = 18;
    final inner = r * 0.08;
    final innerRect = Rect.fromCircle(center: c, radius: inner);
    final segPaint = Paint();
    for (var i = 0; i < segs; i++) {
      final a0 = sweep - tail * (1 - i / segs);
      final a1 = sweep - tail * (1 - (i + 1) / segs) + 0.01;
      // 平方衰减：尾部几乎看不见，前沿最亮
      final k = math.pow((i + 1) / segs, 2.4).toDouble();
      segPaint.color = green.withOpacity(0.012 + 0.26 * k);

      final p = Path()
        ..moveTo(c.dx + math.cos(a0) * inner, c.dy + math.sin(a0) * inner)
        ..lineTo(c.dx + math.cos(a0) * r, c.dy + math.sin(a0) * r)
        ..arcTo(rect, a0, a1 - a0, false)
        ..lineTo(c.dx + math.cos(a1) * inner, c.dy + math.sin(a1) * inner)
        ..arcTo(innerRect, a1, a0 - a1, false)
        ..close();
      canvas.drawPath(p, segPaint);
    }

    // 前沿：一条从中心到边缘的亮线（用两段不同宽度叠出光晕感）
    final tip = Offset(c.dx + math.cos(sweep) * r, c.dy + math.sin(sweep) * r);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = green.withOpacity(0.14),
    );
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..color = green.withOpacity(0.9),
    );
    // 前沿扫过的外圈小弧
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1),
      sweep - 0.05,
      0.10,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = green.withOpacity(0.55),
    );
  }

  // ── 4. 光点 ───────────────────────────────────────────────
  void _paintBlips(
      Canvas canvas, Offset c, double r, double sweep, double t) {
    var twoPi = math.pi * 2;
    for (final b in blips) {
      final p = Offset(
        c.dx + math.cos(b.angle) * r * b.radius,
        c.dy + math.sin(b.angle) * r * b.radius,
      );

      // 扫描线越过该点的角度 → 永久点亮
      final diff = ((sweep - _startAngle) % twoPi) - (b.angle % twoPi);
      final passed = diff >= -0.02 || b.lit;
      if (!b.lit && passed) {
        b.lit = true;
        b.flashAt = t;
      }

      if (!b.lit) {
        // 未扫描到：一个几乎看不见的暗点
        canvas.drawCircle(
            p, 2.0, Paint()..color = Colors.white.withOpacity(0.10));
        continue;
      }

      final hot = b.score >= 80;
      final col = hot ? green : blue;

      // 点亮瞬间的扩散波纹（0.9 秒内消散）
      final age = (t - b.flashAt) % 1.0;
      if (b.flashAt >= 0 && age < 0.36 && t >= b.flashAt) {
        final k = age / 0.36;
        canvas.drawCircle(
          p,
          4 + k * 22,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 * (1 - k)
            ..color = col.withOpacity(0.55 * (1 - k)),
        );
      }

      // 光晕（径向渐变，不用 MaskFilter.blur）
      canvas.drawCircle(
        p,
        9,
        Paint()
          ..shader = ui.Gradient.radial(p, 9, [
            col.withOpacity(0.45),
            col.withOpacity(0.0),
          ]),
      );
      canvas.drawCircle(p, 3.4, Paint()..color = col);
      canvas.drawCircle(
          p, 1.5, Paint()..color = Colors.white.withOpacity(0.92));

      // 高分点：一圈呼吸环
      if (hot) {
        final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 3);
        canvas.drawCircle(
          p,
          7 + pulse * 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = col.withOpacity(0.28 * (1 - pulse * 0.5)),
        );
      }
    }
  }

  // ── 5. 中心核 ─────────────────────────────────────────────
  void _paintCore(Canvas canvas, Offset c, double r, double t) {
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    // 中心光斑
    canvas.drawCircle(
      c,
      26,
      Paint()
        ..shader = ui.Gradient.radial(c, 26, [
          green.withOpacity(0.22 + 0.08 * pulse),
          green.withOpacity(0.0),
        ]),
    );
    canvas.drawCircle(c, 4.2, Paint()..color = green);
    canvas.drawCircle(
        c, 1.8, Paint()..color = Colors.white.withOpacity(0.95));
    // 呼吸环
    canvas.drawCircle(
      c,
      12 + pulse * 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = green.withOpacity(0.35 * (1 - pulse)),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.phase != phase || old.blips != blips;
}
