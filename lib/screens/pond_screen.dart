import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../data/fish_assets.dart';
import '../models/fish.dart';
import '../services/fish_service.dart';
import '../widgets/fish_photo.dart';

/// 池塘在背景图里的位置（归一化坐标，按图片宽高算）
/// 数值是量着 assets/pond/pond_bg.jpg 里水面描出来的：略小一圈更保险，
/// 鱼不会游到岸上的草里。
class PondSpec {
  static const double cx = 0.455;
  static const double cy = 0.435;
  static const double rx = 0.190;
  static const double ry = 0.168;
}

/// 池塘里的一条鱼（纯本地存档）
class PondFish {
  final String id;
  final String name;
  final String water; // fresh / salt
  final String rarity;

  const PondFish({
    required this.id,
    required this.name,
    required this.water,
    required this.rarity,
  });

  factory PondFish.fromSpecies(FishSpecies f) => PondFish(
        id: f.id,
        name: f.name,
        water: f.waterType,
        rarity: f.rarity,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'water': water, 'rarity': rarity};

  static PondFish fromJson(Map<String, dynamic> j) => PondFish(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        water: (j['water'] ?? 'fresh').toString(),
        rarity: (j['rarity'] ?? 'common').toString(),
      );
}

/// 池塘存档（纯本地）
class PondStore {
  /// 沿用旧存档键：老用户升级后缸里的鱼不会凭空消失
  static const String _key = 'tank_fish_v1';

  static Future<List<PondFish>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => PondFish.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<PondFish> fish) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _key, jsonEncode(fish.map((f) => f.toJson()).toList()));
    } catch (_) {
      // 存不进去只影响下次进来的默认状态，不打断浏览
    }
  }
}

/// 我的池塘：真实环境（背景照片）+ 真实鱼图在水下游动、偶尔跃出水面
class PondScreen extends StatefulWidget {
  const PondScreen({super.key});

  @override
  State<PondScreen> createState() => _PondScreenState();
}

