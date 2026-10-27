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

  /// 胶囊外缘（含白色描边）在底图中的位置。
  /// 实测方式：逐行扫底图里的白色像素，得到 左 251 / 右 889 /
  /// 上 1816 / 下 1952 —— 宽 638、高 136，高度正好等于两倍圆角
  /// （也就是两端是全圆角的「跑道形」）。
  static const Rect _pillSrc = Rect.fromLTWH(251, 1816, 638, 136);

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
                Positioned.fromRect(
                  rect: Rect.fromLTWH(
                    dx + _pillSrc.left * s,
                    dy + _pillSrc.top * s,
                    _pillSrc.width * s,
                    _pillSrc.height * s,
                  ),
                  child: _PillProgress(progress: _c, scale: s),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 「正在获取最新渔情」胶囊 + 内部渐变进度条
///
/// 视觉完全复刻底图里原来那个胶囊（左暗右亮的绿底 + 白色粗描边 +
/// 白色粗体字），只在内部多一层从左往右涨的渐变进度。
class _PillProgress extends StatelessWidget {
  const _PillProgress({required this.progress, required this.scale});

  final Animation<double> progress;

  /// 底图 → 屏幕的缩放系数，所有尺寸都按它换算，保证任何屏幕比例一致
  final double scale;

  @override
  Widget build(BuildContext context) {
    final height = 136 * scale;
    final radius = height / 2;
    // 描边要够粗才压得住亮青绿（2px 会被青绿吞成「没有边框」）
    final stroke = math.max(2.0, 7 * scale);
    // 原图 8 个字横跨约 500px → 单字 ≈ 62px
    final fontSize = 60 * scale;

    return AnimatedBuilder(
      animation: progress,
      builder: (_, __) {
        final p = progress.value.clamp(0.0, 1.0);
        // 白描边内侧留一圈暗色「衬底」。
        //
        // ★ 为什么不能白边直接贴亮填充：进度段的起点是亮青绿，
        //   亮青绿和纯白的明度差只有 0.35，描边会被吃成「看起来没有边框」。
        //   中间垫 2px 暗环之后，白边永远有深色托底，任何进度下都清晰 ——
        //   这才是原设计稿里那种「白圈包着绿」的观感。
        final rim = stroke + math.max(0.8, 1.6 * scale);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // 未完成的轨道：比底图胶囊暗一档，这样「跑到哪」一眼能看出来
            gradient: const LinearGradient(
              colors: [Color(0xFF07280C), Color(0xFF0B6B1A)],
            ),
            border: Border.all(color: Colors.white, width: stroke),
            boxShadow: [
              BoxShadow(
                color: _SplashColors.mint.withOpacity(.28),
                blurRadius: 18 * scale,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(rim),
            child: ClipRRect(
            borderRadius: BorderRadius.circular(math.max(2, radius - rim)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ① 进度填充：先铺满整条渐变，再按进度裁掉右侧 ——
                //    不能把渐变塞进「按比例变窄的容器」里，那样无论进度
                //    多少，渐变的三个色永远被压缩在同一小段里，看起来
                //    像是整块变亮，而不是「从左往右流过去」。
                ClipRect(
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
                // ② 文案：白字 + 深色描边
                //
                // ★ 为什么必须描边：进度涨到黄绿段（#C6FF3D）时，纯白字的
                //   对比度只剩 1.1:1，等于糊成一片。描一圈深绿黑边之后，
                //   白字在「暗绿底」和「亮黄绿底」上都能读 —— 这也是原
                //   设计稿里那行粗白字的观感。
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          _pillText,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: fontSize,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1 * scale,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = math.max(1.2, 3 * scale)
                              ..strokeJoin = StrokeJoin.round
                              ..color = _SplashColors.inkEdge,
                          ),
                        ),
                        Text(
                          _pillText,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1 * scale,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

  /// 立字用的深色描边：比纯黑柔一点，和深绿背景融得住
  static const inkEdge = Color(0xE8051F08);
  static const grad = [Color(0xFF12CE96), Color(0xFF63E052),
      Color(0xFFAEE637)];
}

/// 胶囊文案（抽出常量，描边层和填充层必须完全一致才能对齐）
const _pillText = '正在获取最新渔情';
