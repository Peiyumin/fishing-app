import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fish.dart';
import '../services/fish_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/fish_art.dart';

/// 我的鱼缸（池塘）
///
/// 交互：图鉴点亮过的鱼可以放进来养，鱼会在水里游、甩尾、偶尔跃出水面。
///
/// 设计要点（为什么全部用 Canvas 画、不放图片）：
/// - 用户明确要求「素材集成在 App 里、不走后端」，本地矢量绘制没有任何
///   网络等待，进页面即出水；
/// - 位图鱼无法做「身体行波 + 尾鳍摆动 + 出水旋转」，一动就露馅；
/// - 同种鱼放多条时，位图会一模一样，矢量可以按索引微调体型和朝向。
///
/// 画面的逼真度靠这几层叠出来：
/// 水体深度渐变 → 水面透光 → 水下焦散光网（caustics）→ 斜射光柱 →
/// 远景水草（虚化）→ 鱼群（按景深排序）→ 悬浮微粒 → 气泡 → 近景水草 →
/// 底砂与卵石 → 跃出水面的鱼（水花 + 涟漪）→ 水面波纹 → 玻璃反光 → 暗角。
class FishTankScreen extends StatefulWidget {
  const FishTankScreen({super.key});

  @override
  State<FishTankScreen> createState() => _FishTankScreenState();
}

