import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 俯视鱼背的绘制器（池塘专用）
///
/// 为什么不用图鉴素材：图鉴那 46 张鱼图都是**正侧面**（有眼睛、胸鳍、侧线），
/// 而池塘底图是航拍俯视。把侧影贴到池面 = 一条翻肚子的鱼躺在水上。
///
/// 也不能把侧视纹理铺到俯视轮廓上：素材沿 y 是「背深腹白」、沿 x 是头尾+
/// 鳞片，拉过去会变成一根「玉米棒」。
///
/// 所以整条鱼都是程序化画的，只要三样东西：
///   1. **轮廓**：纺锤形 + 一张张开的燕尾（俯视下唯一能一眼认出「这是鱼」的部件）
///   2. **体色**：取自素材背部主色（[sampleBodyColor]），压暗、去饱和、往水色偏
///   3. **水下感**：边缘羽化 + 越深越淡
class FishTopView {
  const FishTopView._();

  /// 在画布原点画一条全长 [len]、游动相位 [phase] 的鱼（头朝 +x）
  ///
  /// [depth] 0 = 贴着水面，1 = 池底。越深越淡、越偏水色。
  /// [thrust] 摆尾幅度（爆发时 1、滑行时 .35）。
  static void paint(
    Canvas canvas, {
    required double len,
    required double phase,
    required Color body,
    double depth = .5,
    double thrust = 1,
  }) {
    // 体长（不含尾鳍）。尾鳍再往后伸出 .16，所以整体 ≈ 1.16 x len
    final l = len;
    // 俯视整宽 = 体长 x .23（4.3:1）。真实鲫鱼/鲤鱼俯视就这个比例：
    // 再瘦就成柳叶，再胖就成鲇鱼。
    final halfW = l * .100;
    const cols = 24;

    // ── 中心线：前半身几乎笔直，只有尾柄到尾巴摆
    final px = List<double>.filled(cols + 1, 0);
    final py = List<double>.filled(cols + 1, 0);
    final pw = List<double>.filled(cols + 1, 0);
    for (var i = 0; i <= cols; i++) {
      final u = i / cols; // 0 = 尾柄，1 = 吻端
      final q = 1 - u; // 0 = 头，1 = 尾
      px[i] = -l / 2 + l * u;
      // 摆幅沿体轴递增：头 0 → 尾柄 3%。真鱼游动时身体基本是直的，
      // 只有尾柄带一下；头尾一起 S 形扭（之前 8%）看起来像虫子。
      final env = .002 + .030 * math.pow(q, 2.6);
      // 相位沿体轴延迟 .55 个波长（行波从尾传向头）
      final ph = phase - q * 2 * math.pi * .55;
      py[i] = l * env * thrust * math.sin(ph);
      pw[i] = halfW * topWidth(u);
    }

    // ── 尾鳍先画，压在身体下面
    _tail(canvas, px[0], py[0], l, body, phase, depth);

    // ── 鱼身：三角网格 + 顶点色（顶点共享 → 弯了也不出接缝）
    //
    // 横向 t 取 -1.2..1.2，|t|>1 之后用 alpha 羽化出「水下柔边」。
    const rows = 4;
    const tMax = 1.20;
    final pos = <Offset>[];
    final colors = <Color>[];
    for (var i = 0; i < cols; i++) {
      final u0 = i / cols, u1 = (i + 1) / cols;
      for (var j = 0; j < rows; j++) {
        final t0 = -tMax + 2 * tMax * j / rows;
        final t1 = -tMax + 2 * tMax * (j + 1) / rows;
        final a = Offset(px[i], py[i] + pw[i] * t0);
        final b = Offset(px[i + 1], py[i + 1] + pw[i + 1] * t0);
        final c = Offset(px[i + 1], py[i + 1] + pw[i + 1] * t1);
        final d = Offset(px[i], py[i] + pw[i] * t1);
        pos.addAll([a, b, c, a, c, d]);
        final ca = shade(body, t0, u0, depth);
        final cb = shade(body, t0, u1, depth);
        final cc = shade(body, t1, u1, depth);
        final cd = shade(body, t1, u0, depth);
        colors.addAll([ca, cb, cc, ca, cc, cd]);
      }
    }
    canvas.drawVertices(
      ui.Vertices(ui.VertexMode.triangles, pos, colors: colors),
      BlendMode.srcOver,
      Paint(),
    );

    // ── 胸鳍：俯视照片里**看得见**的那一对小三角（长在鳃盖后两侧，
    //    向后外侧张开）。之前把它们画成两个横穿身体的椭圆 → 白色的 X；
    //    现在是从体侧边缘长出去的窄三角，贴着身体，只当「鳍」不当「腿」。
    _pecFins(canvas, px, py, pw, cols, l, body, depth);
  }