class _PondScreenState extends State<PondScreen>
    with SingleTickerProviderStateMixin {
  // 必须在 initState 里就建好：写成延迟初始化的话，如果首帧时背景图还没
  // 到位（build 里没用到它），它会一直到 dispose() 才第一次创建，
  // 那时 element 已经失效 → 「Looking up a deactivated widget's ancestor」。
  late final AnimationController _clock;

  ui.Image? _bg;
  final Map<String, ui.Image> _images = {};

  List<PondFish> _placed = const [];
  List<FishSpecies> _all = const [];
  bool _loading = true;
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
    _boot();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // ① 背景图 + 已养的鱼
    final bg = await _loadImage('assets/pond/pond_bg.jpg');
    final placed = await PondStore.load();
    if (!mounted) return;
    setState(() {
      _bg = bg;
      _placed = placed;
      _loading = false;
    });
    // ② 鱼图按需加载（只加载池里有的，不浪费内存）
    await _ensureFishImages(placed);
    // ③ 图鉴（放鱼面板要用）
    final guide = await FishService.guide();
    if (!mounted) return;
    setState(() {
      _all = [...guide.fresh, ...guide.salt];
    });
  }

  Future<ui.Image?> _loadImage(String path) async {
    try {
      final data = await DefaultAssetBundle.of(context).load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureFishImages(List<PondFish> fish) async {
    final need = fish
        .map((f) => FishAssets.pathOrFallback(f.name, waterType: f.water))
        .toSet()
        .where((p) => !_images.containsKey(p))
        .toList();
    if (need.isEmpty) return;
    final loaded = <String, ui.Image>{};
    for (final p in need) {
      final img = await _loadImage(p);
      if (img != null) loaded[p] = img;
    }
    if (!mounted || loaded.isEmpty) return;
    setState(() => _images.addAll(loaded));
  }

  /// 放鱼 / 收鱼：同种最多 3 条
  Future<void> _toggle(FishSpecies f) async {
    final same = _placed.where((e) => e.id == f.id).length;
    List<PondFish> next;
    if (same == 0) {
      next = [..._placed, PondFish.fromSpecies(f)];
    } else if (same < 3) {
      next = [..._placed, PondFish.fromSpecies(f)];
    } else {
      // 已经 3 条 → 再点就是全部收回
      next = _placed.where((e) => e.id != f.id).toList();
    }
    setState(() => _placed = next);
    await PondStore.save(next);
    await _ensureFishImages(next);
  }

  int _countOf(String id) => _placed.where((e) => e.id == id).length;

  Future<void> _openPicker() async {
    if (_all.isEmpty) {
      // 图鉴还没拉到（断网）时给个提示，但不影响看池塘
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('图鉴还在加载，稍等一下再放鱼'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final unlocked = _all.where((f) => f.unlocked).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PondPickerSheet(
        all: unlocked,
        countOf: _countOf,
        onTap: _toggle,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF10251C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 池塘画面
          if (_bg != null)
            AnimatedBuilder(
              animation: _clock,
              builder: (_, __) => CustomPaint(
                painter: PondPainter(
                  bg: _bg!,
                  images: _images,
                  fish: _placed,
                  t: _clock.value * 60.0,
                ),
              ),
            )
          else
            const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70),
              ),
            ),

          // 顶栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            top: _immersive ? -140 : 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    _glassButton(Icons.arrow_back_ios_new, '返回',
                        () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的池塘',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .5,
                            ),
                          ),
                          Text(
                            '真实鱼图 · 水面会动 · 鱼会跃出来',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    _glassButton(Icons.fullscreen_rounded, '沉浸',
                        () => setState(() => _immersive = !_immersive)),
                  ],
                ),
              ),
            ),
          ),

          // 底部：放鱼面板
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            bottom: _immersive ? -240 : 0,
            left: 0,
            right: 0,
            child: _bottomPanel(),
          ),

          // 沉浸模式下给一个退出的小按钮
          if (_immersive)
            Positioned(
              right: 12,
              bottom: 20,
              child: SafeArea(
                child: _glassButton(Icons.fullscreen_exit_rounded, '退出沉浸',
                    () => setState(() => _immersive = false)),
              ),
            ),

          if (_loading)
            const IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      // 横屏时提示转手机（池塘是竖构图，横过来会裁掉两岸）
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: size.width > size.height
          ? FloatingActionButton.extended(
              onPressed: () => SystemChrome.setPreferredOrientations(
                  [DeviceOrientation.portraitUp]),
              backgroundColor: Colors.black.withOpacity(.6),
              icon: const Icon(Icons.screen_rotation, color: Colors.white),
              label: const Text('横屏看会裁掉两岸，建议转回竖屏',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            )
          : null,
    );
  }

  Widget _glassButton(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.28),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    final counts = <String, int>{};
    for (final f in _placed) {
      counts[f.name] = (counts[f.name] ?? 0) + 1;
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(.62)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_placed.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    '池塘还是空的，点「放鱼」把图鉴里点亮的鱼放进水里',
                    style: TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                )
              else
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final e in counts.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.16),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FishPhoto(name: e.key, height: 18),
                                const SizedBox(width: 6),
                                Text(
                                  e.value > 1 ? '${e.key} ×${e.value}' : e.key,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _openPicker,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(23)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('放鱼',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => setState(() => _immersive = true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(23)),
                        ),
                        child: const Text('沉浸看鱼',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════ 画面绘制 ══════════════════════════

/// 池塘绘制：背景照片 → 水色 → 焦散光网 → 鱼群 → 跃水 → 水面涟漪 → 暗角
class PondPainter extends CustomPainter {
  final ui.Image bg;
  final Map<String, ui.Image> images;
  final List<PondFish> fish;
  final double t; // 秒

  PondPainter({
    required this.bg,
    required this.images,
    required this.fish,
    required this.t,
  }) : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    // 背景「cover」铺满：池塘必须完整落在椭圆区域内
    final scale =
        math.max(size.width / bg.width, size.height / bg.height);
    final dw = bg.width * scale;
    final dh = bg.height * scale;
    final dx = (size.width - dw) / 2;
    final dy = (size.height - dh) / 2;
    final dst = Rect.fromLTWH(dx, dy, dw, dh);
    canvas.drawImageRect(
      bg,
      Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // 水面椭圆（屏幕坐标）
    final water = Rect.fromCenter(
      center: Offset(dx + PondSpec.cx * dw, dy + PondSpec.cy * dh),
      width: PondSpec.rx * 2 * dw,
      height: PondSpec.ry * 2 * dh,
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(water));

    _paintWaterTint(canvas, water);
    _paintCaustics(canvas, water);
    _paintFish(canvas, water);
    _paintRipples(canvas, water);

    canvas.restore();

    _paintJumping(canvas, water);
    _paintVignette(canvas, size);
  }

  /// 水色：中间深、边缘浅（岸边浅水透光），叠一层青绿
  void _paintWaterTint(Canvas canvas, Rect water) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF06231E).withOpacity(.34),
          const Color(0xFF0B3A2E).withOpacity(.20),
          const Color(0xFF1E6B52).withOpacity(.10),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(water);
    canvas.drawOval(water, paint);
  }

  /// 焦散光网：两组正弦线交叉，缓慢流动（水下那种会游动的光斑）
  void _paintCaustics(Canvas canvas, Rect water) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(.055);
    final paint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(.045);

    final n = 13;
    for (var i = 0; i < n; i++) {
      final path = Path();
      for (var k = 0; k <= 24; k++) {
        final fx = k / 24;
        final x = water.left + fx * water.width;
        final phase = t * .28 + i * .55 + fx * 4.2;
        final y = water.top +
            water.height * (i / n) +
            math.sin(phase) * water.height * .035;
        if (k == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, i.isEven ? p : paint2);
    }
    for (var i = 0; i < n; i++) {
      final path = Path();
      for (var k = 0; k <= 20; k++) {
        final fy = k / 20;
        final y = water.top + fy * water.height;
        final phase = t * .22 + i * .7 + fy * 3.6;
        final x = water.left +
            water.width * (i / n) +
            math.sin(phase) * water.width * .03;
        if (k == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, i.isEven ? p : paint2);
    }
  }

  void _paintFish(Canvas canvas, Rect water) {
    if (fish.isEmpty) return;
    final sprites = <_Sprite>[];
    for (var i = 0; i < fish.length; i++) {
      sprites.add(_Sprite.of(fish[i], i, fish.length, t, water));
    }
    sprites.sort((a, b) => a.depth.compareTo(b.depth));
    for (final s in sprites) {
      final img = images[
          FishAssets.pathOrFallback(s.fish.name, waterType: s.fish.water)];
      if (img == null) continue;
      s.paint(canvas, img);
    }
  }

  /// 水面涟漪：几条慢慢散开的椭圆环
  void _paintRipples(Canvas canvas, Rect water) {
    for (var i = 0; i < 3; i++) {
      final cycle = 5.5 + i * 1.7;
      final q = ((t + i * 2.1) % cycle) / cycle;
      final c = Offset(
        water.center.dx + math.sin(i * 2.3) * water.width * .22,
        water.center.dy + math.cos(i * 1.7) * water.height * .18,
      );
      final r = water.width * (.03 + q * .12);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(.10 * (1 - q));
      canvas.drawOval(
        Rect.fromCenter(
            center: c, width: r * 2, height: r * 1.5),
        p,
      );
    }
  }

  /// 跃出水面的鱼：只有靠浅处的鱼会跳
  void _paintJumping(Canvas canvas, Rect water) {
    if (fish.isEmpty) return;
    for (var i = 0; i < fish.length; i++) {
      final s = _Sprite.of(fish[i], i, fish.length, t, water);
      if (s.depth > .55) continue;
      final jump = _jumpPhase(s.seed);
      if (jump < 0 || jump > 1) continue;
      final img = images[
          FishAssets.pathOrFallback(fish[i].name, waterType: fish[i].water)];
      if (img == null) continue;

      // 起跳点固定在这个 sprite 的水面位置（不能每帧随机，否则凭空出现）
      final base = s.center;
      final arc = math.sin(jump * math.pi);
      final dy = -water.height * .34 * arc;
      final wPx = s.lenPx * .95;
      final hPx = wPx * img.height / img.width;
      final rect = Rect.fromCenter(
        center: Offset(base.dx, base.dy + dy),
        width: wPx,
        height: hPx,
      );
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate((s.dir >= 0 ? -1 : 1) * (-.7 + jump * 1.6));
      canvas.scale(s.dir >= 0 ? 1 : -1, 1);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(
            center: Offset.zero, width: rect.width, height: rect.height),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();

      // 落水的水花：起跳和落水各一圈
      if (jump < .12 || jump > .88) {
        final k = jump < .12 ? jump / .12 : (1 - jump) / .12;
        canvas.drawOval(
          Rect.fromCenter(
              center: base,
              width: water.width * .05 * (1.2 - k),
              height: water.width * .02 * (1.2 - k)),
          Paint()..color = Colors.white.withOpacity(.22 * k),
        );
      }
    }
  }

  /// 每 9~17 秒跳一次，返回 0..1 的进度（不在跳跃窗口时返回 -1）
  double _jumpPhase(int seed) {
    final cycle = 9.0 + (seed % 5) * 1.6;
    final offset = (seed % 7) * 1.3;
    final local = (t + offset) % cycle;
    const dur = 1.25;
    if (local > dur) return -1;
    return local / dur;
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withOpacity(.42)],
          stops: const [.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant PondPainter old) =>
      old.t != t || old.fish != fish || old.images != images || old.bg != bg;
}

/// 一条鱼的运行时状态
///
/// 位置 / 朝向 / 大小全部由「种子 + 当前时间」算出来，不保存任何动画状态：
/// 任意一帧都能直接重绘，切后台再回来也不会错位或跳一下。
class _Sprite {
  final PondFish fish;
  final int seed;
  final double depth; // 0 远（小、淡、慢）→ 1 近（大、清、快）
  final Rect water;
  final double dir; // 1 向右 / -1 向左
  final double pos; // 0..1，在水面椭圆里的水平位置
  final double lenPx; // 屏幕上的体长
  final Offset center; // 屏幕坐标
  final double tilt; // 轻微俯仰，别让所有鱼像贴纸一样水平
  final double alpha;

  const _Sprite({
    required this.fish,
    required this.seed,
    required this.depth,
    required this.water,
    required this.dir,
    required this.pos,
    required this.lenPx,
    required this.center,
    required this.tilt,
    required this.alpha,
  });

  factory _Sprite.of(
      PondFish f, int index, int total, double t, Rect water) {
    final seed = index * 37 + 11;
    final depth = total <= 1 ? .55 : ((index * 3) % 10) / 9.0;
    // 单程时间：越近游得越快（近处的鱼视觉位移本来就大）
    final span = 9.5 - depth * 4.5;
    final raw = (t / span + index * .37) % 2.0;
    final forward = raw < 1.0;
    final phase = forward ? raw : 2.0 - raw; // 0..1 来回折返
    final x = .17 + phase * .66;
    final y = .32 + depth * .40 + math.sin(t * .8 + index) * .028;
    final center = Offset(
      water.left + x * water.width,
      water.top + y * water.height,
    );
    // 鱼的长度按池塘宽度给：池塘只占画面一半，比例太小就完全看不清
    final lenPx = water.width * (.155 + depth * .135);
    return _Sprite(
      fish: f,
      seed: seed,
      depth: depth,
      water: water,
      dir: forward ? 1 : -1,
      pos: x,
      lenPx: lenPx,
      center: center,
      tilt: math.sin(t * .9 + index) * .045,
      alpha: .95 - depth * .42,
    );
  }

  void paint(Canvas canvas, ui.Image img) {
    final h = lenPx * img.height / img.width;
    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withOpacity(alpha)
      // 水色覆盖：越深的鱼越被水「吃掉」一点，看着才在水里而不是浮在照片上
      ..colorFilter = ColorFilter.mode(
        const Color(0xFF0B4A3A).withOpacity(.10 + depth * .22),
        BlendMode.srcATop,
      );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.scale(dir, 1);
    canvas.drawImageRect(
      img,
      src,
      Rect.fromCenter(center: Offset.zero, width: lenPx, height: h),
      paint,
    );
    canvas.restore();
  }
}

// ══════════════════════════ 放鱼面板 ══════════════════════════

class _PondPickerSheet extends StatefulWidget {
  final List<FishSpecies> all;
  final int Function(String id) countOf;
  final void Function(FishSpecies) onTap;

  const _PondPickerSheet({
    required this.all,
    required this.countOf,
    required this.onTap,
  });

  @override
  State<_PondPickerSheet> createState() => _PondPickerSheetState();
}

class _PondPickerSheetState extends State<_PondPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * .62,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                const Text('放鱼进池塘',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '同种最多 3 条，再点一次收走 · 退出 App 也还在',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.all.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '还没有点亮的鱼。先去「我的 → 鱼类图鉴」拍照记录渔获，\n点亮之后就能放进池塘养了。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: .88,
                    ),
                    itemCount: widget.all.length,
                    itemBuilder: (_, i) {
                      final f = widget.all[i];
                      final n = widget.countOf(f.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          widget.onTap(f);
                          setState(() {});
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: n > 0
                                ? AppTheme.primaryLight
                                : AppTheme.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: n > 0
                                  ? AppTheme.primary
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  FishPhoto(name: f.name, height: 40),
                                  if (n > 0)
                                    Positioned(
                                      right: -10,
                                      top: -6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        child: Text(
                                          '×$n',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
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
    );
  }
}