class _FishTankScreenState extends State<FishTankScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  /// 图鉴数据（提供已解锁鱼种与稀有度）
  FishGuide _guide = FishService.fallback;

  /// 缸里的鱼（本地存档）
  List<TankFish> _fish = [];

  bool _loading = true;
  bool _immersive = false; // 沉浸模式：隐藏所有浮层，只看水
  bool _landscape = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clock.dispose();
    // 退出页面务必恢复竖屏，否则整个 App 都会停在横屏
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final g = await FishService.guide();
      if (mounted) setState(() => _guide = g);
    } catch (_) {
      // 接口不可用就用内置 fallback，鱼缸照常能看
    }
    final all = [..._guide.fresh, ..._guide.salt];
    final unlocked = all.where((f) => f.unlocked).toList();
    final stored = await TankStore.load();
    if (!mounted) return;
    setState(() {
      // 存档里的鱼必须仍在图鉴里处于点亮状态（防止脏数据）
      _fish = stored.where((t) => unlocked.any((f) => f.id == t.id)).toList();
      if (_fish.isEmpty && unlocked.isNotEmpty) {
        // 第一次进鱼缸：把点亮的鱼各放一条进来，先让水里有东西
        _fish = unlocked.take(6).map(TankFish.fromSpecies).toList();
        TankStore.save(_fish);
      }
      _loading = false;
    });
  }

  Future<void> _persist() async => TankStore.save(_fish);

  void _toast(String m) {
    if (mounted) CenterToast.show(context, m);
  }

  Future<void> _toggleLandscape() async {
    final next = !_landscape;
    await SystemChrome.setPreferredOrientations(next
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitUp]);
    if (mounted) setState(() => _landscape = next);
  }

  // ───────────────────── 放鱼面板 ─────────────────────

  Future<void> _openPicker() async {
    final unlocked = [..._guide.fresh, ..._guide.salt]
        .where((f) => f.unlocked)
        .toList();
    if (unlocked.isEmpty) {
      _toast('还没有点亮的鱼，先去图鉴点亮第 1 种');
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TankPickerSheet(
        all: unlocked,
        inTank: _fish,
        onToggle: (f) {
          setState(() {
            final idx = _fish.indexWhere((t) => t.id == f.id);
            if (idx >= 0) {
              _fish.removeAt(idx);
            } else {
              // 同种最多放 3 条，再多水里就挤成糊了
              final same = _fish.where((t) => t.id == f.id).length;
              if (same >= 3) {
                _toast('同一种鱼最多放 3 条');
                return;
              }
              _fish.add(TankFish.fromSpecies(f));
            }
          });
          _persist();
        },
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  // ───────────────────── 画面 ─────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF07211F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 水面背景（主体画面）
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (_, __) => CustomPaint(
                painter: TankPainter(
                  t: _clock.value * 60, // 秒
                  fish: _fish,
                  seed: _fish.length,
                ),
              ),
            ),
          ),

          // 顶部栏
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _immersive ? 0 : 1,
            child: IgnorePointer(
              ignoring: _immersive,
              child: _topBar(media),
            ),
          ),

          // 底部信息与操作
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: _immersive ? -220 : 0,
            child: _bottomPanel(),
          ),

          // 横屏提示
          if (!_immersive && !_landscape)
            Positioned(
              left: 0,
              right: 0,
              bottom: media.size.height * 0.36,
              child: Center(
                child: GestureDetector(
                  onTap: _toggleLandscape,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.34),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.screen_rotation,
                            size: 15, color: Colors.white70),
                        const SizedBox(width: 7),
                        Text('横屏试试，鱼缸更宽',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white.withOpacity(0.86))),
                        const SizedBox(width: 8),
                        Icon(Icons.close,
                            size: 13, color: Colors.white.withOpacity(0.55)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_loading)
            const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar(MediaQueryData media) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
        child: Row(
          children: [
            _glassBtn(Icons.arrow_back_ios_new, () => Navigator.of(context).pop()),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CYBER TANK',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.4,
                      color: const Color(0xFFC8FF6A),
                      shadows: [
                        Shadow(
                            color: const Color(0xFFC8FF6A).withOpacity(0.55),
                            blurRadius: 14),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '垂钓圈 · 我的鱼缸',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        color: Colors.white.withOpacity(0.62)),
                  ),
                ],
              ),
            ),
            _glassBtn(Icons.visibility_outlined, () {
              setState(() => _immersive = true);
            }),
            const SizedBox(width: 6),
            _glassBtn(_landscape ? Icons.screen_lock_rotation : Icons.screen_rotation,
                _toggleLandscape),
          ],
        ),
      ),
    );
  }

  Widget _glassBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.30),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Icon(icon, size: 17, color: Colors.white.withOpacity(0.88)),
      ),
    );
  }

  Widget _bottomPanel() {
    // 按鱼种归并展示（同种多条只占一个标签）
    final bySpecies = <String, int>{};
    for (final f in _fish) {
      bySpecies[f.name] = (bySpecies[f.name] ?? 0) + 1;
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.42),
              Colors.black.withOpacity(0.66),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '缸里的鱼',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.9)),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_fish.length} 条 · 已点亮 ${_guide.unlockedCount} 种',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withOpacity(0.55)),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/fish-guide'),
                  child: Row(
                    children: [
                      Text('图鉴',
                          style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFFC8FF6A).withOpacity(0.92))),
                      const Icon(Icons.chevron_right,
                          size: 15, color: Color(0xFFC8FF6A)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (bySpecies.isEmpty)
              Text(
                '水里还空着，点下面「放鱼」把图鉴里的鱼放进来',
                style: TextStyle(
                    fontSize: 11.5, color: Colors.white.withOpacity(0.55)),
              )
            else
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final e in bySpecies.entries)
                      Container(
                        margin: const EdgeInsets.only(right: 7),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 16,
                              child: FishArt(
                                name: e.key,
                                size: 15,
                                underwater: false,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${e.key} ×${e.value}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withOpacity(0.92)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: _tankBtn(
                    icon: Icons.add_circle_outline,
                    label: '放鱼',
                    onTap: _openPicker,
                    filled: false,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _tankBtn(
                    icon: Icons.camera_alt_outlined,
                    label: '拍一条入缸',
                    onTap: () => Navigator.of(context).pushNamed('/fish-guide'),
                    filled: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tankBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFC8FF6A) : Colors.black.withOpacity(0.34),
          borderRadius: BorderRadius.circular(11),
          border: filled
              ? null
              : Border.all(color: Colors.white.withOpacity(0.20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 17,
                color: filled ? const Color(0xFF10240F) : Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: filled ? const Color(0xFF10240F) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ 数据 ══════════════════════════

/// 缸里的一条鱼（存档单元）
class TankFish {
  final String id; // 鱼种 id
  final String name;
  final String water; // fresh / salt
  final String rarity;

  const TankFish({
    required this.id,
    required this.name,
    required this.water,
    required this.rarity,
  });

  factory TankFish.fromSpecies(FishSpecies f) => TankFish(
        id: f.id,
        name: f.name,
        water: f.waterType,
        rarity: f.rarity,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'water': water, 'rarity': rarity};

  static TankFish fromJson(Map<String, dynamic> j) => TankFish(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        water: (j['water'] ?? 'fresh').toString(),
        rarity: (j['rarity'] ?? 'common').toString(),
      );
}

/// 鱼缸存档（纯本地，不上后端）
class TankStore {
  static const String _key = 'tank_fish_v1';

  static Future<List<TankFish>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => TankFish.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<TankFish> fish) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _key, jsonEncode(fish.map((f) => f.toJson()).toList()));
    } catch (_) {
      // 存不了只影响下次进入的默认状态，不打断浏览
    }
  }
}

// ══════════════════════════ 放鱼面板 ══════════════════════════

class _TankPickerSheet extends StatefulWidget {
  final List<FishSpecies> all;
  final List<TankFish> inTank;
  final void Function(FishSpecies) onToggle;

  const _TankPickerSheet({
    required this.all,
    required this.inTank,
    required this.onToggle,
  });

  @override
  State<_TankPickerSheet> createState() => _TankPickerSheetState();
}

class _TankPickerSheetState extends State<_TankPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final inTankIds = widget.inTank.map((t) => t.id).toSet();
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.66),
      decoration: const BoxDecoration(
        color: Color(0xFF0D211E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
              child: Row(
                children: [
                  const Text('放鱼进缸',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(width: 8),
                  Text('已点亮 ${widget.all.length} 种',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withOpacity(0.5))),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('完成',
                        style: TextStyle(color: Color(0xFFC8FF6A))),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 108,
                ),
                itemCount: widget.all.length,
                itemBuilder: (_, i) {
                  final f = widget.all[i];
                  final added = inTankIds.contains(f.id);
                  return GestureDetector(
                    onTap: () {
                      widget.onToggle(f);
                      setState(() {});
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: added
                            ? const Color(0xFFC8FF6A).withOpacity(0.14)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: added
                              ? const Color(0xFFC8FF6A).withOpacity(0.65)
                              : Colors.white.withOpacity(0.10),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Center(
                              child: FishArt(
                                name: f.name,
                                rarity: f.rarity,
                                waterType: f.waterType,
                                size: 46,
                                underwater: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            added ? '已入缸 · 点击取出' : '点击放入',
                            style: TextStyle(
                                fontSize: 9.5,
                                color: added
                                    ? const Color(0xFFC8FF6A)
                                    : Colors.white.withOpacity(0.42)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ 绘制 ══════════════════════════

/// 鱼缸画面绘制器
///
/// 时间 [t] 以「秒」为单位。所有动态元素都由 t 的三角函数算出，
/// 不保存状态 → 任意一帧都能独立绘制，切后台回来不会跳。
class TankPainter extends CustomPainter {
  /// 当前时间（秒，循环 60 秒一轮）
  final double t;

  /// 缸里的鱼
  final List<TankFish> fish;

  /// 用于让「随机」布局稳定（同一缸鱼每次进页面位置一致）
  final int seed;

  TankPainter({required this.t, required this.fish, this.seed = 0});

  /// 水面线（画面上方，透过水面能看到天光）
  static const double waterTop = 0.085;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    _paintWaterBody(canvas, w, h);
    _paintSkyAboveWater(canvas, w, h);
    _paintCaustics(canvas, w, h);
    _paintLightShafts(canvas, w, h);
    _paintFarPlants(canvas, w, h);
    _paintParticles(canvas, w, h);
    _paintFishLayer(canvas, w, h);
    _paintBubbles(canvas, w, h);
    _paintForePlants(canvas, w, h);
    _paintFloor(canvas, w, h);
    _paintJumps(canvas, w, h);
    _paintWaterSurface(canvas, w, h);
    _paintGlassSheen(canvas, w, h);
    _paintVignette(canvas, w, h);
  }

  // ───────── 1. 水体 ─────────
  void _paintWaterBody(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, h),
          const [
            Color(0xFF1E7F72), // 近水面：透光的青绿
            Color(0xFF14655C),
            Color(0xFF0C4A45),
            Color(0xFF08302E), // 水底：压暗
          ],
          const [0.0, 0.32, 0.66, 1.0],
        ),
    );
    // 中央偏上的光源感（水下看到的「天光」不是均匀的）
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.52, h * 0.10),
          h * 0.72,
          [Colors.white.withOpacity(0.16), Colors.transparent],
          [0.0, 1.0],
        ),
    );
  }

  // ───────── 2. 水面上方（空气层，透过水面看到的天光）─────────
  void _paintSkyAboveWater(Canvas canvas, double w, double h) {
    final y = h * waterTop;
    final rect = Rect.fromLTWH(0, 0, w, y);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, y),
          const [Color(0xFF8FE3D2), Color(0xFF3FA597)],
        ),
    );
    // 透过水面看到的模糊天光：几条横向亮带，缓慢左右飘
    for (var i = 0; i < 3; i++) {
      final yy = y * (0.22 + i * 0.26);
      final shift = math.sin(t * 0.35 + i) * w * 0.05;
      canvas.drawRect(
        Rect.fromLTWH(shift - w * 0.1, yy, w * 1.2, y * 0.14),
        Paint()
          ..color = Colors.white.withOpacity(0.12 - i * 0.03)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  // ───────── 3. 水下焦散光网 ─────────
  /// 真实水下最抓眼的一层：鱼缸顶部会投下一片会游动的网纹光。
  /// 做法是两条不同相位的正弦网格叠乘，只在水体上部显示。
  void _paintCaustics(Canvas canvas, double w, double h) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h * 0.72));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6);

    for (var band = 0; band < 3; band++) {
      final alpha = 0.20 - band * 0.045;
      paint.color = const Color(0xFFBFF7E8).withOpacity(alpha);
      final phase = t * (0.30 + band * 0.09) + band * 1.7;
      final path = Path();
      var started = false;
      for (double x = 0; x <= w; x += 12) {
        final nx = x / w;
        final y = h *
            (0.10 +
                band * 0.14 +
                0.035 * math.sin(nx * 9.5 + phase) +
                0.018 * math.sin(nx * 21 - phase * 1.6));
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);

      // 反向波纹，与上面交叉形成网状光斑
      final path2 = Path();
      started = false;
      for (double x = 0; x <= w; x += 12) {
        final nx = x / w;
        final y = h *
            (0.16 +
                band * 0.14 +
                0.026 * math.sin(nx * 7.0 - phase * 0.8) +
                0.014 * math.sin(nx * 17 + phase));
        if (!started) {
          path2.moveTo(x, y);
          started = true;
        } else {
          path2.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path2, paint..color = const Color(0xFFBFF7E8).withOpacity(alpha * 0.7));
    }
    canvas.restore();
  }

  // ───────── 4. 斜射光柱 ─────────
  void _paintLightShafts(Canvas canvas, double w, double h) {
    for (var i = 0; i < 3; i++) {
      final sway = math.sin(t * 0.18 + i * 2.1) * w * 0.06;
      final topX = w * (0.20 + i * 0.30) + sway;
      final width = w * (0.09 + i * 0.025);
      final path = Path()
        ..moveTo(topX, 0)
        ..lineTo(topX + width, 0)
        ..lineTo(topX + width * 2.4 + w * 0.10, h)
        ..lineTo(topX + width * 0.7 + w * 0.06, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(topX, 0),
            Offset(topX + width, h),
            [
              Colors.white.withOpacity(0.13 - i * 0.03),
              Colors.white.withOpacity(0.015),
            ],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
  }

  // ───────── 5. 远景水草（虚化、压暗）─────────
  void _paintFarPlants(Canvas canvas, double w, double h) {
    final rnd = math.Random(seed + 17);
    for (var i = 0; i < 9; i++) {
      final baseX = w * (0.04 + rnd.nextDouble() * 0.92);
      final height = h * (0.18 + rnd.nextDouble() * 0.16);
      final sway = math.sin(t * 0.55 + i * 0.9) * w * 0.012;
      _plant(canvas, baseX, h * 0.985, height, sway,
          Color(0xFF0B3B32).withOpacity(0.72), 4, 5.0);
    }
  }

  // ───────── 6. 悬浮微粒 ─────────
  void _paintParticles(Canvas canvas, double w, double h) {
    final rnd = math.Random(seed + 31);
    for (var i = 0; i < 26; i++) {
      final baseX = rnd.nextDouble();
      final baseY = rnd.nextDouble();
      final spd = 0.006 + rnd.nextDouble() * 0.014;
      final drift = math.sin(t * 0.5 + i) * 0.006;
      final x = ((baseX + drift + 1) % 1) * w;
      final y = ((baseY - t * spd) % 1 + 1) % h;
      final r = 0.6 + rnd.nextDouble() * 1.3;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withOpacity(0.10 + rnd.nextDouble() * 0.14),
      );
    }
  }

  // ───────── 7. 鱼群 ─────────
  void _paintFishLayer(Canvas canvas, double w, double h) {
    final list = <_FishSprite>[];
    for (var i = 0; i < fish.length; i++) {
      list.add(_FishSprite(i, fish[i], seed));
    }
    // 远的先画（水里的鱼有前后遮挡，才不像贴纸）
    list.sort((a, b) => a.depth.compareTo(b.depth));

    for (final s in list) {
      final size = h * (0.085 + s.depth * 0.075) * s.sizeFactor;
      final style = FishStyle.from(s.fish.name,
          rarity: s.fish.rarity, waterType: s.fish.water);
      final pos = s.position(t, w, h);
      // 转身时不要瞬间翻面：用「压扁」做过渡最省性能且不别扭
      final flip = s.flipAmount(t);
      final facingRight = s.facingRight(t);
      final bob = math.sin(t * s.bobFreq + s.phase * 7) * h * 0.012;
      final tilt = math.sin(t * s.bobFreq * 0.8 + s.phase * 5) * 0.035;

      canvas.save();
      canvas.translate(pos.dx, pos.dy + bob);
      canvas.rotate(tilt);
      if (flip < 0.98) {
        // flip 从 1 → 0 表示身体侧转，横向压扁
        canvas.scale(flip, 1);
      }
      // 宽度跟着体型走：带鱼会自动拉得很长，鲫鱼短一些
      final box = Rect.fromCenter(
        center: Offset.zero,
        width: size * style.bodyLength,
        height: size,
      );
      FishDraw(
        style: style,
        phase: (t * s.tailFreq + s.phase) % 1,
        facingRight: facingRight,
        underwater: true,
      ).paintInto(
        canvas,
        box,
        // 远景不靠模糊（太贵），靠降低不透明度 + 更小尺寸做空气透视
        opacity: 0.72 + s.depth * 0.28,
      );
      canvas.restore();
    }
  }

  // ───────── 8. 气泡 ─────────
  void _paintBubbles(Canvas canvas, double w, double h) {
    final rnd = math.Random(seed + 47);
    for (var i = 0; i < 22; i++) {
      final baseX = rnd.nextDouble();
      final spd = 0.026 + rnd.nextDouble() * 0.05;
      // 大小差得多一点才自然（真缸里气泡不是统一大小的）
      final size = 1.2 + rnd.nextDouble() * rnd.nextDouble() * 5.0;
      final phase = rnd.nextDouble() * 6.28;
      // 从底往上升，到水面就消失（用取余实现无限循环）
      final prog = ((t * spd + phase) % 1.0);
      final y = h * (0.99 - prog * (0.99 - waterTop));
      final x = w * (baseX + math.sin(t * 1.6 + phase) * 0.012);
      final fade = prog > 0.92 ? (1 - prog) / 0.08 : 1.0;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withOpacity(0.34 * fade);
      canvas.drawCircle(Offset(x, y), size, paint);
      // 气泡左上高光，看起来才是个球不是个圈
      canvas.drawCircle(
        Offset(x - size * 0.3, y - size * 0.35),
        size * 0.30,
        Paint()..color = Colors.white.withOpacity(0.5 * fade),
      );
    }
  }

  // ───────── 9. 近景水草 ─────────
  void _paintForePlants(Canvas canvas, double w, double h) {
    final rnd = math.Random(seed + 61);
    for (var i = 0; i < 11; i++) {
      final baseX = w * (0.02 + rnd.nextDouble() * 0.96);
      final height = h * (0.20 + rnd.nextDouble() * 0.22);
      final sway = math.sin(t * 0.75 + i * 1.3) * w * 0.02;
      final green = Color.lerp(
          const Color(0xFF2F8A44), const Color(0xFF6FBF52), rnd.nextDouble())!;
      _plant(canvas, baseX, h * 1.005, height, sway, green, 6, 6.5);
    }
  }

  /// 一丛水草：从底部向上生长，叶片随 swing 弯曲（越靠上摆幅越大）
  void _plant(Canvas canvas, double baseX, double baseY, double height,
      double swing, Color color, int leaves, double leafWidth) {
    for (var l = 0; l < leaves; l++) {
      final off = (l - (leaves - 1) / 2) * leafWidth * 1.5;
      final hh = height * (0.66 + (l % 3) * 0.16);
      final bend = swing * (1 + (l % 3) * 0.25);
      final path = Path()
        ..moveTo(baseX + off, baseY)
        ..cubicTo(
          baseX + off - leafWidth * 0.8 + bend * 0.3,
          baseY - hh * 0.45,
          baseX + off + bend * 0.75,
          baseY - hh * 0.78,
          baseX + off + bend,
          baseY - hh,
        )
        ..cubicTo(
          baseX + off + bend + leafWidth * 0.55,
          baseY - hh * 0.74,
          baseX + off + leafWidth * 0.75 + bend * 0.3,
          baseY - hh * 0.4,
          baseX + off + leafWidth * 0.9,
          baseY,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(baseX + off, baseY),
            Offset(baseX + off + bend, baseY - hh),
            [Color.lerp(color, Colors.black, 0.45)!, color],
          ),
      );
    }
  }

  // ───────── 10. 底砂与卵石 ─────────
  void _paintFloor(Canvas canvas, double w, double h) {
    final rnd = math.Random(seed + 73);
    // 底砂：一条起伏的带子 + 颗粒
    final floor = Path()
      ..moveTo(0, h * 1.0)
      ..lineTo(0, h * 0.955);
    for (double x = 0; x <= w; x += 14) {
      floor.lineTo(x, h * (0.955 + 0.012 * math.sin(x / w * 7 + 0.6)));
    }
    floor
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      floor,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.94),
          Offset(0, h),
          const [Color(0xFF3B3128), Color(0xFF14100D)],
        ),
    );
    // 砂粒
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * w;
      final y = h * (0.958 + rnd.nextDouble() * 0.04);
      canvas.drawCircle(
        Offset(x, y),
        0.5 + rnd.nextDouble() * 1.2,
        Paint()
          ..color = Color.lerp(
              const Color(0xFF8A7A62), const Color(0xFF3A322A), rnd.nextDouble())!
              .withOpacity(0.55),
      );
    }
    // 卵石：椭圆 + 顶面高光
    for (var i = 0; i < 7; i++) {
      final cx = w * (0.06 + rnd.nextDouble() * 0.88);
      final cy = h * (0.962 + rnd.nextDouble() * 0.028);
      final rx = w * (0.032 + rnd.nextDouble() * 0.05);
      final ry = rx * (0.52 + rnd.nextDouble() * 0.22);
      final stone = Rect.fromCenter(
          center: Offset(cx, cy), width: rx * 2, height: ry * 2);
      canvas.drawOval(
        stone,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx - rx * 0.25, cy - ry * 0.4),
            rx,
            const [Color(0xFF6E6656), Color(0xFF2A251F)],
            [0.0, 1.0],
          ),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx - rx * 0.22, cy - ry * 0.42),
            width: rx * 0.8,
            height: ry * 0.5),
        Paint()..color = Colors.white.withOpacity(0.10),
      );
    }
  }

  // ───────── 11. 跃出水面的鱼 ─────────
  /// 每条鱼有自己的跳跃周期，正在跳的那不到 1 秒里：
  /// 先加速上浮 → 破水腾空（抛物线）→ 落水溅起水花与涟漪。
  ///
  /// 两个细节决定了它像不像真的：
  /// ① 起跳点必须是**这条鱼当时的实际位置**（不能随便挑个 x，否则鱼是凭空钻出来的）；
  /// ② 只有游在浅水区的鱼才会跳，水底的大鱼跳不出画面。
  void _paintJumps(Canvas canvas, double w, double h) {
    if (fish.isEmpty) return;
    const jumpDur = 0.95; // 一次完整跳跃的时长（秒）
    const risePart = 0.22; // 前 22% 用来上浮
    final surfaceY = h * waterTop;

    for (var i = 0; i < fish.length; i++) {
      final sprite = _FishSprite(i, fish[i], seed);
      // 深水区的鱼不跳（真实缸里也是贴水面的鱼才跃）
      if (sprite.depth > 0.55) continue;

      final period = 9.0 + (i % 4) * 2.5;
      final offset = i * 2.37;
      final cycle = (t + offset) % period;
      if (cycle > jumpDur) continue;
      final p = cycle / jumpDur;

      final jumpStart = t - cycle;
      final startPos = sprite.position(jumpStart, w, h);
      final rightward = sprite.facingRight(jumpStart);
      final dir = rightward ? 1.0 : -1.0;
      final style = FishStyle.from(fish[i].name,
          rarity: fish[i].rarity, waterType: fish[i].water);
      final size = h * (0.085 + sprite.depth * 0.05) * sprite.sizeFactor;

      double x;
      double y;
      double angle;
      var inAir = false;

      if (p < risePart) {
        // ① 水下加速上浮：从它原来的深度斜着冲向水面
        final k = p / risePart;
        final ease = k * k; // 加速上浮
        x = startPos.dx + dir * w * 0.035 * ease;
        y = startPos.dy + (surfaceY - startPos.dy) * ease;
        angle = dir * (-0.10 - 0.55 * ease);
      } else {
        // ② 腾空：抛物线 + 身体翻转
        inAir = true;
        final q = (p - risePart) / (1 - risePart);
        final peak = h * (0.085 + (i % 3) * 0.03);
        x = startPos.dx + dir * w * (0.035 + q * 0.20);
        y = surfaceY - 4 * peak * q * (1 - q);
        angle = dir * (-0.65 + q * 1.75); // 出水上仰 → 入水低头

        // ③ 落水：水花 + 涟漪（在落点，不是起跳点）
        if (q > 0.80) {
          _paintSplash(
              canvas, w, h, x, surfaceY, (q - 0.80) / 0.20);
        }
      }

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      FishDraw(
        style: style,
        phase: (t * 3.6) % 1, // 空中尾巴甩得更快
        facingRight: rightward,
        underwater: !inAir, // 水里的那一小段带水色，出水后是本色
      ).paintInto(
        canvas,
        Rect.fromCenter(
          center: Offset.zero,
          width: size * style.bodyLength,
          height: size,
        ),
      );
      canvas.restore();

      // 破水瞬间的水花
      if (p < risePart + 0.06 && p > risePart - 0.02) {
        _paintSplash(canvas, w, h, x, surfaceY, 0.35, upward: true);
      }
    }
  }

  void _paintSplash(Canvas canvas, double w, double h, double cx, double cy,
      double k, {bool upward = false}) {
    if (k <= 0 || k > 1) return;
    // 涟漪：两个圆环向外扩
    for (var r = 0; r < 2; r++) {
      final rk = (k * 1.6 - r * 0.28).clamp(0.0, 1.0);
      if (rk <= 0) continue;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy),
            width: w * 0.10 * rk + w * 0.03,
            height: h * 0.012 * rk + h * 0.004),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withOpacity(0.30 * (1 - rk)),
      );
    }
    // 飞溅的水珠
    final rnd = math.Random(7);
    final count = upward ? 6 : 10;
    for (var i = 0; i < count; i++) {
      final ang = -math.pi / 2 + (rnd.nextDouble() - 0.5) * 2.1;
      final spd = 0.5 + rnd.nextDouble() * 0.9;
      final px = cx + math.cos(ang) * w * 0.05 * spd * k;
      final py = cy +
          math.sin(ang) * h * 0.05 * spd * k +
          (upward ? -1 : 1) * h * 0.03 * k * k;
      canvas.drawCircle(
        Offset(px, py),
        1.0 + rnd.nextDouble() * 1.6,
        Paint()..color = Colors.white.withOpacity(0.55 * (1 - k)),
      );
    }
  }

  // ───────── 12. 水面波纹 ─────────
  void _paintWaterSurface(Canvas canvas, double w, double h) {
    final y0 = h * waterTop;
    // 水面亮带
    canvas.drawRect(
      Rect.fromLTWH(0, y0 - 6, w, 8),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, y0 - 6),
          Offset(0, y0 + 2),
          [Colors.white.withOpacity(0.22), Colors.transparent],
        ),
    );
    // 横向波纹线（2 条，相位不同）
    for (var i = 0; i < 2; i++) {
      final path = Path();
      var started = false;
      for (double x = 0; x <= w; x += 10) {
        final nx = x / w;
        final y = y0 +
            2.4 * math.sin(nx * 26 + t * (1.5 + i * 0.6)) +
            1.2 * math.sin(nx * 11 - t * 1.1);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 1.6 : 1.0
          ..color = Colors.white.withOpacity(i == 0 ? 0.38 : 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );
    }
  }

  // ───────── 13. 玻璃反光 ─────────
  void _paintGlassSheen(Canvas canvas, double w, double h) {
    final path = Path()
      ..moveTo(w * 0.06, 0)
      ..lineTo(w * 0.24, 0)
      ..lineTo(w * 0.10, h)
      ..lineTo(w * 0.0, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(w * 0.2, h),
          [Colors.white.withOpacity(0.07), Colors.transparent],
        ),
    );
  }

  // ───────── 14. 暗角 ─────────
  void _paintVignette(Canvas canvas, double w, double h) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.48),
          h * 0.78,
          [Colors.transparent, Colors.black.withOpacity(0.42)],
          [0.62, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(TankPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.fish.length != fish.length ||
      oldDelegate.seed != seed;
}

/// 一条鱼的游动参数（由索引决定，保证每次进页面一样）
class _FishSprite {
  final int index;
  final TankFish fish;

  /// 0 = 最远（小、暗、慢），1 = 最近（大、亮、快）
  final double depth;
  final double phase;
  final double tailFreq;
  final double bobFreq;
  final double sizeFactor;

  /// 横向速度（整屏宽度 / 秒）
  final double speed;

  /// 起始进度 0~1（决定初始横向位置）
  final double start;

  _FishSprite(this.index, this.fish, int seed)
      : depth = _rand(seed, index, 1, 0.15, 1.0),
        phase = _rand(seed, index, 2, 0, 6.283),
        tailFreq = _rand(seed, index, 3, 1.1, 2.2),
        bobFreq = _rand(seed, index, 4, 0.35, 0.85),
        sizeFactor = _rand(seed, index, 5, 0.88, 1.16),
        speed = _rand(seed, index, 6, 0.020, 0.052),
        start = _rand(seed, index, 7, 0, 1);

  /// 稳定的伪随机（同一条鱼每次进页面参数一致）
  static double _rand(int seed, int i, int salt, double lo, double hi) {
    var h = seed * 374761393 + i * 668265263 + salt * 2246822519;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h & 0x7fffffff;
    return lo + (h % 100000) / 100000.0 * (hi - lo);
  }

  /// 来回游：u∈[0,2) 折返，避免鱼一直单向「循环穿越」的不自然
  double _cycle(double t) {
    final span = 2.0 / speed; // 一个来回所需秒数
    final u = ((t / span + start) % 1.0) * 2.0;
    return u;
  }

  Offset position(double t, double w, double h) {
    final u = _cycle(t);
    // u<1：从左到右；u>1：从右到左
    final raw = u <= 1 ? u : 2 - u;
    // 中段游得快、快到边界时减速（真鱼是「冲一下、滑一段」，不是匀速传送带）
    final p = (raw + 0.06 * math.sin(raw * math.pi * 2)).clamp(0.0, 1.0);
    final x = w * (0.06 + p * 0.88);
    // 每条鱼在自己的深度带里游
    final band = 0.30 + depth * 0.58;
    final y = h * band;
    return Offset(x, y);
  }

  bool facingRight(double t) => _cycle(t) <= 1;

  /// 转身时做横向压扁过渡（1 = 正面，趋向 0 = 侧转）
  double flipAmount(double t) {
    final u = _cycle(t);
    // 在折返点附近（u 接近 0 / 1 / 2）压扁
    final edge = math.min(
      math.min((u - 0).abs(), (u - 1).abs()),
      (u - 2).abs(),
    );
    // 只在折返点极小一段做压扁过渡：真鱼掉头很快，
    // 过渡拉得太长会像「被门夹住」
    return (edge / 0.015).clamp(0.35, 1.0);
  }
}