  /// 一对胸鳍：从体侧边缘向后外侧张开的窄三角
  ///
  /// 这是俯视下第二个「这是鱼」的信号（第一个是尾鳍）。真实航拍里它们
  /// 只比水暗一点点，所以 alpha 给得很低，形状够就行。
  static void _pecFins(Canvas canvas, List<double> px, List<double> py,
      List<double> pw, int cols, double l, Color body, double depth) {
    final i0 = (cols * .58).round();
    final i1 = (cols * .66).round();
    final finColor = shade(body, .55, .60, depth);
    final paint = Paint()
      ..color = finColor.withOpacity((.52 - depth * .12).clamp(.0, 1.0));
    for (final sgn in const [-1.0, 1.0]) {
      final rootA = Offset(px[i0], py[i0] + pw[i0] * sgn);
      final rootB = Offset(px[i1], py[i1] + pw[i1] * sgn);
      // 尖端：向后 .10 体长，向外 .055 体长
      final mx = (rootA.dx + rootB.dx) / 2;
      final my = (rootA.dy + rootB.dy) / 2;
      final dx = -l * .105, dy = l * .070 * sgn;
      final path = Path()
        ..moveTo(rootA.dx, rootA.dy)
        ..lineTo(mx + dx, my + dy)
        ..lineTo(rootB.dx, rootB.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  /// 俯视半宽轮廓：u = 0 尾柄、1 吻端（返回值 0~1，乘半宽）
  ///
  /// 真鱼俯视是**三段**：
  ///   尾柄 .11 →（前 18% 急剧变粗）.62 → 最宽 1.0（u=.52）→ 吻端椭圆收口
  /// 最宽处必须落在中前段（.52 附近），落正中就是一片对称的柳叶。
  /// 吻端用椭圆（sqrt）收口：直线收口会变成一个尖锥（像鱼雷/老鼠头），
  /// 而鱼吻从上面看是**圆钝**的一小截。
  static double topWidth(double u) {
    // 尾柄：.10 起，前 20% 急剧变粗到 .55
    if (u <= .20) {
      final k = u / .20;
      return .10 + .45 * math.pow(k, .82);
    }
    // 躯干：.55 → 最宽 1.0（u=.60，鳃盖后一点）
    if (u <= .60) {
      final k = (u - .20) / .40;
      final s = k * k * (3 - 2 * k);
      return .55 + .45 * s;
    }
    // 头：1.0 → .30（u=.96），**凹形收窄**（pow>1）。鱼头不是直锥：
    // 鳃盖处还宽，越往吻端收得越快，最后收成一个窄吻。
    if (u <= .96) {
      final k = (u - .60) / .36;
      return 1.0 - .70 * math.pow(k, 1.55);
    }
    // 吻端圆角：最后 4% 按四分之一圆收掉（不收口就是被切了一刀）
    final k = (u - .96) / .04;
    return .30 * math.sqrt((1 - k * k).clamp(0.0, 1.0));
  }

  /// 顶点色：**水里的一条深色剪影**，不是立体模型
  ///
  /// 真实航拍照片里一条鱼几乎看不到高光、眼睛、鳞片，就是一块比水暗、
  /// 边缘发虚的深色。所以这里只做四件事：压暗 / 去饱和 / 往水色偏 / 边缘羽化。
  static Color shade(Color base, double t, double u, double depth) {
    final at = t.abs().clamp(0.0, 1.20);
    final hsv = HSVColor.fromColor(base);
    // 亮度：贴水面 .23 → 池底 .13。素材是白底摄影棚光，直接用会像「浮在水
    // 面的亮纸」；压到这里才是「隔着一层水看鱼背」。
    final lum = .13 + .10 * depth;
    // 横向：中脊略亮（离水面最近），体侧渐暗 —— 差 16% 刚好有体积但不至于
    // 变成一根圆管。
    final side = 1.0 - .18 * math.pow((at / 1.20).clamp(0.0, 1.0), .90);
    // 中脊高光：|t| < .3 的一条窄亮带。没有它整条鱼就是一块死板的深色斑；
    // 有了它，眼睛会读出「这是圆的背」。
    final ridge = 1.0 + .22 * math.pow((1 - (at / .34).clamp(0.0, 1.0)), 2);
    // 纵向：头略亮、尾柄略暗（尾巴细，被水吃掉）
    final endFade = .92 + .08 * u.clamp(0.0, 1.0);
    // 饱和度：留一点，鲫鱼灰绿 / 鲤鱼金褐的差别靠它；但不要多，
    // 鲤鱼的金黄原样搬进绿水就是「枯叶色」。
    final sat = (hsv.saturation * .52 + .05).clamp(0.0, .68);
    var c = HSVColor.fromAHSV(
            1, hsv.hue, sat, (lum * side * ridge * endFade).clamp(0.0, 1.0))
        .toColor();
    // 往池水色偏（水吸收红光，水下不该是暖调）
    c = Color.lerp(c, const Color(0xFF1E3329), .26)!;
    // 边缘羽化：|t| 超过 1.0 之后 .20 宽度内 alpha 归零
    final edge = at <= 1.0 ? 1.0 : (1 - (at - 1.0) / .14).clamp(0.0, 1.0);
    // 深水里的鱼更淡（隔着更厚的水）
    final a = (255 * edge * (.68 + .32 * depth)).round();
    return c.withAlpha(a);
  }

  /// 尾鳍：从尾柄张开的**燕尾扇**
  ///
  /// 俯视下认出「这是鱼」几乎全靠这一片：它必须明显比尾柄宽、向外张开、
  /// 中间有凹口，而且要和身体连在一起（根部宽度 = 尾柄宽度）。
  /// 之前根部比尾柄宽、鳍又短又窄，看上去就是「鱼屁股后面粘了一片叶子」。
  static void _tail(Canvas canvas, double x0, double y0, double l, Color body,
      double phase, double depth) {
    // 尾柄半宽 = .115 x .11 ≈ .0127 x l，根部必须照这个来
    final rootH = l * .0130;
    final finLen = l * .200; // 尾鳍长 = 体长 20%（真鱼尾巴差不多这么长）
    final spread = l * .130; // 展开半宽 = 体长 13%（张开后明显比身体宽）
    // 绕尾柄摆 ±.35 弧度（±20°），和身体后段的摆动反相
    final swing = math.sin(phase - 2 * math.pi * .85) * .35;
    final ca = math.cos(swing), sa = math.sin(swing);

    // (back, side)：沿体轴向后 / 垂直体轴，再绕尾柄转到全局
    Offset p(double back, double side) =>
        Offset(x0 - back * ca - side * sa, y0 - back * sa + side * ca);

    final root0 = p(0, -rootH);
    final root1 = p(0, rootH);
    final tipU = p(finLen, -spread);
    final tipD = p(finLen, spread);
    final notch = p(finLen * .48, 0); // 燕尾凹口
    final ctrlU = p(finLen * .52, -spread * 1.06);
    final ctrlD = p(finLen * .52, spread * 1.06);

    final path = Path()
      ..moveTo(root0.dx, root0.dy)
      ..quadraticBezierTo(ctrlU.dx, ctrlU.dy, tipU.dx, tipU.dy)
      ..lineTo(notch.dx, notch.dy)
      ..lineTo(tipD.dx, tipD.dy)
      ..quadraticBezierTo(ctrlD.dx, ctrlD.dy, root1.dx, root1.dy)
      ..close();

    // 尾鳍是半透明薄膜，比身体**暗**一点（不是更亮）。调亮就成了亮三角。
    // ★ 颜色必须走和身体同一套 shade()：直接拿原始背色（金黄/银白）填，
    //   尾鳍会是浅卡其，贴在墨绿的鱼身上就是「屁股后面粘了片叶子」。
    final finColor = shade(body, 0, .04, depth);
    canvas.drawPath(
      path,
      Paint()..color = finColor.withOpacity((.78 - depth * .12).clamp(.0, 1.0)),
    );
  }

  /// 从素材图采「背部主色」：只取鱼背中段一块，跳过透明像素
  ///
  /// 素材是白底摄影棚图，整张平均会偏白；所以只取 x .30~.72 / y .18~.42
  /// （背部靠前的一块），并跳过 alpha < 180 的像素。
  static Future<Color> sampleBodyColor(ui.Image img) async {
    final data =
        await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return const Color(0xFF6E7A5E);
    final w = img.width, h = img.height;
    final x0 = (w * .30).round(), x1 = (w * .72).round();
    final y0 = (h * .18).round(), y1 = (h * .42).round();
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 4;
        final a = data.getUint8(i + 3);
        if (a < 180) continue;
        r += data.getUint8(i);
        g += data.getUint8(i + 1);
        b += data.getUint8(i + 2);
        n++;
      }
    }
    if (n == 0) return const Color(0xFF6E7A5E);
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }
}
