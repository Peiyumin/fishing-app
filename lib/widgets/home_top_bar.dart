import 'package:flutter/material.dart';

import '../app_theme.dart';
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
///   （Ma Shan Zheng 的「渔」「报」两字子集，2.9KB）。
///   字号 18 → 30：毛笔字的字面比黑体小一圈，同样 30pt 视觉上只有黑体 24pt 左右，
///   这正是「气势」的来源；再大就会顶到 62 高的工具栏。
///
/// ★ 字体族名就写在下面的 TextStyle 里（`'YuBaoBrush'`），必须和
///   pubspec.yaml `fonts:` 段声明的 family **一模一样** ——
///   写错的后果是 Flutter 静默回落系统字体（不报错、只是「不像毛笔字」），
///   所以 `test/v48_home_header_test.dart` 会读渲染后的 TextStyle 逐字核对。
class HomeTopBar extends StatelessWidget implements PreferredSizeWidget {
  /// 工具栏高度：标题 30pt + 毛笔字上下留白，46 会挤，62 正好
  static const double barHeight = 62;

  const HomeTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
          // 毛笔字笔画细，30pt 才有「两字撑满一条栏」的份量
          fontSize: 30,
          height: 1.1,
          // 毛笔字挨太近会粘成一团，拉开 3
          letterSpacing: 3,
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
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
      ),
    );
  }
}
