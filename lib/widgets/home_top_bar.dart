import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/home_mode.dart';
import 'mode_tabs.dart';
import 'msg_bell.dart';

/// 首页顶栏（v2.1.84 定稿）
///
/// 用户提的三点：
///   ① 「渔报」下面那条白线去掉；
///   ② 标题从居中挪到左上角；
///   ③ 字号加大，字体要「气势磅礴、笔锋犀利」。
///
/// 三条各自的做法与坑：
///
/// **① 那条线不是 Divider，是主题给的 1px 底边。**
///   `AppBarTheme.shape`（v2.1.59 统一二级页时加的）给**所有** AppBar 画了
///   `Border(bottom: BorderSide(divider, 1))`。二级页是白底 + 白顶栏，这条线
///   用来收边很合适；但首页顶栏是近黑通栏（`headerGradient`），浅灰的 1px 线
///   压在黑底上就是一条白胶带，把「渔报」和下面的天气通栏硬生生切断。
///   这里显式传 `Border()`（四条边都是 `BorderSide.none`）覆盖主题，
///   **只影响首页**，别的页面继续用那条线。
///
/// **② 左上角。** 主题里 `centerTitle: true`，这里必须显式写 false，
///   光把 title 换成左对齐的 Row 是不够的 —— AppBar 会把整块 title 再居中。
///
/// **③ 毛笔字。** 系统里没有「笔锋犀利」的中文毛笔字体（安卓/iOS 只有黑体、
///   宋体），手写 `fontFamily: 'Songti SC'` 这类系统字体名在别的机器上解析不到
///   就是方块 —— 所以走**随包字体** `assets/fonts/yubao_brush.ttf`
///   （「渔」「报」两字子集，2.4KB）。
///
///   ★ v2.1.85 换了字体：原来用 Ma Shan Zheng（马善政毛笔楷书），
///   用户反馈「字再大一点、笔画再细一点」—— 马善政是**厚楷**，
///   字号一加笔画只会更粗，往相反方向走；换成 **Long Cang（龙藏行书）**：
///   同样是毛笔，但用笔瘦、收锋利，放大到 34 反而更透气。
///   （同批对比过 Zhi Mang Xing 偏飘、Liu Jian Mao Cao 太草「报」字认不出。）
///   字号 18 → 30 → **34**：毛笔字字面比黑体小一圈，34 视觉上约等于黑体 27，
///   两字正好撑满一条 62 高的工具栏。
///
/// ★ 字体族名就写在下面的 TextStyle 里（`'YuBaoBrush'`），必须和
///   pubspec.yaml `fonts:` 段声明的 family **一模一样** ——
///   写错的后果是 Flutter 静默回落系统字体（不报错、只是「不像毛笔字」），
///   所以 `test/v48_home_header_test.dart` 会读渲染后的 TextStyle 逐字核对。
class HomeTopBar extends StatelessWidget implements PreferredSizeWidget {
  /// 工具栏高度：标题 34pt（行高 1.05 ≈ 36）+ 上下各 13 的留白 = 62
  static const double barHeight = 62;

  /// 标题下面那条钓法分类（台钓 / 路亚 / 钓场 / 海钓）
  final HomeMode mode;
  final ValueChanged<HomeMode>? onModeChanged;

  /// ★ v2.1.90：嵌进首页滚动流里用（首页改版：标题导航和下面卡片整体滚动）。
  ///
  /// 为 true 时顶栏**不再自己画那条 headerGradient**，只保留结构
  /// （状态栏留白 + 62 的标题行 + 38 的分类条），背景交给外层的
  /// `HomeHeaderBlock` 统一画一次。
  ///
  /// 为什么必须抽走背景：`AppTheme.headerGradient` 是
  /// **topLeft → bottomRight 的对角渐变**。顶栏和天气卡各画一次，
  /// 两块的渐变起点不同，接缝处颜色会「断层」—— 一眼就能看出是
  /// 两块拼起来的，正好和「组在一起不要分开」相反。
  final bool embedded;

  const HomeTopBar({
    super.key,
    this.mode = HomeMode.taiDiao,
    this.onModeChanged,
    this.embedded = false,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(barHeight + ModeTabs.height);

  @override
  Widget build(BuildContext context) {
    final bar = AppBar(
      toolbarHeight: barHeight,
      // ★ 主题是 centerTitle: true；不写这一行，title 会被整块居中，
      //   光在 title 里写 Row/Align 是拗不过来的。
      centerTitle: false,
      titleSpacing: 18,
      // 顶栏是近黑渐变（flexibleSpace），前景必须显式改白：
      // 主题 foregroundColor 是近黑，黑图标压在黑底上会直接消失。
      foregroundColor: Colors.white,
      // ★ 去掉主题那条 1px 底边线（四边 none，不画任何线）
      shape: const Border(),
      title: const Text(
        '渔报',
        style: TextStyle(
          fontFamily: 'YuBaoBrush',
          // 行书笔画瘦，34 才够份量；再大就会顶到 62 高的工具栏
          fontSize: 34,
          // 行书上下都有出锋，行高留 1.05 避免贴边被裁
          height: 1.05,
          // 笔画细了更要拉开间距，不然两字会挨在一起；3 → 5
          letterSpacing: 5,
          color: Colors.white,
          // 黑底上给一点点投影，笔锋的边缘更「立」起来
          shadows: [
            Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 10),
          child: MsgBellButton(),
        ),
      ],
      // ★ v2.1.86：分类条挂在 AppBar 的 bottom 上，而不是塞进页面 body ——
      //   塞 body 会跟着列表滚走，用户划到下面想换个钓法还得先划回顶部。
      //   挂 bottom 后它和标题一样常驻，滑到底也在。
      //
      //   背景不用另画：AppBar 的 flexibleSpace 铺满整条（含 bottom 区），
      //   所以这里保持透明，顶栏到分类条是一整片渐变。
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(ModeTabs.height),
        child: ModeTabs(mode: mode, onChanged: onModeChanged),
      ),
      // embedded：背景由外层 HomeHeaderBlock 统一画（见 embedded 字段的注释）
      backgroundColor: embedded ? Colors.transparent : null,
      flexibleSpace: embedded
          ? null
          : Container(
              decoration:
                  const BoxDecoration(gradient: AppTheme.headerGradient),
            ),
    );

    if (!embedded) return bar;

    // ★ embedded（进滚动流）时必须**显式给定高度**。
    //
    //   AppBar 内部是 `Column(mainAxisSize: max)` + 若干 flex 子项，
    //   在 Scaffold 的 appBar 槽里拿到的是固定高度；一旦塞进 ListView，
    //   高度约束变成无限，Flutter 直接断言：
    //     「RenderFlex children have non-zero flex but incoming height
    //      constraints are unbounded」—— 整页白屏。
    //   高度 = 标题行 + 分类条 + 状态栏（AppBar 的 primary 会自己吃掉 top padding）。
    return SizedBox(
      height: barHeight + ModeTabs.height + MediaQuery.of(context).padding.top,
      child: bar,
    );
  }
}
