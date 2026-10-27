import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 启动封面：内置在安装包里的品牌页（设计稿原图铺满 + 动态进度胶囊）
///
/// ★ 底图 `assets/startup/splash_brand.jpg` 里那个「正在获取最新渔情」
///   绿色胶囊是**被擦掉的**（见 `.verify` 里的擦除脚本）。胶囊由本文件
///   按原图坐标重绘，因为只有这样里面的进度才能动 —— 位图上的胶囊动不了。
///
/// ★ 底图是 1140×2050 的竖图，手机屏幕比例千奇百怪，所以必须用
///   `BoxFit.cover` 的等比缩放铺满，然后**用同一个缩放系数**换算胶囊
///   坐标，否则一旦换机型，进度胶囊就会和底图错位（偏上或偏下）。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.ready = false, this.onFinished});

  /// 启动数据（预览页 / 广告配置）是否已经拉完。
  /// 拉完就把进度推到 100%，播完收尾动画后回调 [onFinished] 交给上层。
  final bool ready;

  /// 进度条播完之后调用，上层据此切到主界面
  final VoidCallback? onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ---------------- 底图与胶囊的原始像素坐标（设计稿坐标系） ----------------
  static const double _imgW = 1140;
  static const double _imgH = 2050;

  /// 进度条外缘在底图中的位置（v2.1.44 改版）。
  ///
  /// 原来是 638×136 的「胶囊按钮」（251,1816），用户反馈「太高太短」——
  /// 高 136 在 2050 高的图上占 6.6%，看着像一颗圆角方块，不像加载条。
  /// 现在改成 **780×40** 的细长条，中心不变（1884），两端仍是全圆角：
  ///   宽 780 → 屏宽 390 时约 321dp（两侧各留 34dp），比原来长 22%；
  ///   高  40 → 约 16dp，是原胶囊的三分之一，视觉上就是一根进度条。
  static const Rect _barSrc = Rect.fromLTWH(180, 1864, 780, 40);

  /// 进度条上方那行小字（正在获取最新渔情）在设计稿里的顶部 y
  static const double _labelTop = 1802;

  /// 文案字号（设计稿坐标）：比原胶囊的 60 小，因为条本身变扁了，
  /// 文字再那么大就会「字比条粗」，看着像按钮不是进度条。
  static const double _labelSize = 44;

  /// 进度前 90% 由时间推进（像真在加载），最后 10% 等数据真的到位
  static const Duration _growDuration = Duration(milliseconds: 2100);
  static const Duration _finishDuration = Duration(milliseconds: 380);

  /// 启动页最短展示时长。
  /// 接上快网时启动接口 200ms 就回来了，如果不设下限，这个页面总共只
  /// 亮 0.6 秒 —— 用户既看不清图，进度条也只是一闪，观感像「闪屏故障」。
  static const Duration _minShow = Duration(milliseconds: 1600);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _growDuration,
  );

  /// 专门计「最短展示」的控制器。
  ///
  /// ★ 不要用 `DateTime.now()` 算经过时间：那是真实时钟，而动画走的是
  ///   ticker。在 widget 测试里两者不同步（ticker 是假时钟），会出现
  ///   「进度停在 0.9 不涨满」的假象；用控制器表达，两边天然一致。
  late final AnimationController _minShowCtrl = AnimationController(
    vsync: this,
    duration: _minShow,
  );

  Timer? _watchdog;
  bool _finishing = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.animateTo(0.90, duration: _growDuration, curve: Curves.easeOutCubic);
    _minShowCtrl.forward();
    if (widget.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
    // 兜底：万一启动接口一直不回来（弱网/后端挂了），也别把用户
    // 卡在这个页面上 —— 9 秒后强制收尾，进主界面再看各自页面的错误态。
    _watchdog = Timer(const Duration(seconds: 9), () {
      if (mounted) _finish();
    });
  }

  @override
  void didUpdateWidget(covariant SplashScreen old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _finish();
  }

  Future<void> _finish() async {
    if (_finishing || _done) return;
    _finishing = true;
    _watchdog?.cancel();
    // 先等「最短展示」这段走完（已经在跑，这里直接复用同一个 TickerFuture）
    if (!_minShowCtrl.isCompleted) {
      await _minShowCtrl.forward();
      if (!mounted) return;
    }
    await _c.animateTo(1.0, duration: _finishDuration, curve: Curves.easeOut);
    if (!mounted) return;
    // 满格之后再亮一下，让「加载完成」有落点，不是戛然而止
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _done = true;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _c.dispose();
    _minShowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 底图顶部是纯黑，状态栏必须用白字，否则在黑色上看不见
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS（深色底 → 白字）
        systemNavigationBarColor: Color(0xFF00140A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: LayoutBuilder(
          builder: (_, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            // BoxFit.cover：取两边缩放比的较大者，多出来的部分居中裁掉
            final s = math.max(w / _imgW, h / _imgH);
            final dx = (w - _imgW * s) / 2;
            final dy = (h - _imgH * s) / 2;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: dx,
                  top: dy,
                  width: _imgW * s,
                  height: _imgH * s,
                  child: Image.asset(
                    'assets/startup/splash_brand.jpg',
                    fit: BoxFit.fill, // 外层已按 cover 算好精确尺寸
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Color(0xFF00140A)),
                    // 底图从黑里淡入 240ms：冷启动时系统启动图是纯黑，
                    // 直接硬切会出现「黑 → 图」的跳变，淡入后是「图从黑里浮现」
                    frameBuilder: (_, child, frame, wasSync) {
                      if (wasSync) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                        child: child,
                      );
                    },
                  ),
                ),
                // 文案放在条的上方，不再塞进条里：
                // 条只有 40 高（屏上约 16dp），字放进去会顶满、像按钮
                Positioned(
                  left: dx,
                  top: dy + _labelTop * s,
                  width: _imgW * s,
                  child: Center(
                    child: Text(
                      _pillText,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: _labelSize * s,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1 * s,
                        color: Colors.white.withOpacity(.92),
                        shadows: [
                          Shadow(
                            color: const Color(0xCC00140A),
                            blurRadius: 6 * s,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 进度条本体
                Positioned.fromRect(
                  rect: Rect.fromLTWH(
                    dx + _barSrc.left * s,
                    dy + _barSrc.top * s,
                    _barSrc.width * s,
                    _barSrc.height * s,
                  ),
                  child: _SplashBar(progress: _c, scale: s),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 启动进度条（v2.1.44）
///
/// 从「胶囊按钮」改成真正的细长进度条：白色细边 + 深绿轨道 + 渐变填充，
/// 填充从左往右长。高度只有 40 个设计像素，圆角取一半，两端仍是圆的。
///
/// ★ 白边内侧特意留一圈深色衬底（[Padding]）：填充段最左端是亮青绿，
///   和纯白描边的明度差很小，不留衬底会被吃成「看起来没有边框」。
class _SplashBar extends StatelessWidget {
  const _SplashBar({required this.progress, required this.scale});

  final Animation<double> progress;

  /// 底图 → 屏幕的缩放系数，所有尺寸都按它换算，保证任何屏幕比例一致
  final double scale;

  @override
  Widget build(BuildContext context) {
    final h = 40 * scale;
    final radius = h / 2;
    final stroke = math.max(1.0, 2.2 * scale);
    final rim = stroke * 1.3;

    return AnimatedBuilder(
      animation: progress,
      builder: (_, __) {
        final p = progress.value.clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            // 未完成的轨道：比底图暗一档，「跑到哪」一眼能看出来
            color: const Color(0xFF06170C),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withOpacity(.88),
              width: stroke,
            ),
            boxShadow: [
              BoxShadow(
                color: _SplashColors.mint.withOpacity(.20),
                blurRadius: 12 * scale,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(rim),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(math.max(1, radius - rim)),
              child: ClipRect(
                // 先铺满整条渐变，再按进度裁掉右侧 —— 不能把渐变塞进
                // 「按比例变窄的容器」里，那样渐变色会被压在同一小段里，
                // 看起来像整块变亮，而不是「从左往右流过去」。
                clipper: _ProgressClipper(p),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: _SplashColors.grad,
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 只保留左侧 [p] 比例的裁剪器（进度条从左往右长）
class _ProgressClipper extends CustomClipper<Rect> {
  const _ProgressClipper(this.p);

  final double p;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * p, size.height);

  @override
  bool shouldReclip(_ProgressClipper old) => old.p != p;
}

/// 启动页专用色（与底图取样一致，不进全局色板）
class _SplashColors {
  static const mint = Color(0xFF12E8A8);

  static const grad = [Color(0xFF12CE96), Color(0xFF63E052),
      Color(0xFFAEE637)];
}

/// 胶囊文案（抽出常量，描边层和填充层必须完全一致才能对齐）
const _pillText = '正在获取最新渔情';
