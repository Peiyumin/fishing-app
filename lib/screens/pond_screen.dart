import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../data/fish_assets.dart';
import '../models/fish.dart';
import '../services/fish_service.dart';
import '../widgets/fish_photo.dart';

/// 池塘在背景图里的位置（归一化坐标，按图片宽高算）
///
/// 数值是**量着 assets/pond/pond_bg.jpg 里真实水面**标出来的
/// （把椭圆描红画在照片上逐次对齐，见 .verify/pond_calib2.png）。
/// 上一版 0.474 / 0.487 / 0.216 / 0.191 的椭圆比真实水面**大一圈**
/// —— 左、上、下三边各多出 30~40px，鱼游到那一带就压到岸上的草里。
/// 这一版把水面 bbox（照片像素 x 95~300、y 285~545）换算后取内切。
class PondSpec {
  static const double cx = 0.502;
  static const double cy = 0.493;
  static const double rx = 0.170;
  static const double ry = 0.148;
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

  /// 最大放大倍数。底图 1024px 宽，铺满一屏约 576px，3 倍时 2.25 倍插值
  /// 已经能看清水花，再放就只剩马赛克了。
  static const double maxZoom = 3.0;

  @override
  State<PondScreen> createState() => _PondScreenState();
}

class _PondScreenState extends State<PondScreen>
    with TickerProviderStateMixin {
  // ★ 用 Ticker + ValueNotifier 而不是 AnimationController:
  //   AnimationController.repeat() 到时长末尾会把 value 归零 → `value * 60`
  //   算出来的时间从 60 跳回 0，所有鱼瞬间位移一大截（每秒 60 帧里总有
  //   一帧会看到，表现为「抽搐」）。Ticker 的 elapsed 是单调递增的，
  //   永远不会回头，鱼也就不会跳。
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  /// 画布视口（缩放 + 平移）：用户说的「360 全景、能拉近看鱼」
  final ValueNotifier<PondView> _view =
      ValueNotifier<PondView>(const PondView(1, Offset.zero));

  /// 把「时间」和「视口」合成一个 repaint 源交给 CustomPainter
  ///
  /// ★ 关键性能改动：以前是 `ValueListenableBuilder` 包着 CustomPaint —— 每帧
  ///   重建整棵 widget 子树（含顶栏、面板、渐变），滑走的时候这些重建全都在
  ///   跟转场动画抢帧，就是用户说的「向右滑关闭有卡顿」。
  ///   现在 widget 树一帧都不重建，只把 listenable 交给 painter 重绘。
  late final Listenable _repaint;

  // 手势基准
  double _gStartZoom = 1;
  Offset _gStartPan = Offset.zero;
  Offset _gFocal = Offset.zero;
  Offset _tapPos = Offset.zero;
  AnimationController? _zoomCtl;

  /// 每帧复用的 Paint / Shader 缓存，避免每帧 new 几十个渐变
  final PondPaintCache _cache = PondPaintCache();

  ui.Image? _bg;
  final Map<String, ui.Image> _images = {};

  List<PondFish> _placed = const [];
  List<FishSpecies> _all = const [];
  bool _loading = true;
  bool _immersive = false;

  /// 放大后「复位」胶囊要不要显示（只在小范围重建，不带动整页）
  final ValueNotifier<bool> _zoomed = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([_clock, _view]);
    // ★ 时钟：`_base + raw`，冻结时把 `_base` 反向补偿掉已经流走的时间。
    //   为什么不 `_ticker.stop()/_ticker.start()`：Ticker.start() 会把
    //   elapsed 从 0 重新计，等于把时间倒回 0 —— 所有鱼的位置、摆尾相位
    //   一起重置，回到页面那一帧会看到鱼「瞬移」。
    _ticker = createTicker((elapsed) {
      final raw = elapsed.inMicroseconds / 1000000.0;
      if (_frozen) {
        _base -= raw - _lastRaw;
        _lastRaw = raw;
        return; // 不回写 → 不重绘：转场那几帧一次 paint 都不做
      }
      _lastRaw = raw;
      _clock.value = _base + raw;
    })..start();
    _boot();
  }

  bool _frozen = false;
  double _base = 0;
  double _lastRaw = 0;

  /// 本页路由的转场动画（pop 时用它判断「该冻结画面了」）
  ///
  /// 必须在 didChangeDependencies 里取一次存下来：dispose() 阶段再去
  /// `ModalRoute.of(context)` 会抛「Looking up a deactivated widget's
  /// ancestor is unsafe」，而且那一抛会把后面的 _ticker.dispose() 一起跳过，
  /// 引擎会报「An animation is still running after the widget tree was disposed」。
  Animation<double>? _routeAnim;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (!identical(a, _routeAnim)) {
      _routeAnim?.removeListener(_onRouteAnim);
      _routeAnim = a;
      _routeAnim?.addListener(_onRouteAnim);
    }
  }

  /// 开始 pop 时立刻冻结画面
  ///
  /// 转场那 300ms 里，池塘的动画帧和滑走动画在同一帧预算里，冻住最贵的
  /// 那一半，滑走就顺了。回到本页（forward / completed）再解冻。
  void _onRouteAnim() {
    _frozen = _routeAnim?.status == AnimationStatus.reverse;
  }

  @override
  void dispose() {
    _routeAnim?.removeListener(_onRouteAnim);
    _zoomCtl?.dispose();
    _ticker.dispose();
    _clock.dispose();
    _view.dispose();
    _zoomed.dispose();
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

  /// 投放 / 收回
  ///
  /// ★ 投放上限 = **图鉴里该鱼种已记录的条数**（FishSpecies.count）。
  ///   发一条鱼获 → 后端按识别出的鱼种给图鉴 +1 → 这里就能多投一条。
  ///   不再是无限制往池里加（用户明确要求「有多少条就可以投放多少条」）。
  Future<void> _toggle(FishSpecies f) async {
    final quota = f.count;
    final same = _countOf(f.id);
    if (quota <= 0) {
      _toast('图鉴里还没有「${f.name}」\n发一条这种鱼的鱼获，图鉴 +1 后才能投放');
      return;
    }
    List<PondFish> next;
    if (same >= quota) {
      // 已经投满 → 再点收回一条
      final idx = _placed.lastIndexWhere((e) => e.id == f.id);
      if (idx < 0) return;
      next = [..._placed]..removeAt(idx);
    } else {
      if (_placed.length >= kPondMaxFish) {
        // 一屏画一百多条既看不清也掉帧，到上限就提示先收走几条
        _toast('池塘养满了（$kPondMaxFish 条），先收走几条再投');
        return;
      }
      next = [..._placed, PondFish.fromSpecies(f)];
    }
    setState(() => _placed = next);
    await PondStore.save(next);
    await _ensureFishImages(next);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
    ));
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
    // 只有图鉴里有条数的鱼才能投（count > 0）
    final unlocked = _all.where((f) => f.count > 0).toList();
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

  // ══════════════════ 手势：缩放 / 环视 / 双击看鱼 ══════════════════


  void _onScaleStart(ScaleStartDetails d) {
    _gStartZoom = _view.value.zoom;
    _gStartPan = _view.value.pan;
    _gFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final size = MediaQuery.of(context).size;
    // 1 倍时不吃单指拖动：留着给系统的「向右滑返回」用
    if (_gStartZoom <= 1.001 && d.scale < 1.01) return;
    final zoom = (_gStartZoom * d.scale).clamp(1.0, PondScreen.maxZoom);
    // 焦点保持：手指按住的那个点在放大过程中一直贴在手指下面
    final scene = (_gFocal - _gStartPan) / _gStartZoom;
    final pan = _clampPan(d.localFocalPoint - scene * zoom, zoom, size);
    _view.value = PondView(zoom, pan);
    _zoomed.value = zoom > 1.02;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // 松手时如果几乎回到 1 倍，直接归位（避免停在 1.004 这种别扭状态）
    if (_view.value.zoom < 1.05) _setView(const PondView(1, Offset.zero));
  }

  Offset _clampPan(Offset p, double zoom, Size s) =>
      PondView.clampPan(p, zoom, s);

  void _setView(PondView v) {
    _view.value = v;
    _zoomed.value = v.zoom > 1.02;
  }

  void _onDoubleTap() {
    final size = MediaQuery.of(context).size;
    if (_view.value.zoom > 1.05) {
      _animateTo(const PondView(1, Offset.zero));
      return;
    }
    // 双击放大：把双击的位置放到屏幕中心附近
    const z = 2.4;
    final p = _clampPan(size.center(Offset.zero) - _tapPos * z, z, size);
    _animateTo(PondView(z, p));
  }

  /// 放大/复位做一小段过渡，直接跳会被吓一跳
  void _animateTo(PondView target) {
    final ctl = _zoomCtl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    final from = _view.value;
    ctl.reset();
    void tick() {
      final k = Curves.easeOutCubic.transform(ctl.value);
      _setView(PondView(
        from.zoom + (target.zoom - from.zoom) * k,
        Offset.lerp(from.pan, target.pan, k)!,
      ));
    }

    ctl.addListener(tick);
    ctl.forward().whenComplete(() => ctl.removeListener(tick));
  }

  /// 「沉浸看鱼」：收起面板 + 拉近到 2.2 倍
  void _immersiveZoom() {
    setState(() => _immersive = true);
    final size = MediaQuery.of(context).size;
    const z = 2.2;
    final p = _clampPan(size.center(Offset.zero) * (1 - z), z, size);
    _animateTo(PondView(z, p));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF10251C),
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onDoubleTapDown: (d) => _tapPos = d.localPosition,
        onDoubleTap: _onDoubleTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 池塘画面
            //
            // ★ 不再用 ValueListenableBuilder 包 CustomPaint：那样每帧重建整棵
            //   子树。现在 painter 自己监听 `_repaint`（时钟 + 视口），widget
            //   一帧都不重建；外面再套 RepaintBoundary，滑走时这一层直接当
            //   纹理平移，不用重新栅格化。
            if (_bg != null)
              RepaintBoundary(
                child: CustomPaint(
                  painter: PondPainter(
                    bg: _bg!,
                    images: _images,
                    fish: _placed,
                    clock: _clock,
                    view: _view,
                    cache: _cache,
                    repaint: _repaint,
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
                            '双指放大 · 拖动看鱼 · 双击拉近',
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

          // 放大后浮出的「倍数 + 复位」胶囊（只重建这一小块）
          Positioned(
            right: 12,
            bottom: _immersive ? 74 : 150,
            child: ValueListenableBuilder<bool>(
              valueListenable: _zoomed,
              builder: (_, on, __) => AnimatedOpacity(
                opacity: on ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !on,
                  child: GestureDetector(
                    onTap: () => _animateTo(const PondView(1, Offset.zero)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.42),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<PondView>(
                            valueListenable: _view,
                            builder: (_, v, __) => Text(
                              '${v.zoom.toStringAsFixed(1)}×',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.close_fullscreen,
                              size: 13, color: Colors.white70),
                          const SizedBox(width: 2),
                          const Text('复位',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
                        onPressed: _immersiveZoom,
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

/// 池里同时最多画多少条鱼
///
/// 图鉴全点亮理论上能放 138 条（46 种 × 3），但一屏一百多条既看不清、
/// 也会明显掉帧，池塘本来也养不下这么多。放鱼超过这个数会提示先收走几条。
const int kPondMaxFish = 24;

/// 池塘绘制：背景照片 → 水色 → 柔光斑 → 鱼群 → 水面波纹 → 跃水 → 暗角
///
/// 注意：**水面不要画直线网格**。上一版那层「焦散光网」是两组互相垂直的
/// 正弦线，在真实池塘照片上看起来就是一张贴在池底的渔网（用户原话：
/// 「把动态水波纹显示的网格给隐藏掉」）。现在改成几团大而极淡的径向光斑，
/// 边缘靠渐变化开，没有一条直边。
/// 视口：缩放 + 平移（用户要的「360 全景、能拉近看鱼」）
///
/// 场景坐标系 = 首帧的屏幕矩形；屏幕上一点 = `scene * zoom + pan`。
/// zoom = 1、pan = 0 时和以前完全一样，不会动到已经标定好的 [PondSpec]。
class PondView {
  final double zoom;
  final Offset pan;
  const PondView(this.zoom, this.pan);

  /// 把平移夹在「刚好不留白」的范围内
  ///
  /// 场景坐标系就是首帧屏幕矩形，所以放大后可见区域是 [pan, pan + zoom*size]，
  /// 要盖住 [0, size] 就必须 `size*(1-zoom) <= pan <= 0`。
  /// 写成一个静态方法是为了能被单测直接验证（不依赖手势）。
  static Offset clampPan(Offset p, double zoom, Size s) {
    final minX = s.width * (1 - zoom);
    final minY = s.height * (1 - zoom);
    return Offset(p.dx.clamp(minX, 0.0), p.dy.clamp(minY, 0.0));
  }
}

/// 跨帧复用的 Paint / Shader
///
/// ★ 为什么要这个：原来每帧都现做六七个 `RadialGradient` / `ImageShader`。
///   平时看不出来，但「向右滑关闭池塘」那 300ms 里这些构造全在跟转场动画
///   抢同一帧的时间，就是用户反馈的那一下卡顿。
///   渐变 shader 只要矩形和颜色不变就能一直用 —— 半径改成「单位圆」建一次，
///   绘制时用 `canvas.scale` 放大，省钱且效果一样。
class PondPaintCache {
  Size? size;
  Rect? waterRect;

  Paint? waterTint; // 水面青绿
  Paint? vignette; // 暗角
  Paint? glow; // 柔光斑（单位圆，白色径向）
  Paint? shadow; // 鱼影（单位圆，中心深、边缘全透）

  /// 每条鱼图的纹理 shader：图不变就一直复用
  final Map<ui.Image, ui.ImageShader> tex = {};

  ui.ImageShader texOf(ui.Image img) => tex.putIfAbsent(
        img,
        () => ui.ImageShader(
          img,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        ),
      );

  void ensure(Size s, Rect water) {
    if (size == s && waterRect == water && waterTint != null) return;
    size = s;
    waterRect = water;

    vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withOpacity(.42)],
        stops: const [.62, 1.0],
      ).createShader(Offset.zero & s);

    waterTint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF06231E).withOpacity(.30),
          const Color(0xFF0B3A2E).withOpacity(.18),
          const Color(0xFF1E6B52).withOpacity(.09),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(water);

    glow = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withOpacity(.05), Colors.white.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));

    shadow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF06231E).withOpacity(.34),
          const Color(0xFF06231E).withOpacity(0),
        ],
        stops: const [.42, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
  }
}

/// 池塘绘制：背景照片 → 水色 → 柔光斑 → 鱼群 → 水面波纹 → 跃水 → 暗角
///
/// 注意：**水面不要画直线网格**。上一版那层「焦散光网」是两组互相垂直的
/// 正弦线，在真实池塘照片上看起来就是一张贴在池底的渔网（用户原话：
/// 「把动态水波纹显示的网格给隐藏掉」）。现在改成几团大而极淡的径向光斑，
/// 边缘靠渐变化开，没有一条直边。
class PondPainter extends CustomPainter {
  final ui.Image bg;
  final Map<String, ui.Image> images;
  final List<PondFish> fish;
  final ValueListenable<double> clock;
  final ValueListenable<PondView> view;
  final PondPaintCache cache;

  PondPainter({
    required this.bg,
    required this.images,
    required this.fish,
    required this.clock,
    required this.view,
    required this.cache,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final v = view.value;

    // 整场（照片 + 鱼）一起缩放平移：放大后鱼跟着变大，才「看得清姿态」
    canvas.save();
    canvas.translate(v.pan.dx, v.pan.dy);
    canvas.scale(v.zoom);

    // 背景「cover」铺满：池塘必须完整落在椭圆区域内
    final scale = math.max(size.width / bg.width, size.height / bg.height);
    final dw = bg.width * scale;
    final dh = bg.height * scale;
    final dx = (size.width - dw) / 2;
    final dy = (size.height - dh) / 2;
    canvas.drawImageRect(
      bg,
      Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
      Rect.fromLTWH(dx, dy, dw, dh),
      Paint()..filterQuality = FilterQuality.medium,
    );

    // 水面椭圆（场景坐标）
    final water = Rect.fromCenter(
      center: Offset(dx + PondSpec.cx * dw, dy + PondSpec.cy * dh),
      width: PondSpec.rx * 2 * dw,
      height: PondSpec.ry * 2 * dh,
    );
    cache.ensure(size, water);

    // 每帧只算一次位置：水里的和空中的用同一份数据，否则跃水时会「两个影子」
    final list =
        fish.length > kPondMaxFish ? fish.sublist(0, kPondMaxFish) : fish;
    final swimmers = <_Swimmer>[];
    for (var i = 0; i < list.length; i++) {
      swimmers.add(_Swimmer.of(list[i], i, list.length, t, water));
    }
    final under = <_Swimmer>[
      ...swimmers.where((s) => !s.airborne),
    ]..sort((a, b) => a.depth.compareTo(b.depth));
    final air = <_Swimmer>[
      ...swimmers.where((s) => s.airborne),
    ]..sort((a, b) => a.depth.compareTo(b.depth));

    canvas.save();
    canvas.clipPath(Path()..addOval(water));

    canvas.drawOval(water, cache.waterTint!);
    _paintLightPatches(canvas, water, t);
    _paintFish(canvas, under);
    _paintMicroRipples(canvas, water, t);

    canvas.restore();

    _paintJumps(canvas, water, air);
    canvas.restore();

    // 暗角不跟着缩放，永远贴在屏幕上
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      cache.vignette!,
    );
  }

  /// 柔光斑：几团很大、很淡的径向渐变在水面下慢慢漂
  ///
  /// 只用「圆的渐变」，没有任何线段 —— 即使用户盯着看也看不出网格。
  /// shader 是单位圆，靠 canvas.scale 放大成椭圆，不再每帧 new。
  void _paintLightPatches(Canvas canvas, Rect water, double t) {
    const n = 5;
    final paint = cache.glow!;
    for (var i = 0; i < n; i++) {
      final ph = i * 1.73;
      final cx =
          water.center.dx + math.sin(t * .11 + ph) * water.width * .30;
      final cy =
          water.center.dy + math.cos(t * .09 + ph * 1.31) * water.height * .26;
      final rw = water.width * (.24 + .05 * math.sin(t * .07 + ph));
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(rw, rw * .78);
      canvas.drawCircle(Offset.zero, 1, paint);
      canvas.restore();
    }
  }

  void _paintFish(Canvas canvas, List<_Swimmer> list) {
    for (final s in list) {
      final img = images[
          FishAssets.pathOrFallback(s.fish.name, waterType: s.fish.water)];
      if (img == null) continue;
      s.paint(canvas, img, cache);
    }
  }

  /// 水面上的零星星点：很小、很快散，让水「活着」但不抢戏
  void _paintMicroRipples(Canvas canvas, Rect water, double t) {
    final squash = water.height / water.width;
    for (var i = 0; i < 4; i++) {
      final cycle = 2.6 + i * .9;
      final q = ((t / cycle) + i * .31) % 1.0;
      if (q > .55) continue; // 大部分时间是干净的，只偶尔冒一个
      final c = Offset(
        water.center.dx + math.sin(i * 3.1 + t * .07) * water.width * .27,
        water.center.dy + math.cos(i * 1.7 + t * .05) * water.height * .24,
      );
      final r = water.width * (.012 + .05 * q);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 2, height: r * 2 * squash),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9
          ..color = Colors.white.withOpacity(.10 * (1 - q / .55)),
      );
    }
  }

  /// 跃出水面的鱼：出水 → 抛物线 → 落回水面，两头各炸一圈水花
  void _paintJumps(Canvas canvas, Rect water, List<_Swimmer> list) {
    for (final s in list) {
      final img = images[
          FishAssets.pathOrFallback(s.fish.name, waterType: s.fish.water)];
      if (img == null) continue;
      final q = s.jumpQ;
      final stride = s.bodyLen * .9;
      // 起跳点 → 落水点：整段都在同一条朝向上往前挪，不会瞬移
      final launch = s.center;
      final landing = Offset(
        launch.dx + math.cos(s.heading) * stride,
        launch.dy + math.sin(s.heading) * stride,
      );
      final now = Offset.lerp(launch, landing, q)!;
      final height = water.height * .24 * 4 * q * (1 - q);
      final h = s.bodyLen * img.height / img.width;
      final grow = 1 + .10 * math.sin(math.pi * q);

      canvas.save();
      canvas.translate(now.dx, now.dy - height);
      // 朝向沿用游动方向（含左右镜像），再叠一层绕自身的翻转：
      // 出水时鼻尖朝上、顶点大致水平、入水时朝下
      canvas.rotate(s.facing > 0 ? s.heading : s.heading + math.pi);
      canvas.scale(s.facing, 1);
      canvas.rotate(-.85 + q * 1.7);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(
          center: Offset.zero,
          width: s.bodyLen * grow,
          height: h * grow,
        ),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(
            const Color(0xFF0B4A3A).withOpacity(.06),
            BlendMode.srcATop,
          ),
      );
      canvas.restore();

      // 出水 / 落水的水花
      if (q < .18) _splash(canvas, launch, q / .18, water);
      if (q > .82) _splash(canvas, landing, (q - .82) / .18, water);
    }
  }

  /// 水花：k = 0（刚砸下去）→ 1（散完）
  void _splash(Canvas canvas, Offset at, double k, Rect water) {
    if (k <= 0 || k >= 1) return;
    final squash = water.height / water.width;
    final rMax = water.width * .13;
    final fade = (1 - k) * (1 - k);
    for (var i = 0; i < 3; i++) {
      final q = k - i * .16;
      if (q <= 0) continue;
      final r = rMax * q;
      canvas.drawOval(
        Rect.fromCenter(center: at, width: r * 2, height: r * 2 * squash),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + (1 - q) * 1.2
          ..color = Colors.white.withOpacity(.30 * fade * (1 - i * .26)),
      );
    }
    // 溅起来的小水珠
    final lift = water.height * .045;
    for (var d = 0; d < 7; d++) {
      final a = -math.pi * (.18 + .64 * (d / 6));
      final dist = rMax * .8 * k;
      canvas.drawCircle(
        Offset(
          at.dx + math.cos(a) * dist,
          at.dy + math.sin(a) * dist - lift * math.sin(math.pi * k),
        ),
        1.1 + 1.5 * (1 - k),
        Paint()..color = Colors.white.withOpacity(.40 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PondPainter old) {
    // 时间推进靠 `repaint`（clock + view）驱动，这里只管「换了一批鱼/图」。
    return old.fish != fish || old.images != images || old.bg != bg;
  }
}

/// 一条鱼的运行时状态
///
/// 位置 / 朝向 / 大小全部由「种子 + 当前时间」算出来，不保存任何动画状态：
/// 任意一帧都能直接重绘，切后台再回来也不会错位或跳一下。
///
/// ★ 为什么不「像真的在游」—— 前几版逐个踩坑，最后归结成四条：
///   1. **整条鱼一起晃**（`rotate(sin(phase)*.05)`）→ 看起来是贴纸在摇。
///      真实鱼是头几乎不动、**尾越靠后摆得越大**，所以振幅必须做成
///      沿体轴递增的包络（头 1.6% → 尾 10%），并且去掉整体摇晃。
///   2. **波长太短**（原来 2.9 rad ≈ 半条波）→ 鱼像在「扭腰」。
///      carangiform 的鱼体上大约 1 个波，这里取 0.95 个波长，形成 S 形。
///   3. **匀速巡航**（原来恒定角速度）→ 机械感。真实鱼是
///      **爆发-滑行**：猛摆两下冲一段、再滑一段。用时间扭曲
///      `tw = t + A·sin(ωt)` 实现：轨迹依然连续，速度却周期变化。
///   4. **尾巴不跟身体**：相位必须沿体轴**延迟**（波从头部传向尾部），
///      否则整条鱼一起左右平移，那是鱼雷不是鱼。
class _Swimmer {
  final PondFish fish;
  final int seed;
  final double depth; // 0 远（小、淡、慢）→ 1 近（大、清、快）
  final Offset center; // 水面上的屏幕坐标
  final double heading; // 朝向（弧度，屏幕坐标 y 向下）
  final double facing; // 1 朝右 / -1 朝左（素材本身朝右）
  final double foreshorten; // 身体被透视压短的比例 0.55~1
  final double bodyLen; // 体长（像素）
  final double swimPhase; // 摆尾相位（弧度）
  final double bob; // 慢速上浮/下沉相位
  final double thrust; // 0.35~1：当前推力（爆发时大、滑行时小）
  final double jumpQ; // 跃水进度 0..1；不在空中为 -1

  const _Swimmer({
    required this.fish,
    required this.seed,
    required this.depth,
    required this.center,
    required this.heading,
    required this.facing,
    required this.foreshorten,
    required this.bodyLen,
    required this.swimPhase,
    required this.bob,
    required this.thrust,
    required this.jumpQ,
  });

  bool get airborne => jumpQ >= 0;

  factory _Swimmer.of(PondFish f, int index, int total, double t, Rect water) {
    final seed = index * 37 + 11;
    final depth = total <= 1 ? .55 : ((index * 3) % 10) / 9.0;
    // 绕一圈的时间：越近游得越快（近处鱼的视觉位移本来就大）
    final period = 8.5 - depth * 2.5 + (seed % 5) * 0.6;
    final w = 2 * math.pi / period;
    final p1 = seed * .71;
    final p2 = seed * 1.37;
    final p3 = seed * 2.11;

    // ── 爆发-滑行 ──────────────────────────────────────────────
    // tw 是「被扭曲的时间」：轨迹 u(tw)、v(tw) 依旧光滑，
    // 但 gain = dtw/dt 周期性变化 → 速度时快时慢，像真的在窜。
    const warpA = .34;
    final wg = .55 + depth * .30;
    final gPh = wg * t + seed * .37;
    final tw = t + warpA * math.sin(gPh);
    final gain = 1 + warpA * wg * math.cos(gPh);

    // 归一化椭圆坐标：两个不同频率的正弦叠加 → 没有折角的漫游轨迹
    final u =
        .58 * math.sin(w * tw + p1) + .10 * math.sin(1.9 * w * tw + p3);
    final v =
        .42 * math.sin(.63 * w * tw + p2) + .10 * math.sin(1.31 * w * tw + p1);

    // 速度（解析求导，含时间扭曲的链式项）→ 朝向连续，不会左右硬翻
    final du = (.58 * w * math.cos(w * tw + p1) +
            .10 * 1.9 * w * math.cos(1.9 * w * tw + p3)) *
        gain;
    final dv = (.42 * .63 * w * math.cos(.63 * w * tw + p2) +
            .10 * 1.31 * w * math.cos(1.31 * w * tw + p1)) *
        gain;

    // 可用半径给椭圆的 44%：再留半个体长，鱼头不会顶到岸
    final ex = water.width * .44;
    final ey = water.height * .44;
    final vx = du * ex;
    final vy = dv * ey;
    final heading = math.atan2(vy, vx);
    // 跃水要看出「整条鱼离开水面」，所以只让游在池子中间（水面最宽处）的鱼跳；
    // 靠岸的鱼一跳就会飞到岸上的芦苇里
    final radial = math.sqrt(u * u + v * v);

    // 每条鱼落在自己的「泳道」上下错开：不加的话同一时刻会叠在一起，
    // 池子看着像只有一条鱼。±0.10 池高，仍在椭圆内。
    final lane = (index % 3) - 1;

    final bodyLen = water.width * (.175 + depth * .145);
    // 摆尾频率 1.1~2.0 Hz（真实鲫鱼巡游 1~3 Hz）。频率按鱼固定，
    // 推力另用 thrust 体现，避免「频率忽快忽慢」造成的抖动感。
    final hz = 1.15 + (1 - depth) * .45 + (seed % 4) * .09;

    return _Swimmer(
      fish: f,
      seed: seed,
      depth: depth,
      center: Offset(
        water.center.dx + u * ex,
        water.center.dy + v * ey + lane * water.height * .10,
      ),
      heading: heading,
      facing: math.cos(heading) >= 0 ? 1 : -1,
      // 朝镜头 / 背镜头时，投影上身体会变短 —— 转身因此是连续缩短再展开
      foreshorten: .55 + .45 * math.cos(heading).abs(),
      bodyLen: bodyLen,
      swimPhase: t * 2 * math.pi * hz + seed,
      bob: t * .62 + seed * .8,
      thrust: (.66 + .34 * math.cos(gPh)).clamp(.35, 1.0),
      jumpQ: _jumpPhase(seed, t, depth, radial),
    );
  }

  /// 每 8.5~15 秒跳一次，返回 0..1（不在跳跃窗口时返回 -1）
  ///
  /// `radial` 是鱼在归一化椭圆里的半径：只有游在池子中间的鱼才跳，
  /// 靠岸的鱼一跳就会飞进岸边的芦苇丛里。
  static double _jumpPhase(int seed, double t, double depth, double radial) {
    if (depth > .62) return -1; // 只有靠浅处的鱼才跳
    if (radial > .55) return -1; // 太靠边不跳
    final cycle = 8.5 + (seed % 5) * 1.6;
    final local = (t + (seed % 7) * 1.3) % cycle;
    const dur = 1.15;
    if (local > dur) return -1;
    return local / dur;
  }

  void paint(Canvas canvas, ui.Image img, PondPaintCache cache) {
    final h = bodyLen * img.height / img.width; // 身体厚度（垂直于身体方向）

    // 投在水底的影子：用「单位圆径向渐变」代替 MaskFilter.blur。
    // 效果几乎一样，但 blur 每条鱼都要开一个 layer 做高斯模糊 —— 24 条鱼
    // 就是 24 次离屏模糊，滑走时特别贵。
    canvas.save();
    canvas.translate(center.dx, center.dy + h * .40);
    canvas.rotate(heading);
    canvas.scale(bodyLen * .52, h * .58);
    canvas.drawCircle(Offset.zero, 1, cache.shadow!);
    canvas.restore();

    final tint = Paint()
      ..filterQuality = FilterQuality.medium
      // 越深的鱼越被水「吃掉」一点：远的看着更淡、更融进水里。
      // 上限别太高 —— 0.30 那档远处的鱼几乎看不见，池子看起来是空的
      ..colorFilter = ColorFilter.mode(
        const Color(0xFF0B4A3A)
            .withOpacity((.15 - depth * .10).clamp(0.0, 1.0)),
        BlendMode.srcATop,
      );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // 朝向 = 游动方向；朝左时整体镜像（素材本身朝右）
    canvas.rotate(facing > 0 ? heading : heading + math.pi);
    canvas.scale(facing * foreshorten, 1);

    // 巡游时身体只有极轻微的上浮/下沉 —— 这一层只留 3% 体厚，
    // 再大就会变成「一条船在浪里上下颠」，是很强的假信号
    canvas.translate(0, math.sin(bob) * h * .03);

    if (bodyLen >= 42) {
      _paintBentBody(canvas, img, h, tint, cache);
    } else {
      // 远处的小鱼看不出波动，整张画更省
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: bodyLen, height: h),
        tint,
      );
    }
    canvas.restore();
  }

  /// 弯着画一条鱼：14 列 × 2 行的三角网格，纹理是原图
  ///
  /// 为什么不用「切 N 段 drawImageRect 拼」：相邻段位移不同 → 接缝处出现
  /// 可见错位（第一版实测鱼身上有一条直线断带）。网格顶点是相邻三角形
  /// **共享**的，插值由 GPU 做，接缝天然连续。
  ///
  /// 振幅沿体轴递增：`env = 0.016 + 0.086 * q^1.55`（q=0 是头、q=1 是尾），
  /// 尾端约 10% 体长、头部 1.6% —— 真实鱼的比例大约是 6~8 倍差。
  void _paintBentBody(
      Canvas canvas, ui.Image img, double h, Paint tint, PondPaintCache cache) {
    const cols = 14;
    final bigL = bodyLen;
    final dy = List<double>.filled(cols + 1, 0);
    for (var i = 0; i <= cols; i++) {
      // 纹理左边是鱼尾、右边是鱼头（素材本身就是鱼头朝右）
      final q = 1 - i / cols;
      final env = .016 + .086 * math.pow(q, 1.55);
      // 相位沿体轴延迟 0.95 个波长：波从头部传向尾部，身体才是 S 形
      final ph = swimPhase - q * 2 * math.pi * .95;
      dy[i] = bigL * env * thrust * math.sin(ph);
    }
    final w = img.width.toDouble();
    final ih = img.height.toDouble();
    final pos = <Offset>[];
    final texOff = <Offset>[];
    for (var i = 0; i < cols; i++) {
      final x0 = -bigL / 2 + bigL * i / cols;
      final x1 = -bigL / 2 + bigL * (i + 1) / cols;
      final tx0 = w * i / cols;
      final tx1 = w * (i + 1) / cols;
      final a = Offset(x0, -h / 2 + dy[i]);
      final b = Offset(x1, -h / 2 + dy[i + 1]);
      final c = Offset(x1, h / 2 + dy[i + 1]);
      final d = Offset(x0, h / 2 + dy[i]);
      final ta = Offset(tx0, 0);
      final tb = Offset(tx1, 0);
      final tc = Offset(tx1, ih);
      final td = Offset(tx0, ih);
      // 两个三角形：a-b-c、a-c-d
      pos.addAll([a, b, c]);
      texOff.addAll([ta, tb, tc]);
      pos.addAll([a, c, d]);
      texOff.addAll([ta, tc, td]);
    }
    tint.shader = cache.texOf(img);
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        pos,
        textureCoordinates: texOff,
      ),
      BlendMode.srcOver,
      tint,
    );
    tint.shader = null; // 这个 Paint 是复用的，用完把 shader 摘掉
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
                    '按图鉴条数投放 · 池里最多 $kPondMaxFish 条 · 退出 App 也还在',
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
                      final quota = f.count;
                      final full = n >= quota;
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
                                          // 投满变灰：一眼看出这条鱼不能再加了
                                          color: full
                                              ? AppTheme.textSecondary
                                              : AppTheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        child: Text(
                                          '$n/$quota',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9.5,
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
                              Text(
                                n > 0 ? '已投 $n / 共 $quota' : '可投 $quota 条',
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: AppTheme.textSecondary),
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
